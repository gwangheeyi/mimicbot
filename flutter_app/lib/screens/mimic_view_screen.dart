import 'dart:developer' as developer;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/robot_target_scope.dart';
import '../services/tts_service.dart';
import '../widgets/robot_target_badge.dart';

/// 메뉴 2 — 실시간 모방.
///
/// 화면이 상/하로 분리됩니다.
/// 위: 사용자의 손동작 비디오(연결된 카메라), 아래: 로봇이 따라하는 화면.
class MimicViewScreen extends StatefulWidget {
  const MimicViewScreen({super.key});

  @override
  State<MimicViewScreen> createState() => _MimicViewScreenState();
}

class _MimicViewScreenState extends State<MimicViewScreen>
    with WidgetsBindingObserver {
  bool _mimicking = false;

  /// 로봇 백엔드가 돌려준 마지막 상태 문구 (어느 대상이 따라하는지 보여준다).
  String? _mimicStatus;

  // 카메라 상태.
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _selectedIndex = 0;
  bool _loading = true;
  String? _error;

  // 초기화 재진입 방지: 이전 초기화가 끝나기 전 새 초기화가 겹치면
  // 두 스트림이 카메라를 두고 다투다 서로를 닫아 "잠깐 켜졌다 꺼짐"이 발생한다.
  bool _busy = false;

  final TtsService _tts = TtsService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 진입 시 인사말.
    _tts.speak('안녕 친구야. 내가 너의 행동을 따라 해 볼게!');
    _initCameras();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    // 앱이 백그라운드로 가면 카메라를 반납하고, 복귀하면 다시 연결한다.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCameras();
    }
  }

  /// 카메라 관련 에러를 콘솔 로그(`MimicBot.camera`)에 남기고,
  /// 화면 표시용 문자열을 만들어 반환한다.
  String _logCameraError(String context, Object error, StackTrace stack) {
    // CameraException이면 code/description를 분리해 더 진단하기 쉽게 남긴다.
    final detail = error is CameraException
        ? '[${error.code}] ${error.description ?? ''}'
        : error.toString();
    developer.log(
      '$context 실패: $detail',
      name: 'MimicBot.camera',
      level: 1000, // SEVERE
      error: error,
      stackTrace: stack,
    );
    // developer.log는 웹에서 브라우저 콘솔로만 나가므로,
    // 터미널(flutter run)에도 보이도록 debugPrint를 함께 사용한다.
    debugPrint('[MimicBot.camera] $context 실패: $detail');
    debugPrint('$stack');
    return detail;
  }

  /// 에러 상세 문자열에서 흔한 원인을 골라 사용자에게 안내할 한 줄을 만든다.
  String _friendlyHint(String detail) {
    final d = detail.toLowerCase();
    if (d.contains('notreadable') || d.contains('trackstart')) {
      return '다른 앱(예: Zoom)이 카메라를 사용 중입니다.\n'
          '그 앱을 완전히 종료(작업 표시줄 트레이 포함)한 뒤 새로고침하세요.';
    }
    if (d.contains('notallowed') || d.contains('permissiondenied')) {
      return '브라우저에서 카메라 권한이 거부되었습니다.\n'
          '주소창의 카메라/자물쇠 아이콘에서 "허용"으로 바꾼 뒤 새로고침하세요.';
    }
    if (d.contains('notfound') || d.contains('devicesnotfound')) {
      return '사용 가능한 카메라를 찾지 못했습니다.';
    }
    if (d.contains('insecure') || d.contains('security')) {
      return '보안 컨텍스트(localhost 또는 https)에서만 카메라를 쓸 수 있습니다.';
    }
    return '이 플랫폼에서 카메라가 지원되지 않거나 권한이 없을 수 있습니다.';
  }

  /// 연결된 카메라 목록을 조회하고 첫 번째 카메라를 시작한다.
  Future<void> _initCameras() async {
    if (_busy) return; // 이미 초기화 중이면 중복 실행하지 않는다.
    _busy = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cameras = await availableCameras();
      final summary = '카메라 ${cameras.length}개 감지: '
          '${cameras.map((c) => '${c.name}(${c.lensDirection.name})').join(', ')}';
      developer.log(summary, name: 'MimicBot.camera');
      debugPrint('[MimicBot.camera] $summary');
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() {
          _cameras = [];
          _loading = false;
          _error = '연결된 카메라를 찾을 수 없습니다.';
        });
        return;
      }
      _cameras = cameras;
      await _startCamera(0);
    } catch (e, st) {
      final detail = _logCameraError('카메라 목록 조회(availableCameras)', e, st);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '카메라를 사용할 수 없습니다.\n${_friendlyHint(detail)}\n\n$detail';
      });
    } finally {
      _busy = false;
    }
  }

  /// 드롭다운에서 카메라를 바꿀 때 호출. 초기화 재진입을 막는다.
  Future<void> _selectCamera(int index) async {
    if (_busy) return;
    _busy = true;
    try {
      await _startCamera(index);
    } finally {
      _busy = false;
    }
  }

  /// 지정한 인덱스의 카메라로 컨트롤러를 (재)생성한다.
  Future<void> _startCamera(int index) async {
    setState(() => _loading = true);

    // 기존 컨트롤러 정리. 웹캠은 단일 접근이라 새 스트림을 열기 전에
    // 반드시 이전 스트림을 완전히 닫아야 "잠깐 켜졌다 꺼짐"을 피할 수 있다.
    final previous = _controller;
    _controller = null;
    await previous?.dispose();

    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      await controller.initialize();
      developer.log('카메라 시작됨: ${_cameras[index].name} '
          '(${controller.value.previewSize})', name: 'MimicBot.camera');
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _selectedIndex = index;
        _loading = false;
        _error = null;
      });
    } catch (e, st) {
      final detail =
          _logCameraError('카메라 시작(${_cameras[index].name})', e, st);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '카메라를 시작할 수 없습니다.\n${_friendlyHint(detail)}\n\n$detail';
      });
    }
  }

  String _cameraLabel(CameraDescription cam, int index) {
    final dir = switch (cam.lensDirection) {
      CameraLensDirection.front => '전면',
      CameraLensDirection.back => '후면',
      CameraLensDirection.external => '외장',
    };
    return '카메라 ${index + 1} · $dir';
  }

  /// 모방 시작/정지. 홈에서 고른 대상(Gazebo 가상 / OMX-AI 실물)이 따라한다.
  Future<void> _toggle() async {
    final backend = RobotTargetScope.of(context).backend;
    final next = !_mimicking;
    setState(() => _mimicking = next);
    final status = next ? await backend.startMimic() : await backend.stopMimic();
    if (!mounted) return;
    setState(() => _mimicStatus = status);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('실시간 모방'),
        actions: [
          IconButton(
            onPressed: _initCameras,
            icon: const Icon(Icons.refresh),
            tooltip: '카메라 다시 검색',
          ),
          const RobotTargetBadge(),
        ],
      ),
      body: Column(
        children: [
          // 위: 사용자 손동작 — 실제 카메라 미리보기.
          Expanded(
            child: _CameraPane(
              controller: _controller,
              loading: _loading,
              error: _error,
              cameras: _cameras,
              selectedIndex: _selectedIndex,
              onSelect: _selectCamera,
              cameraLabel: _cameraLabel,
              active: _mimicking,
            ),
          ),
          const Divider(height: 2, thickness: 2),
          // 아래: 로봇 모방 화면 (플레이스홀더).
          Expanded(
            child: _RobotPane(
              active: _mimicking,
              // 백엔드가 알려준 상태를 그대로 보여준다. 아직 시작 전이면 대기 중.
              statusText: _mimicStatus ?? '대기 중',
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _controller == null ? null : _toggle,
        icon: Icon(_mimicking ? Icons.stop : Icons.play_arrow),
        label: Text(_mimicking ? '모방 정지' : '모방 시작'),
        backgroundColor: _mimicking ? Colors.red : null,
      ),
    );
  }
}

/// 상단 카메라 패널: 미리보기 + (2개 이상일 때) 카메라 선택 드롭다운.
class _CameraPane extends StatelessWidget {
  const _CameraPane({
    required this.controller,
    required this.loading,
    required this.error,
    required this.cameras,
    required this.selectedIndex,
    required this.onSelect,
    required this.cameraLabel,
    required this.active,
  });

  final CameraController? controller;
  final bool loading;
  final String? error;
  final List<CameraDescription> cameras;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final String Function(CameraDescription, int) cameraLabel;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildContent(context),
          // 라벨 배지.
          Positioned(
            top: 12,
            left: 12,
            child: _Badge(text: '내 손동작 (카메라)', color: Colors.teal),
          ),
          // 카메라가 2개 이상이면 선택 드롭다운 표시.
          if (cameras.length >= 2)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: selectedIndex,
                    dropdownColor: Colors.black87,
                    iconEnabledColor: Colors.white,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    items: [
                      for (var i = 0; i < cameras.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(cameraLabel(cameras[i], i)),
                        ),
                    ],
                    onChanged: loading
                        ? null
                        : (i) {
                            if (i != null && i != selectedIndex) onSelect(i);
                          },
                  ),
                ),
              ),
            ),
          // 상태 표시.
          if (controller != null)
            Positioned(
              bottom: 12,
              left: 12,
              child: Row(
                children: [
                  Icon(active ? Icons.circle : Icons.circle_outlined,
                      size: 12,
                      color: active ? Colors.greenAccent : Colors.white38),
                  const SizedBox(width: 6),
                  Text(active ? '동작 인식 중…' : '대기 중',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          // 진단 배지: 컨트롤러 초기화 여부와 프리뷰 해상도.
          if (controller != null)
            Positioned(
              bottom: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: Colors.black54,
                child: Text(
                  'init:${controller!.value.isInitialized} '
                  'size:${controller!.value.previewSize}',
                  style: const TextStyle(color: Colors.amber, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, size: 48, color: Colors.white38),
              const SizedBox(height: 12),
              Text(error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      );
    }
    if (controller != null && controller!.value.isInitialized) {
      final size = controller!.value.previewSize;
      // 웹/네이티브 모두에서 영역을 꽉 채우도록 FittedBox(cover)로 감싼다.
      // previewSize가 아직 없으면 CameraPreview에 그대로 맡긴다.
      if (size == null) {
        return SizedBox.expand(child: CameraPreview(controller!));
      }
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: CameraPreview(controller!),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 하단 로봇 모방 패널 (플레이스홀더).
class _RobotPane extends StatelessWidget {
  const _RobotPane({required this.active, required this.statusText});

  final bool active;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.black,
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy,
                    size: 56, color: Colors.deepPurple.withValues(alpha: 0.6)),
                const SizedBox(height: 8),
                const Text('로봇 모방',
                    style: TextStyle(color: Colors.white54)),
              ],
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: _Badge(text: '로봇 모방', color: Colors.deepPurple),
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
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
