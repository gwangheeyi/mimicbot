from contextlib import asynccontextmanager
from typing import AsyncIterator

import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from open_manipulator_app_bridge.config import load_config
from open_manipulator_app_bridge.ros_publisher import OmxCommandPublisher


CONFIG = load_config()
COMMAND_PUBLISHER: OmxCommandPublisher | None = None


class CommandRequest(BaseModel):
    command: str


class MimicRequest(BaseModel):
    enabled: bool


class CommandResponse(BaseModel):
    success: bool
    command: str
    message: str
    # 명령 토픽을 듣고 있는 노드 수. 0이면 발행은 됐지만 로봇은 못 받은 것입니다.
    subscribers: int = 0


# FastAPI 서버가 시작될 때 ROS2 Publisher를 한 번 생성하고,
# 서버가 종료될 때 Publisher와 ROS2 노드를 안전하게 정리합니다.
# 요청이 들어올 때마다 ROS2 노드를 반복 생성하지 않도록 하여
# 노드 이름 충돌과 불필요한 초기화 비용을 방지합니다.
@asynccontextmanager
async def lifespan(
    app: FastAPI,
) -> AsyncIterator[None]:
    global COMMAND_PUBLISHER

    COMMAND_PUBLISHER = OmxCommandPublisher()

    yield

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
@app.post(
    "/robot/command",
    response_model=CommandResponse,
)
def send_robot_command(
    request: CommandRequest,
) -> CommandResponse:
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
