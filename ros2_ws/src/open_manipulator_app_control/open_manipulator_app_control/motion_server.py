import rclpy
from rclpy.node import Node
from std_msgs.msg import String

from open_manipulator_app_control.motion_controller import MotionController


class MotionServer(Node):
    """
    앱이나 다른 ROS2 노드에서 전달한 동작 이름을 받아 OMX-AI를 움직이는 노드입니다.

    /open_manipulator/motion_command 토픽으로 home, ready, left, right, up 같은 문자열이
    들어오면 MotionController의 공통 동작 함수를 호출합니다.
    """

    def __init__(self) -> None:
        super().__init__("open_manipulator_motion_server")

        self.motion_controller = MotionController(self)

        self.command_subscription = self.create_subscription(
            String,
            "/open_manipulator/motion_command",
            self._command_callback,
            10,
        )

        self.get_logger().info("OMX-AI 동작 서버가 시작되었습니다.")

    # 앱 또는 ROS2 토픽에서 받은 문자열 명령을 확인하고,
    # 앞뒤 공백과 대소문자를 정리한 다음 해당 로봇 동작을 실행합니다.
    def _command_callback(self, message: String) -> None:
        motion_name = message.data.strip().lower()

        success = self.motion_controller.execute_motion(motion_name)

        if not success:
            self.get_logger().error(
                f"동작 명령 처리 실패: {motion_name}"
            )


# ROS2를 초기화하고 OMX-AI 동작 서버 노드를 실행합니다.
# 노드가 종료되면 사용한 자원을 정리하고 ROS2를 정상적으로 종료합니다.
def main(args=None) -> None:
    rclpy.init(args=args)

    node = MotionServer()

    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        node.get_logger().info("OMX-AI 동작 서버를 종료합니다.")
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
