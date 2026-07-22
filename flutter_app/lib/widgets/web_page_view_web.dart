import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Web용: 외부 페이지(mediamtx WebRTC 등)를 `<iframe>`으로 임베드한다.
class WebPageView extends StatefulWidget {
  const WebPageView({super.key, required this.url});

  /// 임베드할 페이지 주소.
  final String url;

  @override
  State<WebPageView> createState() => _WebPageViewState();
}

class _WebPageViewState extends State<WebPageView> {
  /// 같은 viewType을 두 번 등록하면 예외가 나므로 등록한 것을 기억해 둔다.
  static final Set<String> _registered = {};

  late String _viewType;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(WebPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) setState(_register);
  }

  void _register() {
    // 주소가 다르거나 다시 그리면 새 viewType이 되어야 iframe이 새로 만들어진다.
    _viewType = 'web-page:${_attempt++}:${widget.url}';
    if (_registered.add(_viewType)) {
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
        final frame = web.HTMLIFrameElement()
          ..src = widget.url
          // WebRTC 자동재생을 위해 카메라/마이크/자동재생 권한을 허용한다.
          ..allow = 'autoplay; camera; microphone; fullscreen';
        frame.style
          ..border = 'none'
          ..width = '100%'
          ..height = '100%';
        return frame;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
