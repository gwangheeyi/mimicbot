# Gazebo 가상 대상 실행 순서

동작 명령(메뉴 1)과 실시간 모방(메뉴 2)을 쓰기 위한 준비입니다.

## 동작 명령 메뉴

앱의 **동작 명령** 메뉴에서 버튼을 누르면 Gazebo 안의 OMX-AI가 움직이고, 그 모습이
앱 위쪽 화면에 영상으로 보입니다. 그러려면 ROS2 쪽에서 아래 네 가지를 켜 두어야 합니다.

## 전체 경로

```
[버튼] ─HTTP POST :8000/robot/command─► app_bridge_server
        ─/open_manipulator/motion_command─► motion_server
        ─/arm_controller/joint_trajectory─► Gazebo

[영상] Gazebo 카메라 ─ros_gz_bridge─► /front_camera/image
        ─web_video_server :8080─► 앱 화면
```

## 실행 (터미널 4개)

각 터미널마다 먼저:

```bash
cd ~/mimicbot/ros2_ws
source /opt/ros/jazzy/setup.bash
source install/setup.bash
```

**1. Gazebo**

```bash
ros2 launch open_manipulator_bringup open_manipulator_x_gazebo.launch.py
```

**2. 동작 서버** — 명령을 받아 로봇팔을 움직입니다.

```bash
ros2 run open_manipulator_app_control motion_server
```

**3. 브리지 서버** — 앱의 HTTP 요청을 ROS2 토픽으로 바꿉니다.

```bash
ros2 run open_manipulator_app_bridge app_bridge_server
```

**4. 영상 서버** — Gazebo 카메라를 MJPEG으로 내보냅니다.

```bash
ros2 run ros_gz_bridge parameter_bridge \
  /front_camera/image@sensor_msgs/msg/Image@gz.msgs.Image \
  /front_camera/camera_info@sensor_msgs/msg/CameraInfo@gz.msgs.CameraInfo &
ros2 run web_video_server
```

`web_video_server`가 없으면 `sudo apt install ros-jazzy-web-video-server`.

## 확인

- 브리지: `curl http://127.0.0.1:8000/health` → `{"status":"ok",...}`
- 영상: 브라우저에서 `http://127.0.0.1:8080` → 토픽 목록에 `/front_camera/image`

## 앱에서 보낼 수 있는 동작

`lib/config/robot_commands.dart`의 `RobotCommands.gestures`가 프리셋 버튼 목록입니다.
ROS2 쪽 `robot_config.py`의 `MOTION_POSITIONS`와 짝이 맞아야 합니다.

| 버튼 | 명령어 |
|---|---|
| 준비 | `ready` |
| 홈 | `home` |
| 왼쪽 | `left` |
| 오른쪽 | `right` |
| 업 | `up` |

## 다른 기기에서 실행할 때

`lib/config/app_config.dart`의 `robotServerHost`를 ROS2가 도는 머신 주소로 바꿉니다.

| 실행 환경 | 값 |
|---|---|
| 같은 PC (Web·Windows·Linux) | `127.0.0.1` (기본값) |
| 안드로이드 에뮬레이터 | `10.0.2.2` |
| 안드로이드 실기기 | ROS 머신의 LAN IP (예: `192.168.0.10`) |

Web에서 다른 머신에 붙일 때는 브라우저 CORS 때문에 브리지 서버에 CORS 허용을
추가해야 할 수 있습니다(영상은 `<img>`라 영향 없음).

---

# 실시간 모방 메뉴 (손으로 로봇 움직이기)

웹캠에 손을 비추면 로봇이 따라 합니다.

| 손 | 로봇 |
|---|---|
| 엄지·검지를 벌리면 | 그리퍼가 벌어짐 (벌린 만큼 비례) |
| 엄지·검지를 붙이면 | 그리퍼가 닫힘 |
| 손목을 좌우로 | joint1 회전 |
| 손목을 위아래로 | joint2 회전 |

그리퍼는 열림/닫힘 두 단계가 아니라 손가락을 벌린 만큼 따라갑니다.
손을 카메라 정면으로 향한 채 움직이면 인식이 가장 잘 됩니다.

## 인식은 앱이 아니라 ROS2 노드가 합니다

`hand_mimic_node`가 웹캠을 직접 열어 mediapipe로 손을 찾고, 팔과 그리퍼를 움직이면서
손 관절을 그려 넣은 영상을 `/hand_camera/image`로 내보냅니다. 앱은 그 영상을 받아
보여주고 시작/정지만 시킵니다.

**웹캠은 한 번에 한 프로그램만 열 수 있습니다.** 앱이나 다른 프로그램(Zoom 등)이
카메라를 잡고 있으면 노드가 열지 못합니다.

## 추가 실행 (앞의 5개에 더해서)

```bash
ros2 run open_manipulator_app_control hand_mimic_node
```

웹캠이 여러 대면 장치 번호를 지정합니다 (`/dev/video0`이 0번):

```bash
ros2 run open_manipulator_app_control hand_mimic_node --ros-args -p camera_index:=1
```

## 모델 파일

mediapipe 손 인식 모델(`hand_landmarker.task`, 7.8MB)이 필요합니다. 용량이 커서
git에 넣지 않았습니다. "손 인식 모델을 찾을 수 없습니다"가 뜨면:

```bash
./scripts/download_hand_model.sh
cd ros2_ws && colcon build --symlink-install --packages-select open_manipulator_app_control
```

## 확인

```bash
ros2 topic hz /hand_camera/image     # 14Hz 안팎이면 정상
ros2 topic list | grep mimic_enable  # 시작/정지 통로
```

브라우저에서 `http://127.0.0.1:8080/stream?topic=/hand_camera/image` 로 손 관절이
그려진 영상을 직접 볼 수도 있습니다.

## 동작이 어색할 때

`ros2_ws/src/open_manipulator_app_control/open_manipulator_app_control/hand_mimic_config.py`
의 숫자만 고치면 됩니다. 자주 손대는 값들입니다.

| 값 | 뜻 |
|---|---|
| `PINCH_CLOSED_RATIO` / `OPEN` | 손가락을 얼마나 붙여야/벌려야 끝으로 볼지 |
| `JOINT1_AT_LEFT` / `AT_RIGHT` | 좌우로 움직이는 폭 |
| `JOINT2_AT_TOP` / `AT_BOTTOM` | 위아래로 움직이는 폭 |
| `SMOOTHING_FACTOR` | 작을수록 부드럽고 반응이 늦음 |

`--symlink-install`로 빌드해 두었으므로 이 파일은 고치고 노드만 다시 실행하면 됩니다.
