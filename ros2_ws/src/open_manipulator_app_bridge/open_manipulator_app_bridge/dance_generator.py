"""ollama(qwen3:4b)로 로봇팔 춤 동작(관절 키프레임)을 생성합니다.

LLM에게 4개 관절(joint1~4)의 시간별 목표 각도를 JSON으로 받게 하고, 관절
한계로 잘라내고 시간순으로 정리해 안전한 궤적으로 다듬습니다. ollama가 없거나
응답이 이상하면 내장 폴백 춤으로 대체하므로, 이 함수는 항상 춤을 돌려줍니다.
"""

import json
import math
import random
import urllib.error
import urllib.request
from typing import Any


OLLAMA_URL = "http://localhost:11434/api/chat"
DEFAULT_MODEL = "qwen3:4b"
DEFAULT_SECONDS = 5.0
DEFAULT_TIMEOUT = 150.0

# joint1~4 안전 범위(라디안). 이 범위를 넘는 값은 잘라냅니다.
# 실제 로봇/시뮬레이션이 다치지 않도록 관절 한계보다 조금 안쪽으로 잡았습니다.
JOINT_LIMITS: list[tuple[float, float]] = [
    (-2.0, 2.0),   # joint1 (좌우 회전)
    (-1.4, 1.3),   # joint2 (어깨)
    (-1.3, 1.3),   # joint3 (팔꿈치)
    (-1.6, 1.6),   # joint4 (손목)
]

# 첫 동작이 너무 급하지 않도록, 첫 키프레임을 이 시각 이후로 둡니다(초).
FIRST_KEYFRAME_AT = 0.6


SYSTEM_PROMPT = (
    "You are a choreographer for a 4-joint robot arm. "
    "Output ONLY JSON, no prose. "
    "Joints in radians: joint1 base rotation, joint2 shoulder, "
    "joint3 elbow, joint4 wrist. "
    "Schema: {\"keyframes\":[{\"t\":<seconds>,\"positions\":[j1,j2,j3,j4]}]}. "
    "Give 6-8 keyframes with t strictly increasing from about 0 to 5. "
    "Stay within joint1[-2,2] joint2[-1.4,1.3] joint3[-1.3,1.3] "
    "joint4[-1.6,1.6]. Make it rhythmic, lively and varied — swing the "
    "base left/right and bob the arm up/down like a dance."
)

USER_PROMPT = "5초 동안 신나게 춤추는 동작을 만들어줘."


# 내장 폴백 춤. ollama가 없거나 응답이 못 쓸 때 이걸로 대신합니다.
# 좌우로 흔들며 위아래로 까딱이는 리듬 동작입니다.
FALLBACK_KEYFRAMES: list[dict[str, Any]] = [
    {"t": 0.6, "positions": [0.8, -0.6, 0.4, 0.6]},
    {"t": 1.2, "positions": [-0.8, -0.9, 0.6, -0.6]},
    {"t": 1.8, "positions": [0.8, -0.4, 0.2, 0.8]},
    {"t": 2.4, "positions": [-0.8, -1.0, 0.7, -0.4]},
    {"t": 3.0, "positions": [1.0, -0.5, 0.3, 0.6]},
    {"t": 3.6, "positions": [-1.0, -0.9, 0.6, -0.7]},
    {"t": 4.2, "positions": [0.6, -0.3, 0.2, 0.5]},
    {"t": 5.0, "positions": [0.0, -0.7, 0.5, 0.2]},
]


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


# 실물 로봇(맥시)용으로 춤 키프레임을 더 안전하게 다듬습니다.
#   1) 관절 위치를 (더 보수적인) joint_limits 로 잘라 바닥 찧기 등 위험 자세를 막고,
#   2) 키프레임 사이 관절 각속도가 max_joint_velocity(rad/s)를 넘으면 그 구간의
#      시간 간격을 늘려(그리고 이후 키프레임도 함께 밀어) 천천히 움직이게 합니다.
# 가상(미키)에는 적용하지 않아 활발한 춤을 그대로 둡니다.
def apply_physical_safety(
    keyframes: list[dict[str, Any]],
    joint_limits: list[tuple[float, float]] | None = None,
    max_joint_velocity: float | None = None,
) -> list[dict[str, Any]]:
    if not keyframes:
        return keyframes

    result = [
        {"t": float(f["t"]), "positions": [float(v) for v in f["positions"]]}
        for f in keyframes
    ]

    # 1) 위치 한계 클램프(바닥 찧기 등 방지).
    if joint_limits:
        for frame in result:
            frame["positions"] = [
                _clamp(value, low, high)
                for value, (low, high) in zip(frame["positions"], joint_limits)
            ]

    # 2) 속도 제한: 너무 빠른 전이는 시간 간격을 늘려 완만하게.
    if max_joint_velocity and max_joint_velocity > 0:
        for i in range(1, len(result)):
            prev, cur = result[i - 1], result[i]
            dt = cur["t"] - prev["t"]
            max_delta = max(
                (
                    abs(c - p)
                    for c, p in zip(cur["positions"], prev["positions"])
                ),
                default=0.0,
            )
            needed_dt = max_delta / max_joint_velocity
            if needed_dt > dt:
                shift = needed_dt - dt
                for j in range(i, len(result)):
                    result[j]["t"] = round(result[j]["t"] + shift, 3)

    return result


# LLM이 준 키프레임을 안전하게 다듬습니다.
# 관절 수·타입을 확인하고, 한계로 자르고, 시간순으로 정렬해 역행/중복을 없앱니다.
def _sanitize(raw_keyframes: Any) -> list[dict[str, Any]]:
    if not isinstance(raw_keyframes, list):
        return []

    cleaned: list[dict[str, Any]] = []

    for frame in raw_keyframes:
        if not isinstance(frame, dict):
            continue
        try:
            time_seconds = float(frame["t"])
            positions = frame["positions"]
            if not isinstance(positions, list) or len(positions) != 4:
                continue
            clamped = [
                _clamp(float(value), low, high)
                for value, (low, high) in zip(positions, JOINT_LIMITS)
            ]
        except (KeyError, TypeError, ValueError):
            continue

        if time_seconds < 0:
            continue

        cleaned.append({"t": time_seconds, "positions": clamped})

    cleaned.sort(key=lambda item: item["t"])

    # 시간이 앞선 것보다 뒤여야 컨트롤러가 받습니다. 같거나 역행하는 건 버립니다.
    result: list[dict[str, Any]] = []
    last_time = -1.0
    for frame in cleaned:
        if frame["t"] <= last_time:
            continue
        result.append(frame)
        last_time = frame["t"]

    return result


# 키프레임 시간을 [FIRST_KEYFRAME_AT, seconds] 구간으로 다시 폅니다.
# LLM이 준 시간이 5초를 넘거나 0에 붙어 있어도 정확히 원하는 길이의 춤이 되고,
# 첫 동작이 너무 급하게 튀지 않습니다.
def _rescale_time(
    keyframes: list[dict[str, Any]],
    seconds: float,
) -> list[dict[str, Any]]:
    times = [frame["t"] for frame in keyframes]
    low, high = min(times), max(times)
    span = high - low if high > low else 1.0
    usable = max(seconds - FIRST_KEYFRAME_AT, 0.1)

    return [
        {
            "t": round(
                FIRST_KEYFRAME_AT + (frame["t"] - low) / span * usable,
                3,
            ),
            "positions": frame["positions"],
        }
        for frame in keyframes
    ]


# ollama에 춤 생성을 요청하고 키프레임 목록(정리 전)을 돌려줍니다.
# 연결 실패·타임아웃·형식 오류는 빈 목록으로 처리해 폴백으로 넘어갑니다.
def _request_llm(model: str, timeout: float) -> Any:
    payload = {
        "model": model,
        "think": False,          # qwen3의 사고 과정 출력을 끕니다.
        "format": "json",        # JSON만 나오도록 강제합니다.
        "stream": False,
        "keep_alive": "10m",     # 다음 호출이 빠르도록 모델을 잠시 띄워 둡니다.
        "options": {
            "temperature": 0.8,
            "num_predict": 512,  # 출력 길이를 제한해 응답을 앞당깁니다.
        },
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": USER_PROMPT},
        ],
    }

    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        OLLAMA_URL,
        data=data,
        headers={"Content-Type": "application/json"},
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError):
        return []

    content = body.get("message", {}).get("content", "")

    try:
        parsed = json.loads(content)
    except (json.JSONDecodeError, TypeError):
        return []

    if isinstance(parsed, dict):
        return parsed.get("keyframes", [])
    return parsed


# 5초 춤 키프레임과 출처("llm"/"fallback")를 돌려줍니다.
# LLM이 쓸 만한 키프레임을 2개 이상 주면 그것을, 아니면 폴백을 씁니다.
def generate_dance(
    model: str = DEFAULT_MODEL,
    seconds: float = DEFAULT_SECONDS,
    timeout: float = DEFAULT_TIMEOUT,
) -> tuple[list[dict[str, Any]], str]:
    keyframes = _sanitize(_request_llm(model, timeout))
    source = "llm"

    if len(keyframes) < 2:
        keyframes = [dict(frame) for frame in FALLBACK_KEYFRAMES]
        source = "fallback"

    return _rescale_time(keyframes, seconds), source


# (t, [joint1, joint2, joint3, joint4]) 짝들을 키프레임 목록으로 만듭니다.
def _frames(*pairs: tuple[float, list[float]]) -> list[dict[str, Any]]:
    return [
        {"t": float(t), "positions": [float(v) for v in positions]}
        for t, positions in pairs
    ]


# 미리 만들어 둔 10가지 춤. 버튼을 누를 때마다 이 중 하나를 무작위로 골라
# 바로 실행합니다(LLM을 기다리지 않아 즉시 반응). 각 춤은 성격이 다릅니다.
# 모든 값은 실행 직전 관절 한계로 잘리고 5초로 다시 맞춰지므로 안전합니다.
DANCE_LIBRARY: list[dict[str, Any]] = [
    {"name": "좌우 스윙", "keyframes": _frames(
        (0.0, [1.2, -0.4, 0.3, 0.2]), (0.7, [-1.2, -0.4, 0.3, 0.2]),
        (1.4, [1.2, -0.4, 0.3, 0.2]), (2.1, [-1.2, -0.4, 0.3, 0.2]),
        (2.8, [1.2, -0.4, 0.3, 0.2]), (3.5, [-1.2, -0.4, 0.3, 0.2]),
        (4.2, [0.0, -0.5, 0.4, 0.2]))},
    {"name": "위아래 바운스", "keyframes": _frames(
        (0.0, [0.0, -0.2, 0.2, 0.5]), (0.6, [0.0, -1.1, 0.9, 0.9]),
        (1.2, [0.0, -0.2, 0.2, 0.5]), (1.8, [0.0, -1.1, 0.9, 0.9]),
        (2.4, [0.0, -0.2, 0.2, 0.5]), (3.0, [0.0, -1.1, 0.9, 0.9]),
        (3.6, [0.0, -0.6, 0.5, 0.6]))},
    {"name": "빙글 회전", "keyframes": _frames(
        (0.0, [-1.6, -0.5, 0.4, 0.2]), (1.0, [-0.8, -0.9, 0.6, 0.4]),
        (2.0, [0.0, -0.5, 0.4, 0.2]), (3.0, [0.8, -0.9, 0.6, 0.4]),
        (4.0, [1.6, -0.5, 0.4, 0.2]), (4.6, [0.0, -0.5, 0.4, 0.2]))},
    {"name": "손목 웨이브", "keyframes": _frames(
        (0.0, [0.3, -0.6, 0.5, -1.4]), (0.5, [0.3, -0.6, 0.5, 1.4]),
        (1.0, [-0.3, -0.6, 0.5, -1.4]), (1.5, [-0.3, -0.6, 0.5, 1.4]),
        (2.0, [0.3, -0.6, 0.5, -1.4]), (2.5, [0.3, -0.6, 0.5, 1.4]),
        (3.0, [0.0, -0.6, 0.5, 0.0]))},
    {"name": "펌프 업", "keyframes": _frames(
        (0.0, [0.0, 0.0, 0.0, 0.0]), (0.5, [0.0, -1.3, 1.0, 0.8]),
        (1.0, [0.0, 0.0, 0.0, 0.0]), (1.5, [0.0, -1.3, 1.0, 0.8]),
        (2.0, [0.0, 0.0, 0.0, 0.0]), (2.5, [0.0, -1.3, 1.0, 0.8]),
        (3.0, [0.0, -0.6, 0.5, 0.3]))},
    {"name": "로봇 각", "keyframes": _frames(
        (0.0, [1.5, -0.3, 0.2, 0.0]), (0.8, [1.5, -1.2, 1.2, 1.5]),
        (1.6, [-1.5, -1.2, 1.2, 1.5]), (2.4, [-1.5, -0.3, 0.2, 0.0]),
        (3.2, [0.0, -1.2, 1.2, -1.5]), (4.0, [0.0, -0.3, 0.2, 0.0]))},
    {"name": "트위스트", "keyframes": _frames(
        (0.0, [1.0, -0.6, 0.5, 1.0]), (0.6, [-1.0, -0.6, 0.5, -1.0]),
        (1.2, [1.0, -0.6, 0.5, 1.0]), (1.8, [-1.0, -0.6, 0.5, -1.0]),
        (2.4, [1.0, -0.6, 0.5, 1.0]), (3.0, [-1.0, -0.6, 0.5, -1.0]),
        (3.6, [0.0, -0.6, 0.5, 0.0]))},
    {"name": "인사 반복", "keyframes": _frames(
        (0.0, [0.0, -0.3, 0.2, 0.2]), (0.7, [0.0, 0.6, 0.8, 1.0]),
        (1.4, [0.0, -0.3, 0.2, 0.2]), (2.1, [0.0, 0.6, 0.8, 1.0]),
        (2.8, [0.0, -0.3, 0.2, 0.2]), (3.5, [0.0, 0.6, 0.8, 1.0]),
        (4.2, [0.0, -0.4, 0.3, 0.2]))},
    {"name": "흔들흔들", "keyframes": _frames(
        (0.0, [0.6, -0.6, 0.5, 0.3]), (0.3, [-0.6, -0.6, 0.5, 0.3]),
        (0.6, [0.6, -0.6, 0.5, 0.3]), (0.9, [-0.6, -0.6, 0.5, 0.3]),
        (1.2, [0.6, -0.6, 0.5, 0.3]), (1.5, [-0.6, -0.6, 0.5, 0.3]),
        (1.8, [0.6, -0.6, 0.5, 0.3]), (2.1, [-0.6, -0.6, 0.5, 0.3]),
        (2.4, [0.6, -0.6, 0.5, 0.3]), (2.7, [-0.6, -0.6, 0.5, 0.3]),
        (3.0, [0.0, -0.6, 0.5, 0.3]))},
    {"name": "큰 원 그리기", "keyframes": _frames(
        (0.0, [1.5, -0.3, 0.3, 0.2]), (0.8, [1.0, -1.0, 0.8, 0.5]),
        (1.6, [0.0, -1.2, 1.0, 0.7]), (2.4, [-1.0, -1.0, 0.8, 0.5]),
        (3.2, [-1.5, -0.3, 0.3, 0.2]), (4.0, [-0.7, -0.6, 0.5, 0.3]),
        (4.6, [0.0, -0.5, 0.4, 0.2]))},
]


# 손으로 만든 위 춤들 외에, 프로그램으로 여러 춤을 더 만들어 총 개수를 채웁니다.
# 관절마다 서로 다른 진폭·주파수·위상의 사인 진동을 겹쳐 다양한 리듬을 냅니다.
# 진폭을 기준 자세에서 관절 한계 안쪽으로만 잡아 항상 안전합니다.
# 시드를 고정하므로 매번 같은 춤들이 나옵니다.
_GEN_BASE_POSE = [0.0, -0.6, 0.5, 0.2]


def _generate_dances(count: int, start_number: int) -> list[dict[str, Any]]:
    dances: list[dict[str, Any]] = []

    for offset in range(count):
        rnd = random.Random(7000 + start_number + offset)

        amplitudes: list[float] = []
        frequencies: list[float] = []
        phases: list[float] = []
        for joint, (low, high) in enumerate(JOINT_LIMITS):
            base = _GEN_BASE_POSE[joint]
            # 기준 자세에서 위아래로 벗어날 수 있는 여유(한계 안쪽).
            span = max(min(base - low, high - base), 0.1)
            amplitudes.append(rnd.uniform(0.4, 0.95) * span)
            frequencies.append(rnd.choice([1.0, 1.5, 2.0, 2.5, 3.0]))
            phases.append(rnd.uniform(0.0, 2 * math.pi))

        frame_count = rnd.choice([7, 8, 9, 10])
        keyframes: list[dict[str, Any]] = []
        for step in range(frame_count):
            t = (step / (frame_count - 1)) * 5.0
            positions = [
                round(
                    _GEN_BASE_POSE[joint]
                    + amplitudes[joint]
                    * math.sin(
                        2 * math.pi * frequencies[joint] * (t / 5.0)
                        + phases[joint]
                    ),
                    3,
                )
                for joint in range(4)
            ]
            keyframes.append({"t": round(t, 3), "positions": positions})

        dances.append(
            {"name": f"춤 {start_number + offset}", "keyframes": keyframes}
        )

    return dances


# 손으로 만든 10가지 + 자동 생성 20가지 = 총 30가지.
DANCE_LIBRARY.extend(_generate_dances(20, start_number=11))


# 바로 앞에 춘 춤은 피해서, 누를 때마다 다른 춤이 나오게 합니다.
_last_dance_index = -1


# 10가지 춤 중 하나를 무작위로 골라 (키프레임, 이름)을 돌려줍니다.
# 직전에 춘 춤과 겹치지 않게 하고, 관절 한계로 잘라 5초로 맞춥니다.
def pick_random_dance(
    seconds: float = DEFAULT_SECONDS,
) -> tuple[list[dict[str, Any]], str]:
    global _last_dance_index

    if len(DANCE_LIBRARY) > 1:
        index = random.randrange(len(DANCE_LIBRARY))
        while index == _last_dance_index:
            index = random.randrange(len(DANCE_LIBRARY))
        _last_dance_index = index
    else:
        index = 0

    dance = DANCE_LIBRARY[index]
    keyframes = _rescale_time(_sanitize(dance["keyframes"]), seconds)

    return keyframes, dance["name"]
