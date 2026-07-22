#!/bin/bash
#
# 미키/맥시 깨우기·재우기 스크립트가 공통으로 쓰는 함수 모음입니다.
# 단독 실행용이 아니라 다른 스크립트에서 source 해서 씁니다.
#
# 브리지의 /robot/wake · /robot/sleep 는 target(대상 enum 이름)으로
# 프로파일(gazeboLeRobot=미키 / omxAi=맥시)을 골라 띄우거나 끕니다.

MIMIC_PORT="${MIMIC_PORT:-8000}"

# 브리지 헬스체크. $1=BASE(http://host:port). 살아 있으면 0.
mimic_health() {
    curl -sf -m 3 "$1/health" >/dev/null 2>&1
}

# 깨우기. $1=BASE, $2=target. 서버 응답(JSON)을 stdout으로. 실패 시 1.
mimic_wake() {
    curl -sf -m 60 -X POST "$1/robot/wake" \
        -H 'Content-Type: application/json' \
        -d "{\"target\":\"$2\"}"
}

# 재우기. $1=BASE, $2=target. 서버 응답(JSON)을 stdout으로. 실패 시 1.
mimic_sleep() {
    curl -sf -m 30 -X POST "$1/robot/sleep" \
        -H 'Content-Type: application/json' \
        -d "{\"target\":\"$2\"}"
}

# 서버 응답(JSON)을 서비스별로 보기 좋게 출력. $1=JSON. (python3는 ROS 환경에 항상 있음)
mimic_print() {
    python3 - "$1" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
print(data.get("message", ""))
mark = {"started": "✓", "already_running": "·", "error": "✗",
        "stopped": "✓", "running": "✓", "exited": "✗"}
for s in data.get("services", []):
    line = f"  {mark.get(s.get('status'), '?')} {s.get('label', s.get('name'))} [{s.get('status')}]"
    if s.get("pid"):
        line += f" pid={s['pid']}"
    if s.get("message"):
        line += f" — {s['message']}"
    print(line)
    if s.get("log"):
        print(f"      log: {s['log']}")
sys.exit(0 if data.get("success", True) else 2)
PY
}
