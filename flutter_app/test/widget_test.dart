// Basic smoke test for the Mimic Bot home menu.

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/main.dart';

void main() {
  testWidgets('Home menu shows the three screens and navigates',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MimicBotApp());

    // 세 개의 메뉴가 홈에 표시된다 (상단 버튼 + 설명 카드에 등장).
    expect(find.text('동작 명령'), findsWidgets);
    expect(find.text('실시간 모방'), findsWidgets);
    expect(find.text('자율 작업'), findsWidgets);

    // 상단 메뉴 버튼(첫 번째 '동작 명령')을 탭하면 해당 스크린으로 이동한다.
    await tester.tap(find.text('동작 명령').first);
    await tester.pumpAndSettle();

    expect(find.text('안녕'), findsOneWidget);
    expect(find.text('경례'), findsOneWidget);
  });
}
