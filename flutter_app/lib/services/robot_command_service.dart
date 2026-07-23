import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';


class RobotCommandResult {
  const RobotCommandResult({
    required this.success,
    required this.message,
    this.command,
  });

  final bool success;
  final String message;
  final String? command;
}


// "Micky 깨우기" 결과. 요약 메시지와 함께, 서비스별 실행 상태를 담은
// 복사 가능한 상세 로그(log)를 돌려줍니다. 실패 원인을 화면에서 바로
// 확인하고 복사할 수 있게 하기 위함입니다.
class WakeResult {
  const WakeResult({
    required this.success,
    required this.message,
    required this.log,
  });

  final bool success;
  final String message;
  final String log;
}


// 손 모방에 쓸 수 있는 웹캠 하나. index는 /dev/videoN의 N, name은 사람이 읽을 이름.
class CameraInfo {
  const CameraInfo({required this.index, required this.name});

  final int index;
  final String name;
}


class RobotCommandService {
  RobotCommandService({
    required this.host,
    this.target,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// 명령·영상을 보낼 컴퓨터 주소(브리지 서버가 도는 곳).
  /// 대상(Gazebo 가상 / OMX-AI 실물)마다 다르다.
  final String host;

  /// 어느 대상인지(RobotTarget.name: gazeboLeRobot / omxAi). 깨우기·재우기 때
  /// 브리지가 어느 프로파일(미키=Gazebo / 맥시=실물 follower)을 띄울지 고르는 데
  /// 쓴다. null이면 브리지의 기본 프로파일을 쓴다(하위호환).
  final String? target;

  final http.Client _client;

  // Flutter 앱의 버튼에서 전달된 로봇 명령을 JSON 형식으로 변환하여
  // OMX-AI 브리지 서버의 /robot/command API로 전송합니다.
  // HTTP 상태 코드와 서버 응답을 확인한 뒤 UI에서 사용할 수 있는
  // RobotCommandResult 객체로 결과를 반환합니다.
  Future<RobotCommandResult> sendCommand(
    String command,
  ) async {
    return _post(
      AppConfig.commandEndpoint(host),
      // 대상을 함께 보내 맥시(실물)면 브리지가 lerobot 제어 서버로 넘기게 한다.
      // 미키(가상)는 target이 있어도 ROS2로 발행한다(브리지가 판단).
      {'command': command, if (target != null) 'target': target},
    );
  }

  // 손 모방을 시작하거나 정지합니다.
  // hand_mimic_node가 꺼져 있으면 서버가 실패로 알려줍니다.
  Future<RobotCommandResult> setMimic(
    bool enabled,
  ) async {
    return _post(
      AppConfig.mimicEndpoint(host),
      // 맥시(실물)면 브리지가 lerobot 제어 서버의 손 모방으로 넘긴다.
      {'enabled': enabled, if (target != null) 'target': target},
    );
  }

  // 웹캠을 확보(true)하거나 반환(false)합니다.
  // 실시간 모방 화면에 들어오면 확보, 나가면 반환해 장치를 놓아줍니다.
  Future<RobotCommandResult> setCamera(
    bool enabled,
  ) async {
    return _post(
      AppConfig.cameraEndpoint(host),
      {'enabled': enabled},
    );
  }

  // 그 컴퓨터에 연결된 웹캠 목록을 가져옵니다. 실시간 모방 화면의 카메라
  // 선택 드롭다운을 채우는 데 씁니다. 실패하면 빈 목록을 돌려줍니다.
  Future<List<CameraInfo>> listCameras() async {
    try {
      final response = await _client
          .get(Uri.parse(AppConfig.cameraListEndpoint(host)))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return const [];

      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final cameras = (data['cameras'] as List?) ?? const [];
      return cameras
          .map((entry) => entry as Map<String, dynamic>)
          .map((camera) => CameraInfo(
                index: camera['index'] as int,
                name: camera['name'] as String? ?? '카메라 ${camera['index']}',
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // 손 모방에 쓸 웹캠을 고릅니다. 고른 장치 번호를 hand_mimic_node로 보내
  // 그 카메라로 다시 열게 합니다.
  Future<RobotCommandResult> selectCamera(int index) async {
    return _post(
      AppConfig.cameraSelectEndpoint(host),
      {'index': index},
    );
  }

  // ollama(qwen3:4b)로 5초 춤 동작을 만들어 로봇에 실행시킵니다.
  // 서버가 LLM 생성을 마칠 때까지 기다리므로 수십 초 걸릴 수 있습니다.
  Future<RobotCommandResult> dance() async {
    // 대상을 함께 보내 실물(맥시)이면 브리지가 팔로워(/leader)로 보내고
    // 속도·바닥 안전을 적용하게 한다. 미키(가상)는 기본 그대로.
    return _post(
      AppConfig.danceEndpoint(host),
      {if (target != null) 'target': target},
    );
  }

  // 자율(정책 실행) — 맥시(실물)에서 학습된 정책을 실행한다. command는 사용자가
  // 패널에 입력한 전체 실행 명령(lerobot-record ...). 제어 서버가 팔로워를 넘겨받아
  // 그 명령을 돌리므로 오래 걸릴 수 있다. 서버는 시작만 알리고 바로 응답한다.
  Future<RobotCommandResult> runPolicy(String command) async {
    return _post(
      AppConfig.autonomousEndpoint(host),
      {if (target != null) 'target': target, 'command': command},
    );
  }

  // ollama(qwen3:4b)로 사용자 질문에 대답을 받습니다(자율 화면 대화).
  // 앱은 돌려받은 문장을 TTS로 읽어 줍니다. 로컬 추론이라 몇 초~수십 초 걸릴 수
  // 있습니다. 어떤 경우든 말로 읽어 줄 수 있는 문장을 돌려줍니다.
  Future<String> chat(String message) async {
    try {
      final response = await _client
          .post(
            Uri.parse(AppConfig.chatEndpoint(host)),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'message': message}),
          )
          // qwen3 첫 응답은 모델 로딩 때문에 느릴 수 있어 넉넉히 주되,
          // 무한정 매달리지 않도록 상한을 둔다.
          .timeout(const Duration(seconds: 150));

      final Map<String, dynamic> data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        final reply = (data['reply'] as String? ?? '').trim();
        return reply.isNotEmpty ? reply : '음, 뭐라고 말해야 할지 모르겠어요.';
      }
      return '지금은 대답하기 어려워요. 잠시 뒤에 다시 물어봐 주세요.';
    } on TimeoutException {
      return '미키가 생각하는 데 너무 오래 걸려요. 미키를 깨웠는지, 로봇 컴퓨터가 켜져 있는지 확인해 주세요.';
    } catch (_) {
      return '서버에 연결하지 못했어요. 미키를 깨웠는지 확인해 주세요.';
    }
  }

  // qwen3:4b를 미리 메모리에 올려 두도록 요청합니다(예열). 대화 화면에 들어올 때
  // 부르면 첫 대답이 빨라집니다. 서버는 로딩을 백그라운드로 하고 바로 응답하므로
  // 앱은 기다리지 않습니다. 실패해도 대화는 첫 요청 때 로딩되니 조용히 넘어갑니다.
  Future<void> warmup() async {
    try {
      await _client
          .post(
            Uri.parse(AppConfig.chatWarmupEndpoint(host)),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(const {}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // 예열 실패는 무시한다.
    }
  }

  // "Micky 깨우기" — 로봇을 쓰기 위한 브링업·서비스(Gazebo, 카메라 브리지,
  // 모션 서버, 손 모방 노드, 웹 영상 서버)를 브리지 서버가 한꺼번에
  // 백그라운드로 띄우도록 요청합니다. 서버는 프로세스만 띄우고 바로
  // 응답하므로 앱은 오래 기다리지 않습니다.
  //
  // 서비스별 상태(시작·이미 실행 중·실패)를 여러 줄 로그로 정리해 돌려주어
  // 화면에서 그대로 보여주고 복사할 수 있게 합니다.
  Future<WakeResult> wake() async {
    return _postWake(
      AppConfig.wakeEndpoint(host),
      okMessage: 'Micky를 깨웠습니다.',
      failMessage: '깨우기에 실패했습니다.',
    );
  }

  // "미키 재우기" — 깨우기로 띄운 모든 서비스를 종료하도록 요청합니다.
  Future<WakeResult> sleep() async {
    return _postWake(
      AppConfig.sleepEndpoint(host),
      okMessage: 'Micky를 재웠습니다.',
      failMessage: '재우기에 실패했습니다.',
    );
  }

  // 깨우기/재우기 공통. 서버가 돌려준 서비스별 상태를 여러 줄 로그로 정리해
  // 화면에서 그대로 보여주고 복사할 수 있게 합니다.
  Future<WakeResult> _postWake(
    String endpoint, {
    required String okMessage,
    required String failMessage,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse(endpoint),
        headers: const {
          'Content-Type': 'application/json',
        },
        // 대상을 함께 보내 브리지가 맞는 프로파일(미키/맥시)을 띄우게 한다.
        body: jsonEncode({if (target != null) 'target': target}),
      );

      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        final services = (data['services'] as List?) ?? const [];
        final log = StringBuffer();
        for (final entry in services) {
          final service = entry as Map<String, dynamic>;
          final status = service['status'] as String? ?? '?';
          final label = service['label'] as String? ?? service['name'] ?? '?';
          final pid = service['pid'];
          final detail = service['message'] as String?;
          log.write('[$status] $label');
          if (pid != null) log.write(' (pid $pid)');
          if (detail != null && detail.isNotEmpty) log.write(' — $detail');
          log.writeln();
        }

        return WakeResult(
          success: data['success'] as bool? ?? true,
          message: data['message'] as String? ?? okMessage,
          log: log.toString().trimRight(),
        );
      }

      return WakeResult(
        success: false,
        message: data['detail'] as String? ?? failMessage,
        log: response.body,
      );
    } catch (error) {
      return WakeResult(
        success: false,
        message: '서버 연결 오류',
        log: '$error',
      );
    }
  }

  // 브리지 서버에 JSON을 보내고 결과를 해석하는 공통 부분입니다.
  Future<RobotCommandResult> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _client.post(
        Uri.parse(endpoint),
        headers: const {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      final Map<String, dynamic> responseData =
          jsonDecode(response.body)
              as Map<String, dynamic>;

      if (response.statusCode == 200) {
        // 서버가 200을 주더라도 success가 false일 수 있습니다.
        // 명령을 토픽에 발행은 했지만 받는 노드가 없는 경우가 그렇습니다.
        // 이때 성공으로 처리하면 로봇이 안 움직이는 이유를 알 수 없게 됩니다.
        return RobotCommandResult(
          success: responseData['success'] as bool? ?? true,
          command: responseData['command'] as String?,
          message:
              responseData['message'] as String? ??
              '명령을 전송했습니다.',
        );
      }

      return RobotCommandResult(
        success: false,
        message:
            responseData['detail'] as String? ??
            '명령 전송에 실패했습니다.',
      );
    } catch (error) {
      return RobotCommandResult(
        success: false,
        message: '서버 연결 오류: $error',
      );
    }
  }

  // HTTP 통신에 사용한 Client 객체를 닫아
  // 네트워크 자원을 안전하게 해제합니다.
  void dispose() {
    _client.close();
  }
}