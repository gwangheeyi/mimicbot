import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../config/robot_commands.dart';
import '../services/robot_backend.dart';
import '../services/robot_target_scope.dart';
import '../services/tts_service.dart';
import '../widgets/camera_stream_view.dart';
import '../widgets/command_log_panel.dart';
import '../widgets/robot_target_badge.dart';
import '../widgets/zoomable_stream_view.dart';

/// 메뉴 2 — 실시간 모방.
///
/// 화면이 상/하로 나뉩니다.
/// 위: 손 관절을 찾아 표시한 영상, 아래: 그 손을 따라 하는 Gazebo 로봇.
///
/// 손 인식은 앱이 아니라 ROS2의 `hand_mimic_node`가 합니다. 그 노드가 웹캠을 직접
/// 열어 mediapipe로 손을 찾고, 팔과 그리퍼를 움직이면서 관절을 그려 넣은 영상을
/// ROS 토픽으로 내보냅니다. 앱은 그 영상을 받아 보여주고 시작/정지만 시킵니다.
/// 웹캠은 한 번에 한 프로그램만 열 수 있어, 앱이 카메라를 직접 잡으면 노드가
/// 열지 못합니다.
class MimicViewScreen extends StatefulWidget {
  const MimicViewScreen({super.key});

  @override
  State<MimicViewScreen> createState() => _MimicViewScreenState();
}

class _MimicViewScreenState extends State<MimicViewScreen> {
  bool _mimicking = false;

  /// 로봇 백엔드가 돌려준 상태 기록. 최신이 앞에 온다.
  ///
  /// 시작/정지가 왜 실패했는지는 이 기록에만 남으므로 복사해 갈 수 있어야 한다.
  final List<String> _log = [];

  /// 시작/정지 요청이 오가는 동안 버튼을 잠가 두 번 눌리지 않게 한다.
  bool _busy = false;

  final TtsService _tts = TtsService();

  /// 지금 명령을 보내는 백엔드.
  ///
  /// dispose에서는 context를 쓸 수 없으므로(위젯이 이미 트리에서 빠진 뒤다)
  /// 미리 들고 있다가 화면을 떠날 때 이걸로 모방을 끈다.
  RobotBackend? _backend;

  static const String _greeting = '안녕 친구야. 내가 너의 행동을 따라 해 볼게!';

  @override
  void initState() {
    super.initState();
    // 진입 시 인사말.
    _tts.speak(_greeting);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final backend = RobotTargetScope.of(context).backend;
    if (identical(backend, _backend)) return;

    // 화면을 보는 도중 실행 대상을 바꾸면(가상 ↔ 실물) 백엔드가 교체된다.
    // 이전 대상이 계속 따라 하고 있으면 안 되므로 멈추고 준비 자세로 되돌린다.
    final previous = _backend;
    previous?.stopMimic().then((_) {
      previous.playGesture(RobotCommands.ready);
    });
    _backend = backend;
    if (_mimicking) setState(() => _mimicking = false);
  }

  /// 모방 시작/정지. 홈에서 고른 대상(Gazebo 가상 / OMX-AI 실물)이 따라한다.
  Future<void> _toggle() async {
    if (_busy) return;
    final backend = _backend;
    if (backend == null) return;
    final next = !_mimicking;
    setState(() => _busy = true);

    final status = next ? await backend.startMimic() : await backend.stopMimic();
    if (!mounted) return;
    setState(() {
      // 노드가 꺼져 있으면 시작에 실패한다. 그때는 켜진 것처럼 보이면 안 된다.
      _mimicking = status.contains('실패') ? _mimicking : next;
      _log.insert(0, status);
      _busy = false;
    });
  }

  @override
  void dispose() {
    // 이 화면을 떠나면 모방도 끝나야 한다. 그대로 두면 손 인식 노드가 계속
    // 팔을 움직여서, 메뉴 1의 동작 명령과 같은 토픽을 두고 다투게 된다.
    // 멈춘 뒤에는 손을 따라가다 멈춘 어정쩡한 자세 대신 준비 자세로 되돌린다.
    //
    // 순서가 중요하다. 두 요청을 한꺼번에 보내면 준비 자세가 먼저 도착하고
    // 노드가 그 뒤에 보낸 명령이 덮어쓸 수 있다. 정지 응답을 받은 뒤에 이어 보낸다.
    // 화면은 이미 사라진 뒤라 결과를 보여줄 곳이 없으므로 기다리지 않는다.
    final backend = _backend;
    backend?.stopMimic().then((_) {
      backend.playGesture(RobotCommands.ready);
    });
    _tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('실시간 모방'),
        actions: [
          // 브라우저는 사용자가 누르기 전에는 소리를 막기도 한다.
          // 이 버튼은 확실한 사용자 동작이라 그 경우에도 소리가 난다.
          IconButton(
            onPressed: () => _tts.speak(_greeting),
            icon: const Icon(Icons.volume_up),
            tooltip: '인사말 다시 듣기',
          ),
          const RobotTargetBadge(),
        ],
      ),
      body: Column(
        children: [
          // 위: 손 인식 영상 — hand_mimic_node가 관절을 그려 보낸다.
          Expanded(
            child: _StreamPane(
              streamUrl: AppConfig.handCameraStreamUrl,
              badge: '내 손동작 (인식 중)',
              badgeColor: Colors.teal,
              active: _mimicking,
              statusText: _mimicking ? '동작 인식 중…' : '대기 중',
              zoomable: true,
            ),
          ),
          const Divider(height: 2, thickness: 2),
          // 아래: Gazebo 로봇 — 위의 손을 따라 움직인다.
          Expanded(
            child: _StreamPane(
              streamUrl: AppConfig.cameraStreamUrl,
              badge: '로봇 모방',
              badgeColor: Colors.deepPurple,
              active: _mimicking,
              // 백엔드가 알려준 마지막 상태. 아직 시작 전이면 대기 중.
              statusText: _log.isEmpty ? '대기 중' : _log.first,
              zoomable: false,
              log: _log,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _toggle,
        icon: Icon(_mimicking ? Icons.stop : Icons.play_arrow),
        label: Text(_mimicking ? '모방 정지' : '모방 시작'),
        backgroundColor: _mimicking ? Colors.red : null,
      ),
    );
  }
}

/// 영상 한 칸: 스트림 위에 라벨과 상태를 얹는다.
class _StreamPane extends StatelessWidget {
  const _StreamPane({
    required this.streamUrl,
    required this.badge,
    required this.badgeColor,
    required this.active,
    required this.statusText,
    required this.zoomable,
    this.log,
  });

  final String streamUrl;
  final String badge;
  final Color badgeColor;
  final bool active;
  final String statusText;

  /// 줌 슬라이더를 붙일지. 손 인식 화면만 붙인다.
  final bool zoomable;

  /// 왼쪽에 겹쳐 보여줄 명령 기록. null이면 그리지 않는다.
  final List<String>? log;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (zoomable)
            ZoomableStreamView(streamUrl: streamUrl)
          else
            CameraStreamView(streamUrl: streamUrl),
          Positioned(
            top: 12,
            left: 12,
            child: _Badge(text: badge, color: badgeColor),
          ),
          // 왼쪽에 겹쳐 놓는 명령 기록. 기록이 있을 때만 그려 영상을 가리지 않는다.
          if (log != null && log!.isNotEmpty)
            Positioned(
              left: 12,
              top: 44,
              bottom: 40,
              width: 260,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: CommandLogPanel(log: log!, compact: true),
              ),
            ),
          Positioned(
            bottom: 12,
            left: 12,
            child: Row(
              children: [
                Icon(active ? Icons.circle : Icons.circle_outlined,
                    size: 12,
                    color: active ? Colors.greenAccent : Colors.white38),
                const SizedBox(width: 6),
                Text(statusText,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
