from threading import Lock

import rclpy
from rclpy.executors import SingleThreadedExecutor
from rclpy.node import Node
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

        self._executor = SingleThreadedExecutor()
        self._executor.add_node(self._node)

        self._publish_lock = Lock()

    # 앱에서 전달된 명령 이름을 설정 파일의 실제 ROS2 명령 문자열로
    # 변환하고 /open_manipulator/motion_command 토픽으로 발행합니다.
    # 등록되지 않은 명령은 발행하지 않고 ValueError를 발생시켜
    # 잘못된 로봇 명령이 실행되는 것을 방지합니다.
    def publish_command(self, command_name: str) -> str:
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

        self._node.get_logger().info(
            f"open_manipulator 명령 발행: {ros_command}"
        )

        return ros_command

    # ROS2 Publisher 노드와 Executor를 안전하게 종료하고
    # 프로그램이 종료될 때 사용하던 ROS2 자원을 해제합니다.
    def shutdown(self) -> None:
        self._executor.remove_node(self._node)
        self._node.destroy_node()

        if rclpy.ok():
            rclpy.shutdown()
