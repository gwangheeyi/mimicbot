import 'package:flutter/material.dart';

import 'screens/home_menu_screen.dart';
import 'services/robot_target_scope.dart';

void main() {
  runApp(const MimicBotApp());
}

class MimicBotApp extends StatefulWidget {
  const MimicBotApp({super.key});

  @override
  State<MimicBotApp> createState() => _MimicBotAppState();
}

class _MimicBotAppState extends State<MimicBotApp> {
  /// 실행 대상 선택은 앱 전체가 공유한다. 세 메뉴가 모두 같은 대상을 보게 하려고
  /// MaterialApp 위에 스코프를 두었다 (Navigator로 띄운 화면도 찾을 수 있다).
  final RobotTargetController _target = RobotTargetController();

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RobotTargetScope(
      notifier: _target,
      child: MaterialApp(
        title: 'Mimic Bot',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomeMenuScreen(),
      ),
    );
  }
}
