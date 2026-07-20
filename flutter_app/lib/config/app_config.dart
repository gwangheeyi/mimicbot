class AppConfig {
  AppConfig._();

  /// ROS2(브리지 서버·web_video_server)가 도는 머신 주소.
  ///
  /// 앱과 같은 PC에서 돌리면 127.0.0.1 그대로 두면 되고, 안드로이드 실기기처럼
  /// 다른 기기에서 접속할 때는 ROS 머신의 LAN IP(예: '192.168.0.10')로 바꾼다.
  /// 안드로이드 에뮬레이터에서 호스트 PC를 가리킬 때는 '10.0.2.2'.
  static const String robotServerHost = '127.0.0.1';

  /// open_manipulator_app_bridge의 FastAPI 포트.
  static const int robotServerPort = 8000;

  /// web_video_server 포트. Gazebo 카메라 영상을 MJPEG으로 내보낸다.
  static const int videoServerPort = 8080;

  /// Gazebo 월드의 카메라를 ros_gz_bridge로 넘긴 ROS2 이미지 토픽.
  ///
  /// 월드 파일(`empty_world.sdf`)의 `<topic>`과 같아야 한다. 토픽 이름이 틀리면
  /// web_video_server가 200 OK만 주고 영상은 한 장도 보내지 않는다.
  /// 지금 뭐가 있는지는 브라우저에서 `http://<host>:8080` 으로 확인할 수 있다.
  static const String cameraTopic = '/front_camera/image';

  static const String robotServerBaseUrl =
      'http://$robotServerHost:$robotServerPort';

  static const String robotCommandEndpoint =
      '$robotServerBaseUrl/robot/command';

  /// 손 모방 시작/정지.
  static const String mimicEndpoint = '$robotServerBaseUrl/robot/mimic';

  /// hand_mimic_node가 손 관절을 그려 넣어 내보내는 영상 토픽.
  static const String handCameraTopic = '/hand_camera/image';

  /// 실시간 모방 화면 위쪽에 띄울 손 인식 영상.
  static const String handCameraStreamUrl =
      'http://$robotServerHost:$videoServerPort/stream'
      '?topic=$handCameraTopic&type=mjpeg';

  /// 로봇 시점 화면에 띄울 MJPEG 스트림 주소.
  static const String cameraStreamUrl =
      'http://$robotServerHost:$videoServerPort/stream'
      '?topic=$cameraTopic&type=mjpeg';
}
