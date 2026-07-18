import 'package:flutter/material.dart';

/// 앱이 실제로 움직일 대상.
///
/// 홈 화면에서 하나를 고르면 세 메뉴(동작 명령·실시간 모방·자율 작업)가
/// 모두 그 대상으로 동작한다.
enum RobotTarget {
  /// LeRobot을 Gazebo에서 가상으로 실행.
  gazeboLeRobot(
    label: 'Gazebo 가상',
    subtitle: 'LeRobot 시뮬레이션',
    description: 'LeRobot을 Gazebo에서 가상으로 실행합니다. '
        '실제 하드웨어 없이 안전하게 시험해 볼 수 있어, 동작을 처음 맞춰볼 때 적합합니다.',
    icon: Icons.view_in_ar,
    color: Colors.teal,
  ),

  /// Robotis OMX-AI 실제 로봇 시연.
  omxAi(
    label: 'OMX-AI 실물',
    subtitle: 'Robotis 실제 로봇',
    description: 'Robotis에서 개발한 OMX-AI 실제 로봇으로 시연합니다. '
        '로봇이 실제로 움직이므로 시작 전에 주변 안전을 먼저 확인하세요.',
    icon: Icons.precision_manufacturing,
    color: Colors.deepOrange,
  );

  const RobotTarget({
    required this.label,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.color,
  });

  /// 버튼·배지에 쓰는 짧은 이름.
  final String label;

  /// 무엇인지 한 줄로.
  final String subtitle;

  /// 홈 화면에서 고를 때 보여줄 설명.
  final String description;

  final IconData icon;
  final Color color;

  /// 실제 로봇이라 움직이기 전에 주의가 필요한 대상인지.
  bool get isPhysical => this == RobotTarget.omxAi;
}
