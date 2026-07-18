import 'package:flutter/material.dart';

import '../services/robot_target_scope.dart';

/// 지금 어느 대상으로 움직이는지 알려주는 작은 배지.
///
/// 세 메뉴의 앱바에 두어, 가상인지 실물인지 헷갈린 채로 실행하는 일을 막는다.
class RobotTargetBadge extends StatelessWidget {
  const RobotTargetBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final target = RobotTargetScope.of(context).value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: target.color.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: target.color),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(target.icon, size: 14, color: target.color),
            const SizedBox(width: 6),
            Text(
              target.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: target.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
