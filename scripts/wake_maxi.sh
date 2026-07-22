#!/bin/bash
#
# 맥시(OMX-AI 실물) 깨우기.
# 미키와 맥시는 동시에 뜨면 안 되므로, 먼저 미키(가상)를 재우고 → 맥시를 깨웁니다.
# 앱 홈에서 맥시를 고르고 "깨우기"를 누르는 것과 같은 동작(target=omxAi)입니다.
# 무엇을 띄우는지는 브리지의 omxAi 프로파일(app_bridge_config.yaml)이 정합니다.
#
# 사용:
#   ./scripts/wake_maxi.sh                  # 기본: 맥시 IP(로컬 테스트)
#   ./scripts/wake_maxi.sh 192.168.0.30     # 로봇 PC의 브리지 IP
#   MAXI_HOST=... ./scripts/wake_maxi.sh
#   SKIP_CONFIRM=1 ./scripts/wake_maxi.sh   # 안전 확인 없이 바로
#
# 재우기는:  ./scripts/sleep_maxi.sh

set -euo pipefail

HOST="${1:-${MAXI_HOST:-192.168.129.109}}"
BASE="http://${HOST}:${MIMIC_PORT:-8000}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=_mimic_wake_lib.sh
source "${SCRIPT_DIR}/_mimic_wake_lib.sh"

echo "=== 맥시(OMX-AI 실물) 깨우기 ===  대상 브리지: ${BASE}"

# 1) 먼저 미키(가상)를 재운다. 상대 브리지가 없거나 실패해도 계속 진행(best-effort).
echo "→ 먼저 미키(가상) 정리..."
SKIP_CONFIRM=1 "${SCRIPT_DIR}/sleep_micky.sh" \
    || echo "  (미키 정리 건너뜀 — 브리지 없음/실패, 계속 진행)"

# 2) 맥시 브리지 확인.
if ! mimic_health "$BASE"; then
    echo "❌ 맥시 브리지에 연결할 수 없습니다: ${BASE}"
    echo "   • 이 컴의 브리지라면 먼저:  ./scripts/start_mimicbot.sh"
    echo "   • 다른 PC라면 그 PC에서 브리지가 떴는지, IP·포트·방화벽(8000)을 확인하세요."
    exit 1
fi

# 3) 실물이 움직이므로 안전 확인 (SKIP_CONFIRM=1로 생략).
echo "⚠️  깨우면 실물 서보에 토크가 걸리고 명령/모방이 실제 팔로 나갑니다."
echo "   팔 주변에 사람·물건이 없는지 확인하세요."
if [ -t 0 ] && [ "${SKIP_CONFIRM:-}" != "1" ]; then
    read -r -p "계속하려면 Enter, 취소하려면 Ctrl-C ... " _
fi

# 4) 맥시 깨우기.
echo "→ 맥시 깨우기 (target=omxAi) ..."
RESP="$(mimic_wake "$BASE" omxAi)" || { echo "❌ 깨우기 요청 실패"; exit 1; }
if mimic_print "$RESP"; then status=0; else status=$?; fi

echo
echo "로그 실시간:  tail -f ~/mimicbot/logs/*.log"
echo "상태 확인:    curl -s ${BASE}/robot/wake/status"
echo "재우기:       ./scripts/sleep_maxi.sh"
exit "$status"
