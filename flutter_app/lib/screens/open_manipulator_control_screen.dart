import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../config/robot_commands.dart';
import '../services/robot_command_service.dart';


class OmxControlScreen extends StatefulWidget {
  const OmxControlScreen({
    super.key,
  });

  @override
  State<OmxControlScreen> createState() =>
      _OmxControlScreenState();
}


class _OmxControlScreenState
    extends State<OmxControlScreen> {
  final RobotCommandService _commandService =
      RobotCommandService(host: AppConfig.omxAiHost);

  bool _isSending = false;
  String _statusMessage = '명령 대기 중';

  // 사용자가 누른 버튼의 로봇 명령을 공통 서비스 함수에 전달하고
  // 서버 응답 결과를 화면 아래 상태 메시지로 표시합니다.
  // 명령 전송 중에는 중복 클릭을 방지하기 위해 버튼을 비활성화합니다.
  Future<void> _sendCommand(
    String command,
  ) async {
    if (_isSending) {
      return;
    }

    setState(() {
      _isSending = true;
      _statusMessage = '$command 명령 전송 중...';
    });

    final result = await _commandService.sendCommand(
      command,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSending = false;
      _statusMessage = result.message;
    });
  }

  // 버튼에 표시할 문자와 실제로 전송할 로봇 명령을 받아
  // 모든 OMX-AI 제어 버튼이 동일한 디자인과 동작을 사용하도록
  // 공통 ElevatedButton 위젯을 생성합니다.
  Widget _buildCommandButton({
    required String label,
    required String command,
    IconData? icon,
  }) {
    return SizedBox(
      width: 155,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _isSending
            ? null
            : () => _sendCommand(command),
        icon: Icon(
          icon ?? Icons.smart_toy,
        ),
        label: Text(label),
      ),
    );
  }

  @override
  void dispose() {
    _commandService.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OMX-AI 제어'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  _buildCommandButton(
                    label: '준비 자세',
                    command: RobotCommands.ready,
                    icon: Icons.accessibility_new,
                  ),
                  _buildCommandButton(
                    label: '홈 위치',
                    command: RobotCommands.home,
                    icon: Icons.home,
                  ),
                  _buildCommandButton(
                    label: '왼쪽 이동',
                    command: RobotCommands.left,
                    icon: Icons.arrow_back,
                  ),
                  _buildCommandButton(
                    label: '오른쪽 이동',
                    command: RobotCommands.right,
                    icon: Icons.arrow_forward,
                  ),
                  _buildCommandButton(
                    label: '위로 이동',
                    command: RobotCommands.up,
                    icon: Icons.arrow_upward,
                  ),
                  _buildCommandButton(
                    label: '아래로 이동',
                    command: RobotCommands.down,
                    icon: Icons.arrow_downward,
                  ),
                  _buildCommandButton(
                    label: '그리퍼 열기',
                    command:
                        RobotCommands.openGripper,
                    icon: Icons.open_in_full,
                  ),
                  _buildCommandButton(
                    label: '그리퍼 닫기',
                    command:
                        RobotCommands.closeGripper,
                    icon: Icons.close_fullscreen,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: () => _sendCommand(
                    RobotCommands.stop,
                  ),
                  icon: const Icon(
                    Icons.stop_circle,
                    size: 32,
                  ),
                  label: const Text(
                    '긴급 정지',
                    style: TextStyle(
                      fontSize: 18,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_isSending)
                const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}