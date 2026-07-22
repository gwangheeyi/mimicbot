import 'package:flutter/material.dart';

import '../config/robot_commands.dart';
import '../services/robot_backend.dart';
import '../services/robot_target_scope.dart';
import '../services/tts_service.dart';
import '../widgets/command_log_panel.dart';
import '../widgets/robot_camera_view.dart';
import '../widgets/robot_target_badge.dart';

/// 메뉴 1 — 동작 명령.
///
/// 로봇 시점 화면에서 특정 지점을 탭하면 로봇이 그 지점으로 이동하고,
/// "준비", "왼쪽" 같은 프리셋/텍스트 명령을 주면 로봇이 그 동작을 따라합니다.
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

  /// 프리셋 버튼에 붙일 아이콘. 동작 목록 자체는 [RobotCommands.gestures]가 갖고 있다.
  static const _icons = <String, IconData>{
    RobotCommands.ready: Icons.accessibility_new,
    RobotCommands.home: Icons.home_outlined,
    RobotCommands.left: Icons.arrow_back,
    RobotCommands.right: Icons.arrow_forward,
    RobotCommands.up: Icons.arrow_upward,
    RobotCommands.attention: Icons.straighten,
    RobotCommands.salute: Icons.back_hand,
  };

  /// 진입 시 손 모방을 한 번 껐는지. 화면당 한 번이면 충분하다.
  bool _mimicStopped = false;

  /// 진입 인사말. 지금 고른 대상의 이름(미키/맥시)으로 자기소개한다.
  /// 맥시로 테스트하면 "안녕, 나는 맥시야 …" 로 인사한다.
  String _greeting(BuildContext context) =>
      '안녕, 나는 ${RobotTargetScope.of(context).value.robotName}야. '
      '네가 버튼을 누르면 내가 따라해 볼게!';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mimicStopped) return;
    _mimicStopped = true;

    // 진입 시 인사말(대상 이름 반영). context가 준비된 이 시점에 말한다.
    _tts.speak(_greeting(context));
    _resetToReady(RobotTargetScope.of(context).backend);
  }

  /// 진입할 때 로봇을 알려진 자세로 맞춘다.
  ///
  /// 손 모방이 돌고 있으면 이 화면의 명령과 같은 토픽을 두고 다툰다. 메뉴 2를
  /// 정상적으로 빠져나왔다면 이미 꺼져 있지만, 앱이 강제로 종료된 뒤라면 노드만
  /// 켜진 채 남아 있을 수 있어 진입할 때 한 번 확실히 끄고 준비 자세로 되돌린다.
  ///
  /// 멈추기 전에 자세 명령을 보내면 노드가 그 뒤에 보낸 명령이 덮어쓰므로
  /// 정지 응답을 받은 뒤에 이어 보낸다.
  Future<void> _resetToReady(RobotBackend backend) async {
    await backend.stopMimic();
    // 로봇이 실제로 움직이는 일이니 기록에 남긴다.
    _addLog(await backend.playGesture(RobotCommands.ready));
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
        actions: [
          // 브라우저는 사용자가 누르기 전에는 소리를 막기도 한다.
          // 이 버튼은 확실한 사용자 동작이라 그 경우에도 소리가 난다.
          IconButton(
            onPressed: () => _tts.speak(_greeting(context)),
            icon: const Icon(Icons.volume_up),
            tooltip: '인사말 다시 듣기',
          ),
          const RobotTargetBadge(),
        ],
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
                      // 잘린 모서리 밖으로 영상이 삐져나오지 않게 한다.
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // 로봇 시점 카메라. 맥시(실물)=mediamtx WebRTC,
                          // 미키(가상)=Gazebo web_video MJPEG.
                          RobotCameraView(
                            target: RobotTargetScope.of(context).value,
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
                for (final g in RobotCommands.gestures)
                  ActionChip(
                    avatar: Icon(_icons[g.command], size: 18),
                    label: Text(g.label),
                    // 로봇에는 한글 이름이 아니라 등록된 명령어를 보낸다.
                    onPressed: () => _sendCommand(g.command),
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
                      hintText: '명령 입력 (예: 왼쪽)',
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
              child: CommandLogPanel(log: _log),
            ),
          ),
        ],
      ),
    );
  }
}
