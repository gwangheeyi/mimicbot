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
    try {
      final response = await _client.post(
        Uri.parse(
          AppConfig.robotCommandEndpoint,
        ),
        headers: const {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'command': command,
        }),
      );

      final Map<String, dynamic> responseData =
          jsonDecode(response.body)
              as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return RobotCommandResult(
          success: true,
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