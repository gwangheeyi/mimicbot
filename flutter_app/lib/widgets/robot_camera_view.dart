import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/robot_target.dart';
import 'camera_stream_view.dart';
import 'web_page_view.dart';

/// 로봇 시점 카메라. 대상에 따라 소스가 다르다.
/// - 맥시(실물): 외부 mediamtx WebRTC 페이지(웹에서 iframe 임베드).
/// - 미키(가상): Gazebo 카메라 web_video_server MJPEG.
class RobotCameraView extends StatelessWidget {
  const RobotCameraView({super.key, required this.target});

  final RobotTarget target;

  @override
  Widget build(BuildContext context) {
    if (target.isPhysical) {
      return WebPageView(url: AppConfig.maxiCameraUrl);
    }
    return CameraStreamView(streamUrl: AppConfig.cameraStreamUrl(target.host));
  }
}
