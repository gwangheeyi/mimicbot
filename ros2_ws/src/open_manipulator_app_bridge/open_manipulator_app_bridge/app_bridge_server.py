import threading
from contextlib import asynccontextmanager
from typing import AsyncIterator

import uvicorn
from fastapi import Body, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from open_manipulator_app_bridge.chat_responder import answer as chat_answer
from open_manipulator_app_bridge.chat_responder import warmup as chat_warmup
from open_manipulator_app_bridge.config import load_config
from open_manipulator_app_bridge.dance_generator import (
    apply_physical_safety,
    generate_dance,
    pick_random_dance,
)
from open_manipulator_app_bridge.ros_publisher import OmxCommandPublisher
from open_manipulator_app_bridge.wake_manager import WakeManager


CONFIG = load_config()
COMMAND_PUBLISHER: OmxCommandPublisher | None = None
# 대상(프로파일) 이름 -> 그 대상의 서비스들을 관리하는 WakeManager.
# 미키(gazeboLeRobot)=Gazebo, 맥시(omxAi)=실물 follower 처럼 대상마다 다른 목록.
WAKE_MANAGERS: dict[str, WakeManager] = {}
# target 없이 온 요청에 쓸 기본 프로파일 이름.
DEFAULT_PROFILE: str = "gazeboLeRobot"


class CommandRequest(BaseModel):
    command: str
    # 어느 대상(gazeboLeRobot=미키 / omxAi=맥시)인지. 맥시는 lerobot 제어 서버로
    # 명령을 넘기고, 미키는 ROS2 토픽으로 발행한다. 없으면 ROS2(하위호환).
    target: str | None = None


# "깨우기"/"재우기" 요청. target(대상 enum 이름: gazeboLeRobot / omxAi)으로
# 어느 프로파일을 띄울지 고른다. 없으면 default_profile 을 쓴다(하위호환).
class WakeRequest(BaseModel):
    target: str | None = None


# "춤" 요청. target(대상 enum 이름)으로 어느 로봇으로 보낼지, 실물이면 안전
# 다듬기를 적용할지를 정한다. 없으면 기본 토픽(미키)로 보낸다.
class DanceRequest(BaseModel):
    target: str | None = None


# "자율(정책 실행)" 요청. 맥시(실물)만 지원 — lerobot 제어 서버가 팔로워를
# 넘겨받아 lerobot-record 로 학습된 정책을 실행한다. policy_path 는 앱 패널 입력.
class AutonomousRequest(BaseModel):
    target: str | None = None
    # 실행할 전체 명령(lerobot-record ...). 있으면 그대로 실행한다.
    command: str = ""
    # command 가 없을 때만 쓰는 정책 경로(설정 템플릿으로 명령을 만든다).
    policy_path: str = ""


class MimicRequest(BaseModel):
    enabled: bool
    # 맥시(실물)면 lerobot 제어 서버의 손 모방으로 넘긴다. 없으면 ROS2(미키).
    target: str | None = None


class ChatRequest(BaseModel):
    message: str


class ChatResponse(BaseModel):
    success: bool
    reply: str


class CommandResponse(BaseModel):
    success: bool
    command: str
    message: str
    # 명령 토픽을 듣고 있는 노드 수. 0이면 발행은 됐지만 로봇은 못 받은 것입니다.
    subscribers: int = 0


# "Micky 깨우기"로 띄운 서비스 하나의 결과입니다.
class WakeService(BaseModel):
    name: str
    label: str
    # started / already_running / error
    status: str
    pid: int | None = None
    message: str | None = None


class WakeResponse(BaseModel):
    success: bool
    message: str
    services: list[WakeService]


# 춤 키프레임 하나(시각 t와 관절 4개 각도).
class DanceKeyframe(BaseModel):
    t: float
    positions: list[float]


class DanceResponse(BaseModel):
    success: bool
    message: str
    # library(10가지 중 랜덤) / ai(ollama가 만듦) / fallback(내장 춤)
    source: str
    # 고른 춤 이름(랜덤일 때) 또는 "AI 즉흥".
    name: str
    seconds: float
    keyframes: list[DanceKeyframe]


# FastAPI 서버가 시작될 때 ROS2 Publisher를 한 번 생성하고,
# 서버가 종료될 때 Publisher와 ROS2 노드를 안전하게 정리합니다.
# 요청이 들어올 때마다 ROS2 노드를 반복 생성하지 않도록 하여
# 노드 이름 충돌과 불필요한 초기화 비용을 방지합니다.
@asynccontextmanager
async def lifespan(
    app: FastAPI,
) -> AsyncIterator[None]:
    global COMMAND_PUBLISHER
    global DEFAULT_PROFILE

    COMMAND_PUBLISHER = OmxCommandPublisher()

    wake_config = CONFIG.get("wake", {})
    log_dir = wake_config.get("log_dir", "~/mimicbot/logs")
    profiles = wake_config.get("profiles")

    if profiles:
        # 대상별 프로파일 형식. 프로파일마다 WakeManager 하나.
        DEFAULT_PROFILE = wake_config.get(
            "default_profile", next(iter(profiles))
        )
        for name, services in profiles.items():
            WAKE_MANAGERS[name] = WakeManager(
                services=services, log_dir=log_dir
            )
    else:
        # 옛 형식(wake.services 단일 목록) 하위호환.
        DEFAULT_PROFILE = "default"
        WAKE_MANAGERS["default"] = WakeManager(
            services=wake_config.get("services", []),
            log_dir=log_dir,
        )

    yield

    # 브리지가 내려갈 때 "깨우기"로 띄운 자식 프로세스도 함께 정리합니다.
    for manager in WAKE_MANAGERS.values():
        manager.sleep()

    if COMMAND_PUBLISHER is not None:
        COMMAND_PUBLISHER.shutdown()


app = FastAPI(
    title="open_manipulator App Bridge",
    version="1.0.0",
    lifespan=lifespan,
)


# Flutter 앱을 웹(Chrome)에서 실행하면 앱과 이 서버의 포트가 달라
# 브라우저가 교차 출처 요청으로 보고 막습니다. JSON 본문을 보내는 POST는
# 먼저 OPTIONS 프리플라이트가 나가는데, 허용해 주지 않으면 앱에는
# "Failed to fetch"로만 보이고 서버 로그에는 아무것도 남지 않습니다.
#
# 로컬에서 로봇을 다루는 개발용 브리지라 출처를 열어 둡니다.
# 외부에 노출할 서버라면 allow_origins를 실제 주소로 좁혀야 합니다.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# 앱과 ROS2 브리지 서버의 정상 작동 여부를 확인하기 위한
# 상태 확인 API입니다. Flutter 앱이 서버 연결 상태를 표시할 때
# 사용할 수 있으며 로봇 명령은 발행하지 않습니다.
@app.get("/health")
def health_check() -> dict[str, str]:
    return {
        "status": "ok",
        "service": "open_manipulator_app_bridge",
    }


# Flutter 앱에서 전달받은 command 값을 검사한 뒤
# 해당 명령을 ROS2 토픽으로 발행합니다.
# 성공하면 실행된 실제 명령을 반환하고, 잘못된 명령이면
# HTTP 400 오류를 반환합니다.
# 맥시(lerobot) 실물 대상의 요청을 lerobot 제어 서버(HTTP)로 넘깁니다.
# 동작 명령은 /pose {name}, 손 모방은 /mimic {enabled} 로 보냅니다.
def _forward_to_lerobot(
    url: str, path: str, payload: dict, label: str
) -> CommandResponse:
    import json as _json
    import urllib.error
    import urllib.request

    data = _json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{url}{path}",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            body = _json.loads(resp.read().decode("utf-8"))
        return CommandResponse(
            success=bool(body.get("success", True)),
            command=label,
            message=str(body.get("message", "OK")),
            subscribers=1,
        )
    except urllib.error.HTTPError as err:
        try:
            body = _json.loads(err.read().decode("utf-8"))
            message = str(body.get("error", err.reason))
        except Exception:  # noqa: BLE001
            message = str(err)
        return CommandResponse(
            success=False, command=label, message=message, subscribers=0
        )
    except (urllib.error.URLError, TimeoutError, OSError) as err:
        return CommandResponse(
            success=False,
            command=label,
            message=(
                f"lerobot 제어 서버에 연결 못함({url}). 맥시를 깨웠는지 확인하세요. "
                f"({err})"
            ),
            subscribers=0,
        )


@app.post(
    "/robot/command",
    response_model=CommandResponse,
)
def send_robot_command(
    request: CommandRequest,
) -> CommandResponse:
    # 실물(lerobot) 대상이면 ROS2 대신 lerobot 제어 서버로 넘긴다.
    lerobot_urls = CONFIG.get("ros", {}).get("lerobot_control_url_by_target", {}) or {}
    if request.target and request.target in lerobot_urls:
        return _forward_to_lerobot(
            str(lerobot_urls[request.target]),
            "/pose",
            {"name": request.command},
            request.command,
        )

    if COMMAND_PUBLISHER is None:
        raise HTTPException(
            status_code=503,
            detail="ROS2 Publisher가 준비되지 않았습니다.",
        )

    try:
        (
            published_command,
            subscriber_count,
        ) = COMMAND_PUBLISHER.publish_command(
            request.command
        )
    except ValueError as error:
        raise HTTPException(
            status_code=400,
            detail=str(error),
        ) from error

    # 발행 자체는 성공했지만 받는 노드가 없으면 로봇은 움직이지 않습니다.
    # 앱에 성공으로만 알리면 원인을 찾을 단서가 사라지므로 구분해서 알립니다.
    if subscriber_count == 0:
        return CommandResponse(
            success=False,
            command=published_command,
            message=(
                "명령을 발행했지만 받는 노드가 없습니다. "
                "motion_server가 실행 중인지 확인하세요."
            ),
            subscribers=0,
        )

    return CommandResponse(
        success=True,
        command=published_command,
        message="open_manipulator 명령을 발행했습니다.",
        subscribers=subscriber_count,
    )


# 손 모방을 시작하거나 정지합니다.
# 앱의 "모방 시작 / 모방 정지" 버튼이 이 API를 부릅니다.
@app.post(
    "/robot/mimic",
    response_model=CommandResponse,
)
def set_mimic(
    request: MimicRequest,
) -> CommandResponse:
    # 실물(lerobot) 대상이면 lerobot 제어 서버의 손 모방으로 넘긴다.
    lerobot_urls = CONFIG.get("ros", {}).get("lerobot_control_url_by_target", {}) or {}
    if request.target and request.target in lerobot_urls:
        return _forward_to_lerobot(
            str(lerobot_urls[request.target]),
            "/mimic",
            {"enabled": request.enabled},
            f"mimic_{request.enabled}",
        )

    if COMMAND_PUBLISHER is None:
        raise HTTPException(
            status_code=503,
            detail="ROS2 Publisher가 준비되지 않았습니다.",
        )

    subscriber_count = (
        COMMAND_PUBLISHER.publish_mimic_enable(
            request.enabled
        )
    )

    action = "시작" if request.enabled else "정지"

    if subscriber_count == 0:
        return CommandResponse(
            success=False,
            command=f"mimic_{request.enabled}",
            message=(
                "손 모방 노드가 실행 중이 아닙니다. "
                "hand_mimic_node를 먼저 실행하세요."
            ),
            subscribers=0,
        )

    return CommandResponse(
        success=True,
        command=f"mimic_{request.enabled}",
        message=f"손 모방을 {action}했습니다.",
        subscribers=subscriber_count,
    )


# ollama(qwen3:4b)로 사용자의 말에 짧게 대답합니다(자율 화면의 음성 대화).
# 앱은 돌려받은 대답을 TTS로 읽어 줍니다. 로컬 모델이라 외부 API 키가 필요 없습니다.
# CPU 추론이라 몇 초~수십 초 걸릴 수 있어, 앱은 넉넉히 기다립니다.
@app.post(
    "/robot/chat",
    response_model=ChatResponse,
)
def chat(request: ChatRequest) -> ChatResponse:
    chat_config = CONFIG.get("chat", {})

    reply = chat_answer(
        request.message,
        model=str(chat_config.get("model", "qwen3:4b")),
        timeout=float(chat_config.get("timeout", 60.0)),
    )

    if reply is None:
        return ChatResponse(
            success=False,
            reply="지금은 생각이 잘 안 나요. 잠시 뒤에 다시 물어봐 주세요.",
        )

    return ChatResponse(success=True, reply=reply)


# qwen3:4b를 백그라운드 스레드에서 미리 메모리에 올려 둡니다(예열).
# 응답을 기다리지 않고 바로 돌아오므로, 부르는 쪽이 멈추지 않습니다.
def _start_warmup() -> None:
    chat_config = CONFIG.get("chat", {})
    model = str(chat_config.get("model", "qwen3:4b"))
    threading.Thread(
        target=chat_warmup,
        args=(model,),
        daemon=True,
    ).start()


# 앱의 대화 화면에 들어올 때 부릅니다. qwen3:4b를 미리 올려 두어 첫 대답을
# 빠르게 합니다. 로딩은 백그라운드에서 하고 바로 응답합니다.
@app.post(
    "/robot/chat/warmup",
    response_model=ChatResponse,
)
def chat_warmup_endpoint() -> ChatResponse:
    _start_warmup()
    return ChatResponse(success=True, reply="미키를 준비시키고 있어요.")


# 5초짜리 춤 동작을 로봇에 실행시킵니다.
# 기본은 미리 만들어 둔 10가지 춤 중 하나를 무작위로 골라 바로 실행합니다
# (누를 때마다 다른 춤, 즉시 반응). ?use_ai=true 로 부르면 ollama(qwen3:4b)가
# 즉흥으로 만들지만 CPU 추론이라 수십 초 걸릴 수 있습니다.
# 어느 경우든 관절 한계로 잘라 안전한 궤적으로 발행합니다.
# 대상이 실물 로봇인지(=대상별 팔 토픽이 따로 지정된 대상인지) 판별합니다.
def _is_physical_target(target: str | None) -> bool:
    if not target:
        return False
    by_target = CONFIG.get("ros", {}).get("arm_command_topic_by_target", {})
    return target in (by_target or {})


@app.post(
    "/robot/dance",
    response_model=DanceResponse,
)
def dance_robot(
    use_ai: bool = False,
    request: DanceRequest | None = Body(default=None),
) -> DanceResponse:
    if COMMAND_PUBLISHER is None:
        raise HTTPException(
            status_code=503,
            detail="ROS2 Publisher가 준비되지 않았습니다.",
        )

    target = request.target if request else None
    dance_config = CONFIG.get("dance", {})
    seconds = float(dance_config.get("seconds", 5.0))

    if use_ai:
        keyframes, llm_source = generate_dance(
            model=str(dance_config.get("model", "qwen3:4b")),
            seconds=seconds,
            timeout=float(dance_config.get("timeout", 150.0)),
        )
        name = "AI 즉흥"
        source = "ai" if llm_source == "llm" else "fallback"
        origin = "AI(qwen3:4b)가 만든"
    else:
        keyframes, name = pick_random_dance(seconds)
        source = "library"
        origin = f"랜덤 춤 '{name}'"

    # 실물(맥시)이면 속도·바닥 한계를 더 보수적으로 다듬어 무리가 가지 않게 합니다.
    if _is_physical_target(target):
        safety = dance_config.get("physical_safety", {}) or {}
        limits = safety.get("joint_limits")
        keyframes = apply_physical_safety(
            keyframes,
            joint_limits=[tuple(pair) for pair in limits] if limits else None,
            max_joint_velocity=safety.get("max_joint_velocity"),
        )
        # 속도 제한으로 시간이 늘어났을 수 있으니 실제 길이를 반영합니다.
        if keyframes:
            seconds = float(keyframes[-1]["t"])

    subscriber_count = COMMAND_PUBLISHER.publish_trajectory(keyframes, target)

    if subscriber_count == 0:
        return DanceResponse(
            success=False,
            message=(
                f"{origin} 춤을 준비했지만 받는 컨트롤러가 없습니다. "
                "로봇 컨트롤러(팔로워/arm_controller)가 실행 중인지 확인하세요."
            ),
            source=source,
            name=name,
            seconds=seconds,
            keyframes=[DanceKeyframe(**frame) for frame in keyframes],
        )

    return DanceResponse(
        success=True,
        message=(
            f"{origin} {seconds:.0f}초 춤을 시작합니다 "
            f"(키프레임 {len(keyframes)}개)."
        ),
        source=source,
        name=name,
        seconds=seconds,
        keyframes=[DanceKeyframe(**frame) for frame in keyframes],
    )


# 웹캠을 확보하거나 반환합니다.
# 앱의 실시간 모방 화면에 들어오면 확보(True), 나가면 반환(False)을 부릅니다.
# 화면을 안 볼 때는 hand_mimic_node가 웹캠 장치를 잡지 않도록 합니다.
@app.post(
    "/robot/camera",
    response_model=CommandResponse,
)
def set_camera(
    request: MimicRequest,
) -> CommandResponse:
    if COMMAND_PUBLISHER is None:
        raise HTTPException(
            status_code=503,
            detail="ROS2 Publisher가 준비되지 않았습니다.",
        )

    subscriber_count = (
        COMMAND_PUBLISHER.publish_camera_enable(
            request.enabled
        )
    )

    action = "확보" if request.enabled else "반환"

    if subscriber_count == 0:
        return CommandResponse(
            success=False,
            command=f"camera_{request.enabled}",
            message=(
                "손 모방 노드가 실행 중이 아닙니다. "
                "hand_mimic_node를 먼저 실행하세요."
            ),
            subscribers=0,
        )

    return CommandResponse(
        success=True,
        command=f"camera_{request.enabled}",
        message=f"카메라를 {action}했습니다.",
        subscribers=subscriber_count,
    )


# 설정 파일에 등록된 명령 목록을 Flutter 앱에 반환합니다.
# 앱에서 버튼을 동적으로 만들거나 지원 명령을 확인할 때
# 동일한 명령 정의를 재사용할 수 있습니다.
@app.get("/robot/commands")
def get_robot_commands() -> dict[str, list[str]]:
    command_names = list(
        CONFIG["commands"].keys()
    )

    return {
        "commands": command_names,
    }


# "자율(정책 실행)" — 맥시(lerobot)에서 학습된 정책을 실행합니다.
# 제어 서버가 팔로워를 넘겨받아 lerobot-record 를 돌립니다(수십 초 이상).
# 미키(가상)는 정책 실행을 지원하지 않습니다.
@app.post(
    "/robot/autonomous",
    response_model=CommandResponse,
)
def run_autonomous_policy(request: AutonomousRequest) -> CommandResponse:
    lerobot_urls = CONFIG.get("ros", {}).get("lerobot_control_url_by_target", {}) or {}
    if not (request.target and request.target in lerobot_urls):
        return CommandResponse(
            success=False,
            command="autonomous",
            message="자율(정책 실행)은 실물(맥시)에서만 지원합니다.",
            subscribers=0,
        )
    return _forward_to_lerobot(
        str(lerobot_urls[request.target]),
        "/autonomous",
        {"command": request.command, "policy_path": request.policy_path},
        "autonomous",
    )


# target(대상 enum 이름)으로 프로파일을 고른다. 없거나 모르는 이름이면 기본.
def _resolve_profile(target: str | None) -> str:
    if target and target in WAKE_MANAGERS:
        return target
    return DEFAULT_PROFILE


# "깨우기" 버튼이 부르는 API입니다.
# target 프로파일(미키=Gazebo, 맥시=실물 follower)에 맞는 브링업·서비스를
# 한꺼번에 백그라운드로 띄웁니다. 프로세스만 띄우고 바로 응답합니다.
# 대상을 바꿔 깨우면, 먼저 다른 프로파일에서 띄운 것들을 정리해 충돌을 막습니다.
@app.post(
    "/robot/wake",
    response_model=WakeResponse,
)
def wake_robot(
    request: WakeRequest | None = Body(default=None),
) -> WakeResponse:
    if not WAKE_MANAGERS:
        raise HTTPException(
            status_code=503,
            detail="깨우기 관리자가 준비되지 않았습니다.",
        )

    target = request.target if request else None
    profile = _resolve_profile(target)

    # 다른 프로파일이 떠 있으면 먼저 정리(대상 전환 시 잔여 프로세스 방지).
    for name, manager in WAKE_MANAGERS.items():
        if name != profile:
            manager.sleep()

    services = [WakeService(**item) for item in WAKE_MANAGERS[profile].wake()]

    # 깨우면서 qwen3:4b를 백그라운드로 미리 올려 둡니다(첫 대답을 빠르게).
    # ollama serve가 부팅될 때까지 기다렸다가 로딩하므로 응답을 막지 않습니다.
    _start_warmup()

    started = [s for s in services if s.status == "started"]
    running = [s for s in services if s.status == "already_running"]
    failed = [s for s in services if s.status == "error"]

    parts: list[str] = []
    if started:
        parts.append(f"{len(started)}개 시작")
    if running:
        parts.append(f"{len(running)}개 이미 실행 중")
    if failed:
        parts.append(f"{len(failed)}개 실패")

    # "Micky"는 앱에서 대상 이름(미키/맥시)으로 치환해 보여 줍니다.
    message = (
        "Micky를 깨웠습니다 (기존 프로세스 정리 후 새로 시작) — " + ", ".join(parts)
        if parts
        else "깨울 서비스가 없습니다."
    )

    return WakeResponse(
        success=not failed,
        message=message,
        services=services,
    )


# "재우기" 버튼이 부르는 API입니다.
# target을 주면 그 프로파일만, 없으면 안전을 위해 모든 프로파일을 종료합니다.
# 미키·맥시를 서로 배타적으로 쓰기 위해, 상대만 콕 집어 재울 수 있게 합니다.
@app.post(
    "/robot/sleep",
    response_model=WakeResponse,
)
def sleep_robot(
    request: WakeRequest | None = Body(default=None),
) -> WakeResponse:
    if not WAKE_MANAGERS:
        raise HTTPException(
            status_code=503,
            detail="깨우기 관리자가 준비되지 않았습니다.",
        )

    target = request.target if request else None

    if target and target in WAKE_MANAGERS:
        # 지정한 대상만 재운다.
        managers = [WAKE_MANAGERS[target]]
    else:
        # target이 없으면 전부 재운다(하위호환·안전).
        managers = list(WAKE_MANAGERS.values())

    # 서비스 이름이 겹칠 수 있으니 이름으로 중복 제거.
    seen: dict[str, WakeService] = {}
    for manager in managers:
        for item in manager.sleep():
            service = WakeService(**item)
            seen[service.name] = service
    services = list(seen.values())

    return WakeResponse(
        success=True,
        message=f"Micky를 재웠습니다 — {len(services)}개 서비스 종료",
        services=services,
    )


# "깨우기"로 띄운 서비스들의 현재 실행 상태를 돌려줍니다.
# target으로 어느 프로파일 상태를 볼지 고릅니다(없으면 기본 프로파일).
@app.get(
    "/robot/wake/status",
    response_model=WakeResponse,
)
def wake_status(target: str | None = None) -> WakeResponse:
    if not WAKE_MANAGERS:
        raise HTTPException(
            status_code=503,
            detail="깨우기 관리자가 준비되지 않았습니다.",
        )

    profile = _resolve_profile(target)
    services = [
        WakeService(**item) for item in WAKE_MANAGERS[profile].status()
    ]
    running = [s for s in services if s.status == "running"]

    return WakeResponse(
        success=True,
        message=f"[{profile}] {len(running)}/{len(services)}개 서비스 실행 중",
        services=services,
    )


# YAML 설정 파일에 정의된 호스트와 포트 값으로
# FastAPI Uvicorn 서버를 실행합니다.
def main() -> None:
    server_config = CONFIG["server"]

    uvicorn.run(
        app,
        host=str(server_config["host"]),
        port=int(server_config["port"]),
    )


if __name__ == "__main__":
    main()
