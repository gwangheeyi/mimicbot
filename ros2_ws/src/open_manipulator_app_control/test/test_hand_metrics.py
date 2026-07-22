"""손 관절 계산이 의도대로 동작하는지 확인합니다.

카메라나 ROS2 없이 돌아가므로 로봇을 켜지 않고도 매핑을 시험할 수 있습니다.
"""

import pytest

from open_manipulator_app_control.hand_metrics import (
    arm_joint_positions,
    base_arm_pose,
    gripper_position,
    pinch_openness,
    smooth,
)
from open_manipulator_app_control.hand_mimic_config import (
    ARM_BASE_POSE,
    ARM_UP_POSE,
    JOINT1_AT_LEFT,
    JOINT1_AT_RIGHT,
    MIMIC_START_JOINT1,
)


# 손목(0)과 중지 밑동(9)의 거리를 손바닥 크기(0.1)로 삼고,
# 엄지 끝(4)과 검지 끝(8)을 얼마나 떼어 놓느냐로 핀치 동작을 만듭니다.
def _make_hand(pinch_distance: float) -> list[tuple[float, float]]:
    landmarks = [(0.5, 0.5)] * 21

    landmarks[0] = (0.5, 0.5)  # 손목
    landmarks[9] = (0.5, 0.4)  # 중지 밑동 → 손바닥 크기 0.1

    landmarks[4] = (0.5, 0.4)  # 엄지 끝
    landmarks[8] = (0.5 + pinch_distance, 0.4)  # 검지 끝

    return landmarks


def test_손가락을_붙이면_0_벌리면_1에_가깝다():
    # 손바닥 크기(0.1)의 0.25배 이내로 붙이면 완전히 닫힌 것으로 봅니다.
    closed = pinch_openness(_make_hand(0.02))
    # 1.5배 이상 벌리면 활짝 벌린 것입니다.
    opened = pinch_openness(_make_hand(0.16))

    assert closed == 0.0
    assert opened == 1.0


def test_중간쯤_벌리면_중간값이_나온다():
    # 두 기준의 한가운데(0.875배)면 0.5 언저리여야 합니다.
    half = pinch_openness(_make_hand(0.0875))

    assert 0.45 < half < 0.55


def test_손이_멀어져도_판정이_같다():
    # 손 전체가 절반으로 줄면(카메라에서 멀어진 상황)
    # 비율은 그대로이므로 같은 값이 나와야 합니다.
    near = _make_hand(0.08)
    far = [
        (0.5 + (x - 0.5) / 2, 0.5 + (y - 0.5) / 2)
        for x, y in near
    ]

    assert pinch_openness(near) == pytest.approx(pinch_openness(far))


def test_벌린_만큼_그리퍼가_벌어진다():
    assert gripper_position(0.0, -0.01, 0.019) == pytest.approx(-0.01)
    assert gripper_position(1.0, -0.01, 0.019) == pytest.approx(0.019)
    # 절반이면 두 값의 가운데입니다. 두 단계가 아니라 이어진 값이어야 합니다.
    assert gripper_position(0.5, -0.01, 0.019) == pytest.approx(0.0045)


def test_손목_좌우는_joint1로_손을_올리면_팔이_선다():
    left = arm_joint_positions(0.0, 0.5)
    right = arm_joint_positions(1.0, 0.5)
    # y = 0(맨 위)이면 완전히 올린 자세, y >= 0.5면 기본 자세(바닥).
    top = arm_joint_positions(0.5, 0.0)
    bottom = arm_joint_positions(0.5, 1.0)

    assert left[0] == pytest.approx(JOINT1_AT_LEFT)
    assert right[0] == pytest.approx(JOINT1_AT_RIGHT)
    # 손을 올리면(top) joint2/3/4가 올린 자세로, 내리면(bottom) 기본 자세로.
    assert top[1:] == pytest.approx(ARM_UP_POSE)
    assert bottom[1:] == pytest.approx(ARM_BASE_POSE)

    # 관절은 항상 네 개여야 컨트롤러가 받습니다.
    assert len(left) == 4


def test_손을_내려도_기본_자세_밑으로_떨어지지_않는다():
    # 화면 아래 절반(y >= 0.5)은 모두 기본 90도 자세로 유지됩니다.
    # 예전처럼 팔이 아래로 뚝 떨어지지 않아야 합니다.
    middle = arm_joint_positions(0.5, 0.5)
    low = arm_joint_positions(0.5, 1.0)
    # mediapipe가 0~1 밖의 값을 줘도 기본 자세를 넘지 않습니다.
    beyond = arm_joint_positions(-0.5, 1.8)

    assert middle[1:] == pytest.approx(ARM_BASE_POSE)
    assert low[1:] == pytest.approx(ARM_BASE_POSE)
    assert beyond[1:] == pytest.approx(ARM_BASE_POSE)
    assert beyond[0] == pytest.approx(JOINT1_AT_LEFT)


def test_시작_자세는_왼쪽_45도에서_시작한다():
    base = base_arm_pose()

    # joint1은 왼쪽 45도(오른손잡이 대비), joint2/3/4는 기본 자세여야 합니다.
    assert base[0] == pytest.approx(MIMIC_START_JOINT1)
    assert base[1:] == pytest.approx(ARM_BASE_POSE)


def test_첫_프레임은_그대로_이후는_섞인다():
    assert smooth(None, [1.0, 2.0], 0.5) == [1.0, 2.0]
    assert smooth([0.0, 0.0], [1.0, 2.0], 0.5) == [0.5, 1.0]
