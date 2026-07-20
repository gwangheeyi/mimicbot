import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'camera_stream_placeholder.dart';

/// Web용 MJPEG 뷰어.
///
/// 브라우저는 `<img src="...mjpeg">`를 그 자체로 재생할 수 있으므로, MJPEG을 직접
/// 파싱하지 않고 플랫폼 뷰로 `<img>`를 화면에 얹는다. iframe과 달리 문서를 하나 더
/// 띄우지 않아 가볍고, 스타일을 직접 줄 수 있다.
class CameraStreamView extends StatefulWidget {
  const CameraStreamView({super.key, required this.streamUrl});

  /// MJPEG 스트림 주소.
  final String streamUrl;

  @override
  State<CameraStreamView> createState() => _CameraStreamViewState();
}

class _CameraStreamViewState extends State<CameraStreamView> {
  /// 같은 viewType을 두 번 등록하면 예외가 나므로 등록한 것을 기억해 둔다.
  static final Set<String> _registered = {};

  late String _viewType;
  bool _failed = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(CameraStreamView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamUrl != widget.streamUrl) _register();
  }

  void _register() {
    _failed = false;
    // 주소가 다르거나 다시 연결하면 새 viewType이 되어야 `<img>`가 새로 만들어진다.
    _viewType = 'camera-stream:${_attempt++}:${widget.streamUrl}';
    if (_registered.add(_viewType)) {
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
        final image = web.HTMLImageElement()..src = widget.streamUrl;
        image.style
          ..width = '100%'
          ..height = '100%'
          ..objectFit = 'contain';
        image.onError.listen((_) {
          if (mounted) setState(() => _failed = true);
        });
        return image;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return CameraStreamPlaceholder(
        error: '영상 서버에 연결할 수 없습니다.',
        onRetry: () => setState(_register),
      );
    }
    return HtmlElementView(viewType: _viewType);
  }
}
