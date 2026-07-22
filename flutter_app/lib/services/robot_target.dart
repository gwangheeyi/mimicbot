import 'package:flutter/material.dart';

import '../config/app_config.dart';

/// 앱이 실제로 움직일 대상.
///
/// 홈 화면에서 하나를 고르면 세 메뉴(동작 명령·실시간 모방·자율 작업)가
/// 모두 그 대상으로 동작한다. 대상마다 명령·영상을 주고받을 컴퓨터([host])가
/// 다르다 — 가상은 보통 앱과 같은 컴, 실물은 로봇이 연결된 다른 컴이다.
enum RobotTarget {
  /// LeRobot을 Gazebo에서 가상으로 실행.
  gazeboLeRobot(
    label: 'Gazebo 가상',
    subtitle: 'LeRobot 시뮬레이션',
    description: 'LeRobot을 Gazebo에서 가상으로 실행합니다. '
        '실제 하드웨어 없이 안전하게 시험해 볼 수 있어, 동작을 처음 맞춰볼 때 적합합니다.',
    icon: Icons.view_in_ar,
    color: Colors.teal,
    robotName: '미키',
  ),

  /// Robotis OMX-AI 실제 로봇 시연.
  omxAi(
    label: 'OMX-AI 실물',
    subtitle: 'Robotis 실제 로봇',
    description: 'Robotis에서 개발한 OMX-AI 실제 로봇으로 시연합니다. '
        '로봇이 실제로 움직이므로 시작 전에 주변 안전을 먼저 확인하세요.',
    icon: Icons.precision_manufacturing,
    color: Colors.deepOrange,
    robotName: '맥시',
  );

  const RobotTarget({
    required this.label,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.color,
    required this.robotName,
  });

  /// 버튼·배지에 쓰는 짧은 이름.
  final String label;

  /// 무엇인지 한 줄로.
  final String subtitle;

  /// 홈 화면에서 고를 때 보여줄 설명.
  final String description;

  final IconData icon;
  final Color color;

  /// 이 대상의 명령·영상을 주고받을 컴퓨터 주소(브리지 서버가 도는 곳).
  ///
  /// 시연 중 맥시(실물) IP를 바꿀 수 있어 항상 현재 값을 읽는다.
  /// 미키(가상)=로컬, 맥시(실물)=설정한 IP.
  String get host =>
      this == RobotTarget.omxAi ? AppConfig.maxiHost : AppConfig.mickyHost;

  /// 이 대상의 로봇 이름. 가상은 '미키', 실물(OMX-AI)은 '맥시'.
  /// 깨우기 버튼 등 화면에 이 이름으로 표시한다.
  final String robotName;

  /// 실제 로봇이라 움직이기 전에 주의가 필요한 대상인지.
  bool get isPhysical => this == RobotTarget.omxAi;
}
