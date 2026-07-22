class AppConfig {
  AppConfig._();

  // ── 대상별 서버 주소 ──────────────────────────────────────────────
  //
  // 실행 대상(Gazebo 가상 / OMX-AI 실물)마다 명령·영상을 받을 컴퓨터가 다르다.
  // 앱은 각 대상의 브리지 서버(:8000)로 HTTP 명령을 보내고, web_video_server
  // (:8080)에서 영상을 받는다. 대상이 바뀌면 아래 host만 바뀔 뿐 나머지는 같다.

  /// 미키(Gazebo 가상) 서버 주소 — 시연에서는 앱과 같은 로컬 컴퓨터.
  ///
  /// 안드로이드 에뮬레이터에서 호스트 PC를 가리킬 때는 '10.0.2.2'.
  /// 실행 시 `--dart-define=MICKY_HOST=...` 로 기본값을 바꿀 수 있다.
  static String mickyHost =
      const String.fromEnvironment('MICKY_HOST', defaultValue: '127.0.0.1');

  /// 맥시(OMX-AI 실물) 서버 주소 — 실제 로봇이 연결된 다른 컴퓨터의 IP.
  ///
  /// 시연 중 홈 화면에서 직접 입력해 바꿀 수 있고(재빌드 불필요), 실행 시
  /// `--dart-define=MAXI_HOST=192.168.0.20` 로 기본값을 줄 수도 있다.
  /// 그 컴퓨터에서 `hostname -I` 로 IP를 확인해 넣는다. 브리지 서버는 0.0.0.0으로
  /// 열려 있어 IP로 접속을 받고, 그 컴의 방화벽에서 8000·8080 포트를 열어야 한다.
  static String maxiHost =
      const String.fromEnvironment('MAXI_HOST', defaultValue: '192.168.129.109');

  // 예전 이름 호환용 별칭.
  static String get gazeboHost => mickyHost;
  static String get omxAiHost => maxiHost;

  /// open_manipulator_app_bridge의 FastAPI 포트.
  static const int robotServerPort = 8000;

  /// web_video_server 포트. 카메라 영상을 MJPEG으로 내보낸다.
  static const int videoServerPort = 8080;

  /// 맥시(lerobot) 제어 서버 포트. 동작 명령·손 모방 제어와 손 인식 MJPEG을 제공.
  static const int lerobotControlPort = 8100;

  /// 맥시 손 모방 시 제어 서버가 내보내는 손 인식 영상(웹캠+손 뼈대) 주소.
  /// 실물은 web_video(:8080)가 아니라 이 스트림을 쓴다.
  static String lerobotHandStreamUrl(String host) =>
      'http://$host:$lerobotControlPort/hand_stream';

  /// 맥시(실물) 로봇 시점 카메라. 외부 mediamtx의 WebRTC 페이지를 그대로 띄운다.
  /// MJPEG이 아니라 WebRTC HTML 페이지라 웹에서는 iframe으로 임베드한다.
  /// 실행 시 `--dart-define=MAXI_CAMERA_URL=...` 로 바꿀 수 있다.
  static String maxiCameraUrl = const String.fromEnvironment(
    'MAXI_CAMERA_URL',
    defaultValue: 'http://192.168.129.107:8889/mystream/',
  );

  /// Gazebo 월드의 카메라를 ros_gz_bridge로 넘긴 ROS2 이미지 토픽.
  ///
  /// 월드 파일(`empty_world.sdf`)의 `<topic>`과 같아야 한다. 토픽 이름이 틀리면
  /// web_video_server가 200 OK만 주고 영상은 한 장도 보내지 않는다.
  /// 지금 뭐가 있는지는 브라우저에서 `http://<host>:8080` 으로 확인할 수 있다.
  static const String cameraTopic = '/front_camera/image';

  /// hand_mimic_node가 손 관절을 그려 넣어 내보내는 영상 토픽.
  static const String handCameraTopic = '/hand_camera/image';

  // ── host로 각 URL을 만든다 ────────────────────────────────────────

  static String baseUrl(String host) => 'http://$host:$robotServerPort';

  static String commandEndpoint(String host) =>
      '${baseUrl(host)}/robot/command';

  /// 손 모방 시작/정지.
  static String mimicEndpoint(String host) => '${baseUrl(host)}/robot/mimic';

  /// 웹캠 확보/반환. 실시간 모방 화면 진입/이탈에 맞춰 부른다.
  static String cameraEndpoint(String host) => '${baseUrl(host)}/robot/camera';

  /// ollama(qwen3:4b)로 5초 춤 동작을 만들어 실행. 생성에 수십 초가 걸릴 수 있다.
  static String danceEndpoint(String host) => '${baseUrl(host)}/robot/dance';

  /// ollama(qwen3:4b)로 사용자 질문에 대답. 자율 화면 대화에 쓴다.
  static String chatEndpoint(String host) => '${baseUrl(host)}/robot/chat';

  /// qwen3:4b를 미리 메모리에 올려 두는 예열. 대화 화면 진입 시 부른다.
  static String chatWarmupEndpoint(String host) =>
      '${baseUrl(host)}/robot/chat/warmup';

  /// 자율(정책 실행) — 맥시(실물)에서 학습된 정책(lerobot-record)을 실행.
  static String autonomousEndpoint(String host) =>
      '${baseUrl(host)}/robot/autonomous';

  /// "Micky 깨우기" — 브링업·서비스를 한꺼번에 백그라운드로 시작.
  static String wakeEndpoint(String host) => '${baseUrl(host)}/robot/wake';

  /// "미키 재우기" — 깨우기로 띄운 모든 서비스를 종료.
  static String sleepEndpoint(String host) => '${baseUrl(host)}/robot/sleep';

  /// 로봇 시점 화면에 띄울 MJPEG 스트림 주소.
  static String cameraStreamUrl(String host) =>
      'http://$host:$videoServerPort/stream'
      '?topic=$cameraTopic&type=mjpeg';

  /// 실시간 모방 화면 위쪽에 띄울 손 인식 영상.
  static String handCameraStreamUrl(String host) =>
      'http://$host:$videoServerPort/stream'
      '?topic=$handCameraTopic&type=mjpeg';
}
