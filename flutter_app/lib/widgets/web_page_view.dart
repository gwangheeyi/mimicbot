/// 외부 웹 페이지(예: mediamtx WebRTC 스트림)를 화면에 임베드하는 위젯.
///
/// mediamtx의 `http://<ip>:8889/<path>/` 는 MJPEG이 아니라 WebRTC 플레이어 HTML
/// 페이지라, `<img>`로는 못 띄우고 웹에서는 `<iframe>`으로 임베드한다.
///
/// - **Web**: iframe으로 그 페이지를 그대로 띄운다.
/// - **Android / Windows**: 임베드 대신 안내를 보여 준다(웹 전용).
library;

export 'web_page_view_io.dart'
    if (dart.library.js_interop) 'web_page_view_web.dart';
