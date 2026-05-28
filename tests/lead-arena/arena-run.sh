#!/usr/bin/env bash
# 사용: bash arena-run.sh A plan-complex
# 후보 lead 구조로 실 claude lead 를 띄우고 자극(확정 plan)을 줘 산출물 수집.
# claude 토큰 소모 — 사용자 ! 로 실행.
set -uo pipefail
cd "$(dirname "$0")"
ARENA="$(pwd)"; ROOT="$(cd ../.. && pwd)"
cand="${1:?candidate A|B|C|D}"; stim="${2:?stimulus name}"
candf="$ARENA/candidates/$cand.md"
stimf="$ARENA/stimuli/$stim.md"
[ -f "$candf" ] || { echo "없는 후보: $candf" >&2; exit 1; }
[ -f "$stimf" ] || { echo "없는 자극: $stimf" >&2; exit 1; }

# 후보 lead 로 fixture prompts 트리 구성 (원본 안 건드림).
FIX="$(mktemp -d)"; cp -r "$ROOT/prompts" "$FIX/prompts"
cp "$candf" "$FIX/prompts/roles/01-orchestration/lead.md"

# 격리 PROJECT_ROOT + profile (dev·tester 워커 + reviewer).
PROJ="$(mktemp -d)"; ( cd "$PROJ" && git init -q )
SESSION="arena-$cand-$stim-$$"
PROF="$PROJ/profile.sh"
cat > "$PROF" <<EOF
LAYOUT=tiled
WORKERS=("dev:dev" "tester:tester")
REVIEWERS=("rev:reviewer-quality")
LEAD_MODEL=opus
EOF

export SESSION_OVERRIDE="$SESSION" HARNESS_PROJECT="$PROJ" PROMPTS_DIR="$FIX/prompts"
# 자극을 확정 plan 으로 주입 (--plan 인자 — awa-up plan 합본 경로).
echo "=== arena run: 후보=$cand 자극=$stim 세션=$SESSION PROJ=$PROJ ==="
echo "출력 디렉터리: $PROJ/.agent-harness/"
bash "$ROOT/bin/awa-up.sh" "$PROF" --plan "$stimf"
echo "$cand $stim $SESSION $PROJ" > "$ARENA/.last-run"
echo "lead 가 분해·배정·승인게이트를 처리하도록 두고, 안정되면 다음을 실행해 산출물 수집:"
echo "  bash $ARENA/arena-score.sh"
