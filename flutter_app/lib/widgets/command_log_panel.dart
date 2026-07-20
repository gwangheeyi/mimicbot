import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 명령 기록 패널 — 전체 복사와 부분 선택을 지원한다.
///
/// 동작 명령·실시간 모방 두 화면이 같은 방식으로 기록을 보여주도록 여기 모았다.
/// 부모가 준 크기를 그대로 채우므로, 화면 아래 칸에도 영상 위 겹침 패널에도 쓸 수 있다.
class CommandLogPanel extends StatelessWidget {
  const CommandLogPanel({
    super.key,
    required this.log,
    this.emptyText = '명령 기록이 여기에 표시됩니다.',
    this.compact = false,
  });

  /// 최신 기록이 앞에 오는 목록.
  final List<String> log;

  /// 기록이 없을 때 보여줄 안내.
  final String emptyText;

  /// 영상 위에 겹쳐 놓을 때처럼 좁은 자리에서 쓸 때 글자와 여백을 줄인다.
  final bool compact;

  Future<void> _copyAll(BuildContext context) async {
    if (log.isEmpty) return;
    // 화면에 보이는 순서(최신이 위) 그대로 담는다.
    await Clipboard.setData(ClipboardData(text: log.join('\n')));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('명령 기록 ${log.length}줄을 복사했습니다.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (log.isEmpty) {
      return Center(
        child: Text(
          emptyText,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white38,
            fontSize: compact ? 11 : null,
          ),
        ),
      );
    }

    final textStyle = TextStyle(
      color: compact ? Colors.white70 : null,
      fontSize: compact ? 11 : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '명령 기록 ${log.length}줄',
              style: TextStyle(
                color: Colors.white54,
                fontSize: compact ? 10 : 12,
              ),
            ),
            const Spacer(),
            // 로그를 통째로 클립보드에 복사.
            compact
                ? IconButton(
                    onPressed: () => _copyAll(context),
                    icon: const Icon(Icons.copy_all, size: 16),
                    color: Colors.white70,
                    tooltip: '전체 복사',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  )
                : TextButton.icon(
                    onPressed: () => _copyAll(context),
                    icon: const Icon(Icons.copy_all, size: 16),
                    label: const Text('전체 복사'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
          ],
        ),
        // 한 줄만 필요할 때는 드래그해서 골라 복사할 수 있다.
        Expanded(
          child: SelectionArea(
            child: ListView.builder(
              itemCount: log.length,
              itemBuilder: (context, i) => Padding(
                padding: EdgeInsets.symmetric(vertical: compact ? 1 : 2),
                child: Text('• ${log[i]}', style: textStyle),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
