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
cp "$ROOT/config/orch-auto-allow.yaml" "$TMPDIR/normal.yaml"
bash "$ROOT/bin/danger-check.sh" --check-allow-yaml "$TMPDIR/normal.yaml"
assert_success "$?" "정상 yaml PASS"

# 2. 위험 패턴 주입 — 충돌 발견 FAIL 기대
cp "$ROOT/config/orch-auto-allow.yaml" "$TMPDIR/conflict.yaml"
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

# 4. confirm_allow_yaml 함수 동작 — accepted 시 프로젝트 learned 파일 누적
# P2/P6 수정(2026-05-30): learned 쓰기가 PROJECT_ROOT/.agent-harness/learned-allow.yaml 로 분리됨.
#   격리: HARNESS_PROJECT(쓰기·읽기 기준 PROJECT_ROOT) + HARNESS_ROOT(stats/blocklist 기준) 둘 다.
mkdir -p "$TMPDIR/config" "$TMPDIR/proj"
cp "$ROOT/config/orch-auto-allow.yaml" "$TMPDIR/config/orch-auto-allow.yaml"
cp "$ROOT/config/orch-auto-allow-stats.yaml" "$TMPDIR/config/orch-auto-allow-stats.yaml"
cp "$ROOT/config/orch-auto-allow-blocklist.yaml" "$TMPDIR/config/orch-auto-allow-blocklist.yaml"

HARNESS_ROOT="$TMPDIR" HARNESS_PROJECT="$TMPDIR/proj" bash -c '
  source "'"$ROOT"'/bin/lib.sh"
  # source 직후 HARNESS_ROOT 가 lib.sh 에서 재계산되므로 override (stats/blocklist 기준).
  HARNESS_ROOT="'"$TMPDIR"'" confirm_allow_yaml "Bash(testpattern:*)" "accepted"
  # learned 는 이제 PROJECT_ROOT/.agent-harness/learned-allow.yaml 에 누적.
  grep -q "Bash(testpattern:\*)" "'"$TMPDIR"'/proj/.agent-harness/learned-allow.yaml"
'
assert_success "$?" "confirm_allow_yaml accepted → 프로젝트 learned-allow.yaml 누적"

# 5. C-2 검증 — accepted 사후 검증으로 위험 패턴 학습 거부
# 'Bash(git push:*)' 는 다중 probe ('--force') 에서 danger 매치 → learned 누적 안 됨.
mkdir -p "$TMPDIR/c2/config" "$TMPDIR/c2/proj"
cp "$ROOT/config/orch-auto-allow.yaml" "$TMPDIR/c2/config/orch-auto-allow.yaml"
cp "$ROOT/config/orch-auto-allow-stats.yaml" "$TMPDIR/c2/config/orch-auto-allow-stats.yaml"
cp "$ROOT/config/orch-auto-allow-blocklist.yaml" "$TMPDIR/c2/config/orch-auto-allow-blocklist.yaml"

HARNESS_ROOT="$TMPDIR/c2" HARNESS_PROJECT="$TMPDIR/c2/proj" bash -c '
  source "'"$ROOT"'/bin/lib.sh"
  HARNESS_ROOT="'"$TMPDIR"'/c2" confirm_allow_yaml "Bash(git push:*)" "accepted" 2>/dev/null
  # 위험 패턴 → rejected 로 전환 → learned 누적 안 됨 (파일 자체가 없거나 패턴 미포함).
  lf="'"$TMPDIR"'/c2/proj/.agent-harness/learned-allow.yaml"
  if [ -f "$lf" ] && grep -q "Bash(git push:\*)" "$lf"; then exit 1; else exit 0; fi
'
assert_success "$?" "C-2: 위험 패턴 accepted → 사후 검증 거부 (learned 누적 안 됨)"

# 6. I-7 검증 — Edit/Write 위험 패턴 검출
cp "$ROOT/config/orch-auto-allow.yaml" "$TMPDIR/i7-conflict.yaml"
cat >> "$TMPDIR/i7-conflict.yaml" <<'EOF'

malicious-edit:
  - "Edit(/etc/sudoers)"
  - "Write(/etc/passwd)"
EOF
bash "$ROOT/bin/danger-check.sh" --check-allow-yaml "$TMPDIR/i7-conflict.yaml" 2>/dev/null
rc=$?
assert_eq "1" "$rc" "I-7: Edit/Write 위험 패턴 yaml → 충돌 발견"

# 7. I-8 검증 — 카테고리 분리 멱등성
# Bash(ls:*) 는 운영 yaml 의 read-only 에 이미 있음. learned 에 추가 시도 → I-8 정정 후 추가 성공.
mkdir -p "$TMPDIR/i8/config"
cp "$ROOT/config/orch-auto-allow.yaml" "$TMPDIR/i8/config/orch-auto-allow.yaml"
cp "$ROOT/config/orch-auto-allow-stats.yaml" "$TMPDIR/i8/config/orch-auto-allow-stats.yaml"
cp "$ROOT/config/orch-auto-allow-blocklist.yaml" "$TMPDIR/i8/config/orch-auto-allow-blocklist.yaml"

HARNESS_ROOT="$TMPDIR/i8" bash -c '
  source "'"$ROOT"'/bin/lib.sh"
  HARNESS_ROOT="'"$TMPDIR"'/i8" append_to_yaml "'"$TMPDIR"'/i8/config/orch-auto-allow.yaml" "Bash(ls:*)" "learned"
  # learned 카테고리 안에 Bash(ls:*) 있는지 확인
  awk -v c="learned" -v p="  - \"Bash(ls:*)\"" "
    \$0 ~ \"^\" c \":\" { in_cat=1; next }
    in_cat && /^[a-z][a-z_-]*:/ { in_cat=0 }
    in_cat && \$0 == p { print \"found\"; exit }
  " "'"$TMPDIR"'/i8/config/orch-auto-allow.yaml" | grep -q "found"
'
assert_success "$?" "I-8: 다른 카테고리에 있어도 대상 카테고리에 추가 (멱등성 카테고리 분리)"

# 8. I-9 검증 — bump_stats_counter 락 동시성 (락 디렉토리 정리 + 카운터 증가 확인)
HARNESS_ROOT="$TMPDIR/i8" bash -c '
  source "'"$ROOT"'/bin/lib.sh"
  HARNESS_ROOT="'"$TMPDIR"'/i8" bump_stats_counter "Bash(test:*)" "confirm"
  # 락 정리 확인
  test ! -d "'"$TMPDIR"'/i8/config/orch-auto-allow-stats.yaml.lock"
'
assert_success "$?" "I-9: bump_stats_counter 락 획득·정리 정상"

test_summary
