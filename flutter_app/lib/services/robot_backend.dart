import '../config/robot_commands.dart';
import 'autonomous_skills.dart';
import 'robot_command_service.dart';
import 'robot_target.dart';

/// 화면이 로봇에게 시키는 명령들.
///
/// 세 메뉴가 모두 이 인터페이스만 보고 동작하므로, 실행 대상(Gazebo 가상 / OMX-AI 실물)이
/// 바뀌어도 화면 코드는 그대로다. 대상별 구현은 아래 두 클래스에 있다.
///
/// [playGesture]·[startMimic]·[stopMimic]·[dance]는 **실제로 로봇에 나간다** — 두 대상
/// 모두 각자의 브리지 서버(미키=로컬, 맥시=설정한 IP)로 명령을 보낸다. 목적지는 매번
/// [RobotTarget.host]를 읽어 정하므로, 시연 중 맥시 IP를 바꿔도 다음 명령부터 그 주소로
/// 나간다. 즉 OMX-AI 실물을 고르면 같은 명령이 실물 로봇 컴퓨터로 가서 실제로 팔이
/// 움직인다. [moveToPoint]·[runSkillStep]·[stop]은 아직 화면상으로만 진행하며, 실제
/// 연결은 각 구현의 `// 연결 지점:` 주석 자리에 채우면 된다.
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

  /// 미리 정의된 동작을 재생. [gesture]는 `RobotCommands.gestures`의 명령어.
  Future<String> playGesture(String gesture);

  /// 사람 손동작 따라하기 시작 / 정지.
  Future<String> startMimic();
  Future<String> stopMimic();

  /// 조용히(부드럽게) 리더 위치로 가서 대기한다.
  /// 실물(맥시)은 리더-팔로워라 리더 자세로 이동해 teleop로 대기하고,
  /// 가상(미키)은 리더가 없어 준비 자세로 되돌린다.
  Future<String> restToLeader();

  /// 학습된 정책(모방학습)을 실행한다. [command]는 전체 실행 명령(lerobot-record ...).
  /// 실물(맥시)만 지원 — 팔로워가 그 명령으로 스스로 작업을 수행한다.
  Future<String> runPolicy(String command);

  /// ollama(qwen3:4b)로 5초 춤 동작을 만들어 실행한다.
  Future<String> dance();

  /// 자율행동 [skill]의 [stepIndex]번째 단계를 수행.
  Future<String> runSkillStep(AutonomousSkill skill, int stepIndex);

  /// 진행 중인 동작을 즉시 멈춘다.
  Future<String> stop();

  /// 로그 한 줄 앞에 어느 대상인지 붙인다. 대상이 바뀐 걸 화면에서 바로 알 수 있다.
  String line(String message) => '[${target.label}] $message';

  /// 현재 대상 host로 브리지에 붙는 통로를 만들어 [action]을 실행하고 정리한다.
  ///
  /// host를 그때그때 읽으므로, 시연 중 맥시 IP를 바꿔도 다음 명령부터 바로
  /// 그 주소로 나간다(백엔드를 다시 만들 필요가 없다).
  Future<T> withService<T>(
    Future<T> Function(RobotCommandService service) action,
  ) async {
    final service =
        RobotCommandService(host: target.host, target: target.name);
    try {
      return await action(service);
    } finally {
      service.dispose();
    }
  }
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
  Future<String> playGesture(String gesture) => withService((service) async {
        // 앱 → 브리지 서버(/robot/command) → /open_manipulator/motion_command
        // → motion_server → /arm_controller/joint_trajectory → Gazebo.
        final result = await service.sendCommand(gesture);
        if (!result.success) {
          return line('동작 명령 실패 "$gesture" — ${result.message}');
        }
        return line('동작 명령 → "${result.command ?? gesture}"');
      });

  @override
  Future<String> startMimic() => withService((service) async {
        // 브리지 서버 → /open_manipulator/mimic_enable → hand_mimic_node.
        // 노드가 웹캠에서 손을 찾아 팔과 그리퍼를 직접 움직인다.
        final result = await service.setMimic(true);
        if (!result.success) {
          return line('실시간 모방 시작 실패 — ${result.message}');
        }
        return line('실시간 모방 시작 — 가상 로봇이 따라합니다');
      });

  @override
  Future<String> stopMimic() => withService((service) async {
        final result = await service.setMimic(false);
        if (!result.success) {
          return line('실시간 모방 정지 실패 — ${result.message}');
        }
        return line('실시간 모방 정지');
      });

  @override
  Future<String> restToLeader() =>
      // 가상은 리더가 없으므로 준비 자세로 되돌린다.
      playGesture(RobotCommands.ready);

  @override
  Future<String> runPolicy(String command) async =>
      // 가상은 학습된 정책 실행을 지원하지 않는다(lerobot 실물 전용).
      line('자율(정책 실행)은 실물(맥시)에서만 됩니다.');

  @override
  Future<String> dance() => withService((service) async {
        // 브리지 서버가 ollama로 춤을 만들어 Gazebo 로봇에 실행시킨다.
        final result = await service.dance();
        return line(result.message);
      });

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
/// 명령은 실제 로봇이 연결된 다른 컴퓨터(AppConfig.omxAiHost)의 브리지 서버로
/// 나간다. 통신 경로는 Gazebo 가상과 같고 목적지 컴퓨터만 다르다.
/// 가상과 달리 실제로 팔이 움직이므로, 시작 전에 주변 안전을 먼저 확인해야 한다.
class OmxAiBackend extends RobotBackend {
  const OmxAiBackend() : super(RobotTarget.omxAi);

  @override
  Future<String> moveToPoint(int x, int y) async {
    // 연결 지점: OMX-AI에 목표 지점을 발행.
    return line('이동 명령 → 목표 지점 ($x, $y)');
  }

  @override
  Future<String> playGesture(String gesture) => withService((service) async {
        // 앱 → 맥시(실물 로봇 컴퓨터)의 브리지 서버(/robot/command) → 로봇.
        final result = await service.sendCommand(gesture);
        if (!result.success) {
          return line('동작 명령 실패 "$gesture" — ${result.message}');
        }
        return line('동작 명령 → "${result.command ?? gesture}"');
      });

  @override
  Future<String> startMimic() => withService((service) async {
        final result = await service.setMimic(true);
        if (!result.success) {
          return line('실시간 모방 시작 실패 — ${result.message}');
        }
        return line('실시간 모방 시작 — 실제 로봇이 따라합니다');
      });

  @override
  Future<String> stopMimic() => withService((service) async {
        final result = await service.setMimic(false);
        if (!result.success) {
          return line('실시간 모방 정지 실패 — ${result.message}');
        }
        return line('실시간 모방 정지');
      });

  @override
  Future<String> restToLeader() => withService((service) async {
        // 특수 명령 "leader" — 제어 서버가 팔로워를 리더 위치로 조용히 옮긴 뒤
        // teleop(리더 추종)으로 대기시킨다.
        final result = await service.sendCommand('leader');
        if (!result.success) {
          return line('리더 위치로 대기 실패 — ${result.message}');
        }
        return line('리더 위치로 이동해 대기합니다');
      });

  @override
  Future<String> runPolicy(String command) => withService((service) async {
        // 제어 서버가 팔로워를 넘겨받아 그 명령(lerobot-record)을 실행한다.
        final result = await service.runPolicy(command);
        if (!result.success) {
          return line('자율(정책 실행) 실패 — ${result.message}');
        }
        return line(result.message);
      });

  @override
  Future<String> dance() => withService((service) async {
        // 브리지 서버가 ollama로 춤을 만들어 실제 로봇에 실행시킨다.
        final result = await service.dance();
        return line(result.message);
      });

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
