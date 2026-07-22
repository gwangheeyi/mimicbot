import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../services/robot_command_service.dart';
import '../services/robot_target.dart';
import '../services/robot_target_scope.dart';
import '../widgets/flow_diagram.dart';
import 'command_control_screen.dart';
import 'mimic_view_screen.dart';
import 'autonomous_screen.dart';

/// 홈 화면.
/// 최상단: 실행 대상 선택 (Gazebo 가상 / OMX-AI 실물) — 세 메뉴에 모두 적용된다.
/// 상단: 3개 기능으로 가는 가로 버튼 메뉴.
/// 아래: ROS 기반 모방 학습 원리와 메뉴별 작동 방식을 도표로 설명.
class HomeMenuScreen extends StatelessWidget {
  const HomeMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mimic Bot'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Micky 깨우기 (모든 브링업·서비스 백그라운드 시작) ──
              const _WakeButton(),
              const SizedBox(height: 24),

              // ── 실행 대상 선택 (세 메뉴 공통) ────────────────────
              const _SectionTitle(
                icon: Icons.hub,
                title: '실행 대상',
              ),
              const SizedBox(height: 8),
              const _TargetSelector(),
              const SizedBox(height: 28),

              // ── 상단 가로 버튼 메뉴 ──────────────────────────────
              Row(
                children: [
                  _MenuButton(
                    icon: Icons.touch_app,
                    label: '동작 명령',
                    color: Colors.indigo,
                    onTap: () => _open(context, const CommandControlScreen()),
                  ),
                  const SizedBox(width: 12),
                  _MenuButton(
                    icon: Icons.compare_arrows,
                    label: '실시간 모방',
                    color: Colors.teal,
                    onTap: () => _open(context, const MimicViewScreen()),
                  ),
                  const SizedBox(width: 12),
                  _MenuButton(
                    icon: Icons.smart_toy,
                    label: '자율 작업',
                    color: Colors.deepOrange,
                    onTap: () => _open(context, const AutonomousScreen()),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // ── 섹션 1: 모방 학습 원리 (ROS 기반) ────────────────
              const _SectionTitle(
                icon: Icons.school,
                title: '로봇 모방 학습의 원리 (ROS 기반)',
              ),
              const SizedBox(height: 8),
              Text(
                '모방 로봇은 사람의 시연을 보고 따라 하도록 학습합니다. '
                '카메라·센서로 사람을 관찰하고, 그 움직임을 로봇 관절로 변환한 뒤, '
                '모방 학습으로 만든 정책이 로봇을 제어합니다. 이 과정의 각 단계는 '
                'ROS 노드로 구현되고 토픽(topic)으로 데이터를 주고받습니다.',
                style: TextStyle(
                    height: 1.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 18),

              Pipeline(
                loopBackLabel: '피드백 루프  /joint_states, /camera',
                nodes: const [
                  FlowNode(
                    icon: Icons.person,
                    title: '1. 사람 시연 (Demonstration)',
                    subtitle: '사람이 원하는 동작을 직접 보여줍니다.',
                    color: Colors.indigo,
                    topic: '/camera/image_raw',
                  ),
                  FlowNode(
                    icon: Icons.visibility,
                    title: '2. 인식 (Perception)',
                    subtitle: '카메라·센서로 관찰하고 포즈/물체를 추정합니다. '
                        '(예: MediaPipe, 딥러닝 검출)',
                    color: Colors.cyan,
                    topic: '/hand_pose, /object_pose',
                  ),
                  FlowNode(
                    icon: Icons.transform,
                    title: '3. 리타게팅 (Retargeting)',
                    subtitle: '사람의 관절 좌표를 로봇의 관절 구조에 맞게 변환합니다.',
                    color: Colors.teal,
                    topic: '/target_trajectory',
                  ),
                  FlowNode(
                    icon: Icons.psychology,
                    title: '4. 모방 학습 · 정책 (Policy)',
                    subtitle: '시연 데이터로 정책을 학습합니다. '
                        '(행동 복제 BC, 역강화학습, 확산 정책 등)',
                    color: Colors.deepPurple,
                    topic: '/cmd_trajectory',
                  ),
                  FlowNode(
                    icon: Icons.route,
                    title: '5. 모션 플래닝 (MoveIt)',
                    subtitle: '충돌을 피하는 실제 실행 경로를 생성합니다.',
                    color: Colors.orange,
                    topic: '/joint_command',
                  ),
                  FlowNode(
                    icon: Icons.precision_manufacturing,
                    title: '6. 제어 · 구동 (Controller)',
                    subtitle: '액추에이터를 구동해 로봇이 동작을 수행하고, '
                        '결과를 다시 관찰해 반복 개선합니다.',
                    color: Colors.redAccent,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── ROS 노드 통신 그래프 ─────────────────────────────
              const _SectionTitle(
                icon: Icons.account_tree,
                title: 'ROS 노드 간 통신 (Pub/Sub)',
              ),
              const SizedBox(height: 6),
              Text(
                '각 기능은 독립된 노드로 동작하며, 토픽을 발행(publish)하고 '
                '구독(subscribe)해 느슨하게 연결됩니다.',
                style: TextStyle(
                    height: 1.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: PubSubGraph(
                    nodes: [
                      ('camera_node', Colors.cyan),
                      ('perception', Colors.teal),
                      ('policy', Colors.deepPurple),
                      ('moveit', Colors.orange),
                      ('controller', Colors.redAccent),
                    ],
                    topics: [
                      '/image_raw',
                      '/hand_pose',
                      '/cmd_traj',
                      '/joint_cmd',
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // ── 섹션 2: 메뉴별 모방 방식 ─────────────────────────
              const _SectionTitle(
                icon: Icons.widgets,
                title: '메뉴별 모방 작동 방식',
              ),
              const SizedBox(height: 16),

              _ConceptCard(
                icon: Icons.touch_app,
                color: Colors.indigo,
                title: '동작 명령',
                description: '가장 단순한 모방입니다. 화면의 한 점을 지정하거나 '
                    '"안녕·경례" 같은 명령을 주면, 미리 정의된 동작(모션 프리미티브)을 '
                    '그대로 재생합니다. 실시간 학습 없이 즉시 1:1로 따라 합니다.',
                nodes: const [
                  FlowNode(
                    icon: Icons.ads_click,
                    title: '명령 입력',
                    subtitle: '탭 지점 좌표 또는 프리셋 동작 선택',
                    color: Colors.indigo,
                    topic: '/goal_point, /gesture_cmd',
                  ),
                  FlowNode(
                    icon: Icons.menu_book,
                    title: '동작 프리미티브 선택',
                    subtitle: '명령에 대응하는 저장된 동작을 불러옴',
                    color: Colors.indigo,
                    topic: '/joint_command',
                  ),
                  FlowNode(
                    icon: Icons.precision_manufacturing,
                    title: '로봇 실행',
                    subtitle: '지정 지점 이동 또는 동작 재생',
                    color: Colors.indigo,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _ConceptCard(
                icon: Icons.compare_arrows,
                color: Colors.teal,
                title: '실시간 모방',
                description: '사람의 손동작을 카메라로 실시간 캡처해 로봇이 곧바로 '
                    '따라 하는 미러링입니다. 위 화면(사람)과 아래 화면(로봇)이 '
                    '거의 지연 없이 대응합니다. 연속적인 포즈 추정과 리타게팅이 핵심입니다.',
                nodes: const [
                  FlowNode(
                    icon: Icons.videocam,
                    title: '카메라 캡처',
                    subtitle: '사용자 손동작 영상 (상단 화면)',
                    color: Colors.teal,
                    topic: '/camera/image_raw',
                  ),
                  FlowNode(
                    icon: Icons.back_hand,
                    title: '포즈 추정 · 리타게팅',
                    subtitle: '손 관절 추출 → 로봇 관절로 실시간 변환',
                    color: Colors.teal,
                    topic: '/joint_command (stream)',
                  ),
                  FlowNode(
                    icon: Icons.smart_toy,
                    title: '로봇 실시간 추종',
                    subtitle: '사람 동작을 따라 미러링 (하단 화면)',
                    color: Colors.teal,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _ConceptCard(
                icon: Icons.smart_toy,
                color: Colors.deepOrange,
                title: '자율 작업',
                description: '가장 상위 단계입니다. "물건을 옮겨" 같은 자연어 명령을 '
                    '작업 계획으로 분해하고, 모방 학습으로 익힌 스킬(집기·놓기 등)을 '
                    '스스로 순서대로 실행합니다. 인식 결과에 따라 스스로 판단하며 반복합니다.',
                nodes: const [
                  FlowNode(
                    icon: Icons.chat,
                    title: '자연어 명령',
                    subtitle: '"물건을 꺼내서 옮겨"',
                    color: Colors.deepOrange,
                    topic: '/task_goal',
                  ),
                  FlowNode(
                    icon: Icons.checklist,
                    title: '작업 계획 (Task Planner)',
                    subtitle: '접근 → 집기 → 이동 → 놓기 로 분해',
                    color: Colors.deepOrange,
                    topic: '/skill_sequence',
                  ),
                  FlowNode(
                    icon: Icons.psychology,
                    title: '학습된 스킬 실행',
                    subtitle: '모방 학습 정책이 각 스킬을 수행',
                    color: Colors.deepOrange,
                    topic: '/joint_command',
                  ),
                  FlowNode(
                    icon: Icons.autorenew,
                    title: '인식 기반 자율 반복',
                    subtitle: '결과를 관찰하며 완료까지 스스로 조정',
                    color: Colors.deepOrange,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

/// "Micky 깨우기" 버튼.
///
/// 한 번 누르면 로봇을 쓰기 위해 필요한 브링업·서비스(Gazebo, 카메라 브리지,
/// 모션 서버, 손 모방 노드, 웹 영상 서버)를 브리지 서버가 한꺼번에
/// 백그라운드로 띄운다. 프로세스만 띄우고 바로 응답하므로 몇 초 안에 끝난다.
///
/// 이 버튼은 브리지 서버(:8000)가 이미 떠 있어야 동작한다. 브리지 서버가
/// 나머지 서비스를 자식 프로세스로 실행한다.
class _WakeButton extends StatefulWidget {
  const _WakeButton();

  @override
  State<_WakeButton> createState() => _WakeButtonState();
}

class _WakeButtonState extends State<_WakeButton> {
  bool _waking = false;
  // 재우는 중인지 — 재우기 버튼에 진행 표시를 띄우고 버튼을 잠근다.
  bool _sleeping = false;
  // Micky가 깨어 있는지(마지막 깨우기가 성공했는지) — 아이콘·재우기 버튼 표시 기준.
  bool _awake = false;
  // 마지막 깨우기 결과의 서비스별 상세 로그(복사 대상).
  String _log = '';
  // 마지막 결과가 성공이었는지 — 로그 상자 색을 정한다.
  bool _lastSuccess = true;

  bool get _busy => _waking || _sleeping;

  Future<void> _wake() async {
    if (_busy) return;

    // 지금 고른 대상의 컴퓨터를 깨운다. Gazebo 가상이면 내 컴, OMX-AI 실물이면
    // 로봇이 연결된 다른 컴. 각 컴의 브리지 서버가 무엇을 띄울지는 그 컴에서 정한다.
    final target = RobotTargetScope.of(context).value;
    final service =
        RobotCommandService(host: target.host, target: target.name);

    setState(() => _waking = true);

    final result = await service.wake();
    service.dispose();

    if (!mounted) return;
    // 서버 메시지의 기본 이름(Micky)을 대상 이름(미키/맥시)으로 바꿔 보여 준다.
    final message = result.message.replaceAll('Micky', target.robotName);
    setState(() {
      _waking = false;
      _awake = result.success;
      _lastSuccess = result.success;
      // 상세 로그가 없으면 요약 메시지라도 보여 준다.
      _log = result.log.isNotEmpty ? result.log : message;
    });

    _showResult(message, result.success);
  }

  // "미키 재우기" — 깨우기로 띄운 모든 서비스를 끈다.
  Future<void> _sleep() async {
    if (_busy) return;

    final target = RobotTargetScope.of(context).value;
    final service =
        RobotCommandService(host: target.host, target: target.name);

    setState(() => _sleeping = true);

    final result = await service.sleep();
    service.dispose();

    if (!mounted) return;
    final message = result.message.replaceAll('Micky', target.robotName);
    setState(() {
      _sleeping = false;
      // 성공적으로 껐으면 다시 자는 상태로.
      if (result.success) _awake = false;
      _lastSuccess = result.success;
      _log = result.log.isNotEmpty ? result.log : message;
    });

    _showResult(message, result.success);
  }

  void _showResult(String message, bool success) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            success ? Colors.green.shade700 : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _copyLog() async {
    await Clipboard.setData(ClipboardData(text: _log));
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('로그를 클립보드에 복사했습니다'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const color = Colors.amber;
    // 지금 고른 대상 — 이 대상의 컴퓨터를 깨운다(가상=내 컴, 실물=로봇 컴).
    final target = RobotTargetScope.of(context).value;
    // 자는 중이면 달(수면) 아이콘, 깨어났으면 해(기상) 아이콘.
    final stateIcon = _awake ? Icons.wb_sunny : Icons.bedtime;
    // 대상에 따라 로봇 이름이 바뀐다. 가상=미키, OMX-AI 실물=맥시.
    final name = target.robotName;
    final title = _waking
        ? '$name 깨우는 중…'
        : (_awake ? '$name 깨어남' : '$name 깨우기');
    final subtitle = _awake
        ? '다시 누르면 꺼진 서비스만 다시 시작합니다 · ${target.label}(${target.host})'
        : '${target.label} 컴퓨터(${target.host})의 브링업·서비스를 한꺼번에 시작합니다';

    final wakeCard = Material(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _busy ? null : _wake,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.7)),
          ),
          child: Row(
            children: [
              if (_waking)
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: color,
                  ),
                )
              else
                Icon(stateIcon, size: 30, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_waking)
                Icon(
                  _awake ? Icons.check_circle : Icons.bolt,
                  color: _awake ? Colors.green : color,
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 깨어 있으면 오른쪽에 절반 크기(2:1)의 "미키 재우기" 버튼을 붙인다.
        if (_awake)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 2, child: wakeCard),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: _SleepButton(
                    robotName: name,
                    sleeping: _sleeping,
                    onTap: _busy ? null : _sleep,
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(width: double.infinity, child: wakeCard),

        // ── 에러/실행 로그 (복사 가능) ──────────────────────────
        if (_log.isNotEmpty) ...[
          const SizedBox(height: 10),
          _WakeLogPanel(
            log: _log,
            isError: !_lastSuccess,
            onCopy: _copyLog,
          ),
        ],
      ],
    );
  }
}

/// "<로봇> 재우기" 버튼. 깨어 있을 때만 깨우기 버튼 오른쪽에 절반 크기로 뜬다.
/// 누르면 깨우기로 띄운 모든 서비스를 끈다. 대상에 따라 미키/맥시로 표시한다.
class _SleepButton extends StatelessWidget {
  const _SleepButton({
    required this.robotName,
    required this.sleeping,
    required this.onTap,
  });

  /// 재울 로봇 이름(미키/맥시). 버튼 라벨에 쓴다.
  final String robotName;
  final bool sleeping;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const color = Colors.indigo;
    return Material(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.7)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (sleeping)
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: color,
                  ),
                )
              else
                const Icon(Icons.bedtime, size: 26, color: color),
              const SizedBox(height: 6),
              Text(
                sleeping ? '재우는 중…' : '$robotName 재우기',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 깨우기 결과 로그 상자. 실패 시 빨간 테두리로 강조하고, 우측 상단 복사
/// 버튼으로 전체 로그를 클립보드에 복사할 수 있다.
class _WakeLogPanel extends StatelessWidget {
  const _WakeLogPanel({
    required this.log,
    required this.isError,
    required this.onCopy,
  });

  final String log;
  final bool isError;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final accent = isError ? Colors.redAccent : Colors.green;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.receipt_long,
                size: 16,
                color: accent,
              ),
              const SizedBox(width: 6),
              Text(
                isError ? '에러 로그' : '실행 로그',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: accent,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('복사'),
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 로그는 길 수 있으므로 스크롤 가능하고, 길게 눌러 선택·복사도 된다.
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            width: double.infinity,
            child: SingleChildScrollView(
              child: SelectableText(
                log,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 실행 대상 선택 — 여기서 고른 대상으로 세 메뉴가 모두 동작한다.
class _TargetSelector extends StatelessWidget {
  const _TargetSelector();

  @override
  Widget build(BuildContext context) {
    // 대상이 바뀌면 이 위젯이 자동으로 다시 그려진다.
    final controller = RobotTargetScope.of(context);
    final selected = controller.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<RobotTarget>(
            segments: [
              for (final target in RobotTarget.values)
                ButtonSegment(
                  value: target,
                  icon: Icon(target.icon),
                  label: Text(target.label),
                ),
            ],
            selected: {selected},
            onSelectionChanged: (s) => controller.value = s.first,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: selected.color.withValues(alpha: 0.25),
              selectedForegroundColor: selected.color,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected.color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected.color.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(selected.icon, size: 18, color: selected.color),
                  const SizedBox(width: 8),
                  Text(
                    selected.subtitle,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: selected.color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                selected.description,
                style: TextStyle(
                  height: 1.5,
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              // 실물 로봇(맥시)일 때: 서버 IP를 보여주고 바로 바꿀 수 있게 한다.
              if (selected.isPhysical) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.lan, size: 16, color: selected.color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '맥시 서버 IP  ${AppConfig.maxiHost}:${AppConfig.robotServerPort}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _editMaxiIp(context, controller),
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('IP 변경'),
                      style: TextButton.styleFrom(
                        foregroundColor: selected.color,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 16, color: Colors.amber),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '실제 로봇이 움직입니다. 로봇 주변에 사람과 물건이 없는지 확인하세요.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade200,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 맥시(실물 로봇) 서버 IP를 입력받아 바꾼다. 재빌드 없이 즉시 적용된다.
  /// 이후 모든 명령·영상이 이 IP의 브리지 서버로 나간다.
  Future<void> _editMaxiIp(
    BuildContext context,
    RobotTargetController controller,
  ) async {
    final textController = TextEditingController(text: AppConfig.maxiHost);
    final ip = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('맥시(실물 로봇) 서버 IP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '실물 로봇이 연결된 컴퓨터의 IP를 입력하세요.\n'
              '그 컴퓨터에서 hostname -I 로 확인할 수 있어요.',
              style: TextStyle(fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: '예: 192.168.0.20',
                prefixIcon: Icon(Icons.lan),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(textController.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    textController.dispose();

    if (ip == null) return;
    final trimmed = ip.trim();
    if (trimmed.isEmpty) return;

    AppConfig.maxiHost = trimmed;
    // 이 IP를 쓰는 화면들(깨우기 버튼·배지 등)을 다시 그린다.
    controller.refresh();
  }
}

/// 상단 가로 메뉴 버튼 하나.
class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.6)),
            ),
            child: Column(
              children: [
                Icon(icon, size: 30, color: color),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 섹션 제목 (아이콘 + 텍스트 + 밑줄).
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

/// 메뉴별 개념 설명 카드: 제목 + 설명 + 미니 파이프라인.
class _ConceptCard extends StatelessWidget {
  const _ConceptCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.nodes,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final List<FlowNode> nodes;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 10),
              Text(title,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ],
          ),
          const SizedBox(height: 10),
          Text(description,
              style: TextStyle(
                  height: 1.5,
                  fontSize: 13.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Pipeline(nodes: nodes),
        ],
      ),
    );
  }
}
