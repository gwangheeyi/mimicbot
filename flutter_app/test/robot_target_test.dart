// 실행 대상(Gazebo 가상 / OMX-AI 실물) 선택이 앱 전체에 실제로 적용되는지 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/main.dart';
import 'package:flutter_app/screens/command_control_screen.dart';
import 'package:flutter_app/services/autonomous_skills.dart';
import 'package:flutter_app/services/robot_backend.dart';
import 'package:flutter_app/services/robot_target.dart';
import 'package:flutter_app/services/robot_target_scope.dart';

void main() {
  group('백엔드', () {
    test('대상을 바꾸면 백엔드도 함께 바뀐다', () {
      final controller = RobotTargetController();

      // 기본값은 안전한 가상 실행.
      expect(controller.value, RobotTarget.gazeboLeRobot);
      expect(controller.backend, isA<GazeboLeRobotBackend>());

      controller.value = RobotTarget.omxAi;

      expect(controller.backend, isA<OmxAiBackend>());
      expect(controller.backend.target, RobotTarget.omxAi,
          reason: '대상과 백엔드가 어긋나면 엉뚱한 로봇이 움직인다');
      controller.dispose();
    });

    test('대상이 바뀌면 알림이 가서 화면이 다시 그려진다', () {
      final controller = RobotTargetController();
      var notified = 0;
      controller.addListener(() => notified++);

      controller.value = RobotTarget.omxAi;
      expect(notified, 1);

      // 같은 값으로 다시 설정하면 알리지 않는다.
      controller.value = RobotTarget.omxAi;
      expect(notified, 1);
      controller.dispose();
    });

    test('명령에 어느 대상인지가 붙는다', () async {
      const gazebo = GazeboLeRobotBackend();
      const omx = OmxAiBackend();

      expect(await gazebo.moveToPoint(45, 60), contains('Gazebo 가상'));
      expect(await gazebo.moveToPoint(45, 60), contains('(45, 60)'));
      expect(await omx.playGesture('ready'), contains('OMX-AI 실물'));
      expect(await omx.playGesture('ready'), contains('ready'));

      final skill = AutonomousSkills.all.first;
      expect(await omx.runSkillStep(skill, 0), contains(skill.steps[0]));
    });

    test('실물 로봇만 안전 확인 대상으로 표시된다', () {
      expect(RobotTarget.gazeboLeRobot.isPhysical, isFalse);
      expect(RobotTarget.omxAi.isPhysical, isTrue);
    });
  });

  group('화면', () {
    testWidgets('홈에서 두 실행 대상을 고를 수 있고, 실물은 안전 안내가 뜬다',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MimicBotApp());

      // 두 선택지가 모두 있고, 기본은 가상 실행이라 안전 안내가 없다.
      expect(find.text('실행 대상'), findsOneWidget);
      expect(find.text('Gazebo 가상'), findsWidgets);
      expect(find.text('OMX-AI 실물'), findsWidgets);
      expect(find.text('LeRobot 시뮬레이션'), findsOneWidget);
      expect(find.textContaining('로봇 주변에 사람과 물건이 없는지'), findsNothing);

      // 실물로 바꾸면 설명과 안전 안내가 바뀐다.
      await tester.tap(find.text('OMX-AI 실물').first);
      await tester.pumpAndSettle();

      expect(find.text('Robotis 실제 로봇'), findsOneWidget);
      expect(find.textContaining('로봇 주변에 사람과 물건이 없는지'), findsOneWidget);
    });

    testWidgets('홈에서 고른 대상이 다른 메뉴까지 따라가고 명령도 그 대상으로 나간다',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MimicBotApp());

      // 홈에서 실물 로봇을 고른다.
      await tester.tap(find.text('OMX-AI 실물').first);
      await tester.pumpAndSettle();

      // 다른 메뉴로 이동한다.
      await tester.tap(find.text('동작 명령').first);
      await tester.pumpAndSettle();

      // 앱바 배지가 고른 대상을 보여준다 (가상인 줄 알고 실물을 움직이는 사고 방지).
      expect(
        find.descendant(
          of: find.byType(CommandControlScreen),
          matching: find.text('OMX-AI 실물'),
        ),
        findsOneWidget,
      );

      // 명령이 실제로 그 대상의 백엔드로 나간다.
      // 버튼에는 '준비'라고 쓰여 있어도 로봇에는 등록된 명령어 'ready'가 나가야 한다.
      await tester.tap(find.widgetWithText(ActionChip, '준비'));
      await tester.pumpAndSettle();

      // 진입할 때 준비 자세로 맞추는 기록이 이미 한 줄 있으므로 여러 줄이 된다.
      expect(find.textContaining('[OMX-AI 실물]'), findsWidgets);
      expect(find.textContaining('"ready"'), findsWidgets);
      // 가상 대상으로는 아무것도 나가지 않아야 한다.
      expect(find.textContaining('[Gazebo 가상]'), findsNothing);
    });

    testWidgets('기본값은 가상 실행이라 실수로 실물이 움직이지 않는다',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MimicBotApp());
      await tester.tap(find.text('동작 명령').first);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ActionChip, '준비'));
      await tester.pumpAndSettle();

      // 가상 대상은 브리지 서버로 HTTP를 보낸다. 테스트에서는 서버가 없어 실패
      // 로그가 남지만, 여기서 확인할 것은 명령이 실물이 아닌 가상으로 갔다는 점이다.
      expect(find.textContaining('[Gazebo 가상]'), findsWidgets);
      expect(find.textContaining('[OMX-AI 실물]'), findsNothing);
    });
  });
}
