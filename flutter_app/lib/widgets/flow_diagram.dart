import 'package:flutter/material.dart';

/// 파이프라인(세로 플로우) 한 단계를 나타내는 데이터.
class FlowNode {
  const FlowNode({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.topic,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  /// 이 단계에서 다음 단계로 가는 화살표에 표시할 ROS 토픽/메시지 라벨.
  final String? topic;
}

/// 세로 방향 파이프라인 다이어그램.
/// 각 노드 사이에 화살표(+토픽 라벨)를 자동으로 끼워 넣는다.
class Pipeline extends StatelessWidget {
  const Pipeline({super.key, required this.nodes, this.loopBackLabel});

  final List<FlowNode> nodes;

  /// 마지막 → 처음으로 되돌아가는 피드백 루프 라벨(선택).
  final String? loopBackLabel;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < nodes.length; i++) {
      children.add(_FlowStepCard(node: nodes[i]));
      final isLast = i == nodes.length - 1;
      if (!isLast) {
        children.add(_FlowArrow(label: nodes[i].topic));
      }
    }
    if (loopBackLabel != null) {
      children.add(_FlowArrow(label: loopBackLabel, loop: true));
    }
    return Column(children: children);
  }
}

class _FlowStepCard extends StatelessWidget {
  const _FlowStepCard({required this.node});
  final FlowNode node;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: node.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: node.color.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: node.color.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(node.icon, color: node.color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(node.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 3),
                Text(node.subtitle,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowArrow extends StatelessWidget {
  const _FlowArrow({this.label, this.loop = false});
  final String? label;
  final bool loop;

  @override
  Widget build(BuildContext context) {
    final color = loop ? Colors.amber : Colors.white38;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            children: [
              Container(width: 2, height: 14, color: color),
              Icon(loop ? Icons.replay : Icons.arrow_downward,
                  size: 16, color: color),
            ],
          ),
          if (label != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Text(
                label!,
                style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: loop ? Colors.amber : Colors.white70),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// ROS 노드 간 Pub/Sub 통신을 가로로 보여주는 그래프.
/// [nodes]는 노드 이름, 그 사이의 [topics]는 화살표 위 토픽 이름.
class PubSubGraph extends StatelessWidget {
  const PubSubGraph({super.key, required this.nodes, required this.topics});

  /// 각 노드: (이름, 색).
  final List<(String, Color)> nodes;

  /// 노드 사이 토픽 이름. 길이는 nodes.length - 1.
  final List<String> topics;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < nodes.length; i++) {
      children.add(_node(nodes[i].$1, nodes[i].$2));
      if (i < topics.length) {
        children.add(_topicArrow(topics[i]));
      }
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: children),
    );
  }

  Widget _node(String name, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hub, size: 14, color: color),
          const SizedBox(width: 6),
          Text(name,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _topicArrow(String topic) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(topic,
              style: const TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                  color: Colors.white60)),
          const SizedBox(height: 2),
          const Icon(Icons.arrow_forward, size: 16, color: Colors.white38),
        ],
      ),
    );
  }
}
