/// Gazebo 카메라 영상(web_video_server MJPEG)을 화면에 띄우는 위젯.
///
/// 플랫폼마다 구현이 다르다.
/// - **Web**: 브라우저에 `<img>`를 얹어 MJPEG을 브라우저가 직접 재생한다.
/// - **Android / Windows**: MJPEG 스트림을 직접 받아 JPEG 프레임으로 잘라 그린다.
///
/// `webview_flutter`를 쓰지 않는 이유는 그 패키지가 Windows를 지원하지 않아서다.
/// 세 플랫폼에서 같은 화면을 얻으려고 이렇게 나눴고, 화면 코드는 아래 한 가지
/// [CameraStreamView]만 쓰면 된다.
library;

export 'camera_stream_view_io.dart'
    if (dart.library.js_interop) 'camera_stream_view_web.dart';
