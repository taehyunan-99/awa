#!/usr/bin/env bash
# probe: --plan → .boot/plan.md 합본 부수효과 (토큰0, AGENT_CMD=cat).
# 사용자가 ! 로 실행. claude 미기동.
# 위치: tests/probes/ → repo root 는 두 단계 위.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export AGENT_CMD="cat"

PROJ="$(mktemp -d)"; ( cd "$PROJ" && git init -q )
printf '# PRD\nproduct 요구사항\n' > "$PROJ/PRD.md"
printf '# ARCH\n아키텍처 결정\n' > "$PROJ/ARCH.md"
SES="$(HARNESS_PROJECT="$PROJ" bash -c "source $ROOT/bin/lib.sh; resolve_session")"

echo "=== team-up --plan PRD.md --plan ARCH.md (cat 더미) ==="
bash "$ROOT/bin/team-up.sh" --project "$PROJ" --plan "$PROJ/PRD.md" --plan "$PROJ/ARCH.md" default >/dev/null 2>&1
sleep 0.8

echo "=== 산출 .boot/plan.md ==="
cat "$PROJ/.agent-harness/.boot/plan.md" 2>/dev/null || echo "(plan.md 없음 — FAIL)"

echo "=== team-down + cleanup ==="
bash "$ROOT/bin/team-down.sh" --project "$PROJ" >/dev/null 2>&1
tmux kill-session -t "$SES" 2>/dev/null || true
rm -rf "$PROJ"
echo "probe 완료."
