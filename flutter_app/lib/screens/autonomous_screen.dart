import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../services/autonomous_skills.dart';
import '../services/claude_service.dart';
import '../services/robot_target_scope.dart';
import '../services/tts_service.dart';
import '../widgets/robot_target_badge.dart';

/// 메뉴 3 — 자율 작업.
///
/// 미키가 할 수 있는 일을 [AutonomousSkills]에 미리 자율행동으로 입력해 두고,
/// 사용자가 말을 하면 Claude가 그것이 어떤 행동을 시키는 말인지 이해한다.
/// 자율주행 명령이면 한 번 더 물어 확인한 뒤, 맞다고 하면 정해진 단계대로 로봇을 움직인다.
/// 자율주행과 관계없는 말이면 Claude가 알아서 짧게 대답한다.
class AutonomousScreen extends StatefulWidget {
  const AutonomousScreen({super.key});

  @override
  State<AutonomousScreen> createState() => _AutonomousScreenState();
}

/// 로봇의 현재 대화 상태.
enum _TalkState { idle, listening, thinking, speaking }

class _AutonomousScreenState extends State<AutonomousScreen> {
  final TextEditingController _taskController = TextEditingController();

  // 자율행동 실행 상태.
  AutonomousSkill? _skill;
  int _stepIndex = 0;
  bool _running = false;

  // 대화 관련.
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final ClaudeService _claude = ClaudeService();

  bool _sttAvailable = false;
  _TalkState _talk = _TalkState.idle;
  String _heard = ''; // 사용자가 말한 내용
  String _reply = ''; // 로봇(Claude) 답변
  String? _talkError;

  /// 한 단계를 수행하는 데 걸리는 시간(시뮬레이션).
  static const Duration _stepDuration = Duration(milliseconds: 2500);

  @override
  void initState() {
    super.initState();
    _initVoice();
  }

  Future<void> _initVoice() async {
    // TTS 한국어 여성 음성 설정.
    await _tts.setLanguage('ko-KR');
    await _tts.setSpeechRate(0.5);
    await applyKoreanFemaleVoice(_tts);
    _tts.setCompletionHandler(() {
      if (mounted && _talk == _TalkState.speaking) {
        setState(() => _talk = _TalkState.idle);
      }
    });

    // 진입 시 인사말.
    await _tts.speak('안녕하세요. 무슨일을 도와 드릴까요?');

    // STT 초기화 (지원 플랫폼에서만 성공).
    try {
      _sttAvailable = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted && _talk == _TalkState.listening) {
              setState(() => _talk = _TalkState.idle);
            }
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _talkError = '음성 인식 오류: ${e.errorMsg}';
              _talk = _TalkState.idle;
            });
          }
        },
      );
    } catch (_) {
      _sttAvailable = false;
    }
    if (mounted) setState(() {});
  }

  // ── 자율행동 실행 ────────────────────────────────────────
  /// 미리 입력해 둔 [skill]의 단계를 순서대로 수행한다.
  /// 홈에서 고른 대상(Gazebo 가상 / OMX-AI 실물)이 실제로 움직인다.
  Future<void> _runSkill(AutonomousSkill skill) async {
    final backend = RobotTargetScope.of(context).backend;
    setState(() {
      _skill = skill;
      _stepIndex = 0;
      _running = true;
    });

    for (var i = 0; i < skill.steps.length; i++) {
      // 중간에 정지 버튼을 누르거나 화면을 벗어나면 멈춘다.
      if (!mounted || !_running) return;
      setState(() => _stepIndex = i);
      await backend.runSkillStep(skill, i);
      await Future.delayed(_stepDuration);
    }

    if (!mounted || !_running) return;
    setState(() => _running = false);
    await _speak('${skill.name}, 다 했어요.');
  }

  void _stop() {
    // 실행 루프가 다음 단계로 넘어가기 전에 멈추도록 먼저 표시한다.
    setState(() => _running = false);
    RobotTargetScope.of(context).backend.stop();
    _speak('알겠어요. 멈출게요.');
  }

  Future<void> _speak(String text) async {
    if (!mounted) return;
    setState(() => _talk = _TalkState.speaking);
    await _tts.speak(text);
  }

  // ── 로봇과 대화하기 ──────────────────────────────────────
  Future<void> _onTalkPressed() async {
    if (_talk == _TalkState.listening) {
      await _speech.stop();
      setState(() => _talk = _TalkState.idle);
      return;
    }
    if (_talk != _TalkState.idle) return; // 생각/말하는 중엔 무시

    if (_sttAvailable) {
      await _startListening();
    } else {
      // Windows 등 STT 미지원 → 텍스트 입력으로 대체.
      await _promptText();
    }
  }

  Future<void> _startListening() async {
    setState(() {
      _talkError = null;
      _heard = '';
      _reply = '';
      _talk = _TalkState.listening;
    });
    await _speech.listen(
      listenOptions: SpeechListenOptions(localeId: 'ko_KR', partialResults: true),
      onResult: (result) {
        setState(() => _heard = result.recognizedWords);
        if (result.finalResult && _heard.trim().isNotEmpty) {
          _ask(_heard.trim());
        }
      },
    );
  }

  Future<void> _promptText() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('${ClaudeService.robotName}에게 말하기'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '메시지를 입력하세요'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('보내기'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text != null && text.trim().isNotEmpty) {
      await _send(text.trim());
    }
  }

  /// 아래 입력창에서 보낸 말. 음성과 똑같이 Claude의 판단을 거친다.
  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _talk != _TalkState.idle) return;
    _taskController.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _talkError = null;
      _heard = text.trim();
      _reply = '';
    });
    await _ask(text.trim());
  }

  /// Claude에게 무엇을 시키는 말인지 물어보고, 답변을 말한 뒤 필요하면 실행한다.
  Future<void> _ask(String message) async {
    setState(() => _talk = _TalkState.thinking);
    final RobotDecision decision;
    try {
      decision = await _claude.decide(message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _talkError = e.toString();
        _talk = _TalkState.idle;
      });
      return;
    }
    if (!mounted) return;

    setState(() {
      _reply = decision.reply;
      _talk = _TalkState.speaking;
    });
    await _tts.speak(decision.reply);
    if (!mounted) return;

    // 확인까지 끝난 명령만 실제로 로봇을 움직인다.
    final skill = decision.skill;
    if (decision.action == RobotAction.execute && skill != null) {
      await _runSkill(skill);
    }
  }

  // ── 지침 보기 ────────────────────────────────────────────
  /// 실제로 Claude에게 보내고 있는 지침을 그대로 보여준다.
  Future<void> _showInstructions() async {
    final prompt = await _claude.systemPrompt();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('${ClaudeService.robotName} 대화 지침'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              prompt,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  String get _talkLabel => switch (_talk) {
        _TalkState.listening => '듣는 중… (탭하여 종료)',
        _TalkState.thinking => '${ClaudeService.robotName}가 생각 중…',
        _TalkState.speaking => '${ClaudeService.robotName}가 말하는 중…',
        _TalkState.idle => _sttAvailable
            ? '${ClaudeService.robotName}와 대화하기'
            : '${ClaudeService.robotName}와 대화 (텍스트)',
      };

  IconData get _talkIcon => switch (_talk) {
        _TalkState.listening => Icons.mic,
        _TalkState.thinking => Icons.hourglass_top,
        _TalkState.speaking => Icons.volume_up,
        _TalkState.idle => _sttAvailable ? Icons.mic_none : Icons.keyboard,
      };

  @override
  void dispose() {
    _running = false; // 진행 중인 자율행동 루프를 멈춘다.
    _taskController.dispose();
    _speech.stop();
    _tts.stop();
    _claude.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('자율 작업'),
        actions: [
          IconButton(
            onPressed: _showInstructions,
            icon: const Icon(Icons.article_outlined),
            tooltip: '대화 지침 보기',
          ),
          const RobotTargetBadge(),
        ],
      ),
      body: Column(
        children: [
          // 로봇 시점 화면.
          Expanded(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.smart_toy_outlined,
                            size: 56, color: Colors.white38),
                        const SizedBox(height: 8),
                        Text('${ClaudeService.robotName} 시점 화면',
                            style: const TextStyle(color: Colors.white38)),
                      ],
                    ),
                  ),
                  // 자율행동 실행 중 단계 표시.
                  if (_running && _skill != null)
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: _SkillProgress(
                        skill: _skill!,
                        stepIndex: _stepIndex,
                        onStop: _stop,
                      ),
                    ),
                  // 대화 말풍선 (하단).
                  if (_heard.isNotEmpty || _reply.isNotEmpty)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: _ConversationBubbles(
                        heard: _heard,
                        reply: _reply,
                        robotName: ClaudeService.robotName,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 로봇과 대화하기 버튼.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    (_talk == _TalkState.thinking || _talk == _TalkState.speaking)
                        ? null
                        : _onTalkPressed,
                icon: Icon(_talkIcon),
                label: Text(_talkLabel),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor:
                      _talk == _TalkState.listening ? Colors.red : null,
                ),
              ),
            ),
          ),
          if (_talkError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text(_talkError!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),

          const Divider(height: 24),

          // 미리 입력해 둔 자율행동 — 탭하면 확인 없이 바로 실행.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final skill in AutonomousSkills.all)
                    ActionChip(
                      label: Text(skill.name),
                      tooltip: skill.description,
                      onPressed: _running ? null : () => _runSkill(skill),
                    ),
                ],
              ),
            ),
          ),
          // 말로 시키기 (음성 대신 텍스트).
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _taskController,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    decoration: const InputDecoration(
                      hintText: '${ClaudeService.robotName}에게 말하기 (예: 물건 좀 옮겨줘)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _talk == _TalkState.idle
                      ? () => _send(_taskController.text)
                      : null,
                  icon: const Icon(Icons.send),
                  label: const Text('보내기'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 실행 중인 자율행동의 단계 진행 표시.
class _SkillProgress extends StatelessWidget {
  const _SkillProgress({
    required this.skill,
    required this.stepIndex,
    required this.onStop,
  });

  final AutonomousSkill skill;
  final int stepIndex;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.deepOrange.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '자율 주행 중: ${skill.name} '
                  '(${stepIndex + 1}/${skill.steps.length})',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: onStop,
                icon: const Icon(Icons.stop, color: Colors.white),
                tooltip: '정지',
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < skill.steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    i < stepIndex
                        ? Icons.check_circle
                        : i == stepIndex
                            ? Icons.play_circle_fill
                            : Icons.circle_outlined,
                    size: 14,
                    color: i <= stepIndex ? Colors.white : Colors.white54,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      skill.steps[i],
                      style: TextStyle(
                        fontSize: 12,
                        color: i <= stepIndex ? Colors.white : Colors.white54,
                        fontWeight:
                            i == stepIndex ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 사용자 발화 / 로봇 답변 말풍선.
class _ConversationBubbles extends StatelessWidget {
  const _ConversationBubbles({
    required this.heard,
    required this.reply,
    required this.robotName,
  });

  final String heard;
  final String reply;
  final String robotName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (heard.isNotEmpty)
          _bubble(
            align: Alignment.centerRight,
            color: Colors.blueGrey.shade700,
            icon: Icons.person,
            name: '나',
            text: heard,
          ),
        if (reply.isNotEmpty) ...[
          const SizedBox(height: 6),
          _bubble(
            align: Alignment.centerLeft,
            color: Colors.deepPurple.shade600,
            icon: Icons.smart_toy,
            name: robotName,
            text: reply,
          ),
        ],
      ],
    );
  }

  Widget _bubble({
    required Alignment align,
    required Color color,
    required IconData icon,
    required String name,
    required String text,
  }) {
    return Align(
      alignment: align,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(text,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
