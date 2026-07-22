# 맥시(OMX-AI 실물) 다른 PC 시연 가이드 — lerobot 기반

**구성**: Flutter 앱은 **이 PC(앱 PC)** 에서 실행하고, 실제 로봇(OMX-AI)은 **GPU가 있는 다른 PC(로봇 PC)** 에서 lerobot으로 구동한다.

> 미키(Gazebo 가상)는 ROS2 기반이고, 맥시(실물)는 **lerobot 기반**이다. 이 문서는 맥시(실물)만 다룬다.

---

## 0. 전체 구조

```
┌───────── 앱 PC (이 컴퓨터) ─────────┐        ┌──────── 로봇 PC (GPU) ─────────────┐
│  Flutter 앱                          │        │  브리지 서버 (FastAPI :8000)        │
│   - maxiHost = 로봇 PC IP            │──HTTP──▶│  lerobot 제어 서버 (:8100)          │
│   - maxiCameraUrl = mediamtx 주소    │  :8000  │   = 리더-팔로워 teleop + 포즈 +      │
│                                      │  :8100  │     손모방 + 자율(정책)             │
│   (앱만 실행)                        │◀─MJPEG─│   - 손 인식 영상 /hand_stream       │
└──────────────────────────────────────┘  :8100  │  ollama(qwen3:4b, 대화·춤)          │
                     │                            │  실물 리더+팔로워 (USB)             │
                     │  ── WebRTC(:8889) ──▶      │  카메라 video2·video4 (정책)        │
                     └──────────────────── mediamtx (로봇 시점 카메라 송출) ──────────┘
```

- 앱 → 로봇 PC: 동작 명령·모방·자율은 **HTTP(:8000→:8100)**, 손 인식 영상은 **:8100/hand_stream(MJPEG)**.
- 로봇 시점 카메라는 **mediamtx WebRTC 페이지**(예: `http://<mediamtx IP>:8889/mystream/`)를 앱이 iframe으로 띄운다.
- 앱↔로봇은 **IP(HTTP)만** 오가고, lerobot·ROS·DDS는 로봇 PC 안에서만 돈다. 와이파이로 DDS를 안 태우므로 안정적이다.

---

## A. 로봇 PC 준비 (순서대로)

### A-1. lerobot 파이썬 환경
- venv 준비(예: `~/venv/il`)와 lerobot(editable, 예: `~/il_ws/src/lerobot`) 설치.
- **커스텀 로봇 타입**이 그 lerobot에 있어야 한다: `omx_follower`(robot), `omx_leader`(teleop).
  - 확인: `source ~/venv/il/bin/activate && python -c "from lerobot.robots.omx_follower import OmxFollower; from lerobot.teleoperators.omx_leader import OmxLeader; print('ok')"`
- **mediapipe 설치**(손 모방에 필요): `pip install mediapipe` (cv2는 lerobot이 가져옴).

### A-2. 로봇 USB 연결 + udev 심링크 + 권한
- 리더·팔로워 두 팔을 USB로 연결.
- lerobot 명령은 **`/dev/omx_follower`, `/dev/omx_leader`** 를 쓴다. 그 PC에서 두 팔의 실제 포트(`ls /dev/ttyACM*`)를 확인하고 **udev 규칙으로 심링크**를 만든다(시리얼 번호 기준 권장).
  - 확인: `ls -l /dev/omx_follower /dev/omx_leader`
  - 심링크를 못 쓰면 대안: 아래 A-8에서 제어 서버 인자 `--follower-port/--leader-port`를 실제 포트로.
- USB 권한: `sudo usermod -aG dialout $USER` (로그아웃 후 재로그인).

### A-3. 캘리브레이션 (로봇마다 다름 — 필수)
- 그 로봇으로 **새로 캘리브레이션**해야 한다. 다른 로봇의 캘리브레이션은 안 맞는다.
- 캘리브레이션 파일 위치: `~/.cache/huggingface/lerobot/calibration/robots/omx_follower/omx_follower_arm.json`, `.../teleoperators/omx_leader/omx_leader_arm.json`.
- lerobot 캘리브레이션 절차를 따른다(리더/팔로워 각각).

### A-4. 카메라 확인 (인덱스가 PC마다 다름)
- 정책 실행에 쓰는 카메라 2대(front, wrist)의 실제 장치 번호 확인:
  - `v4l2-ctl --list-devices` 로 어느 카메라가 어느 `/dev/videoN` 인지 확인.
  - `v4l2-ctl -d /dev/videoN --list-formats-ext` 로 **640×480 MJPG 30fps** 지원 확인.
- 손 모방 웹캠(별도)의 번호도 확인(정책 카메라와 겹치지 않게).
- ⚠️ **`backend: V4L2` 를 반드시 넣어야** 640×480 MJPG 설정이 먹는다(기본 ANY는 실패). 아래 config에 이미 반영돼 있음.

### A-5. 학습된 정책 파일 배치
- 모방학습 정책(체크포인트/pretrained_model 폴더)을 로봇 PC에 둔다(예: `~/lerobot_models/omx_project-v2-finetuned`).

### A-6. ollama + 모델
- `ollama` 설치 후 `ollama pull qwen3:4b`.
- ollama는 브리지 시작 스크립트가 띄우고, wake/sleep과 무관하게 **계속 유지**(persistent)된다.

### A-7. mimicbot 저장소 + 브리지 빌드
- `~/mimicbot` 을 로봇 PC에 복사.
- 브리지 패키지 빌드(이 워크스페이스는 복사설치라 그 PC에서 다시 빌드해야 함):
  ```bash
  cd ~/mimicbot/ros2_ws
  source /opt/ros/jazzy/setup.bash
  colcon build --packages-select open_manipulator_app_bridge
  source install/setup.bash
  ```

### A-8. 설정(config) — 로봇 PC에 맞게 수정
| 파일 | 무엇을 |
|---|---|
| `ros2_ws/.../config/app_bridge_config.yaml` (omxAi 프로파일의 `lerobot_control` cmd) | `--follower-port`, `--leader-port`(심링크 안 쓰면), 손모방 `--camera-index` |
| `config/omx_autonomous.json` | 정책 카메라(`/dev/video2`,`/dev/video4` → 실제 번호, `backend: V4L2` 유지), `default_policy_path`(정책 경로), `policy_device`(cuda), dataset 값 |
| `config/omx_poses.json` | home/ready/attention/salute/left/right, mimic_base/up — **그 로봇으로 `/teach` 해서 실측** |
- config 파일(yaml/json) 수정 후 브리지 패키지는 **다시 빌드**(복사설치): `colcon build --packages-select open_manipulator_app_bridge`.
- 앱 자율 화면의 정책 명령 기본값(정책 경로·카메라·device)은 앱에서 편집 가능하지만, 로봇 PC 경로가 다르면 [flutter_app/lib/screens/autonomous_screen.dart](../flutter_app/lib/screens/autonomous_screen.dart)의 `_defaultPolicyCommand`도 그 PC 기준으로 맞추면 편하다.

### A-9. mediamtx (로봇 시점 카메라)
- 로봇 시점 카메라를 mediamtx로 송출(예: `http://<로봇 PC 또는 mediamtx IP>:8889/mystream/`).
- 이 주소를 앱 `maxiCameraUrl`에 넣는다(아래 B-2).

### A-10. GPU / CUDA 확인
- 정책은 `--policy.device=cuda`. 확인:
  ```bash
  source ~/venv/il/bin/activate
  python -c "import torch; print('cuda:', torch.cuda.is_available())"   # True 여야 함
  nvidia-smi
  ```
- `False`면 드라이버/CUDA 설치 필요. (임시로 `cpu`도 되지만 30Hz 제어를 못 채워 불안정.)

### A-11. 방화벽
- 로봇 PC에서 앱이 접속할 포트 열기:
  ```bash
  sudo ufw allow 8000/tcp   # 브리지
  sudo ufw allow 8100/tcp   # lerobot 제어 서버 + 손 인식 스트림
  ```
- mediamtx 포트(예: 8889)도 앱에서 접근 가능해야 함.

### A-12. 브리지 실행
```bash
cd ~/mimicbot
./scripts/start_mimicbot.sh          # 브리지 :8000 + ollama
curl http://localhost:8000/health    # {"status":"ok",...}
```

---

## B. 앱 PC 준비 (이 컴퓨터)

### B-1. 로봇 PC IP 설정
- 로봇 PC에서 `hostname -I` 로 IP 확인.
- [flutter_app/lib/config/app_config.dart](../flutter_app/lib/config/app_config.dart) 의 `maxiHost` 를 **로봇 PC IP** 로.
  - 또는 실행 시 `--dart-define=MAXI_HOST=<로봇 PC IP>`.

### B-2. 로봇 시점 카메라 주소
- 같은 파일의 `maxiCameraUrl` 을 mediamtx 주소로(예: `http://<mediamtx IP>:8889/mystream/`).
  - 또는 `--dart-define=MAXI_CAMERA_URL=...`.

### B-3. Flutter 앱 빌드·실행
- 웹(Chrome)에서 실행(로봇 시점 카메라가 WebRTC iframe이라 **웹 권장**):
  ```bash
  cd flutter_app
  flutter run -d chrome --dart-define=MAXI_HOST=<로봇 PC IP> --dart-define=MAXI_CAMERA_URL=http://<mediamtx IP>:8889/mystream/
  ```
- HTTPS로 서빙하면 HTTP mediamtx가 혼합콘텐츠로 막힐 수 있으니 **HTTP로 서빙**.

---

## C. 시연 실행 순서

1. **로봇 PC**: 로봇 전원 ON → USB·카메라 연결 확인 → `./scripts/start_mimicbot.sh`.
2. **앱 PC**: 앱 실행(위 B-3). 홈에서 **"OMX-AI 실물(맥시)"** 선택.
3. **깨우기 전** 리더 팔을 팔로워 홈 근처에 둔다(깨우면 잠깐 리더를 따라감).
4. 앱에서 **"깨우기"** → 로봇 PC에서 lerobot 제어 서버(:8100)가 뜨고 **리더-팔로워 teleop** 시작.
5. 기능:
   - **동작 명령**(home/ready/attention/salute/left/right): 팔로워가 그 포즈로.
   - **실시간 모방**: 화면 진입 시 조용히 리더 위치로 대기 → "모방 시작" → 웹캠 손동작 따라함(위 칸에 손 인식 영상).
   - **자율 "책상을 정리해줘"**: 정책 명령 확인 후 실행 → 제어 서버가 팔로워를 넘겨받아 lerobot-record(정책)로 스스로 수행 → 끝나면 teleop 재개.
6. **재우기**: 팔로워가 조용히 리더 위치로 이동 후 종료. (ollama는 유지됨.)

> ⚠️ **안전**: 실물이 실제로 움직인다. 깨우기·모방·자율 전에 로봇 주변 사람·물건을 치운다.

---

## D. 빠른 검증 (로봇 PC)
```bash
curl http://localhost:8000/health                         # 브리지
curl http://localhost:8100/health                         # 제어 서버(깨운 뒤): mode, autonomous_running
tail -f ~/mimicbot/logs/lerobot_control.log               # teleop/포즈
tail -f ~/mimicbot/logs/lerobot_autonomous.log            # 정책 실행
```
앱 PC에서: `curl http://<로봇 PC IP>:8000/health` 로 연결 확인.

---

## E. 트러블슈팅 (실제로 겪은 것들)

| 증상 | 원인 · 해결 |
|---|---|
| 깨우기 후 :8100 "연결 못함" | 제어 서버가 시작 중 크래시. `lerobot_control.log` 확인. 모터 순간 미검출 글리치는 재시도로 넘어감. 계속이면 **베이스 모터 케이블** 확인. |
| `Missing motor IDs: 11` | 팔로워 모터(11=베이스)가 버스에서 안 잡힘 — 케이블/전원. |
| 정책이 바로 종료 `FileExistsError ... eval_omx_...` | 데이터셋 폴더가 이미 있음. 제어 서버가 실행 전 자동 삭제하도록 돼 있음(수동 시 `rm -rf ~/.cache/huggingface/lerobot/<repo_id>`). |
| 카메라 `failed to set ... width=640 (actual 1280)` | lerobot 기본 backend=ANY 문제. **카메라 config에 `backend: V4L2`** 넣기(이미 반영). |
| `cuda available: False` | GPU/드라이버 없음. 드라이버·CUDA 설치, 또는 임시 `--policy.device=cpu`(느림). |
| 포트 점유로 정책/브링업 실패 | 제어 서버와 lerobot-record가 같은 팔로워 포트 다툼. 앱 자율 경로는 제어 서버가 알아서 놓고→실행→다시 잡음. 수동 실행 시엔 제어 서버부터 끌 것. |
| 자율 화면에 로봇 영상 안 뜸 | mediamtx 송출 여부·주소(`maxiCameraUrl`)·방화벽(8889)·혼합콘텐츠(HTTP 서빙) 확인. |
| 손 모방 위 칸 비어 있음 | 맥시는 "모방 시작" 눌러야 웹캠을 잡고 스트림이 나옴. `--camera-index` 확인. |

---

## F. 로봇 PC마다 반드시 바꿔야 하는 것 (요약)

| 항목 | 위치 |
|---|---|
| follower/leader 포트 | udev 심링크(`/dev/omx_follower`,`/dev/omx_leader`) 또는 `app_bridge_config.yaml`의 제어서버 인자 |
| 정책 카메라 번호 | `config/omx_autonomous.json` 의 `cameras`(video2/4), `backend: V4L2` 유지 |
| 손 모방 웹캠 번호 | `app_bridge_config.yaml` 제어서버 `--camera-index` |
| 정책 경로 | `config/omx_autonomous.json` `default_policy_path` / 앱 명령 `--policy.path` |
| device | 정책 명령 `--policy.device`(cuda) |
| 캘리브레이션 | 그 로봇으로 재캘리브레이션 |
| 포즈 값 | `config/omx_poses.json` — `/teach` 로 실측 |
| maxiHost / maxiCameraUrl | 앱 `app_config.dart`(또는 --dart-define) |

> config(yaml/json) 바꾼 뒤에는 브리지 패키지 **재빌드**(`colcon build --packages-select open_manipulator_app_bridge`) 후 브리지를 다시 띄운다.

---

### 관련 파일
- 브리지 실행: [scripts/start_mimicbot.sh](../scripts/start_mimicbot.sh)
- 맥시 깨우기/재우기: [scripts/wake_maxi.sh](../scripts/wake_maxi.sh), [scripts/sleep_maxi.sh](../scripts/sleep_maxi.sh)
- wake 프로파일: [ros2_ws/.../config/app_bridge_config.yaml](../ros2_ws/src/open_manipulator_app_bridge/config/app_bridge_config.yaml)
- lerobot 제어 서버: [scripts/lerobot/omx_control_server.py](../scripts/lerobot/omx_control_server.py)
- 포즈/자율 설정: [config/omx_poses.json](../config/omx_poses.json), [config/omx_autonomous.json](../config/omx_autonomous.json)
- 앱 주소 설정: [flutter_app/lib/config/app_config.dart](../flutter_app/lib/config/app_config.dart)
