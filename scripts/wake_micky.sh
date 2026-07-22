#!/bin/bash
#
# 미키(Gazebo 가상) 깨우기.
# 미키와 맥시는 동시에 뜨면 안 되므로, 먼저 맥시(실물)를 재우고 → 미키를 깨웁니다.
# 앱 홈에서 미키를 고르고 "깨우기"를 누르는 것과 같은 동작(target=gazeboLeRobot)입니다.
#
# 사용:
#   ./scripts/wake_micky.sh                  # 기본: 127.0.0.1 (내 컴)
#   ./scripts/wake_micky.sh 192.168.0.10     # 미키 브리지가 다른 컴일 때
#   MICKY_HOST=... ./scripts/wake_micky.sh
#
# 재우기는:  ./scripts/sleep_micky.sh

set -euo pipefail

HOST="${1:-${MICKY_HOST:-127.0.0.1}}"
BASE="http://${HOST}:${MIMIC_PORT:-8000}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=_mimic_wake_lib.sh
source "${SCRIPT_DIR}/_mimic_wake_lib.sh"

echo "=== 미키(Gazebo 가상) 깨우기 ===  대상 브리지: ${BASE}"

# 1) 먼저 맥시(실물)를 재운다. 상대 브리지가 없거나 실패해도 계속 진행(best-effort).
echo "→ 먼저 맥시(실물) 정리..."
SKIP_CONFIRM=1 "${SCRIPT_DIR}/sleep_maxi.sh" \
    || echo "  (맥시 정리 건너뜀 — 브리지 없음/실패, 계속 진행)"

# 2) 미키 브리지 확인.
if ! mimic_health "$BASE"; then
    echo "❌ 미키 브리지에 연결할 수 없습니다: ${BASE}"
    echo "   이 컴이라면 먼저:  ./scripts/start_mimicbot.sh"
    exit 1
fi

# 3) 미키 깨우기.
echo "→ 미키 깨우기 (target=gazeboLeRobot) ..."
RESP="$(mimic_wake "$BASE" gazeboLeRobot)" || { echo "❌ 깨우기 요청 실패"; exit 1; }
if mimic_print "$RESP"; then status=0; else status=$?; fi

echo
echo "로그 실시간:  tail -f ~/mimicbot/logs/*.log"
echo "상태 확인:    curl -s ${BASE}/robot/wake/status"
echo "재우기:       ./scripts/sleep_micky.sh"
exit "$status"
