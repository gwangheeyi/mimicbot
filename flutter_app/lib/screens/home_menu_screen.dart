import 'package:flutter/material.dart';

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
              // 실물 로봇일 때만 안전 안내를 띄운다.
              if (selected.isPhysical) ...[
                const SizedBox(height: 8),
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
