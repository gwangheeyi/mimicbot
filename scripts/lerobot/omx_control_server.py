#!/usr/bin/env python
"""omx_control_server.py — lerobot 기반 OMX 팔로워 제어 서버.

리더-팔로워 텔레옵을 기본으로 돌리면서, HTTP로 "포즈 명령"을 받으면 팔로워를
정해진 포즈로 부드럽게 옮기고 유지합니다(그 동안 teleop은 잠깐 멈춤). 앱의 동작
버튼(home/ready/attention/salute 등)이 브리지를 거쳐 이 서버로 오면 팔로워가 그
포즈를 취합니다.

lerobot 모터 버스는 스레드 안전하지 않으므로, 모든 로봇 I/O는 제어 루프 스레드에서만
합니다. HTTP 핸들러는 공유 상태(요청)만 락으로 바꿔 두고, 루프가 다음 주기에 처리합니다.

포즈 값은 로봇마다 다릅니다. 리더 팔을 원하는 자세로 두고 POST /teach 로 현재
리더 위치를 그 이름의 포즈로 저장하면, 정확한 값을 손으로 가르칠 수 있습니다.

실행(venv 안에서):
  source ~/venv/il/bin/activate
  python omx_control_server.py \
    --follower-port /dev/omx_follower --follower-id omx_follower_arm \
    --leader-port /dev/omx_leader --leader-id omx_leader_arm \
    --http-port 8100 --poses ~/mimicbot/config/omx_poses.json

HTTP API:
  GET  /health                 -> {"status":"ok","mode":..,"poses":[..]}
  POST /pose   {"name":"ready"}-> 그 포즈로 이동 후 유지(teleop 멈춤)
  POST /teleop                 -> 리더-팔로워 텔레옵 재개
  POST /teach  {"name":"ready"}-> 현재 리더 위치를 그 이름의 포즈로 저장
"""

import argparse
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from lerobot.robots.omx_follower import OmxFollower, OmxFollowerConfig
from lerobot.teleoperators.omx_leader import OmxLeader, OmxLeaderConfig

from hand_mimic_lerobot import HandMimic


# 다이나믹셀 버스는 가끔 첫 핸드셰이크에서 모터 하나를 순간적으로 못 잡는 글리치가
# 있다. 한 번 실패에 죽지 않도록 몇 번 재시도한다. 실패 시 포트만 닫고(토크 끄기는
# 누락된 모터에 쓰다 또 실패하므로 건드리지 않음) 다시 시도한다.
def connect_with_retry(device, name: str, attempts: int = 5, delay: float = 1.5):
    for i in range(attempts):
        try:
            device.connect()
            return
        except Exception as err:  # noqa: BLE001
            print(f"[omx_control_server] {name} 연결 실패 "
                  f"({i + 1}/{attempts}): {err}", flush=True)
            try:
                device.bus.disconnect(disable_torque=False)
            except Exception:  # noqa: BLE001
                pass
            if i < attempts - 1:
                time.sleep(delay)
            else:
                raise


# 자율(정책 실행) 설정으로 lerobot-record 명령 인자 목록을 만든다.
# policy_path 만 앱에서 받고 나머지는 설정 파일(omx_autonomous.json) 값을 쓴다.
def build_record_command(
    cfg: dict, policy_path: str,
    follower_port: str, follower_id: str,
) -> list[str]:
    return [
        "lerobot-record",
        f"--robot.type=omx_follower",
        f"--robot.port={follower_port}",
        f"--robot.id={follower_id}",
        f"--robot.cameras={cfg.get('cameras', '{}')}",
        f"--policy.path={policy_path}",
        f"--policy.device={cfg.get('policy_device', 'cuda')}",
        f"--display_data={'true' if cfg.get('display_data', True) else 'false'}",
        f"--dataset.repo_id={cfg.get('dataset_repo_id', '')}",
        f"--dataset.single_task={cfg.get('single_task', '')}",
        f"--dataset.num_episodes={cfg.get('num_episodes', 1)}",
        f"--dataset.episode_time_s={cfg.get('episode_time_s', 60)}",
        f"--dataset.reset_time_s={cfg.get('reset_time_s', 5)}",
        f"--dataset.push_to_hub={'true' if cfg.get('push_to_hub', False) else 'false'}",
    ]


# 자율 실행: 팔로워/리더를 놓고 주어진 명령(전체 lerobot-record 명령)을 셸로 돌린 뒤
# 다시 잡는다. 제어 루프(단일 스레드)에서 호출되며, 끝날 때까지(또는 재우기 시) 막는다.
def run_autonomous(state, follower, leader, command: str, mimic) -> None:
    if mimic is not None:
        try:
            mimic.stop()
        except Exception:  # noqa: BLE001
            pass
    with state.lock:
        state.autonomous_running = True
        state.mode = "autonomous"
        state.mimic_instance = None
        state.autonomous_message = "자율 실행 준비"

    # 팔로워/리더 연결 해제(포트를 명령이 잡도록 넘긴다).
    for dev, nm in ((follower, "팔로워"), (leader, "리더")):
        try:
            dev.disconnect()
        except Exception:  # noqa: BLE001
            try:
                dev.bus.disconnect(disable_torque=False)
            except Exception:  # noqa: BLE001
                pass

    # lerobot-record 는 데이터셋 폴더가 이미 있으면 FileExistsError로 죽는다.
    # 명령에서 --dataset.repo_id 를 뽑아 그 폴더를 지운다(없으면 설정값).
    match = re.search(r"--dataset\.repo_id[=\s]+['\"]?([^\s'\"]+)", command)
    repo_id = match.group(1) if match else str(
        state.autonomous_config.get("dataset_repo_id", "")
    ).strip()
    if repo_id:
        hf_home = os.environ.get("HF_LEROBOT_HOME") or str(
            Path.home() / ".cache/huggingface/lerobot"
        )
        ds_dir = Path(hf_home) / repo_id
        if ds_dir.exists():
            try:
                shutil.rmtree(ds_dir)
                print(f"[omx_control_server] 기존 eval 데이터셋 삭제: {ds_dir}",
                      flush=True)
            except Exception as err:  # noqa: BLE001
                print(f"[omx_control_server] eval 데이터셋 삭제 실패: {err}",
                      flush=True)

    # $POLICY_PATH 를 명령에 그대로 두고 싶을 때를 위해 환경에 채워 준다(설정값).
    env = dict(os.environ)
    default_pp = str(state.autonomous_config.get("default_policy_path", "")).strip()
    if default_pp:
        env["POLICY_PATH"] = default_pp

    print(f"[omx_control_server] 자율 실행: {command}", flush=True)
    try:
        state.log_dir.mkdir(parents=True, exist_ok=True)
    except Exception:  # noqa: BLE001
        pass
    log_path = state.log_dir / "lerobot_autonomous.log"

    proc = None
    try:
        log_f = open(log_path, "ab")
        # shell=True 로 따옴표·중괄호가 든 명령을 그대로 파싱해 실행한다.
        # start_new_session 으로 프로세스 그룹을 만들어, 중단 시 자식까지 함께 끈다.
        proc = subprocess.Popen(
            command, shell=True, executable="/bin/bash",
            stdout=log_f, stderr=subprocess.STDOUT,
            start_new_session=True, env=env,
        )
    except Exception as err:  # noqa: BLE001
        with state.lock:
            state.autonomous_message = f"자율 실행 시작 실패: {err}"
    else:
        with state.lock:
            state.autonomous_message = "자율 실행 중"
        # 끝날 때까지 대기. 재우기(stopping) 요청이 오면 그룹째 중단시킨다.
        while proc.poll() is None:
            with state.lock:
                stop = state.stopping
            if stop:
                try:
                    os.killpg(os.getpgid(proc.pid), signal.SIGINT)
                except Exception:  # noqa: BLE001
                    pass
                try:
                    proc.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                    except Exception:  # noqa: BLE001
                        pass
                break
            time.sleep(0.5)
        rc = proc.poll()
        with state.lock:
            state.autonomous_message = f"자율 실행 종료 (code={rc})"
        try:
            log_f.close()
        except Exception:  # noqa: BLE001
            pass

    # 정책이 끝났으면 팔로워/리더를 다시 잡고 teleop 재개(재우기 중이면 생략).
    with state.lock:
        stopping = state.stopping
    if not stopping:
        try:
            connect_with_retry(follower, "팔로워")
            connect_with_retry(leader, "리더")
        except Exception as err:  # noqa: BLE001
            with state.lock:
                state.autonomous_message = f"정책 후 재연결 실패: {err}"
    with state.lock:
        state.autonomous_running = False
        state.mode = "teleop"


# ── 공유 상태 (HTTP 스레드 ↔ 제어 루프) ──────────────────────────────
class State:
    def __init__(self, poses_path: Path, move_seconds: float, fps: int):
        self.lock = threading.Lock()
        self.poses_path = poses_path
        self.move_seconds = move_seconds
        self.fps = fps
        self.poses: dict[str, dict[str, float]] = _load_poses(poses_path)
        # 대기 중인 요청(제어 루프가 소비).
        self.pose_request: str | None = None
        self.teleop_request: bool = False
        self.teach_request: str | None = None
        # 손 모방 시작/정지 요청(True/False). None이면 변화 없음.
        self.mimic_request: bool | None = None
        # 현재 손 모방 인스턴스(제어 루프가 갱신). /hand_stream 이 영상을 읽는다.
        self.mimic_instance = None
        # 손 모방 설정(제어 루프가 HandMimic 만들 때 사용).
        self.hand_model_path: str = ""
        self.camera_index: int = 0
        # 자율(정책 실행) 요청: 정책 경로(str) 또는 None. 실행 중이면 running.
        self.autonomous_request: str | None = None
        self.autonomous_running: bool = False
        self.autonomous_message: str = ""
        # 자율 설정(cameras/dataset 등). main에서 채운다.
        self.autonomous_config: dict = {}
        self.follower_port: str = "/dev/omx_follower"
        self.follower_id: str = "omx_follower_arm"
        self.log_dir: Path = Path.home() / "mimicbot/logs"
        # 마지막 요청 처리 결과(HTTP가 참고).
        self.last_error: str | None = None
        self.mode: str = "teleop"
        self.running: bool = True
        # 종료 요청. True 가 되면 제어 루프가 팔로워를 리더 위치로 천천히 옮긴 뒤
        # 루프를 빠져나가 연결을 해제한다.
        self.stopping: bool = False
        self.return_seconds: float = 2.5


def _load_poses(path: Path) -> dict[str, dict[str, float]]:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def _save_poses(path: Path, poses: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(poses, indent=2, ensure_ascii=False))


# ── HTTP 서버 ────────────────────────────────────────────────────────
def make_handler(state: State):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):  # 조용히
            pass

        def _json(self, code: int, body: dict) -> None:
            data = json.dumps(body).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def _read_json(self) -> dict:
            length = int(self.headers.get("Content-Length", 0) or 0)
            if not length:
                return {}
            try:
                return json.loads(self.rfile.read(length).decode("utf-8"))
            except json.JSONDecodeError:
                return {}

        def do_GET(self):
            path = self.path.split("?")[0]
            if path == "/health":
                with state.lock:
                    self._json(200, {
                        "status": "ok",
                        "mode": state.mode,
                        "poses": sorted(state.poses.keys()),
                        "autonomous_running": state.autonomous_running,
                        "autonomous_message": state.autonomous_message,
                    })
            elif path == "/hand_stream":
                self._hand_stream()
            else:
                self._json(404, {"error": "not found"})

        # 손 그린 웹캠 프레임을 MJPEG(multipart)로 계속 흘려보낸다.
        # 앱의 실시간 모방 화면이 이 주소를 <img>/스트림으로 받아 표시한다.
        def _hand_stream(self) -> None:
            self.send_response(200)
            self.send_header(
                "Content-Type",
                "multipart/x-mixed-replace; boundary=frame",
            )
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            try:
                while True:
                    with state.lock:
                        inst = state.mimic_instance
                        running = state.running
                    if not running:
                        break
                    jpeg = inst.get_jpeg() if inst else None
                    if jpeg:
                        self.wfile.write(
                            b"--frame\r\nContent-Type: image/jpeg\r\n"
                            b"Content-Length: " + str(len(jpeg)).encode()
                            + b"\r\n\r\n" + jpeg + b"\r\n"
                        )
                    time.sleep(0.05)  # ~20fps
            except (BrokenPipeError, ConnectionResetError):
                pass  # 앱이 화면을 나가 연결을 끊음

        def do_POST(self):
            path = self.path.split("?")[0]
            body = self._read_json()
            if path == "/pose":
                name = str(body.get("name", "")).strip()
                # "leader"는 특수 포즈: 현재 리더 위치로 이동 후 대기(포즈 목록에 없어도 됨).
                with state.lock:
                    if name != "leader" and name not in state.poses:
                        self._json(404, {
                            "success": False,
                            "error": f"모르는 포즈: {name}. 먼저 /teach 로 가르치세요.",
                            "poses": sorted(state.poses.keys()),
                        })
                        return
                    state.pose_request = name
                self._json(200, {"success": True, "message": f"포즈 '{name}' 이동 요청"})
            elif path == "/teleop":
                with state.lock:
                    state.teleop_request = True
                self._json(200, {"success": True, "message": "텔레옵 재개 요청"})
            elif path == "/mimic":
                enabled = bool(body.get("enabled", True))
                with state.lock:
                    state.mimic_request = enabled
                self._json(200, {
                    "success": True,
                    "message": f"손 모방 {'시작' if enabled else '정지'} 요청",
                })
            elif path == "/teach":
                name = str(body.get("name", "")).strip()
                if not name:
                    self._json(400, {"success": False, "error": "name 필요"})
                    return
                with state.lock:
                    state.teach_request = name
                self._json(200, {"success": True, "message": f"현재 리더 자세를 '{name}' 로 저장 요청"})
            elif path == "/autonomous":
                # 자율 실행 요청. command(전체 명령)를 그대로 실행한다.
                # command 가 비면 policy_path + 설정으로 명령을 만든다(하위호환).
                command = str(body.get("command", "")).strip()
                if not command:
                    policy = str(body.get("policy_path", "")).strip() or str(
                        state.autonomous_config.get("default_policy_path", "")
                    ).strip()
                    if policy:
                        command = shlex.join(build_record_command(
                            state.autonomous_config, policy,
                            state.follower_port, state.follower_id,
                        ))
                with state.lock:
                    if state.autonomous_running:
                        self._json(409, {
                            "success": False,
                            "error": "이미 자율(정책)이 실행 중입니다.",
                        })
                        return
                    if not command:
                        self._json(400, {
                            "success": False,
                            "error": "실행할 명령이 비어 있습니다. 패널에 lerobot-record 명령을 넣으세요.",
                        })
                        return
                    state.autonomous_request = command
                self._json(200, {
                    "success": True,
                    "message": "자율 실행을 시작합니다. 팔로워를 넘겨받아 명령을 돌립니다.",
                })
            else:
                self._json(404, {"error": "not found"})

    return Handler


# ── 제어 루프 (로봇 I/O는 여기서만) ──────────────────────────────────
def only_pos(action: dict) -> dict[str, float]:
    return {k: float(v) for k, v in action.items() if k.endswith(".pos")}


# start -> target 를 steps 단계로 선형 보간한 프레임 목록.
def interp_frames(
    start: dict[str, float],
    target: dict[str, float],
    steps: int,
) -> list[dict[str, float]]:
    steps = max(1, steps)
    return [
        {k: start.get(k, target[k]) + (target[k] - start.get(k, target[k])) * (s + 1) / steps
         for k in target}
        for s in range(steps)
    ]


# 포즈를 실제 목표 관절값으로 푼다.
# - 보통 포즈: {"shoulder_pan.pos": .., ...} 그대로.
# - 파생 포즈: {"base": "ready", "offset": {"shoulder_pan.pos": 25}} 처럼
#   다른 포즈를 기준으로 오프셋을 더한다(예: left=레디에서 베이스 +45°).
#   base 를 다시 가르치면 파생 포즈도 함께 따라간다.
def resolve_pose(poses: dict, name: str, _depth: int = 0) -> dict[str, float] | None:
    p = poses.get(name)
    if p is None or _depth > 8:
        return None
    if isinstance(p, dict) and "base" in p:
        base = resolve_pose(poses, str(p["base"]), _depth + 1)
        if base is None:
            return None
        target = dict(base)
        for key, val in only_pos(p.get("offset", {})).items():
            target[key] = target.get(key, 0.0) + float(val)
        return target
    return only_pos(p)


def control_loop(state: State, follower: OmxFollower, leader: OmxLeader) -> None:
    period = 1.0 / state.fps
    # 진행 중인 포즈 이동(보간) 프레임과 인덱스.
    move_frames: list[dict[str, float]] = []
    move_index = 0
    hold_target: dict[str, float] | None = None
    # 종료 시 리더 위치로 되돌아가는 이동 프레임(설정 전이면 None).
    return_frames: list[dict[str, float]] | None = None
    return_index = 0
    # 손 모방(웹캠) 인스턴스. None이면 모방 꺼짐.
    mimic: HandMimic | None = None
    # 이동(move_frames) 완료 후 teleop(리더 추종)으로 대기할지. "leader" 정착에 쓴다.
    then_teleop = False

    while True:
        loop_start = time.perf_counter()

        with state.lock:
            if not state.running:
                break
            stopping = state.stopping
            return_seconds = state.return_seconds
            pose_req = state.pose_request
            state.pose_request = None
            teleop_req = state.teleop_request
            state.teleop_request = False
            teach_req = state.teach_request
            state.teach_request = None
            mimic_req = state.mimic_request
            state.mimic_request = None
            autonomous_req = state.autonomous_request
            state.autonomous_request = None
            poses = state.poses

        # 0) 종료 요청 — 팔로워를 리더 위치로 천천히 옮긴 뒤 루프를 끝낸다.
        # 이렇게 하면 재우기 때 팔로워가 갑자기 토크가 풀려 떨어지지 않고,
        # 리더(보통 자연스러운 쉼 자세)로 부드럽게 맞춘 뒤 연결이 해제된다.
        if stopping:
            if mimic is not None:
                mimic.stop()
                mimic = None
            if return_frames is None:
                try:
                    leader_pos = only_pos(leader.get_action())
                    cur = only_pos(follower.get_observation())
                except Exception:  # noqa: BLE001
                    leader_pos, cur = {}, {}
                return_frames = interp_frames(
                    cur, leader_pos, int(return_seconds * state.fps)
                ) if leader_pos else []
                return_index = 0
            try:
                if return_index < len(return_frames):
                    follower.send_action(return_frames[return_index])
                    return_index += 1
                else:
                    break  # 이동 완료 → 루프 종료 → 연결 해제(토크 off)
            except Exception:  # noqa: BLE001
                break
            dt = time.perf_counter() - loop_start
            if dt < period:
                time.sleep(period - dt)
            continue

        # 0.5) 자율(정책) 실행 — 팔로워/리더를 놓고 lerobot-record 를 돌린 뒤 다시 잡는다.
        # lerobot-record 가 팔로워 포트와 카메라를 직접 잡으므로, 제어 서버는 잠시
        # 연결을 해제해 넘겨준다. 정책이 끝나면(또는 재우기 요청 시) 다시 연결한다.
        if autonomous_req:
            run_autonomous(state, follower, leader, autonomous_req,
                           mimic if mimic else None)
            mimic = None  # 자율 실행 중 모방은 정리됨
            continue

        # 1) teach: 현재 리더 위치를 포즈로 저장.
        if teach_req:
            try:
                current = only_pos(leader.get_action())
                with state.lock:
                    state.poses[teach_req] = current
                    _save_poses(state.poses_path, state.poses)
            except Exception as err:  # noqa: BLE001
                with state.lock:
                    state.last_error = f"teach 실패: {err}"

        # 2) teleop 재개 요청 — 손 모방 중이면 끄고 리더 추종으로.
        if teleop_req:
            if mimic is not None:
                mimic.stop()
                mimic = None
            move_frames, move_index, hold_target = [], 0, None
            with state.lock:
                state.mode = "teleop"

        # 2.5) 손 모방 시작/정지.
        if mimic_req is True and mimic is None:
            base = resolve_pose(poses, "mimic_base") or {}
            up = resolve_pose(poses, "mimic_up") or base
            if not base:
                with state.lock:
                    state.last_error = "mimic_base 포즈가 없습니다(먼저 /teach)."
            else:
                try:
                    mimic = HandMimic(
                        state.hand_model_path, base, up,
                        camera_index=state.camera_index,
                    )
                    mimic.start()
                    move_frames, move_index, hold_target = [], 0, None
                    with state.lock:
                        state.mode = "mimic"
                except Exception as err:  # noqa: BLE001
                    mimic = None
                    with state.lock:
                        state.last_error = f"손 모방 시작 실패: {err}"
        elif mimic_req is False and mimic is not None:
            mimic.stop()
            mimic = None
            with state.lock:
                state.mode = "teleop"

        # 3) 포즈 이동 요청 — 현재 팔로워 위치에서 목표까지 부드럽게 보간.
        # 포즈 명령이 오면 손 모방보다 우선(모방 끄고 그 자세로).
        # 특수 포즈 "leader": 현재 리더 위치로 조용히 이동한 뒤 teleop(리더 추종)으로
        # 대기한다. 실시간 모방 화면 진입/이탈 시 이걸로 리더 위치에 대기시킨다.
        if pose_req == "leader":
            try:
                target = only_pos(leader.get_action())
            except Exception:  # noqa: BLE001
                target = None
        elif pose_req:
            target = resolve_pose(poses, pose_req)
        else:
            target = None

        if target:
            if mimic is not None:
                mimic.stop()
                mimic = None
            try:
                obs = only_pos(follower.get_observation())
            except Exception:  # noqa: BLE001
                obs = {}
            move_frames = interp_frames(
                obs, target, int(state.move_seconds * state.fps)
            )
            move_index = 0
            hold_target = target
            # "leader" 정착이면 이동 후 teleop로 대기, 일반 포즈면 그 자세 유지.
            then_teleop = pose_req == "leader"
            with state.lock:
                state.mode = "pose"

        # 손 모방 스레드가 에러나면(웹캠 등) 끄고 알린다.
        if mimic is not None and mimic.error():
            with state.lock:
                state.last_error = mimic.error()
            mimic.stop()
            mimic = None
            with state.lock:
                state.mode = "teleop"

        # 4) 실제 제어. 우선순위: 포즈 이동 > 손 모방 > 포즈 유지 > teleop.
        try:
            if move_frames and move_index < len(move_frames):
                follower.send_action(move_frames[move_index])
                move_index += 1
                # 이동이 방금 끝났고 "leader" 정착이면 teleop(리더 추종)으로 대기.
                if move_index >= len(move_frames) and then_teleop:
                    move_frames, hold_target, then_teleop = [], None, False
                    with state.lock:
                        state.mode = "teleop"
            elif mimic is not None:
                # 손 모방: 웹캠에서 계산한 목표를 따라간다. 손이 안 잡히면
                # 마지막 자세를 유지(아무것도 안 보냄).
                hand_target = mimic.get_target()
                if hand_target:
                    follower.send_action(hand_target)
            elif hold_target is not None:
                # 이동 끝났으면 목표를 계속 보내 유지(teleop 멈춤 상태).
                follower.send_action(hold_target)
            else:
                # teleop: 리더를 그대로 따라감.
                follower.send_action(leader.get_action())
        except Exception as err:  # noqa: BLE001
            with state.lock:
                state.last_error = f"제어 오류: {err}"

        # /hand_stream 핸들러가 접근할 수 있게 현재 손 모방 인스턴스를 공유.
        with state.lock:
            state.mimic_instance = mimic

        # 주기 유지.
        dt = time.perf_counter() - loop_start
        if dt < period:
            time.sleep(period - dt)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--follower-port", default="/dev/omx_follower")
    parser.add_argument("--follower-id", default="omx_follower_arm")
    parser.add_argument("--leader-port", default="/dev/omx_leader")
    parser.add_argument("--leader-id", default="omx_leader_arm")
    parser.add_argument("--http-port", type=int, default=8100)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--move-seconds", type=float, default=2.0,
                        help="포즈로 이동하는 시간(초). 클수록 천천히·안전")
    parser.add_argument("--return-seconds", type=float, default=2.5,
                        help="재우기 때 리더 위치로 되돌아가는 시간(초)")
    parser.add_argument("--poses", default=str(Path.home() / "mimicbot/config/omx_poses.json"))
    parser.add_argument("--camera-index", type=int, default=0,
                        help="손 모방 웹캠 장치 번호(/dev/videoN)")
    parser.add_argument("--hand-model", default=str(
        Path.home() / "mimicbot/ros2_ws/src/open_manipulator_app_control/"
        "models/hand_landmarker.task"),
        help="mediapipe 손 인식 모델(.task) 경로")
    parser.add_argument("--autonomous-config", default=str(
        Path.home() / "mimicbot/config/omx_autonomous.json"),
        help="자율(정책 실행) lerobot-record 설정 파일")
    parser.add_argument("--log-dir", default=str(Path.home() / "mimicbot/logs"))
    args = parser.parse_args()

    state = State(Path(args.poses).expanduser(), args.move_seconds, args.fps)
    state.return_seconds = args.return_seconds
    state.hand_model_path = str(Path(args.hand_model).expanduser())
    state.camera_index = args.camera_index
    state.follower_port = args.follower_port
    state.follower_id = args.follower_id
    state.log_dir = Path(args.log_dir).expanduser()
    try:
        state.autonomous_config = json.loads(
            Path(args.autonomous_config).expanduser().read_text()
        )
    except (OSError, json.JSONDecodeError) as err:
        print(f"[omx_control_server] 자율 설정 로드 실패({args.autonomous_config}): {err}",
              flush=True)
        state.autonomous_config = {}

    follower = OmxFollower(OmxFollowerConfig(port=args.follower_port, id=args.follower_id))
    leader = OmxLeader(OmxLeaderConfig(port=args.leader_port, id=args.leader_id))

    print("[omx_control_server] 팔로워/리더 연결 중...", flush=True)
    connect_with_retry(follower, "팔로워")
    connect_with_retry(leader, "리더")
    print(f"[omx_control_server] 연결됨. teleop 시작. HTTP :{args.http_port}", flush=True)
    print(f"[omx_control_server] 포즈 파일: {state.poses_path} "
          f"(등록: {sorted(state.poses.keys())})", flush=True)

    # 종료 신호 → 팔로워를 리더 위치로 천천히 옮긴 뒤(제어 루프가 처리) 연결 해제.
    # 두 번째 신호가 오면 즉시 멈춘다(강제 종료 대비).
    def stop(*_):
        with state.lock:
            if state.stopping:
                state.running = False  # 두 번째 신호 → 즉시 종료
            state.stopping = True
    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    httpd = ThreadingHTTPServer(("0.0.0.0", args.http_port), make_handler(state))
    http_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    http_thread.start()

    try:
        control_loop(state, follower, leader)
    finally:
        httpd.shutdown()
        try:
            leader.disconnect()
        except Exception:  # noqa: BLE001
            pass
        try:
            follower.disconnect()
        except Exception:  # noqa: BLE001
            pass
        print("[omx_control_server] 종료(연결 해제)", flush=True)


if __name__ == "__main__":
    main()
