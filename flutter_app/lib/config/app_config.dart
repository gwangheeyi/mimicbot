class AppConfig {
  AppConfig._();

  static const String robotServerHost = '127.0.0.1';
  static const int robotServerPort = 8000;

  static const String robotServerBaseUrl =
      'http://$robotServerHost:$robotServerPort';

  static const String robotCommandEndpoint =
      '$robotServerBaseUrl/robot/command';
}