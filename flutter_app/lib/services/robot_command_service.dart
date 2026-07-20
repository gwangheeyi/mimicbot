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


class RobotCommandService {
  RobotCommandService({
    http.Client? client,
  }) : _client = client ?? http.Client();

  final http.Client _client;

  // Flutter 앱의 버튼에서 전달된 로봇 명령을 JSON 형식으로 변환하여
  // OMX-AI 브리지 서버의 /robot/command API로 전송합니다.
  // HTTP 상태 코드와 서버 응답을 확인한 뒤 UI에서 사용할 수 있는
  // RobotCommandResult 객체로 결과를 반환합니다.
  Future<RobotCommandResult> sendCommand(
    String command,
  ) async {
    return _post(
      AppConfig.robotCommandEndpoint,
      {'command': command},
    );
  }

  // 손 모방을 시작하거나 정지합니다.
  // hand_mimic_node가 꺼져 있으면 서버가 실패로 알려줍니다.
  Future<RobotCommandResult> setMimic(
    bool enabled,
  ) async {
    return _post(
      AppConfig.mimicEndpoint,
      {'enabled': enabled},
    );
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