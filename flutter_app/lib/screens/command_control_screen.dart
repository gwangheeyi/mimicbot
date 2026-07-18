import 'package:flutter/material.dart';

import '../services/claude_service.dart';
import '../services/robot_target_scope.dart';
import '../services/tts_service.dart';
import '../widgets/robot_target_badge.dart';

/// 메뉴 1 — 동작 명령.
///
/// 로봇 시점 화면에서 특정 지점을 탭하면 로봇이 그 지점으로 이동하고,
/// "안녕", "경례" 같은 프리셋/텍스트 명령을 주면 로봇이 그 동작을 따라합니다.
class CommandControlScreen extends StatefulWidget {
  const CommandControlScreen({super.key});

  @override
  State<CommandControlScreen> createState() => _CommandControlScreenState();
}

class _CommandControlScreenState extends State<CommandControlScreen> {
  Offset? _target; // 탭한 목표 지점 (스택 로컬 좌표)
  final List<String> _log = [];
  final TextEditingController _commandController = TextEditingController();
  final TtsService _tts = TtsService();

  static const _presets = <_Gesture>[
    _Gesture('안녕', Icons.waving_hand),
    _Gesture('경례', Icons.military_tech),
    _Gesture('악수', Icons.handshake),
    _Gesture('정지', Icons.pan_tool),
  ];

  @override
  void initState() {
    super.initState();
    // 진입 시 인사말.
    _tts.speak('안녕, 나는 ${ClaudeService.robotName}야. 네가 버튼을 누르면 내가 따라해 볼게!');
  }

  void _addLog(String message) {
    if (!mounted) return; // 명령을 보내는 사이 화면을 벗어났을 수 있다.
    setState(() => _log.insert(0, message));
  }

  Future<void> _onTapView(
      TapDownDetails details, BoxConstraints constraints) async {
    final local = details.localPosition;
    setState(() => _target = local);
    // 화면 좌표를 0~100 정규화 좌표로 환산해 로봇에 전달.
    final nx = (local.dx / constraints.maxWidth * 100).clamp(0, 100).round();
    final ny = (local.dy / constraints.maxHeight * 100).clamp(0, 100).round();
    // 홈에서 고른 대상(Gazebo 가상 / OMX-AI 실물)으로 명령이 나간다.
    final backend = RobotTargetScope.of(context).backend;
    _addLog(await backend.moveToPoint(nx, ny));
  }

  Future<void> _sendCommand(String command) async {
    if (command.trim().isEmpty) return;
    final backend = RobotTargetScope.of(context).backend;
    _commandController.clear();
    FocusScope.of(context).unfocus();
    _addLog(await backend.playGesture(command.trim()));
  }

  @override
  void dispose() {
    _commandController.dispose();
    _tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('동작 명령'),
        actions: const [RobotTargetBadge()],
      ),
      body: Column(
        children: [
          // 로봇 시점 뷰 — 탭하면 목표 지점 지정.
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onTapDown: (d) => _onTapView(d, constraints),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Stack(
                        children: [
                          const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.videocam_outlined,
                                    size: 48, color: Colors.white38),
                                SizedBox(height: 8),
                                Text('로봇 시점 화면\n(화면을 탭해 이동 지점을 지정하세요)',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white38)),
                              ],
                            ),
                          ),
                          if (_target != null)
                            Positioned(
                              left: _target!.dx - 16,
                              top: _target!.dy - 16,
                              child: const Icon(Icons.my_location,
                                  size: 32, color: Colors.redAccent),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // 프리셋 동작 명령.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in _presets)
                  ActionChip(
                    avatar: Icon(g.icon, size: 18),
                    label: Text(g.label),
                    onPressed: () => _sendCommand(g.label),
                  ),
              ],
            ),
          ),
          // 자유 텍스트 명령.
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _sendCommand,
                    decoration: const InputDecoration(
                      hintText: '명령 입력 (예: 손 흔들어)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () => _sendCommand(_commandController.text),
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
          // 명령 로그.
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _log.isEmpty
                  ? const Center(
                      child: Text('명령 기록이 여기에 표시됩니다.',
                          style: TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      itemCount: _log.length,
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('• ${_log[i]}'),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Gesture {
  const _Gesture(this.label, this.icon);
  final String label;
  final IconData icon;
}
