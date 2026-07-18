import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'autonomous_skills.dart';

/// 미키가 사용자의 말을 듣고 내린 판단.
enum RobotAction {
  /// 자율행동과 무관 — 대답만 한다.
  chat,

  /// 비슷한 자율행동이 있다 — 맞는지 한 번 더 물어본다.
  confirm,

  /// 사용자가 확인해 줬다 — 자율행동을 실행한다.
  execute,

  /// 자율행동 명령이지만 할 수 있는 것이 없다.
  unsupported,
}

/// Claude가 돌려준 한 번의 판단 결과.
class RobotDecision {
  const RobotDecision({
    required this.reply,
    required this.action,
    required this.skillId,
  });

  /// 미키가 음성으로 말할 답변.
  final String reply;

  /// 무엇을 할지.
  final RobotAction action;

  /// [RobotAction.confirm] / [RobotAction.execute]일 때 대상 자율행동 id.
  /// 그 외에는 빈 문자열.
  final String skillId;

  /// 실행 대상 자율행동. 해당 없으면 null.
  AutonomousSkill? get skill => AutonomousSkills.byId(skillId);
}

/// Claude(Anthropic Messages API)와 대화하는 서비스.
///
/// 단순한 잡담 상대가 아니라 "무엇을 시키는 말인지" 판단하는 역할을 한다.
/// `assets/claude_instructions.md`에 저장해 둔 지침과 자율행동 목록을 시스템
/// 프롬프트로 주고, 구조화 출력(structured outputs)으로 판단 결과를 JSON으로 받는다.
///
/// API 키는 빌드/실행 시 `--dart-define=ANTHROPIC_API_KEY=sk-ant-...` 로 주입한다.
/// (키를 소스에 하드코딩하지 않는다.)
///
/// Windows 데스크톱은 네이티브라 CORS 제약이 없어 직접 호출이 가능하다.
class ClaudeService {
  ClaudeService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _apiKey =
      String.fromEnvironment('ANTHROPIC_API_KEY', defaultValue: '');

  static const String _model = 'claude-opus-4-8';
  static const String _endpoint = 'https://api.anthropic.com/v1/messages';

  /// 저장해 둔 대화 지침 파일.
  static const String _instructionsAsset = 'assets/claude_instructions.md';

  /// 로봇 이름.
  static const String robotName = '미키';

  /// 문맥 유지용 대화 기록. "그거 맞아?" → "응" 흐름을 이해하려면 필요하다.
  /// 무한히 늘어나지 않도록 최근 대화만 남긴다.
  final List<Map<String, dynamic>> _history = [];
  static const int _maxHistoryMessages = 20;

  String? _instructions;

  static bool get hasApiKey => _apiKey.isNotEmpty;

  /// 저장된 지침 원문. 화면에서 "지침 보기"에 쓴다.
  Future<String> instructions() async =>
      _instructions ??= await rootBundle.loadString(_instructionsAsset);

  /// 실제로 Claude에 보내는 시스템 프롬프트 = 저장된 지침 + 자율행동 목록.
  Future<String> systemPrompt() async =>
      '${await instructions()}\n\n${AutonomousSkills.promptSection()}';

  /// 판단 결과를 강제할 JSON 스키마.
  ///
  /// `skill_id`를 enum으로 묶어 두면 Claude가 목록에 없는 행동을 지어낼 수 없다.
  Map<String, dynamic> _decisionSchema() => {
        'type': 'object',
        'properties': {
          'reply': {
            'type': 'string',
            'description': '미키가 음성으로 말할 한국어 답변. 1~2문장, 마크다운과 이모지 없이.',
          },
          'action': {
            'type': 'string',
            'enum': ['chat', 'confirm', 'execute', 'unsupported'],
            'description': 'chat=자율행동과 무관한 대화, confirm=비슷한 자율행동이 있어 한 번 더 확인, '
                'execute=사용자가 확인해 줘서 실행, unsupported=할 수 있는 자율행동이 없음.',
          },
          'skill_id': {
            'type': 'string',
            'enum': AutonomousSkills.idsForSchema,
            'description': 'confirm 또는 execute일 때 대상 자율행동의 id. 그 외에는 빈 문자열.',
          },
        },
        'required': ['reply', 'action', 'skill_id'],
        'additionalProperties': false,
      };

  /// 사용자 발화를 Claude에 보내고 판단 결과를 받는다.
  Future<RobotDecision> decide(String userMessage) async {
    if (!hasApiKey) {
      throw const ClaudeException(
        'API 키가 설정되지 않았습니다.\n'
        '실행 시 --dart-define=ANTHROPIC_API_KEY=sk-ant-... 를 추가하세요.',
      );
    }

    final system = await systemPrompt();
    _history.add({'role': 'user', 'content': userMessage});
    _trimHistory();

    final response = await _client.post(
      Uri.parse(_endpoint),
      headers: {
        'content-type': 'application/json',
        'x-api-key': _apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
        'model': _model,
        // 짧은 음성 답변 + 작은 JSON이라 넉넉하다.
        'max_tokens': 1024,
        'system': system,
        'output_config': {
          // 응답을 판단 스키마에 맞는 JSON으로 강제한다.
          'format': {'type': 'json_schema', 'schema': _decisionSchema()},
          // 음성 대화라 빠를수록 좋지만, 확인 단계를 건너뛰지 않으려면 문맥 판단이 필요하다.
          // 응답이 느리면 low, 엉뚱한 행동을 고르면 high로 조절한다.
          'effort': 'medium',
        },
        'messages': _history,
      }),
    );

    if (response.statusCode != 200) {
      // 실패한 발화는 기록에서 빼야 다음 요청이 오염되지 않는다.
      _history.removeLast();
      String detail = 'HTTP ${response.statusCode}';
      try {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        detail = body['error']?['message']?.toString() ?? detail;
      } catch (_) {
        // 파싱 실패 시 상태코드만 사용.
      }
      throw ClaudeException('Claude 호출 실패: $detail');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));

    // 안전상의 이유로 답변을 거절하면 content가 비어 있을 수 있다.
    if (data['stop_reason'] == 'refusal') {
      _history.removeLast();
      return const RobotDecision(
        reply: '그건 제가 대답하기 어려운 내용이에요. 다른 걸 도와드릴까요?',
        action: RobotAction.chat,
        skillId: '',
      );
    }

    final text = _firstText(data['content'] as List<dynamic>?);
    if (text.isEmpty) {
      _history.removeLast();
      throw const ClaudeException('Claude 응답이 비어 있습니다.');
    }

    // 스키마를 강제했으므로 정상 응답이면 항상 파싱된다.
    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      _history.removeLast();
      throw ClaudeException('Claude 응답을 이해하지 못했습니다: $text');
    }

    // 다음 턴에서 "응, 맞아"를 알아들으려면 방금 한 말을 기억해야 한다.
    _history.add({'role': 'assistant', 'content': text});
    _trimHistory();

    return RobotDecision(
      reply: (decoded['reply'] as String? ?? '').trim(),
      action: _parseAction(decoded['action'] as String?),
      skillId: decoded['skill_id'] as String? ?? '',
    );
  }

  /// 대화를 처음부터 다시 시작한다.
  void resetConversation() => _history.clear();

  String _firstText(List<dynamic>? content) {
    if (content == null) return '';
    for (final block in content) {
      if (block is Map && block['type'] == 'text') {
        return (block['text'] as String? ?? '').trim();
      }
    }
    return '';
  }

  RobotAction _parseAction(String? value) => switch (value) {
        'confirm' => RobotAction.confirm,
        'execute' => RobotAction.execute,
        'unsupported' => RobotAction.unsupported,
        _ => RobotAction.chat,
      };

  /// 첫 메시지는 user여야 하므로 항상 짝수 개씩 잘라낸다.
  void _trimHistory() {
    while (_history.length > _maxHistoryMessages) {
      _history.removeRange(0, 2);
    }
  }

  void dispose() => _client.close();
}

class ClaudeException implements Exception {
  const ClaudeException(this.message);
  final String message;

  @override
  String toString() => message;
}
