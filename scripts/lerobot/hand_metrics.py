"""손 관절 좌표에서 로봇을 움직일 값을 뽑아내는 계산들입니다.

카메라나 ROS2 없이도 시험할 수 있도록 순수 함수로만 두었습니다.
좌표는 mediapipe가 주는 0~1 정규화 값이며, (x, y) 짝의 목록으로 받습니다.
x는 화면 왼쪽이 0, y는 화면 위쪽이 0입니다.
"""

from math import hypot

from hand_mimic_config import (
    ARM_BASE_POSE,
    ARM_UP_POSE,
    JOINT1_AT_LEFT,
    JOINT1_AT_RIGHT,
    MIMIC_START_JOINT1,
    PINCH_CLOSED_RATIO,
    PINCH_OPEN_RATIO,
    RAISE_NEUTRAL_Y,
)


# mediapipe 손 관절 번호입니다.
WRIST = 0
THUMB_TIP = 4
INDEX_FINGER_TIP = 8
MIDDLE_FINGER_MCP = 9


# 두 점 사이의 거리입니다.
def _distance(
    first: tuple[float, float],
    second: tuple[float, float],
) -> float:
    return hypot(first[0] - second[0], first[1] - second[1])


# 값을 [low, high] 구간에서 0~1로 옮깁니다. 구간을 벗어나면 0 또는 1이 됩니다.
def _normalize(value: float, low: float, high: float) -> float:
    if high <= low:
        return 0.0

    return min(1.0, max(0.0, (value - low) / (high - low)))


# 두 값 사이를 비율 t(0~1)로 섞습니다.
def _interpolate(start: float, end: float, t: float) -> float:
    return start + (end - start) * min(1.0, max(0.0, t))


def pinch_openness(landmarks: list[tuple[float, float]]) -> float:
    """엄지와 검지를 얼마나 벌렸는지를 0(붙임)~1(활짝)로 돌려줍니다.

    두 손끝 사이의 거리를 손바닥 크기로 나눈 비율을 씁니다.
    손이 카메라에서 멀어지면 좌표가 모두 함께 작아지지만 비율은 그대로이므로,
    거리와 상관없이 같은 기준으로 판정할 수 있습니다.
    """
    palm_size = _distance(
        landmarks[WRIST],
        landmarks[MIDDLE_FINGER_MCP],
    )

    # 손바닥이 정면을 향하지 않으면 크기가 0에 가까워집니다. 이때는 판정할 수 없습니다.
    if palm_size <= 1e-6:
        return 0.0

    pinch = _distance(
        landmarks[THUMB_TIP],
        landmarks[INDEX_FINGER_TIP],
    )

    return _normalize(
        pinch / palm_size,
        PINCH_CLOSED_RATIO,
        PINCH_OPEN_RATIO,
    )


def gripper_position(
    openness: float,
    closed_position: float,
    open_position: float,
) -> float:
    """벌린 정도(0~1)를 그리퍼 관절 값으로 옮깁니다.

    열림/닫힘 두 단계가 아니라 벌린 만큼 그대로 따라가므로,
    손가락을 조금만 벌리면 그리퍼도 조금만 벌어집니다.
    """
    return _interpolate(closed_position, open_position, openness)


def wrist_position(
    landmarks: list[tuple[float, float]],
) -> tuple[float, float]:
    """손목의 화면 위치 (x, y)를 돌려줍니다."""
    return landmarks[WRIST]


def raise_amount(y: float) -> float:
    """손목의 화면 세로 위치(y)를 '팔을 얼마나 올릴지'(0~1)로 바꿉니다.

    y = 0(화면 맨 위)이면 1(완전히 올림), y가 RAISE_NEUTRAL_Y 이상이면 0(기본 자세).
    그 아래로 손을 더 내려도 0에서 멈추므로 팔이 기본 자세 밑으로 떨어지지 않습니다.
    """
    return _normalize(RAISE_NEUTRAL_Y - y, 0.0, RAISE_NEUTRAL_Y)


def base_arm_pose() -> list[float]:
    """모방을 시작할 때의 기본 자세(앞을 수평으로 보는 90도 자세)입니다.

    joint1은 왼쪽으로 45도(MIMIC_START_JOINT1) 튼 방향에서 시작합니다.
    대개 오른손잡이라 손이 화면 오른쪽에 잡히므로, 왼쪽에서 시작해 두면
    첫 프레임에서 팔이 손 쪽으로 크게 튀지 않고 자연스럽게 따라갑니다.
    """
    return [
        MIMIC_START_JOINT1,
        ARM_BASE_POSE[0],
        ARM_BASE_POSE[1],
        ARM_BASE_POSE[2],
    ]


def arm_joint_positions(x: float, y: float) -> list[float]:
    """손목 위치를 팔 관절 네 개의 각도로 옮깁니다.

    좌우(x)는 joint1로 항상 따라갑니다(위로 든 상태에서 손을 흔들면 좌우로 움직임).
    상하(y)는 기본 자세(ARM_BASE_POSE)와 올린 자세(ARM_UP_POSE) 사이를 오갑니다.
    손을 내리면 기본 90도 자세에서 멈추고, 올릴수록 위로 세워집니다.
    """
    lift = raise_amount(y)

    return [
        _interpolate(JOINT1_AT_LEFT, JOINT1_AT_RIGHT, x),
        _interpolate(ARM_BASE_POSE[0], ARM_UP_POSE[0], lift),
        _interpolate(ARM_BASE_POSE[1], ARM_UP_POSE[1], lift),
        _interpolate(ARM_BASE_POSE[2], ARM_UP_POSE[2], lift),
    ]


def smooth(
    previous: list[float] | None,
    current: list[float],
    factor: float,
) -> list[float]:
    """이전 값과 섞어 손 떨림을 줄입니다.

    factor가 0에 가까울수록 부드럽고, 1이면 현재 값을 그대로 씁니다.
    이전 값이 없으면(첫 프레임) 현재 값을 그대로 씁니다.
    """
    if previous is None:
        return list(current)

    return [
        old + (new - old) * factor
        for old, new in zip(previous, current)
    ]
