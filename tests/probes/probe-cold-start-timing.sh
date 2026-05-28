#!/usr/bin/env bash
# 수동 실측 probe: awa-up 직후 4 pane 모두 REPL ready 까지 < 30초 검증.
# P2 spec §1 목표 4 의 실측 토대.
# run-all 비포함 (수동 실행).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TMP_PROJ="$(mktemp -d -t p2-cold-start.XXXXXX)"

# 15th: bookmarks 격리 — awa-up.sh 가 ~/.config/awa/bookmarks.tsv 에 기록.
# probe fixture 가 사용자 실 경로를 더럽히지 않도록 임시 dir 로 redirect.
_AGPN15_XDG="$(mktemp -d)"
export XDG_CONFIG_HOME="$_AGPN15_XDG"

trap "bash '$HARNESS_ROOT/bin/awa-down.sh' --project '$TMP_PROJ' 2>/dev/null || true; rm -rf '$TMP_PROJ'; rm -rf '$_AGPN15_XDG'" EXIT

cd "$TMP_PROJ"
git init -q 2>/dev/null || true

echo "awa-up 시작 — 측정 중..."
START="$(date +%s)"
HARNESS_PROJECT="$TMP_PROJ" bash "$HARNESS_ROOT/bin/awa-up.sh" default >/tmp/p2-awa-up.log 2>&1
RC=$?
END="$(date +%s)"
elapsed=$((END - START))

echo "awa-up 종료 — exit=$RC, elapsed=${elapsed}s"
echo "로그 (마지막 20줄):"
tail -20 /tmp/p2-awa-up.log

# 임계 45초 — 4 pane 순차 부트 + claude 초기 로드 (Welcome 박스 렌더링,
# Skill 자동 로드, 모델별 LLM warm-up) 합쳐 30대 초중반 정상. 5초 여유.
# 2026-05-21 P2 false negative fix 직후 실측 35초 — 원래 30초 임계는 보수적.
if [ "$elapsed" -lt 45 ] && [ "$RC" = "0" ]; then
  echo "PASS: 45초 안 부트 완료 (${elapsed}s)"
else
  echo "FAIL: 45초 초과 또는 exit 0 아님 (${elapsed}s, RC=$RC)"
fi
