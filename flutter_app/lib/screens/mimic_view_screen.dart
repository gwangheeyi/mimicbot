import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/robot_backend.dart';
import '../services/robot_command_service.dart';
import '../services/robot_target_scope.dart';
import '../services/tts_service.dart';
import '../widgets/camera_stream_view.dart';
import '../widgets/command_log_panel.dart';
import '../widgets/robot_camera_view.dart';
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

  /// 현재 대상 컴퓨터의 카메라 확보/반환 통로.
  ///
  /// 이 화면에 들어오면 웹캠을 확보하고, 나갈 때 반환한다. 화면을 안 볼 때는
  /// hand_mimic_node가 웹캠을 잡지 않아 다른 프로그램이 쓸 수 있다.
  RobotCommandService? _cameraControl;

  /// 이 컴퓨터에 붙은 웹캠 목록. 미키(가상)에서만 채운다 — 맥시(실물)는 카메라를
  /// lerobot 제어 서버가 잡으므로 앱에서 고르지 않는다.
  List<CameraInfo> _cameras = const [];

  /// 지금 고른 웹캠 장치 번호(/dev/videoN의 N). 아직 안 골랐으면 null.
  int? _selectedCameraIndex;

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
    final target = RobotTargetScope.of(context).value;
    final backend = RobotTargetScope.of(context).backend;
    if (identical(backend, _backend)) return;

    // 화면을 보는 도중 실행 대상을 바꾸면(가상 ↔ 실물) 백엔드가 교체된다.
    // 이전 대상이 계속 따라 하고 있으면 안 되므로 멈추고 쉼 자세로 되돌린다.
    // 실물(맥시)은 조용히 리더 위치로 가서 대기, 가상은 준비 자세. 카메라도 반환.
    final previous = _backend;
    previous?.stopMimic().then((_) => previous.restToLeader());
    final previousCamera = _cameraControl;
    previousCamera?.setCamera(false).then((_) => previousCamera.dispose());

    _backend = backend;
    if (_mimicking) setState(() => _mimicking = false);

    if (target.isPhysical) {
      // 맥시(실물): 들어오면 조용히 리더 위치로 가서 대기한다(자동 시작 안 함).
      // 손 모방은 "모방 시작" 버튼으로 켠다. 웹캠은 그때 제어 서버가 잡는다.
      _cameraControl = null;
      _cameras = const [];
      _selectedCameraIndex = null;
      backend.restToLeader();
    } else {
      // 미키(가상): 웹캠을 확보한 뒤 모방을 자동으로 켠다.
      _cameraControl = RobotCommandService(host: target.host);
      _cameraControl!.setCamera(true).then((_) => _autoStartMimic());
      // 붙어 있는 카메라 목록을 받아 선택 메뉴를 채운다.
      _loadCameras();
    }
  }

  /// 미키(가상) 컴퓨터에 붙은 웹캠 목록을 받아 선택 메뉴를 채운다.
  /// 아직 고른 게 없으면 노드 기본값(0번)에 맞춰 초기 선택을 잡는다.
  Future<void> _loadCameras() async {
    final control = _cameraControl;
    if (control == null) return;
    final cameras = await control.listCameras();
    if (!mounted || !identical(control, _cameraControl)) return;
    setState(() {
      _cameras = cameras;
      if (_selectedCameraIndex == null && cameras.isNotEmpty) {
        _selectedCameraIndex =
            cameras.any((c) => c.index == 0) ? 0 : cameras.first.index;
      }
    });
  }

  /// 손 모방에 쓸 웹캠을 바꾼다. 고른 번호를 hand_mimic_node로 보내 그 카메라로
  /// 다시 열게 하고, 결과를 화면 기록에 남긴다.
  Future<void> _selectCamera(int index) async {
    final control = _cameraControl;
    if (control == null || index == _selectedCameraIndex) return;
    setState(() => _selectedCameraIndex = index);
    final result = await control.selectCamera(index);
    if (!mounted) return;
    setState(() => _log.insert(0, result.message));
  }

  /// 모방 시작/정지 버튼. 홈에서 고른 대상(Gazebo 가상 / OMX-AI 실물)이 따라한다.
  Future<void> _toggle() => _setMimic(!_mimicking);

  /// 모방을 [on] 상태로 맞춘다. 이미 그 상태면 아무것도 하지 않는다.
  /// 버튼과 화면 진입 시 자동 시작이 함께 쓴다.
  Future<void> _setMimic(bool on) async {
    if (_busy || on == _mimicking) return;
    final backend = _backend;
    if (backend == null) return;
    setState(() => _busy = true);

    final status = on ? await backend.startMimic() : await backend.stopMimic();
    if (!mounted) return;
    setState(() {
      // 노드가 꺼져 있으면 시작에 실패한다. 그때는 켜진 것처럼 보이면 안 된다.
      _mimicking = status.contains('실패') ? _mimicking : on;
      _log.insert(0, status);
      _busy = false;
    });
  }

  /// 화면에 들어오면(또는 대상이 바뀌면) 모방을 자동으로 켠다.
  /// 웹캠을 확보한 뒤에 부른다. 시작에 실패하면 버튼으로 다시 켤 수 있다.
  void _autoStartMimic() {
    if (!mounted) return;
    _setMimic(true);
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
    // 실물(맥시)은 조용히 리더 위치로 가서 대기, 가상(미키)은 준비 자세로.
    final backend = _backend;
    backend?.stopMimic().then((_) => backend.restToLeader());
    // 화면을 떠나면 웹캠 장치를 반환한다. 요청을 보낸 뒤 통로를 닫는다.
    final camera = _cameraControl;
    camera?.setCamera(false).then((_) => camera.dispose());
    _tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 선택한 대상 컴퓨터의 영상 주소. 대상이 바뀌면 여기가 다시 그려진다.
    final target = RobotTargetScope.of(context).value;
    final host = target.host;
    // 손 인식 영상: 실물(맥시)은 lerobot 제어 서버(:8100/hand_stream),
    // 가상(미키)은 hand_mimic_node → web_video_server(:8080).
    final handStreamUrl = target.isPhysical
        ? AppConfig.lerobotHandStreamUrl(host)
        : AppConfig.handCameraStreamUrl(host);
    return Scaffold(
      appBar: AppBar(
        title: const Text('실시간 모방'),
        actions: [
          // 카메라 선택 — 미키(가상)에서 웹캠이 여러 대일 때 어느 것으로 모방할지
          // 고른다. 맥시(실물)는 제어 서버가 카메라를 잡으므로 여기서 고르지 않는다.
          if (!target.isPhysical && _cameras.isNotEmpty)
            PopupMenuButton<int>(
              icon: const Icon(Icons.videocam),
              tooltip: '카메라 선택',
              onSelected: _selectCamera,
              itemBuilder: (context) => [
                for (final camera in _cameras)
                  PopupMenuItem<int>(
                    value: camera.index,
                    child: Row(
                      children: [
                        Icon(
                          camera.index == _selectedCameraIndex
                              ? Icons.check
                              : Icons.videocam_outlined,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Flexible(child: Text(camera.name)),
                      ],
                    ),
                  ),
              ],
            ),
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
              streamUrl: handStreamUrl,
              badge: '내 손동작 (인식 중)',
              badgeColor: Colors.teal,
              active: _mimicking,
              statusText: _mimicking ? '동작 인식 중…' : '대기 중',
              zoomable: true,
            ),
          ),
          const Divider(height: 2, thickness: 2),
          // 아래: 로봇 시점 — 위의 손을 따라 움직인다.
          // 맥시(실물)=mediamtx WebRTC, 미키(가상)=Gazebo web_video MJPEG.
          Expanded(
            child: _StreamPane(
              view: RobotCameraView(target: target),
              badge: '로봇 모방',
              badgeColor: Colors.deepPurple,
              active: _mimicking,
              // 백엔드가 알려준 마지막 상태. 아직 시작 전이면 대기 중.
              statusText: _log.isEmpty ? '대기 중' : _log.first,
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
    this.streamUrl,
    this.view,
    required this.badge,
    required this.badgeColor,
    required this.active,
    required this.statusText,
    this.zoomable = false,
    this.log,
  }) : assert(streamUrl != null || view != null,
            'streamUrl 또는 view 중 하나는 있어야 한다');

  /// MJPEG 스트림 주소(view가 없을 때 이걸로 영상을 그린다).
  final String? streamUrl;

  /// 직접 그릴 영상 위젯(주면 streamUrl 대신 이걸 쓴다 — 예: WebRTC iframe).
  final Widget? view;

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
          if (view != null)
            view!
          else if (zoomable)
            ZoomableStreamView(streamUrl: streamUrl!)
          else
            CameraStreamView(streamUrl: streamUrl!),
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
