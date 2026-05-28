#!/usr/bin/env bash
# tests/test-allow-deny-no-overlap.sh — allow ∩ deny 충돌 검증 (§7 C5 PASS 조건).
# yaml 임시 사본 격리 — 운영 yaml 변경 없이 검사 (V2 정합).
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# 1. 정상 yaml — 충돌 0건 PASS
cp "$ROOT/config/lead-auto-allow.yaml" "$TMPDIR/normal.yaml"
bash "$ROOT/bin/danger-check.sh" --check-allow-yaml "$TMPDIR/normal.yaml"
assert_success "$?" "정상 yaml PASS"

# 2. 위험 패턴 주입 — 충돌 발견 FAIL 기대
cp "$ROOT/config/lead-auto-allow.yaml" "$TMPDIR/conflict.yaml"
cat >> "$TMPDIR/conflict.yaml" <<'EOF'

malicious:
  - "Bash(sudo:*)"
  - "Bash(rm:*)"
EOF
bash "$ROOT/bin/danger-check.sh" --check-allow-yaml "$TMPDIR/conflict.yaml" 2>/dev/null
rc=$?
assert_eq "1" "$rc" "위험 패턴 주입 yaml → 충돌 발견 (exit 1)"

# 3. yaml 미존재 — abort exit 1
bash "$ROOT/bin/danger-check.sh" --check-allow-yaml "$TMPDIR/notexist.yaml" 2>/dev/null
rc=$?
assert_eq "1" "$rc" "yaml 미존재 → abort"

# 4. confirm_allow_yaml 함수 동작 — accepted 시 learned 카테고리 누적
# HARNESS_ROOT 를 TMPDIR 로 격리해 운영 yaml 보호.
mkdir -p "$TMPDIR/config"
cp "$ROOT/config/lead-auto-allow.yaml" "$TMPDIR/config/lead-auto-allow.yaml"
cp "$ROOT/config/lead-auto-allow-stats.yaml" "$TMPDIR/config/lead-auto-allow-stats.yaml"
cp "$ROOT/config/lead-auto-allow-blocklist.yaml" "$TMPDIR/config/lead-auto-allow-blocklist.yaml"

HARNESS_ROOT="$TMPDIR" bash -c '
  source "'"$ROOT"'/bin/lib.sh"
  # source 직후 HARNESS_ROOT 가 lib.sh 에서 재계산되므로 override.
  HARNESS_ROOT="'"$TMPDIR"'" confirm_allow_yaml "Bash(testpattern:*)" "accepted"
  grep -q "Bash(testpattern:\*)" "'"$TMPDIR"'/config/lead-auto-allow.yaml"
'
assert_success "$?" "confirm_allow_yaml accepted → learned 카테고리 누적"

test_summary
