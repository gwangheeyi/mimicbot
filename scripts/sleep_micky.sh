#!/bin/bash
#
# 미키(Gazebo 가상) 재우기 — 브리지의 /robot/sleep 를 target=gazeboLeRobot 로
# 호출해 미키 프로파일(Gazebo·카메라 브리지·모션·손모방·web_video)만 종료합니다.
# 가상이라 하드웨어 위험은 없습니다.
#
# 사용:
#   ./scripts/sleep_micky.sh                 # 기본: 127.0.0.1 (내 컴)
#   ./scripts/sleep_micky.sh 192.168.0.10    # 미키 브리지가 다른 컴일 때
#   MICKY_HOST=... ./scripts/sleep_micky.sh

set -euo pipefail

HOST="${1:-${MICKY_HOST:-127.0.0.1}}"
BASE="http://${HOST}:${MIMIC_PORT:-8000}"

# shellcheck source=_mimic_wake_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_mimic_wake_lib.sh"

echo "=== 미키(Gazebo 가상) 재우기 ===  대상 브리지: ${BASE}"

if ! mimic_health "$BASE"; then
    echo "❌ 브리지에 연결할 수 없습니다: ${BASE} (이미 꺼져 있을 수 있음)"
    exit 1
fi

RESP="$(mimic_sleep "$BASE" gazeboLeRobot)" || { echo "❌ 재우기 요청 실패"; exit 1; }
mimic_print "$RESP" || true
