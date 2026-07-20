from threading import Lock

import rclpy
from rclpy.executors import SingleThreadedExecutor
from rclpy.node import Node
from std_msgs.msg import Bool
from std_msgs.msg import String

from open_manipulator_app_bridge.config import load_config


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

    # ROS2 Publisher 노드와 Executor를 안전하게 종료하고
    # 프로그램이 종료될 때 사용하던 ROS2 자원을 해제합니다.
    def shutdown(self) -> None:
        self._executor.remove_node(self._node)
        self._node.destroy_node()

        if rclpy.ok():
            rclpy.shutdown()
