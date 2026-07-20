#!/usr/bin/env bash
#
# 손 인식 모델(hand_landmarker.task)을 내려받습니다.
#
# 7.8MB 바이너리라 git에 넣지 않습니다. 저장소를 새로 받았거나
# hand_mimic_node가 "손 인식 모델을 찾을 수 없습니다"라고 하면 이 스크립트를
# 실행한 뒤 open_manipulator_app_control 패키지를 다시 빌드하세요.

set -euo pipefail

MODEL_URL="https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task"
MODEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ros2_ws/src/open_manipulator_app_control/models"
MODEL_PATH="${MODEL_DIR}/hand_landmarker.task"

mkdir -p "${MODEL_DIR}"

if [ -f "${MODEL_PATH}" ]; then
  echo "이미 있습니다: ${MODEL_PATH}"
  exit 0
fi

echo "내려받는 중: ${MODEL_URL}"
curl -fsSL --retry 3 -o "${MODEL_PATH}" "${MODEL_URL}"

echo "완료: ${MODEL_PATH} ($(du -h "${MODEL_PATH}" | cut -f1))"
echo
echo "이제 다시 빌드하세요:"
echo "  cd ros2_ws && colcon build --symlink-install --packages-select open_manipulator_app_control"
