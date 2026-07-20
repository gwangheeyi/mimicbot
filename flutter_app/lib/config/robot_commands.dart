class RobotCommands {
  RobotCommands._();

  static const String ready = 'ready';
  static const String home = 'home';
  static const String left = 'left';
  static const String right = 'right';
  static const String up = 'up';
  static const String down = 'down';
  static const String openGripper = 'open_gripper';
  static const String closeGripper = 'close_gripper';
  static const String stop = 'stop';

  /// 동작 감지로 인식할 동작들.
  ///
  /// ROS2 쪽 `robot_config.py`의 `MOTION_POSITIONS`에 관절값이 등록된 동작만 넣는다.
  /// 여기에 없는 동작을 보내면 `motion_controller.py`가 "등록되지 않은 동작입니다"로 거절한다.
  static const List<RobotGesture> gestures = [
    RobotGesture('준비', ready),
    RobotGesture('홈', home),
    RobotGesture('왼쪽', left),
    RobotGesture('오른쪽', right),
    RobotGesture('업', up),
  ];
}

/// 화면에 보이는 한글 이름과, 로봇에 실제로 보내는 명령어의 짝.
class RobotGesture {
  const RobotGesture(this.label, this.command);

  /// 버튼/로그에 쓰는 한글 이름 (예: '왼쪽').
  final String label;

  /// 로봇에 보내는 명령어 (예: 'left').
  final String command;
}