#!/bin/bash
#
# 맥시(OMX-AI 실물) 재우기 — 브리지의 /robot/sleep 를 target=omxAi 로 호출해
# 맥시 프로파일(실물 follower 브링업·모션·손모방)만 종료합니다.
#
# 사용:
#   ./scripts/sleep_maxi.sh                  # 기본: 맥시 IP(로컬 테스트)
#   ./scripts/sleep_maxi.sh 192.168.0.30     # 로봇 PC의 브리지 IP
#   MAXI_HOST=... ./scripts/sleep_maxi.sh
#   SKIP_CONFIRM=1 ./scripts/sleep_maxi.sh   # 안전 확인 없이 바로

set -euo pipefail

HOST="${1:-${MAXI_HOST:-192.168.129.109}}"
BASE="http://${HOST}:${MIMIC_PORT:-8000}"

# shellcheck source=_mimic_wake_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_mimic_wake_lib.sh"

echo "=== 맥시(OMX-AI 실물) 재우기 ===  대상 브리지: ${BASE}"

if ! mimic_health "$BASE"; then
    echo "❌ 브리지에 연결할 수 없습니다: ${BASE}"
    echo "   • 브리지가 이미 내려갔다면 남은 프로세스는 로봇 PC에서 직접 정리:"
    echo "     pkill -9 -f omx_f_follower_ai ; pkill -9 -f motion_server ; pkill -9 -f hand_mimic_node"
    exit 1
fi

# 재우면 브링업이 종료되어 서보 토크가 풀립니다. 팔이 들려 있으면 받쳐 주세요.
echo "⚠️  재우면 실물 서보 토크가 풀립니다. 팔이 들려 있으면 받쳐 주세요."
if [ -t 0 ] && [ "${SKIP_CONFIRM:-}" != "1" ]; then
    read -r -p "계속하려면 Enter, 취소하려면 Ctrl-C ... " _
fi

RESP="$(mimic_sleep "$BASE" omxAi)" || { echo "❌ 재우기 요청 실패"; exit 1; }
mimic_print "$RESP" || true
