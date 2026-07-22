import 'package:flutter/material.dart';

/// Android / Windows용: 외부 WebRTC 페이지 임베드는 웹 전용이라 안내만 보여 준다.
/// (webview_flutter는 Windows 미지원이라 쓰지 않는다.)
class WebPageView extends StatelessWidget {
  const WebPageView({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off_outlined,
              color: Colors.white38, size: 40),
          const SizedBox(height: 12),
          const Text(
            '이 카메라(WebRTC)는 웹(Chrome)에서 표시됩니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(
            url,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
