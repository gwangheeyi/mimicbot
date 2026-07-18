import 'autonomous_skills.dart';
import 'robot_target.dart';

/// 화면이 로봇에게 시키는 명령들.
///
/// 세 메뉴가 모두 이 인터페이스만 보고 동작하므로, 실행 대상(Gazebo 가상 / OMX-AI 실물)이
/// 바뀌어도 화면 코드는 그대로다. 대상별 구현은 아래 두 클래스에 있다.
///
/// **아직 실제 통신은 하지 않는다.** rosbridge 주소와 양쪽 토픽 이름이 정해지지 않아,
/// 지금은 각 메서드가 "무엇을 보낼지"만 문자열로 돌려주고 화면상으로만 진행한다.
/// 실제 연결은 각 구현의 `// 연결 지점:` 주석 자리에 채우면 되고, 화면은 고치지 않아도 된다.
abstract class RobotBackend {
  const RobotBackend(this.target);

  /// 선택된 대상에 맞는 백엔드를 만든다.
  factory RobotBackend.create(RobotTarget target) => switch (target) {
        RobotTarget.gazeboLeRobot => const GazeboLeRobotBackend(),
        RobotTarget.omxAi => const OmxAiBackend(),
      };

  final RobotTarget target;

  /// 지정한 지점으로 이동. [x], [y]는 화면을 0~100으로 정규화한 좌표.
  Future<String> moveToPoint(int x, int y);

  /// "안녕", "경례" 같은 미리 정의된 동작을 재생.
  Future<String> playGesture(String gesture);

  /// 사람 손동작 따라하기 시작 / 정지.
  Future<String> startMimic();
  Future<String> stopMimic();

  /// 자율행동 [skill]의 [stepIndex]번째 단계를 수행.
  Future<String> runSkillStep(AutonomousSkill skill, int stepIndex);

  /// 진행 중인 동작을 즉시 멈춘다.
  Future<String> stop();

  /// 로그 한 줄 앞에 어느 대상인지 붙인다. 대상이 바뀐 걸 화면에서 바로 알 수 있다.
  String line(String message) => '[${target.label}] $message';
}

/// LeRobot을 Gazebo에서 가상으로 실행하는 백엔드.
///
/// 연결 지점: Gazebo에 띄운 LeRobot의 ROS 인터페이스가 정해지면 각 메서드에서
/// 해당 토픽을 발행하면 된다. 가상이라 하드웨어 안전 제약은 없다.
class GazeboLeRobotBackend extends RobotBackend {
  const GazeboLeRobotBackend() : super(RobotTarget.gazeboLeRobot);

  @override
  Future<String> moveToPoint(int x, int y) async {
    // 연결 지점: Gazebo의 LeRobot에 목표 지점을 발행.
    return line('이동 명령 → 목표 지점 ($x, $y)');
  }

  @override
  Future<String> playGesture(String gesture) async {
    // 연결 지점: LeRobot 동작 프리미티브 재생 요청.
    return line('동작 명령 → "$gesture"');
  }

  @override
  Future<String> startMimic() async {
    // 연결 지점: 손 관절 → LeRobot 관절 리타게팅 스트림 시작.
    return line('실시간 모방 시작 — 가상 로봇이 따라합니다');
  }

  @override
  Future<String> stopMimic() async {
    // 연결 지점: 리타게팅 스트림 정지.
    return line('실시간 모방 정지');
  }

  @override
  Future<String> runSkillStep(AutonomousSkill skill, int stepIndex) async {
    // 연결 지점: 이 단계에 해당하는 LeRobot 스킬/궤적 실행.
    return line('${skill.name} — ${skill.steps[stepIndex]}');
  }

  @override
  Future<String> stop() async {
    // 연결 지점: 현재 목표 취소.
    return line('정지');
  }
}

/// Robotis OMX-AI 실제 로봇으로 시연하는 백엔드.
///
/// 연결 지점: OMX-AI의 ROS 인터페이스가 정해지면 각 메서드에서 해당 토픽을 발행하면 된다.
/// 가상과 달리 실제로 팔이 움직이므로, 실제 통신을 붙일 때는 속도 제한과 비상 정지를
/// 여기서 함께 처리하는 것이 좋다.
class OmxAiBackend extends RobotBackend {
  const OmxAiBackend() : super(RobotTarget.omxAi);

  @override
  Future<String> moveToPoint(int x, int y) async {
    // 연결 지점: OMX-AI에 목표 지점을 발행.
    return line('이동 명령 → 목표 지점 ($x, $y)');
  }

  @override
  Future<String> playGesture(String gesture) async {
    // 연결 지점: OMX-AI 동작 프리미티브 재생 요청.
    return line('동작 명령 → "$gesture"');
  }

  @override
  Future<String> startMimic() async {
    // 연결 지점: 손 관절 → OMX-AI 관절 리타게팅 스트림 시작.
    return line('실시간 모방 시작 — 실제 로봇이 따라합니다');
  }

  @override
  Future<String> stopMimic() async {
    // 연결 지점: 리타게팅 스트림 정지.
    return line('실시간 모방 정지');
  }

  @override
  Future<String> runSkillStep(AutonomousSkill skill, int stepIndex) async {
    // 연결 지점: 이 단계에 해당하는 OMX-AI 스킬/궤적 실행.
    return line('${skill.name} — ${skill.steps[stepIndex]}');
  }

  @override
  Future<String> stop() async {
    // 연결 지점: 현재 궤적 취소 (실물이므로 즉시 멈춰야 한다).
    return line('정지');
  }
}
