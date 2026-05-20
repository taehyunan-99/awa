#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

# T1.1 — HARNESS_PROJECT env 우선
unset HARNESS_PROJECT
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
HARNESS_PROJECT="$TMP"
( source "$ROOT/bin/lib.sh" 2>/dev/null
  assert_eq "$TMP" "$PROJECT_ROOT" "HARNESS_PROJECT 우선"
  assert_eq "$ROOT" "$HARNESS_ROOT" "HARNESS_ROOT 는 bin/lib.sh 부모"
)
unset HARNESS_PROJECT

# T1.2 — git repo 깊은 하위에서 toplevel 반환
G="$(mktemp -d)"
( cd "$G" && git init -q && mkdir -p deep/nested && cd deep/nested
  source "$ROOT/bin/lib.sh" 2>/dev/null
  # macOS mktemp 가 /var/folders/... 와 /private/var/folders/... 양쪽으로 해석되는 케이스 대응
  pr_real="$(cd "$PROJECT_ROOT" && pwd -P)"
  g_real="$(cd "$G" && pwd -P)"
  assert_eq "$g_real" "$pr_real" "git toplevel 반환"
)
rm -rf "$G"

# T1.3 — git 아닌 디렉터리 → PWD 폴백 + stderr 경고
N="$(mktemp -d)"
( cd "$N"
  out="$(source "$ROOT/bin/lib.sh" 2>&1 >/dev/null)"
  echo "$out" | grep -q "git repo 아님"; assert_success "$?" "PWD 폴백 경고"
  n_real="$(cd "$N" && pwd -P)"
  pr_real="$(source "$ROOT/bin/lib.sh" 2>/dev/null; cd "$PROJECT_ROOT" && pwd -P)"
  assert_eq "$n_real" "$pr_real" "PWD 폴백 값"
)
rm -rf "$N"

test_summary
