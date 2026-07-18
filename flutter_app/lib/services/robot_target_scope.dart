import 'package:flutter/material.dart';

import 'robot_backend.dart';
import 'robot_target.dart';

/// 지금 고른 실행 대상과, 그 대상에 맞는 백엔드를 함께 들고 있는 앱 전체 상태.
///
/// 대상이 바뀌면 백엔드도 같이 교체되므로 둘이 어긋날 수 없다.
class RobotTargetController extends ValueNotifier<RobotTarget> {
  RobotTargetController([super.value = RobotTarget.gazeboLeRobot]);

  RobotBackend? _backend;

  /// 현재 대상에 명령을 보내는 백엔드.
  RobotBackend get backend => _backend ??= RobotBackend.create(value);

  @override
  set value(RobotTarget target) {
    if (target == value) return;
    _backend = RobotBackend.create(target);
    super.value = target;
  }
}

/// [RobotTargetController]를 앱 전체에서 꺼내 쓰게 해 주는 스코프.
///
/// [MaterialApp] 위에 두면 Navigator로 띄운 화면들도 모두 찾을 수 있다.
/// 대상이 바뀌면 `of(context)`를 쓴 위젯이 자동으로 다시 그려진다.
class RobotTargetScope extends InheritedNotifier<RobotTargetController> {
  const RobotTargetScope({
    super.key,
    required RobotTargetController super.notifier,
    required super.child,
  });

  static RobotTargetController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<RobotTargetScope>();
    assert(scope != null, 'RobotTargetScope를 찾을 수 없습니다. MimicBotApp 안에서 쓰세요.');
    return scope!.notifier!;
  }
}
