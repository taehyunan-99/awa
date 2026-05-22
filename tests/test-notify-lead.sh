#!/usr/bin/env bash
# notify_lead 의 카운트 + lead pane 식별 (DRY_RUN).
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
export HARNESS_PROJECT="$(mktemp -d)"
( cd "$HARNESS_PROJECT" && git init -q )
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh"
# shellcheck disable=SC1091
source "$ROOT/bin/notify-lead.sh"

STATE="$HARNESS_PROJECT/.agent-harness/state"
mkdir -p "$STATE/pending-asks" "$STATE/incidents" "$STATE/removal-requests"
printf 'LEAD %%9 sid-lead /tmp/lead.jsonl lead\n' > "$STATE/workers.list"
printf 'arch %%5 sid-a /tmp/a.jsonl researcher\n' >> "$STATE/workers.list"

echo "[N1] 항목 0 → 빈 status"
out="$(NOTIFY_DRY_RUN=1 notify_lead)"
assert_contains "$out" "status=[]" "N1 빈 status"

echo "[N2] 항목 추가 → 카운트 반영"
echo '{}' > "$STATE/pending-asks/u1.json"
echo '{}' > "$STATE/incidents/i1.json"
out="$(NOTIFY_DRY_RUN=1 notify_lead)"
assert_contains "$out" "1 ask" "N2 1 ask"
assert_contains "$out" "1 inc" "N2 1 inc"

echo "[N3] lead pane 식별 (workers.list entry_role==lead → %9)"
out="$(NOTIFY_DRY_RUN=1 notify_lead)"
assert_contains "$out" "%9" "N3 lead pane %9"

test_summary
