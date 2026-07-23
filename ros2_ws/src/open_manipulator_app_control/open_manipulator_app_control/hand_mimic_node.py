"""웹캠으로 손을 보고 OMX-AI를 따라 움직이게 하는 노드입니다.

    웹캠 → mediapipe 손 관절 → 팔 관절 각도 / 그리퍼 여닫기
                            → 관절을 그려 넣은 영상(앱 화면용)

손목의 좌우·상하 위치가 팔의 joint1·joint2로, 손을 쥐고 펴는 정도가 그리퍼로 갑니다.
앱의 "모방 시작" 버튼이 /open_manipulator/mimic_enable 로 들어오며,
켜지기 전에는 인식과 영상 송출만 하고 로봇에는 아무것도 보내지 않습니다.
"""

import os

import cv2
import mediapipe as mp
import rclpy
from ament_index_python.packages import get_package_share_directory
from control_msgs.action import GripperCommand
from mediapipe.tasks.python import BaseOptions
from mediapipe.tasks.python import vision
from rclpy.action import ActionClient
from rclpy.node import Node
from sensor_msgs.msg import Image
from std_msgs.msg import Bool
from std_msgs.msg import Int32

from open_manipulator_app_control.hand_metrics import (
    arm_joint_positions,
    base_arm_pose,
    gripper_position,
    pinch_openness,
    smooth,
    wrist_position,
)
from open_manipulator_app_control.hand_mimic_config import (
    ANNOTATED_IMAGE_TOPIC,
    CAMERA_ENABLE_TOPIC,
    CAMERA_HEIGHT,
    CAMERA_INDEX,
    CAMERA_INDEX_TOPIC,
    CAMERA_WIDTH,
    COMMAND_DURATION_SECONDS,
    COMMAND_PERIOD_SECONDS,
    GRIPPER_ACTION_NAME,
    GRIPPER_CHANGE_THRESHOLD,
    GRIPPER_CLOSED_POSITION,
    GRIPPER_MAX_EFFORT,
    GRIPPER_OPEN_POSITION,
    HAND_MODEL_FILENAME,
    MIMIC_ENABLE_TOPIC,
    MIN_DETECTION_CONFIDENCE,
    MIN_PRESENCE_CONFIDENCE,
    MIN_TRACKING_CONFIDENCE,
    PROCESS_RATE_HZ,
    SMOOTHING_FACTOR,
)
from open_manipulator_app_control.motion_controller import MotionController


class HandMimicNode(Node):

    def __init__(self) -> None:
        super().__init__("open_manipulator_hand_mimic")

        self.declare_parameter("camera_index", CAMERA_INDEX)
        self.camera_index = (
            self.get_parameter("camera_index")
            .get_parameter_value()
            .integer_value
        )

        self.motion_controller = MotionController(self)

        self.image_publisher = self.create_publisher(
            Image,
            ANNOTATED_IMAGE_TOPIC,
            10,
        )

        self.enable_subscription = self.create_subscription(
            Bool,
            MIMIC_ENABLE_TOPIC,
            self._enable_callback,
            10,
        )

        # 실시간 모방 화면에 들어오면 켜서 웹캠을 열고, 나가면 꺼서 반환합니다.
        self.camera_enable_subscription = self.create_subscription(
            Bool,
            CAMERA_ENABLE_TOPIC,
            self._camera_enable_callback,
            10,
        )

        # 앱에서 사용할 웹캠 장치 번호를 골라 보냅니다. 카메라가 여러 대일 때
        # 어느 것으로 모방할지 여기서 바꿉니다.
        self.camera_index_subscription = self.create_subscription(
            Int32,
            CAMERA_INDEX_TOPIC,
            self._camera_index_callback,
            10,
        )

        self.gripper_client = ActionClient(
            self,
            GripperCommand,
            GRIPPER_ACTION_NAME,
        )

        self.enabled = False
        self.smoothed_joints: list[float] | None = None
        # 마지막으로 보낸 그리퍼 목표(0~1). None이면 아직 보낸 적이 없습니다.
        self.gripper_openness: float | None = None
        self.seconds_since_command = 0.0
        self.frame_timestamp_ms = 0

        # 웹캠은 시작하자마자 열지 않습니다. 실시간 모방 화면에 들어와
        # 카메라 확보 신호가 올 때 열고, 나가면 반환합니다. 이렇게 하면 화면을
        # 안 볼 때는 장치를 잡지 않아 다른 프로그램이 쓸 수 있습니다.
        self.camera: cv2.VideoCapture | None = None
        self.landmarker = self._create_landmarker()

        self.timer = self.create_timer(
            1.0 / PROCESS_RATE_HZ,
            self._process_frame,
        )

        self.get_logger().info(
            "손 모방 노드가 시작되었습니다. "
            "앱의 실시간 모방 화면에 들어오면 웹캠을 엽니다."
        )

    # 앱에서 카메라 확보/반환 신호를 받습니다.
    # 실시간 모방 화면에 들어오면 True, 나가면 False가 옵니다.
    def _camera_enable_callback(self, message: Bool) -> None:
        if message.data:
            self._acquire_camera()
        else:
            self._release_camera()

    # 앱에서 고른 웹캠 장치 번호를 받습니다. 번호가 바뀌었고 카메라가 이미
    # 열려 있으면, 열려 있던 장치를 반환하고 새 번호로 다시 엽니다. 닫혀 있으면
    # 번호만 바꿔 두고, 다음에 화면에 들어와 확보할 때 새 번호로 열립니다.
    def _camera_index_callback(self, message: Int32) -> None:
        new_index = int(message.data)
        if new_index == self.camera_index:
            return

        self.get_logger().info(
            f"웹캠 장치를 {self.camera_index}번에서 {new_index}번으로 바꿉니다."
        )
        self.camera_index = new_index

        if self.camera is not None:
            self._release_camera()
            self._acquire_camera()

    # 웹캠을 열고 해상도를 맞춥니다. 이미 열려 있으면 그대로 둡니다.
    # 열지 못하면(다른 프로그램이 쓰는 중 등) 노드를 죽이지 않고 경고만 남깁니다.
    def _acquire_camera(self) -> None:
        if self.camera is not None and self.camera.isOpened():
            return

        camera = cv2.VideoCapture(self.camera_index)

        if not camera.isOpened():
            camera.release()
            self.camera = None
            self.get_logger().warning(
                f"웹캠을 열 수 없습니다 (camera_index={self.camera_index}). "
                f"다른 프로그램이 쓰고 있지 않은지 확인하세요."
            )
            return

        camera.set(cv2.CAP_PROP_FRAME_WIDTH, CAMERA_WIDTH)
        camera.set(cv2.CAP_PROP_FRAME_HEIGHT, CAMERA_HEIGHT)
        self.camera = camera
        self.get_logger().info("웹캠을 열었습니다.")

    # 웹캠 장치를 반환합니다. 실시간 모방 화면을 나갈 때 호출됩니다.
    def _release_camera(self) -> None:
        if self.camera is not None:
            self.camera.release()
            self.camera = None
            self.get_logger().info("웹캠을 반환했습니다.")

    # mediapipe 손 인식기를 만듭니다.
    # 모델 파일은 패키지 share/models 에 설치되어 있습니다.
    def _create_landmarker(self) -> vision.HandLandmarker:
        model_path = os.path.join(
            get_package_share_directory("open_manipulator_app_control"),
            "models",
            HAND_MODEL_FILENAME,
        )

        if not os.path.exists(model_path):
            raise RuntimeError(
                f"손 인식 모델을 찾을 수 없습니다: {model_path}. "
                f"scripts/download_hand_model.sh 를 실행한 뒤 다시 빌드하세요."
            )

        options = vision.HandLandmarkerOptions(
            base_options=BaseOptions(model_asset_path=model_path),
            running_mode=vision.RunningMode.VIDEO,
            num_hands=1,
            min_hand_detection_confidence=MIN_DETECTION_CONFIDENCE,
            min_hand_presence_confidence=MIN_PRESENCE_CONFIDENCE,
            min_tracking_confidence=MIN_TRACKING_CONFIDENCE,
        )

        return vision.HandLandmarker.create_from_options(options)

    # 앱에서 모방 시작/정지를 받습니다.
    # 정지할 때는 다음에 다시 시작할 때 이전 자세가 튀어나오지 않도록 상태를 지웁니다.
    def _enable_callback(self, message: Bool) -> None:
        if message.data == self.enabled:
            return

        self.enabled = message.data

        if self.enabled:
            # 모방하려면 웹캠이 필요합니다. 카메라 확보 신호를 놓쳤더라도
            # 여기서 한 번 더 열어 둡니다.
            self._acquire_camera()
            # 기본 90도 자세에서 시작합니다. 이렇게 해 두면 첫 프레임에서 손 위치로
            # 팔이 뚝 떨어지지 않고, 기본 자세에서 부드럽게 손을 따라가기 시작합니다.
            self.smoothed_joints = base_arm_pose()
            self.motion_controller.move_to(
                self.smoothed_joints,
                COMMAND_DURATION_SECONDS,
            )
        else:
            self.smoothed_joints = None
            self.gripper_openness = None

        self.get_logger().info(
            "손 모방 시작" if self.enabled else "손 모방 정지"
        )

    # 프레임 한 장을 읽어 손을 찾고, 켜져 있으면 로봇에 명령을 보냅니다.
    # 관절을 그려 넣은 영상은 켜짐 여부와 상관없이 항상 내보내
    # 사용자가 인식이 잘 되는지 미리 보고 시작할 수 있게 합니다.
    def _process_frame(self) -> None:
        # 카메라가 닫혀 있으면(화면을 안 보는 중) 아무것도 하지 않습니다.
        if self.camera is None:
            return

        read_ok, frame = self.camera.read()

        if not read_ok:
            self.get_logger().warning("웹캠에서 프레임을 읽지 못했습니다.")
            return

        # 거울처럼 좌우를 뒤집습니다. 사용자가 오른손을 오른쪽으로 옮기면
        # 화면에서도 오른쪽으로 움직여야 직관과 맞습니다.
        frame = cv2.flip(frame, 1)

        landmarks = self._detect_hand(frame)

        if landmarks is not None:
            self._draw_landmarks(frame, landmarks)

            if self.enabled:
                self._follow_hand(landmarks)

        self._publish_image(frame)

    # 프레임에서 손 관절을 찾습니다. 손이 없으면 None을 돌려줍니다.
    def _detect_hand(self, frame) -> list[tuple[float, float]] | None:
        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(
            image_format=mp.ImageFormat.SRGB,
            data=rgb_frame,
        )

        # VIDEO 모드는 프레임마다 증가하는 시각을 요구합니다.
        self.frame_timestamp_ms += int(1000.0 / PROCESS_RATE_HZ)
        result = self.landmarker.detect_for_video(
            mp_image,
            self.frame_timestamp_ms,
        )

        if not result.hand_landmarks:
            return None

        return [
            (point.x, point.y)
            for point in result.hand_landmarks[0]
        ]

    # 손 위치와 펴짐 정도를 로봇 명령으로 옮깁니다.
    def _follow_hand(
        self,
        landmarks: list[tuple[float, float]],
    ) -> None:
        x, y = wrist_position(landmarks)

        self.smoothed_joints = smooth(
            self.smoothed_joints,
            arm_joint_positions(x, y),
            SMOOTHING_FACTOR,
        )

        # 카메라 속도(20Hz)로 그대로 보내면 컨트롤러가 따라오지 못하므로
        # 정해진 간격으로만 팔 명령을 보냅니다.
        self.seconds_since_command += 1.0 / PROCESS_RATE_HZ

        if self.seconds_since_command >= COMMAND_PERIOD_SECONDS:
            self.seconds_since_command = 0.0
            self.motion_controller.move_to(
                self.smoothed_joints,
                COMMAND_DURATION_SECONDS,
            )

        self._update_gripper(pinch_openness(landmarks))

    # 엄지와 검지를 벌린 만큼 그리퍼를 벌립니다.
    # 열림/닫힘 두 단계가 아니라 벌린 정도를 그대로 따라갑니다.
    def _update_gripper(self, openness: float) -> None:
        # 목표가 의미 있게 바뀌었을 때만 보냅니다.
        # 매 프레임 보내면 액션 서버에 목표가 쌓여 반응이 밀립니다.
        if (
            self.gripper_openness is not None
            and abs(openness - self.gripper_openness)
            < GRIPPER_CHANGE_THRESHOLD
        ):
            return

        if not self.gripper_client.server_is_ready():
            self.get_logger().warning(
                "그리퍼 액션 서버를 찾지 못했습니다. "
                "gripper_controller가 실행 중인지 확인하세요.",
                throttle_duration_sec=5.0,
            )
            return

        self.gripper_openness = openness

        goal = GripperCommand.Goal()
        goal.command.position = gripper_position(
            openness,
            GRIPPER_CLOSED_POSITION,
            GRIPPER_OPEN_POSITION,
        )
        goal.command.max_effort = GRIPPER_MAX_EFFORT

        self.gripper_client.send_goal_async(goal)

        self.get_logger().info(
            f"그리퍼 {openness * 100:.0f}% 벌림"
        )

    # 손 관절과 뼈대를 프레임에 그립니다.
    # mediapipe tasks 빌드에는 그리기 도구가 없어 직접 그립니다.
    def _draw_landmarks(
        self,
        frame,
        landmarks: list[tuple[float, float]],
    ) -> None:
        height, width = frame.shape[:2]
        points = [
            (int(x * width), int(y * height))
            for x, y in landmarks
        ]

        for connection in vision.HandLandmarksConnections.HAND_CONNECTIONS:
            cv2.line(
                frame,
                points[connection.start],
                points[connection.end],
                (0, 255, 0),
                2,
            )

        for point in points:
            cv2.circle(frame, point, 4, (0, 0, 255), -1)

    # 그려 넣은 영상을 ROS2 토픽으로 내보냅니다.
    # web_video_server가 이 토픽을 받아 앱 화면에 중계합니다.
    #
    # cv_bridge를 쓰지 않고 메시지를 직접 채웁니다. 이 환경의 cv_bridge는
    # OpenCV 5와 맞지 않아 bgr8 변환에서 KeyError가 납니다. bgr8은 바이트를
    # 그대로 넣으면 되는 단순한 형식이라 직접 만드는 편이 안전합니다.
    def _publish_image(self, frame) -> None:
        height, width = frame.shape[:2]

        message = Image()
        message.header.stamp = self.get_clock().now().to_msg()
        message.header.frame_id = "hand_camera"
        message.height = height
        message.width = width
        message.encoding = "bgr8"
        message.is_bigendian = 0
        message.step = width * 3  # 한 줄의 바이트 수 (BGR 3채널)
        message.data = frame.tobytes()

        self.image_publisher.publish(message)

    # 웹캠과 인식기를 정리합니다.
    def destroy_node(self) -> bool:
        if self.camera is not None:
            self.camera.release()

        if self.landmarker is not None:
            self.landmarker.close()

        return super().destroy_node()


# ROS2를 초기화하고 손 모방 노드를 실행합니다.
def main(args=None) -> None:
    rclpy.init(args=args)

    node = HandMimicNode()

    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        node.get_logger().info("손 모방 노드를 종료합니다.")
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
