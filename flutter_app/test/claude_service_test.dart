// 자율 작업 화면의 두뇌 — Claude가 사용자의 말을 어떤 자율행동으로 이해하는지 검증한다.
// 실제 API 호출 없이, 보내는 요청 모양과 받은 판단의 해석을 확인한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_app/services/autonomous_skills.dart';
import 'package:flutter_app/services/claude_service.dart';

/// Claude가 돌려줄 법한 성공 응답을 만든다.
http.Response _decisionResponse({
  required String reply,
  required String action,
  String skillId = '',
}) {
  final body = jsonEncode({
    'stop_reason': 'end_turn',
    'content': [
      {
        'type': 'text',
        'text': jsonEncode({
          'reply': reply,
          'action': action,
          'skill_id': skillId,
        }),
      },
    ],
  });
  return http.Response.bytes(utf8.encode(body), 200);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // API 키가 없으면 decide()가 바로 예외를 던지므로, 키가 주입된 빌드에서만 의미가 있다.
  // `flutter test --dart-define=ANTHROPIC_API_KEY=test-key` 로 실행한다.
  final hasKey = ClaudeService.hasApiKey;

  test('지침과 자율행동 목록이 시스템 프롬프트에 함께 들어간다', () async {
    final service = ClaudeService();
    final prompt = await service.systemPrompt();
    service.dispose();

    // 저장해 둔 지침 파일에서 온 내용.
    expect(prompt, contains('너의 이름은 "미키"이다'));
    expect(prompt, contains('판단 규칙'));
    // 코드의 카탈로그에서 자동으로 붙은 내용.
    expect(prompt, contains('미키가 할 수 있는 자율행동 목록'));
    for (final skill in AutonomousSkills.all) {
      expect(prompt, contains('id: ${skill.id}'));
      expect(prompt, contains(skill.name));
    }
  });

  test('skill_id 스키마가 실제 자율행동 id만 허용한다', () {
    // Claude가 목록에 없는 행동을 지어내면 로봇이 움직일 수 없다.
    expect(AutonomousSkills.idsForSchema, contains('pick_and_place'));
    expect(AutonomousSkills.idsForSchema, contains(''), reason: '해당 없음을 표현할 값');
    expect(AutonomousSkills.idsForSchema.length,
        AutonomousSkills.all.length + 1);
    for (final id in AutonomousSkills.idsForSchema) {
      if (id.isEmpty) continue;
      expect(AutonomousSkills.byId(id), isNotNull);
    }
  });

  test('요청에 모델·구조화 출력 스키마가 올바르게 담긴다', () async {
    if (!hasKey) return;
    late Map<String, dynamic> sent;
    final service = ClaudeService(
      client: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return _decisionResponse(reply: '안녕하세요.', action: 'chat');
      }),
    );

    await service.decide('안녕');
    service.dispose();

    expect(sent['model'], 'claude-opus-4-8');
    final format = sent['output_config']['format'] as Map<String, dynamic>;
    expect(format['type'], 'json_schema');
    final props = format['schema']['properties'] as Map<String, dynamic>;
    expect(props['action']['enum'],
        ['chat', 'confirm', 'execute', 'unsupported']);
    expect(props['skill_id']['enum'], AutonomousSkills.idsForSchema);
    expect(format['schema']['additionalProperties'], false);
  });

  test('자율주행과 무관한 말은 대답만 하고 로봇을 움직이지 않는다', () async {
    if (!hasKey) return;
    final service = ClaudeService(
      client: MockClient((_) async =>
          _decisionResponse(reply: '저는 미키예요.', action: 'chat')),
    );

    final decision = await service.decide('너 이름이 뭐야?');
    service.dispose();

    expect(decision.action, RobotAction.chat);
    expect(decision.reply, '저는 미키예요.');
    expect(decision.skill, isNull, reason: 'chat일 때는 실행할 행동이 없어야 한다');
  });

  test('비슷한 명령은 확인을 거쳐야 실행된다 (confirm → 긍정 → execute)', () async {
    if (!hasKey) return;
    final bodies = <Map<String, dynamic>>[];
    var call = 0;
    final service = ClaudeService(
      client: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        call++;
        // 1번째: 되물어 확인. 2번째: 사용자가 긍정했으니 실행.
        return call == 1
            ? _decisionResponse(
                reply: '혹시 물건 옮기기를 말씀하시는 건가요?',
                action: 'confirm',
                skillId: 'pick_and_place',
              )
            : _decisionResponse(
                reply: '네, 지금 할게요.',
                action: 'execute',
                skillId: 'pick_and_place',
              );
      }),
    );

    final first = await service.decide('저거 좀 옮겨줄래?');
    expect(first.action, RobotAction.confirm,
        reason: '비슷한 명령은 바로 실행하지 않고 확인해야 한다');
    expect(first.skill?.name, '물건 옮기기');

    final second = await service.decide('응 맞아');
    service.dispose();

    expect(second.action, RobotAction.execute);
    expect(second.skill?.id, 'pick_and_place');
    expect(second.skill?.steps.first, '물건 앞으로 접근');

    // "응 맞아"만으로는 무슨 뜻인지 알 수 없다. 앞선 확인 질문이 함께 전달되어야 한다.
    final history = bodies[1]['messages'] as List<dynamic>;
    expect(history.length, 3);
    expect(history[0]['role'], 'user');
    expect(history[0]['content'], '저거 좀 옮겨줄래?');
    expect(history[1]['role'], 'assistant');
    expect(history[1]['content'], contains('pick_and_place'));
    expect(history[2]['content'], '응 맞아');
  });

  test('거절(refusal) 응답은 예외 없이 짧은 대답으로 처리된다', () async {
    if (!hasKey) return;
    final service = ClaudeService(
      client: MockClient((_) async => http.Response.bytes(
            utf8.encode(jsonEncode({'stop_reason': 'refusal', 'content': []})),
            200,
          )),
    );

    final decision = await service.decide('...');
    service.dispose();

    expect(decision.action, RobotAction.chat);
    expect(decision.reply, isNotEmpty);
  });

  test('호출이 실패하면 그 발화는 기록에 남지 않는다', () async {
    if (!hasKey) return;
    final bodies = <Map<String, dynamic>>[];
    var call = 0;
    final service = ClaudeService(
      client: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        call++;
        // 첫 호출은 실패, 두 번째는 성공.
        return call == 1
            ? http.Response.bytes(
                utf8.encode(jsonEncode({
                  'error': {'message': 'overloaded'}
                })),
                529,
              )
            : _decisionResponse(reply: '네.', action: 'chat');
      }),
    );

    await expectLater(service.decide('첫 번째 말'), throwsA(isA<ClaudeException>()));
    await service.decide('두 번째 말');
    service.dispose();

    // 실패한 '첫 번째 말'이 남아 있으면 다음 판단이 오염된다.
    final messages = bodies[1]['messages'] as List<dynamic>;
    expect(messages.length, 1);
    expect(messages.single['content'], '두 번째 말');
  });
}
