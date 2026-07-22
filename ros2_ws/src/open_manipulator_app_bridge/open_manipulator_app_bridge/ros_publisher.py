from threading import Lock
from typing import Any

import rclpy
from rclpy.executors import SingleThreadedExecutor
from rclpy.node import Node
from std_msgs.msg import Bool
from std_msgs.msg import String
from trajectory_msgs.msg import JointTrajectory
from trajectory_msgs.msg import JointTrajectoryPoint

from open_manipulator_app_bridge.config import load_config


# 팔 관절 이름. 궤적 메시지의 positions 순서와 일치해야 합니다.
ARM_JOINT_NAMES = ["joint1", "joint2", "joint3", "joint4"]


class OmxCommandPublisher:
    # Flutter 앱이나 HTTP 서버에서 전달받은 문자열 명령을
    # ROS2 std_msgs/msg/String 메시지로 변환한 뒤
    # OMX-AI 제어 토픽으로 발행하는 Publisher를 초기화합니다.
    # ROS2 노드와 Publisher가 프로그램 전체에서 한 번만 생성되도록
    # 이 클래스에서 공통으로 관리합니다.
    def __init__(self) -> None:
        self._config = load_config()

        ros_config = self._config["ros"]

        if not rclpy.ok():
            rclpy.init()

        self._node: Node = rclpy.create_node(
            ros_config["node_name"]
        )

        self._publisher = self._node.create_publisher(
            String,
            ros_config["command_topic"],
            10,
        )

        # 손 모방 시작/정지. hand_mimic_node가 이 토픽을 듣고 있습니다.
        self._mimic_publisher = self._node.create_publisher(
            Bool,
            ros_config.get(
                "mimic_enable_topic",
                "/open_manipulator/mimic_enable",
            ),
            10,
        )

        # 카메라 확보/반환. 실시간 모방 화면 진입/이탈에 맞춰 hand_mimic_node가
        # 웹캠을 열고 닫도록 신호를 보냅니다.
        self._camera_publisher = self._node.create_publisher(
            Bool,
            ros_config.get(
                "camera_enable_topic",
                "/open_manipulator/camera_enable",
            ),
            10,
        )

        # 춤처럼 여러 자세를 이어 붙인 궤적을 팔 컨트롤러로 바로 보냅니다.
        # 대상마다 팔 궤적 토픽이 다를 수 있어(미키=/arm_controller, 맥시=/leader),
        # 토픽별로 Publisher를 하나씩 만들어 두고 발행 시 대상에 맞는 걸 고릅니다.
        self._default_arm_topic = ros_config.get(
            "arm_command_topic",
            "/arm_controller/joint_trajectory",
        )
        self._arm_topic_by_target = dict(
            ros_config.get("arm_command_topic_by_target", {}) or {}
        )
        self._trajectory_publishers: dict[str, Any] = {}
        for topic in {self._default_arm_topic, *self._arm_topic_by_target.values()}:
            self._trajectory_publishers[topic] = self._node.create_publisher(
                JointTrajectory,
                topic,
                10,
            )

        self._executor = SingleThreadedExecutor()
        self._executor.add_node(self._node)

        self._publish_lock = Lock()

    # 앱에서 전달된 명령 이름을 설정 파일의 실제 ROS2 명령 문자열로
    # 변환하고 /open_manipulator/motion_command 토픽으로 발행합니다.
    # 등록되지 않은 명령은 발행하지 않고 ValueError를 발생시켜
    # 잘못된 로봇 명령이 실행되는 것을 방지합니다.
    #
    # 발행한 명령과 함께 그 토픽의 구독자 수를 돌려줍니다.
    # ROS2 발행은 받는 쪽이 없어도 그냥 성공하기 때문에, 구독자 수를 같이 보지 않으면
    # motion_server가 꺼져 있어도 앱에는 성공으로 보입니다.
    def publish_command(self, command_name: str) -> tuple[str, int]:
        commands = self._config["commands"]

        if command_name not in commands:
            available_commands = ", ".join(commands.keys())

            raise ValueError(
                f"지원하지 않는 명령입니다: {command_name}. "
                f"사용 가능한 명령: {available_commands}"
            )

        ros_command = str(commands[command_name])

        message = String()
        message.data = ros_command

        with self._publish_lock:
            self._publisher.publish(message)
            self._executor.spin_once(timeout_sec=0.05)
            subscriber_count = (
                self._publisher.get_subscription_count()
            )

        if subscriber_count == 0:
            self._node.get_logger().warning(
                f"명령을 발행했지만 받는 노드가 없습니다: {ros_command}. "
                f"motion_server가 실행 중인지 확인하세요."
            )
        else:
            self._node.get_logger().info(
                f"open_manipulator 명령 발행: {ros_command} "
                f"(구독자 {subscriber_count})"
            )

        return ros_command, subscriber_count

    # 손 모방을 시작하거나 정지합니다.
    # 듣고 있는 노드 수를 함께 돌려주어, hand_mimic_node가 꺼져 있는데
    # 앱에는 시작한 것처럼 보이는 일이 없게 합니다.
    def publish_mimic_enable(self, enabled: bool) -> int:
        message = Bool()
        message.data = enabled

        with self._publish_lock:
            self._mimic_publisher.publish(message)
            self._executor.spin_once(timeout_sec=0.05)
            subscriber_count = (
                self._mimic_publisher.get_subscription_count()
            )

        self._node.get_logger().info(
            f"손 모방 {'시작' if enabled else '정지'} "
            f"(구독자 {subscriber_count})"
        )

        return subscriber_count

    # 카메라를 확보(True)하거나 반환(False)합니다.
    # 실시간 모방 화면에 들어오면 True, 나가면 False가 전달됩니다.
    # 듣고 있는 노드 수를 함께 돌려주어, hand_mimic_node가 꺼져 있으면 앱이
    # 알 수 있게 합니다.
    def publish_camera_enable(self, enabled: bool) -> int:
        message = Bool()
        message.data = enabled

        with self._publish_lock:
            self._camera_publisher.publish(message)
            self._executor.spin_once(timeout_sec=0.05)
            subscriber_count = (
                self._camera_publisher.get_subscription_count()
            )

        self._node.get_logger().info(
            f"카메라 {'확보' if enabled else '반환'} "
            f"(구독자 {subscriber_count})"
        )

        return subscriber_count

    # 여러 키프레임(시각 t와 관절 각도)을 하나의 궤적으로 묶어 팔 컨트롤러로
    # 발행합니다. 춤처럼 정해 둘 수 없는 연속 동작을 한 번에 보낼 때 씁니다.
    # target(대상 enum 이름)에 맞는 토픽으로 보냅니다. 없으면 기본 토픽(미키).
    # 듣는 컨트롤러 수를 함께 돌려주어, 받는 쪽이 없으면 앱이 알 수 있게 합니다.
    def publish_trajectory(
        self,
        keyframes: list[dict],
        target: str | None = None,
    ) -> int:
        topic = self._arm_topic_by_target.get(target, self._default_arm_topic)
        publisher = self._trajectory_publishers[topic]

        message = JointTrajectory()
        message.joint_names = ARM_JOINT_NAMES

        for frame in keyframes:
            point = JointTrajectoryPoint()
            point.positions = [float(value) for value in frame["positions"]]

            time_seconds = float(frame["t"])
            point.time_from_start.sec = int(time_seconds)
            point.time_from_start.nanosec = int(
                (time_seconds - int(time_seconds)) * 1e9
            )

            message.points.append(point)

        with self._publish_lock:
            publisher.publish(message)
            self._executor.spin_once(timeout_sec=0.05)
            subscriber_count = publisher.get_subscription_count()

        self._node.get_logger().info(
            f"춤 궤적 발행({topic}): 키프레임 {len(keyframes)}개 "
            f"(구독자 {subscriber_count})"
        )

        return subscriber_count

    # ROS2 Publisher 노드와 Executor를 안전하게 종료하고
    # 프로그램이 종료될 때 사용하던 ROS2 자원을 해제합니다.
    def shutdown(self) -> None:
        self._executor.remove_node(self._node)
        self._node.destroy_node()

        if rclpy.ok():
            rclpy.shutdown()
