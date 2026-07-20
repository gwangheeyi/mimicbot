import 'package:flutter/material.dart';

/// 영상이 아직 없거나 연결에 실패했을 때 보여 줄 안내.
///
/// 플랫폼별 구현(`camera_stream_view_io` / `_web`)이 같은 모습을 쓰도록 여기 둔다.
class CameraStreamPlaceholder extends StatelessWidget {
  const CameraStreamPlaceholder({super.key, this.error, this.onRetry});

  /// 실패 사유. null이면 "연결 중" 상태로 본다.
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              error == null ? Icons.videocam_outlined : Icons.videocam_off,
              size: 48,
              color: Colors.white38,
            ),
            const SizedBox(height: 8),
            Text(
              error ?? 'Gazebo 영상 연결 중…',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              const Text(
                'Gazebo · ros_gz_bridge · web_video_server가 켜져 있는지 확인하세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white24, fontSize: 12),
              ),
              if (onRetry != null)
                TextButton(onPressed: onRetry, child: const Text('다시 연결')),
            ],
          ],
        ),
      ),
    );
  }
}
