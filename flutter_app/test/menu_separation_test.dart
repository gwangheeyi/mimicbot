// 메뉴 1(동작 명령)과 메뉴 2(실시간 모방)가 서로 섞이지 않는지 검증한다.
//
// 손 모방이 켜진 채로 남으면 hand_mimic_node가 계속 팔을 움직이면서
// 메뉴 1의 동작 명령과 같은 토픽(/arm_controller/joint_trajectory)을 두고 다툰다.

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/main.dart';
import 'package:flutter_app/screens/command_control_screen.dart';
import 'package:flutter_app/screens/mimic_view_screen.dart';

void main() {
  // 홈에서 메뉴 이름을 눌러 해당 화면으로 이동한다.
  Future<void> openMenu(WidgetTester tester, String name) async {
    await tester.tap(find.text(name).first);
    await tester.pumpAndSettle();
  }

  // 화면을 떠난다.
  Future<void> goBack(WidgetTester tester) async {
    await tester.pageBack();
    await tester.pumpAndSettle();
  }

  testWidgets('실시간 모방을 떠나면 화면이 정리된다', (WidgetTester tester) async {
    await tester.pumpWidget(const MimicBotApp());

    await openMenu(tester, '실시간 모방');
    expect(find.byType(MimicViewScreen), findsOneWidget);

    // 떠날 때 백엔드에 정지를 보낸다. 예외 없이 화면이 사라져야 한다.
    await goBack(tester);
    expect(find.byType(MimicViewScreen), findsNothing);
  });

  testWidgets('모방 화면을 거쳐 동작 명령으로 가도 기록이 섞이지 않는다',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MimicBotApp());

    // 모방 화면에서 시작을 눌러 기록을 남긴다.
    await openMenu(tester, '실시간 모방');
    await tester.tap(find.text('모방 시작'));
    await tester.pumpAndSettle();
    expect(find.textContaining('실시간 모방'), findsWidgets);

    await goBack(tester);

    // 동작 명령 화면은 모방 기록을 물려받지 않고, 대신 준비 자세로 맞춘 기록만
    // 갖고 시작한다.
    await openMenu(tester, '동작 명령');
    expect(find.byType(CommandControlScreen), findsOneWidget);
    expect(find.textContaining('실시간 모방 시작'), findsNothing);
    expect(find.textContaining('ready'), findsWidgets);
  });

  testWidgets('모방 화면에 다시 들어가면 기록과 상태가 새로 시작된다',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MimicBotApp());

    await openMenu(tester, '실시간 모방');
    await tester.tap(find.text('모방 시작'));
    await tester.pumpAndSettle();
    await goBack(tester);

    // 다시 들어오면 이전 기록이 남아 있지 않고 버튼도 '시작' 상태여야 한다.
    await openMenu(tester, '실시간 모방');
    expect(find.text('모방 시작'), findsOneWidget);
    expect(find.text('모방 정지'), findsNothing);
    expect(find.textContaining('명령 기록'), findsNothing);
  });
}
