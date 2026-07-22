import os
import signal
import subprocess
import time
from pathlib import Path
from typing import Any


# "Micky 깨우기" 버튼이 누르면 로봇을 쓰기 위해 필요한 여러 프로세스
# (Gazebo 브링업, 카메라 브리지, 모션 서버, 손 모방 노드, 웹 영상 서버)를
# 한꺼번에 백그라운드로 띄웁니다.
#
# 브리지 서버 자신은 이미 떠 있으므로 다시 실행하지 않습니다. 여기서 띄우는
# 프로세스들은 브리지 서버의 환경(ROS·워크스페이스 setup.bash가 source 된
# 상태)을 그대로 물려받습니다. 브리지를 `ros2 run`으로 실행했다면 자식
# 프로세스도 같은 환경에서 `ros2` 명령을 찾을 수 있습니다.
class WakeManager:
    def __init__(
        self,
        services: list[dict[str, Any]],
        log_dir: str,
    ) -> None:
        self._services = services
        self._log_dir = Path(log_dir).expanduser()
        self._log_dir.mkdir(parents=True, exist_ok=True)
        # 이름 -> 우리가 띄운 Popen 프로세스.
        self._processes: dict[str, subprocess.Popen[bytes]] = {}

    # 등록된 모든 서비스를 한꺼번에 백그라운드로 시작합니다.
    #
    # 깨울 때마다 먼저 기존 프로세스를 모두 정리하고 새로 시작합니다.
    # 예전에는 우리가 띄운 래퍼(ros2 launch/run)가 살아 있으면 "이미 실행 중"으로
    # 봤는데, 래퍼는 살아 있어도 그 안의 Gazebo·노드가 죽어 있는 경우가 있어
    # 실제로는 안 도는데 안 띄우는 문제가 있었습니다. 이제는 매번 깨끗이 지우고
    # 새로 띄우므로 항상 같은 상태에서 시작합니다.
    def wake(self) -> list[dict[str, Any]]:
        self._kill_existing()

        results: list[dict[str, Any]] = []

        for service in self._services:
            name = service["name"]
            label = service.get("label", name)

            # persistent 서비스(예: ollama)는 이미 떠 있으면 다시 시작하지 않고 둔다.
            # 한 번 뜨면 wake/sleep이 건드리지 않아 계속 살아 있는다.
            if service.get("persistent") and self._is_running(service):
                results.append({
                    "name": name,
                    "label": label,
                    "status": "already_running",
                })
                continue

            try:
                results.append(
                    self._start_service(name, label, service["cmd"])
                )
            except Exception as error:  # noqa: BLE001
                # 하나가 실패해도 나머지는 계속 띄웁니다.
                results.append(
                    {
                        "name": name,
                        "label": label,
                        "status": "error",
                        "message": str(error),
                    }
                )

        return results

    # 깨우기 전에 기존 프로세스를 모두 종료합니다.
    # (1) 우리가 띄웠던 프로세스 그룹을 통째로 죽이고,
    # (2) 이전에 다른 방식으로 떠 있던(래퍼만 남은) 잔여 프로세스도
    #     명령 패턴으로 찾아 정리합니다.
    def _kill_existing(self) -> None:
        # persistent 서비스(예: ollama)는 죽이지 않고 그대로 둔다.
        persistent = {
            s["name"] for s in self._services if s.get("persistent")
        }

        # (1) 우리가 관리 중인 프로세스 그룹부터 종료(persistent 제외).
        alive = [
            process
            for name, process in self._processes.items()
            if name not in persistent and process.poll() is None
        ]

        for process in alive:
            self._signal_group(process, signal.SIGINT)

        # 얌전히 끝날 시간을 준 뒤, 아직 살아 있으면 강제 종료.
        # lerobot 제어 서버는 재우기 때 팔로워를 리더 위치로 "천천히" 옮긴 뒤
        # 연결을 해제하므로(수 초), 유예를 넉넉히 준다. 모든 프로세스가 먼저
        # 끝나면 그 즉시 빠져나오므로, 빨리 끝나는 서비스는 기다리지 않는다.
        for _ in range(80):  # 최대 8초
            if all(process.poll() is not None for process in alive):
                break
            time.sleep(0.1)

        for process in alive:
            if process.poll() is None:
                self._signal_group(process, signal.SIGKILL)

        # persistent 프로세스는 추적 목록에 남겨 둔다(다음에도 그대로).
        self._processes = {
            name: process
            for name, process in self._processes.items()
            if name in persistent
        }

        # (2) 명령 패턴으로 잔여 프로세스 정리. 브리지 서버 자신(app_bridge_server)은
        #     어떤 패턴에도 걸리지 않으므로 안전합니다.
        for pattern in self._stop_patterns():
            try:
                subprocess.run(
                    ["pkill", "-9", "-f", pattern],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                )
            except FileNotFoundError:
                # pkill이 없는 환경이면 (1)번 정리에만 의존합니다.
                pass

    # 프로세스 그룹 전체에 신호를 보냅니다. start_new_session=True로 띄웠으므로
    # 그룹장을 통해 자식(예: ros2 launch가 띄운 Gazebo·노드)까지 함께 종료됩니다.
    def _signal_group(
        self,
        process: subprocess.Popen[bytes],
        sig: int,
    ) -> None:
        try:
            os.killpg(os.getpgid(process.pid), sig)
        except (ProcessLookupError, PermissionError):
            # 이미 사라졌거나 신호를 못 보내면 넘어갑니다.
            pass

    # 각 서비스 명령에서 잔여 프로세스를 찾을 구별 문자열을 뽑습니다.
    # 서비스 정의에 "match"가 있으면 그것을 쓰고, 없으면 명령에서 추론합니다.
    def _stop_patterns(self) -> list[str]:
        patterns: list[str] = []

        for service in self._services:
            # persistent 서비스(예: ollama)는 패턴 정리에서도 제외 — 안 죽인다.
            if service.get("persistent"):
                continue

            match = service.get("match")
            if match:
                patterns.append(str(match))
            else:
                patterns.append(self._derive_pattern(service["cmd"]))

            # Gazebo는 별도 gz 프로세스를 남기므로 함께 정리합니다.
            if any("gazebo" in str(token) for token in service["cmd"]):
                patterns.append("gz sim")

        # 중복 제거(순서 유지).
        return list(dict.fromkeys(p for p in patterns if p))

    # persistent 서비스가 지금 떠 있는지 match(또는 추론) 패턴으로 확인합니다.
    def _is_running(self, service: dict[str, Any]) -> bool:
        pattern = service.get("match") or self._derive_pattern(service["cmd"])
        if not pattern:
            return False
        try:
            return subprocess.run(
                ["pgrep", "-f", str(pattern)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            ).returncode == 0
        except FileNotFoundError:
            return False

    # ros2 launch <pkg> <launchfile> -> launchfile
    # ros2 run <pkg> <exe> ...        -> exe
    # 그 외                            -> 마지막 토큰
    @staticmethod
    def _derive_pattern(cmd: list[str]) -> str:
        if len(cmd) >= 4 and cmd[0] == "ros2" and cmd[1] in ("launch", "run"):
            return cmd[3]
        return cmd[-1] if cmd else ""

    def _start_service(
        self,
        name: str,
        label: str,
        cmd: list[str],
    ) -> dict[str, Any]:
        log_path = self._log_dir / f"{name}.log"
        # append 모드로 열어 두면 여러 번 깨워도 로그가 이어집니다.
        log_file = log_path.open("ab")

        process = subprocess.Popen(
            cmd,
            stdout=log_file,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            # 자식(그리고 그 자식들)을 하나의 프로세스 그룹으로 묶어 두면
            # 나중에 통째로 정지시킬 수 있습니다. Gazebo 런치처럼 여러
            # 프로세스를 부르는 경우에도 고아 프로세스가 남지 않습니다.
            start_new_session=True,
            env=os.environ.copy(),
        )

        self._processes[name] = process

        return {
            "name": name,
            "label": label,
            "status": "started",
            "pid": process.pid,
            "log": str(log_path),
        }

    # 현재 우리가 관리 중인 서비스들의 실행 상태를 돌려줍니다.
    def status(self) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []

        for service in self._services:
            name = service["name"]
            process = self._processes.get(name)

            if process is None:
                state = "stopped"
            elif process.poll() is None:
                state = "running"
            else:
                state = "exited"

            results.append(
                {
                    "name": name,
                    "label": service.get("label", name),
                    "status": state,
                    "pid": process.pid if process is not None else None,
                }
            )

        return results

    # "미키 재우기" — 깨우기로 띄운 모든 서비스를 종료합니다.
    # 깨우기와 같은 정리 로직을 써서, 우리가 띄운 프로세스 그룹은 물론
    # 래퍼만 남은 잔여 프로세스까지 명령 패턴으로 함께 끕니다.
    # 브리지 서버가 내려갈 때도 이 메서드로 자식들을 정리합니다.
    def sleep(self) -> list[dict[str, Any]]:
        self._kill_existing()

        return [
            {
                "name": service["name"],
                "label": service.get("label", service["name"]),
                "status": "stopped",
            }
            for service in self._services
        ]
