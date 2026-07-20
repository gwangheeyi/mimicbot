import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'camera_stream_placeholder.dart';

/// Android / Windows용 MJPEG 뷰어.
///
/// web_video_server는 `multipart/x-mixed-replace`로 JPEG을 계속 흘려보낸다.
/// 경계 문자열을 파싱하는 대신 JPEG 자체의 시작(FFD8)·끝(FFD9) 표식으로 프레임을
/// 잘라낸다. 경계 이름이 서버 버전마다 달라도 이 방법은 그대로 동작한다.
class CameraStreamView extends StatefulWidget {
  const CameraStreamView({super.key, required this.streamUrl});

  /// MJPEG 스트림 주소.
  final String streamUrl;

  @override
  State<CameraStreamView> createState() => _CameraStreamViewState();
}

class _CameraStreamViewState extends State<CameraStreamView> {
  /// 프레임을 못 찾은 채 이만큼 쌓이면 깨진 스트림으로 보고 버린다.
  static const int _maxBufferBytes = 4 * 1024 * 1024;

  static const int _jpegSoi = 0xD8; // FF D8 — JPEG 시작
  static const int _jpegEoi = 0xD9; // FF D9 — JPEG 끝

  /// 연결은 됐는데 이만큼 기다려도 한 장도 안 오면 토픽 이름을 의심한다.
  static const Duration _firstFrameTimeout = Duration(seconds: 10);

  http.Client? _client;
  StreamSubscription<List<int>>? _subscription;
  Timer? _firstFrameTimer;

  final BytesBuilder _buffer = BytesBuilder(copy: false);
  Uint8List? _frame;
  String? _error;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(CameraStreamView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamUrl != widget.streamUrl) {
      _disconnect();
      _connect();
    }
  }

  Future<void> _connect() async {
    setState(() => _error = null);
    final client = http.Client();
    _client = client;
    try {
      final request = http.Request('GET', Uri.parse(widget.streamUrl));
      final response = await client.send(request);
      if (!mounted) return;
      if (response.statusCode != 200) {
        setState(() => _error = '영상 서버 응답 오류 (HTTP ${response.statusCode})');
        return;
      }
      // web_video_server는 없는 토픽을 요청해도 200 OK를 준다. 그래서 연결 성공만으로는
      // 영상이 온다고 볼 수 없고, 첫 프레임이 올 때까지 따로 지켜봐야 한다.
      final topic = request.url.queryParameters['topic'] ?? '(알 수 없음)';
      _firstFrameTimer = Timer(_firstFrameTimeout, () {
        if (_frame == null) {
          _fail('영상 서버에 연결됐지만 영상이 오지 않습니다.\n'
              '이 토픽이 실제로 있는지 확인하세요: $topic');
        }
      });
      _subscription = response.stream.listen(
        _onChunk,
        onError: (Object e) => _fail('영상 수신 중 끊겼습니다.\n$e'),
        onDone: () => _fail('영상 스트림이 종료되었습니다.'),
        cancelOnError: true,
      );
    } catch (e) {
      _fail('영상 서버에 연결할 수 없습니다.\n$e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  /// 받은 바이트를 모아 완성된 JPEG이 있으면 화면에 반영한다.
  void _onChunk(List<int> chunk) {
    _buffer.add(chunk);
    final bytes = _buffer.takeBytes(); // 버퍼를 비우고 통째로 꺼낸다.

    Uint8List? latest;
    var cursor = 0;
    while (true) {
      final start = _findMarker(bytes, _jpegSoi, cursor);
      if (start < 0) break;
      final end = _findMarker(bytes, _jpegEoi, start + 2);
      if (end < 0) {
        cursor = start; // 아직 끝이 안 왔다. 이 시작점부터 다음 청크에서 이어간다.
        break;
      }
      latest = Uint8List.sublistView(bytes, start, end + 2);
      cursor = end + 2;
    }

    // 아직 프레임이 안 끝난 뒷부분만 남겨 둔다.
    final leftover = Uint8List.sublistView(bytes, cursor);
    if (leftover.length <= _maxBufferBytes) _buffer.add(leftover);

    // 한 청크에 여러 장이 들어와도 가장 최신 것만 그리면 된다.
    if (latest == null || !mounted) return;
    _firstFrameTimer?.cancel(); // 영상이 오기 시작했으니 감시를 끈다.
    final frame = Uint8List.fromList(latest); // bytes 원본과 분리해 보관.
    setState(() {
      _frame = frame;
      _error = null;
    });
  }

  /// [from]부터 `FF <marker>` 두 바이트가 처음 나오는 위치.
  static int _findMarker(Uint8List bytes, int marker, int from) {
    for (var i = from; i < bytes.length - 1; i++) {
      if (bytes[i] == 0xFF && bytes[i + 1] == marker) return i;
    }
    return -1;
  }

  void _disconnect() {
    _firstFrameTimer?.cancel();
    _firstFrameTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = null;
    _buffer.clear();
  }

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    if (frame != null) {
      // gaplessPlayback: 다음 프레임을 그리는 동안 화면이 깜빡이지 않게 한다.
      return Image.memory(frame, gaplessPlayback: true, fit: BoxFit.contain);
    }
    return CameraStreamPlaceholder(
      error: _error,
      onRetry: () {
        _disconnect();
        _connect();
      },
    );
  }
}
