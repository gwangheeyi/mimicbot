import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../services/autonomous_skills.dart';
import '../services/claude_service.dart';
import '../services/robot_command_service.dart';
import '../services/robot_target_scope.dart';
import '../services/tts_service.dart';
import '../widgets/command_log_panel.dart';
import '../widgets/robot_camera_view.dart';
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

  // 춤 실행 중인지. 짧게 잠가 두 번 눌리지 않게 한다.
  bool _dancing = false;

  // 맥시 자율(정책 실행) — 전체 실행 명령 입력과 실행 상태.
  // 기본으로 lerobot-record 명령을 채워 둔다(정책 경로·device 포함). 필요하면
  // 명령칸에서 직접 편집한다(예: GPU 없으면 --policy.device=cuda 를 cpu 로).
  // 카메라는 backend: V4L2 를 꼭 넣어야 640x480 MJPG 설정이 먹는다.
  static const String _defaultPolicyCommand =
      'lerobot-record --robot.type=omx_follower --robot.port=/dev/omx_follower '
      '--robot.id=omx_follower_arm '
      '--robot.cameras="{front: {type: opencv, index_or_path: \'/dev/video2\', '
      'width: 640, height: 480, fps: 30, fourcc: \'MJPG\', backend: V4L2}, '
      'wrist: {type: opencv, index_or_path: \'/dev/video4\', width: 640, '
      'height: 480, fps: 30, fourcc: \'MJPG\', backend: V4L2}}" '
      '--policy.path="/home/gyi/lerobot_models/omx_project-v2-finetuned" '
      '--policy.device=cuda '
      '--display_data=true --dataset.repo_id=gyi/eval_omx_project_v2 '
      '--dataset.single_task="Pick And Place the Pen" --dataset.num_episodes=1 '
      '--dataset.episode_time_s=60 --dataset.reset_time_s=5 '
      '--dataset.push_to_hub=false';
  final TextEditingController _policyController =
      TextEditingController(text: _defaultPolicyCommand);
  bool _policyRunning = false;

  // 대화 관련. 대답은 로컬 ollama(qwen3:4b)가 만들고 TTS로 읽어 준다.
  // TtsService는 소리가 실제로 나는 한국어 음성을 스스로 골라 준다(무음 음성 회피).
  final SpeechToText _speech = SpeechToText();
  final TtsService _tts = TtsService();

  bool _sttAvailable = false;
  _TalkState _talk = _TalkState.idle;
  String _heard = ''; // 사용자가 말한 내용(발화별 줄바꿈 누적, 말풍선에 표시)
  // 이번 화면 대화 세션에서 확정된 발화들(발화마다 줄바꿈으로 누적).
  // 새 발화를 새 줄에 이어 붙이기 위한 기준값이다.
  String _heardCommitted = '';
  String _reply = ''; // 미키(qwen3) 답변
  String? _talkError;

  /// 미키의 상태·질문·답변 기록. 최신이 앞에 온다.
  /// 음성은 인식됐는데 대답이 안 나올 때, 무슨 단계에서 멈췄는지 여기서 확인한다.
  final List<String> _log = [];

  void _addLog(String message) {
    if (!mounted) return;
    setState(() => _log.insert(0, message));
  }

  /// 한 단계를 수행하는 데 걸리는 시간(시뮬레이션).
  static const Duration _stepDuration = Duration(milliseconds: 2500);

  /// 화면 진입 시 예열을 한 번만 요청했는지.
  bool _warmRequested = false;

  @override
  void initState() {
    super.initState();
    _initVoice();
    // 화면에 들어오면 qwen3:4b를 미리 올려 두어 첫 대답을 빠르게 한다.
    // context(대상 host)가 준비된 뒤에 부르도록 첫 프레임 뒤로 미룬다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmUpMicky());
  }

  /// 미키(qwen3)를 미리 예열한다. 대답을 기다리지 않는 백그라운드 요청이다.
  void _warmUpMicky() {
    if (!mounted || _warmRequested) return;
    _warmRequested = true;
    final host = RobotTargetScope.of(context).value.host;
    _addLog('미키를 준비시키는 중… (첫 대답을 빠르게)');
    final service = RobotCommandService(host: host);
    service.warmup().whenComplete(service.dispose);
  }

  Future<void> _initVoice() async {
    // 진입 시 인사말. TtsService가 소리 나는 음성을 스스로 골라 말한다.
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
    _addLog('미키 준비됨 — 말을 걸거나 아래에 입력하세요.');
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

  /// 춤 버튼: 미리 만든 10가지 춤 중 하나를 무작위로 골라 로봇이 춘다.
  Future<void> _dance() async {
    setState(() {
      // 춤 버튼은 대화 말풍선을 비우므로 발화 누적도 초기화한다.
      _heard = '';
      _heardCommitted = '';
      _reply = '';
    });
    await _playDance('신나게 춤춰볼게요!');
  }

  /// "책상을 정리해줘" — 맥시가 학습된 정책을 실행한다(모방학습).
  /// 패널에 입력한 정책 경로로 제어 서버가 lerobot-record 를 돌린다.
  Future<void> _runPolicy() async {
    if (_policyRunning) return;
    final backend = RobotTargetScope.of(context).backend;
    final command = _policyController.text.trim();
    if (command.isEmpty) {
      _addLog('실행할 명령을 입력하세요 (lerobot-record …).');
      return;
    }
    setState(() => _policyRunning = true);
    await _tts.speak('책상을 정리할게요.');
    final status = await backend.runPolicy(command);
    if (!mounted) return;
    setState(() => _policyRunning = false);
    _addLog(status);
  }

  /// 사용자의 말이 춤/댄스 이야기인지 본다. 춤 이야기가 나오면 바로 춤춘다.
  bool _looksLikeDanceRequest(String message) {
    final text = message.toLowerCase();
    return text.contains('춤') ||
        text.contains('댄스') ||
        text.contains('dance');
  }

  /// 실제 춤 실행(대화·버튼 공통). [reply]를 말풍선과 TTS로 먼저 말한 뒤,
  /// 10가지 춤 중 하나를 무작위로 골라 로봇이 춘다. LLM을 기다리지 않아 즉시 반응한다.
  Future<void> _playDance(String reply) async {
    if (_dancing || _running) return;
    final backend = RobotTargetScope.of(context).backend;
    setState(() {
      _dancing = true;
      _talkError = null;
      _reply = reply;
      _talk = _TalkState.speaking;
    });
    _addLog('미키: $reply');

    await _tts.speak(reply);
    final result = await backend.dance();

    if (!mounted) return;
    setState(() {
      _dancing = false;
      if (_talk == _TalkState.speaking) _talk = _TalkState.idle;
    });
    _addLog(result);
    _addLog('미키 준비됨');

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(result),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _speak(String text) async {
    if (!mounted) return;
    setState(() => _talk = _TalkState.speaking);
    await _tts.speak(text);
    if (!mounted) return;
    if (_talk == _TalkState.speaking) {
      setState(() => _talk = _TalkState.idle);
    }
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
      // 이전 발화들은 그대로 두고, 새 발화를 아래 줄에 이어서 인식한다.
      _heard = _heardCommitted;
      _reply = '';
      _talk = _TalkState.listening;
    });
    _addLog('듣는 중…');
    await _speech.listen(
      listenOptions: SpeechListenOptions(localeId: 'ko_KR', partialResults: true),
      onResult: (result) {
        final words = result.recognizedWords;
        setState(() => _heard = _joinHeard(_heardCommitted, words));
        if (result.finalResult && words.trim().isNotEmpty) {
          // 이 발화를 확정해, 다음 발화는 새 줄에 쌓이도록 한다.
          _heardCommitted = _heard.trim();
          _ask(words.trim());
        }
      },
    );
  }

  /// 이전에 확정된 발화들[base] 아래에 새 발화[words]를 줄바꿈으로 잇는다.
  String _joinHeard(String base, String words) {
    if (base.isEmpty) return words;
    if (words.isEmpty) return base;
    return '$base\n$words';
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
    final utterance = text.trim();
    setState(() {
      _talkError = null;
      // 음성과 똑같이 발화별로 줄바꿈해 누적한다.
      _heard = _joinHeard(_heardCommitted, utterance);
      _heardCommitted = _heard;
      _reply = '';
    });
    await _ask(utterance);
  }

  /// 사용자의 말을 처리한다.
  /// 춤/댄스 이야기가 나오면 바로 춤추고, 그 외의 질문은 로컬 ollama(qwen3:4b)가
  /// 대답을 만들어 TTS로 읽어 준다. 외부 API 키 없이 로컬에서 동작한다.
  Future<void> _ask(String message) async {
    _addLog('나: $message');

    if (_looksLikeDanceRequest(message)) {
      await _playDance('좋아요, 신나게 춤춰볼게요!');
      return;
    }

    setState(() {
      _talkError = null;
      _talk = _TalkState.thinking;
    });
    _addLog('미키가 생각 중… (처음엔 모델을 불러오느라 조금 걸려요)');

    // qwen3는 로봇이 연결된 컴퓨터(브리지)에서 돈다. 고른 대상의 host로 물어본다.
    final host = RobotTargetScope.of(context).value.host;
    final service = RobotCommandService(host: host);
    final reply = await service.chat(message);
    service.dispose();

    if (!mounted) return;
    setState(() {
      _reply = reply;
      _talk = _TalkState.speaking;
    });
    _addLog('미키: $reply');
    await _tts.speak(reply);
    if (!mounted) return;
    if (_talk == _TalkState.speaking) {
      setState(() => _talk = _TalkState.idle);
    }
    _addLog('미키 준비됨');
  }

  // ── 지침 보기 ────────────────────────────────────────────
  /// 미키가 어떻게 대화하는지 간단히 보여준다.
  void _showInstructions() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('${ClaudeService.robotName} 대화 방식'),
        content: const SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Text(
              '미키는 로봇 컴퓨터에서 도는 로컬 AI(ollama qwen3:4b)로 대답합니다. '
              '인터넷이나 외부 API 키 없이 동작합니다.\n\n'
              '• 질문을 하면 qwen3가 한두 문장으로 대답하고, 미키가 음성으로 읽어 줍니다.\n'
              '• "춤", "댄스" 이야기가 나오면 바로 10가지 춤 중 하나를 춥니다.\n'
              '• 아래 자율행동 버튼을 누르면 정해진 단계대로 움직입니다.\n\n'
              '대답이 조금 느릴 수 있어요. 로봇 컴퓨터에서 직접 생각하기 때문입니다.',
              style: TextStyle(fontSize: 13, height: 1.6),
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
    _policyController.dispose();
    _speech.stop();
    _tts.stop();
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
          // 로봇 시점 화면 — 동작 명령 화면과 똑같이 Gazebo 카메라 영상을 띄운다.
          // 자율 작업(춤 등)으로 로봇이 움직이면 여기서 실제 동작이 보인다.
          Expanded(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              // 잘린 모서리 밖으로 영상이 삐져나오지 않게 한다.
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 로봇 시점 카메라. 맥시(실물)=mediamtx WebRTC,
                  // 미키(가상)=Gazebo web_video MJPEG.
                  RobotCameraView(
                    target: RobotTargetScope.of(context).value,
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

          // 미키 상태·대화 로그 — 준비됨 / 생각 중 / 질문 / 답변이 여기 쌓인다.
          // 음성은 인식됐는데 대답이 없을 때 어디서 멈췄는지 여기서 확인한다.
          Container(
            height: 96,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: CommandLogPanel(
              log: _log,
              emptyText: '미키 상태와 대화가 여기에 표시됩니다.',
              compact: true,
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

          // 춤추기 — 누를 때마다 10가지 춤 중 하나를 무작위로 춘다.
          // 맥시(실물)는 춤이 팔로워로 안 가므로(ROS2 경로) 버튼을 숨긴다.
          if (!RobotTargetScope.of(context).value.isPhysical)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: (_dancing || _running) ? null : _dance,
                  icon: _dancing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.music_note),
                  label: Text(_dancing ? '춤추는 중…' : '춤추기 (랜덤)'),
                ),
              ),
            ),

          // 맥시(실물) 전용: 학습된 정책(모방학습) 실행 패널.
          // 정책 경로를 입력하고 "책상을 정리해줘"를 누르면 팔로워가 스스로 수행한다.
          if (RobotTargetScope.of(context).value.isPhysical)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _policyController,
                    minLines: 5,
                    maxLines: 12,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: '실행 명령 (lerobot-record …)',
                      helperText:
                          r'전체 명령을 넣으면 그대로 실행됩니다. $POLICY_PATH 는 config의 '
                          'default_policy_path 로 채워지거나, 실제 경로로 바꾸세요.',
                      helperMaxLines: 3,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: (_policyRunning || _running || _dancing)
                        ? null
                        : _runPolicy,
                    icon: _policyRunning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cleaning_services),
                    label: Text(
                        _policyRunning ? '책상 정리 중… (정책 실행)' : '책상을 정리해줘'),
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ],
              ),
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
