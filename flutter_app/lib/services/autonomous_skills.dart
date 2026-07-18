/// 미키가 미리 할 줄 아는 자율행동(자율주행) 목록.
///
/// 메뉴 3 "자율 작업"의 핵심 데이터다. 여기에 미리 입력해 둔 행동만 미키가 할 수 있고,
/// 사용자가 말을 하면 Claude가 이 목록 중 무엇을 시키는 것인지 골라낸다.
/// 새 행동을 추가하려면 이 목록에 항목 하나만 더하면 된다.
/// (Claude에게 주는 설명과 화면의 버튼이 모두 이 목록에서 자동으로 만들어진다.)
class AutonomousSkill {
  const AutonomousSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.examples,
    required this.steps,
  });

  /// Claude가 고르는 식별자. 목록 안에서 유일해야 한다.
  final String id;

  /// 사람에게 보여줄 이름.
  final String name;

  /// 이 행동이 무엇을 하는지. Claude가 의도를 맞출 때 쓴다.
  final String description;

  /// 사용자가 이 행동을 시킬 때 쓸 법한 표현들.
  final List<String> examples;

  /// 실제 자율주행 단계. 순서대로 실행된다.
  final List<String> steps;
}

/// 미리 입력해 둔 자율행동 카탈로그.
abstract final class AutonomousSkills {
  static const List<AutonomousSkill> all = [
    AutonomousSkill(
      id: 'pick_and_place',
      name: '물건 옮기기',
      description: '물건을 집어서 다른 위치로 옮겨 놓는다.',
      examples: ['물건을 꺼내서 옮겨', '저거 좀 저쪽으로 옮겨줘', '상자 좀 옮겨줄래'],
      steps: [
        '물건 앞으로 접근',
        '물건 집기',
        '목표 위치로 이동',
        '물건 내려놓기',
        '원위치로 복귀',
      ],
    ),
    AutonomousSkill(
      id: 'tidy_table',
      name: '테이블 정리',
      description: '테이블 위에 흩어진 물건들을 제자리에 정리한다.',
      examples: ['테이블 위를 정리해', '책상 좀 치워줘', '여기 정리 좀 해줘'],
      steps: [
        '테이블 앞으로 이동',
        '테이블 위 물체 인식',
        '물건 하나씩 집기',
        '지정된 자리에 놓기',
        '정리 상태 확인',
      ],
    ),
    AutonomousSkill(
      id: 'cup_to_shelf',
      name: '컵을 선반에 놓기',
      description: '컵을 집어서 선반 위에 올려 놓는다.',
      examples: ['컵을 집어서 선반에 놓아', '컵 좀 치워줘', '이 컵 선반에 올려줘'],
      steps: [
        '컵 위치 인식',
        '컵 앞으로 접근',
        '컵 집기',
        '선반 앞으로 이동',
        '선반에 컵 올려놓기',
      ],
    ),
    AutonomousSkill(
      id: 'move_to_door',
      name: '문 쪽으로 이동',
      description: '장애물을 피해 문 앞까지 스스로 이동한다.',
      examples: ['문 쪽으로 이동해', '문 앞으로 가', '입구로 가줘'],
      steps: [
        '현재 위치 확인',
        '문까지 경로 계획',
        '장애물 회피하며 주행',
        '문 앞에서 정지',
      ],
    ),
    AutonomousSkill(
      id: 'return_home',
      name: '제자리로 돌아가기',
      description: '처음 출발했던 자리(충전 스테이션)로 돌아간다.',
      examples: ['제자리로 돌아가', '집에 가', '원래 자리로 복귀해', '충전하러 가'],
      steps: [
        '충전 스테이션 위치 확인',
        '복귀 경로 계획',
        '장애물 회피하며 주행',
        '도킹 후 대기',
      ],
    ),
  ];

  /// [id]에 해당하는 자율행동. 없으면 null.
  static AutonomousSkill? byId(String id) {
    for (final skill in all) {
      if (skill.id == id) return skill;
    }
    return null;
  }

  /// Claude가 고를 수 있는 id 목록. 빈 문자열은 "해당 없음"을 뜻한다.
  static List<String> get idsForSchema => [for (final s in all) s.id, ''];

  /// 시스템 지침 뒤에 붙일 자율행동 목록 설명.
  ///
  /// 목록을 코드에서 만들어 주므로 지침 파일과 카탈로그가 서로 어긋나지 않는다.
  static String promptSection() {
    final buffer = StringBuffer('## 미키가 할 수 있는 자율행동 목록\n');
    for (final skill in all) {
      buffer
        ..writeln()
        ..writeln('### ${skill.name}')
        ..writeln('- id: ${skill.id}')
        ..writeln('- 하는 일: ${skill.description}')
        ..writeln('- 사용자가 이렇게 말할 수 있다: '
            '${skill.examples.map((e) => '"$e"').join(', ')}')
        ..writeln('- 실행 단계: ${skill.steps.join(' → ')}');
    }
    return buffer.toString();
  }
}
