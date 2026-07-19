from rclpy.node import Node
from trajectory_msgs.msg import JointTrajectory
from trajectory_msgs.msg import JointTrajectoryPoint

from open_manipulator_app_control.robot_config import (
    ARM_COMMAND_TOPIC,
    ARM_JOINT_NAMES,
    MOTION_DURATION_SECONDS,
    MOTION_POSITIONS,
)


class MotionController:
    """
    OMX-AI 로봇팔의 동작 명령을 생성하고 발행하는 공통 클래스입니다.

    여러 버튼이나 서버 기능에서 관절 메시지 생성 코드를 반복하지 않도록
    JointTrajectory 메시지 생성과 발행 기능을 이 클래스에서 공통으로 처리합니다.
    """

    def __init__(self, node: Node) -> None:
        self.node = node

        self.publisher = node.create_publisher(
            JointTrajectory,
            ARM_COMMAND_TOPIC,
            10,
        )

    # 지정된 동작 이름에 해당하는 관절 위치를 찾아 로봇팔 제어 토픽으로 발행합니다.
    # home, ready, left, right, up 등의 동작 이름을 전달받으며,
    # 등록되지 않은 동작 이름이 들어오면 False를 반환하여 잘못된 명령을 구분합니다.
    def execute_motion(self, motion_name: str) -> bool:
        positions = MOTION_POSITIONS.get(motion_name)

        if positions is None:
            self.node.get_logger().warning(
                f"등록되지 않은 동작입니다: {motion_name}"
            )
            return False

        trajectory_message = self._create_trajectory_message(positions)
        self.publisher.publish(trajectory_message)

        self.node.get_logger().info(
            f"OMX-AI 동작 명령 발행: {motion_name}"
        )

        return True

    # 전달받은 관절 목표 위치를 ROS2 JointTrajectory 메시지로 변환합니다.
    # 관절 이름 순서와 positions 값의 순서는 반드시 서로 일치해야 하며,
    # time_from_start는 로봇팔이 목표 자세까지 이동하는 시간을 의미합니다.
    def _create_trajectory_message(
        self,
        positions: list[float],
    ) -> JointTrajectory:
        message = JointTrajectory()
        message.joint_names = ARM_JOINT_NAMES

        point = JointTrajectoryPoint()
        point.positions = positions
        point.time_from_start.sec = MOTION_DURATION_SECONDS
        point.time_from_start.nanosec = 0

        message.points.append(point)

        return message
