#!/bin/bash
#
# 브리지 서버(:8000)만 띄웁니다. 나머지 브링업·서비스(Gazebo, 카메라 브리지,
# 모션 서버, 손 모방 노드, 웹 영상 서버)는 앱 메인 화면의 "Micky 깨우기"
# 버튼이 브리지 서버를 통해 한꺼번에 백그라운드로 시작합니다.
#
# 즉 순서는: 이 스크립트로 브리지 서버 실행 → 앱 실행 → "Micky 깨우기" 누르기.

set -e

PROJECT_DIR="$HOME/mimicbot"
ROS_WS="$PROJECT_DIR/ros2_ws"
LOG_DIR="$PROJECT_DIR/logs"

mkdir -p "$LOG_DIR"

echo "=== mimicbot 브리지 서버 시작 ==="

# ROS2 환경 설정
source /opt/ros/jazzy/setup.bash

if [ -f "$ROS_WS/install/setup.bash" ]; then
    source "$ROS_WS/install/setup.bash"
else
    echo "ROS2 workspace가 빌드되지 않았습니다. 먼저 colcon build 하세요."
    exit 1
fi

# Ollama 서버(qwen3 대화·AI 춤에 필요) 확인 후 실행.
if ! pgrep -f "ollama serve" > /dev/null; then
    echo "Ollama 서버 실행"
    nohup ollama serve > "$LOG_DIR/ollama.log" 2>&1 &
    sleep 2
else
    echo "Ollama 서버가 이미 실행 중입니다."
fi

# 이미 떠 있으면 다시 띄우지 않습니다.
if pgrep -f "app_bridge_server" > /dev/null; then
    echo "브리지 서버가 이미 실행 중입니다."
    exit 0
fi

# 브리지 서버 실행. "Micky 깨우기" 버튼이 이 서버로 요청을 보내
# 나머지 서비스를 백그라운드로 띄웁니다.
echo "브리지 서버 실행 (:8000)"
nohup ros2 run open_manipulator_app_bridge app_bridge_server \
    > "$LOG_DIR/app_bridge_server.log" 2>&1 &

echo "=== 브리지 서버 실행 완료 ==="
echo "이제 앱을 켜고 메인 화면에서 'Micky 깨우기'를 누르세요."
