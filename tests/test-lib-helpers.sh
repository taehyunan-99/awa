#!/usr/bin/env bash
# lib.sh 의 5차 보조함수 (timestamp/log_safe/summarize_input) 단위 테스트.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
export HARNESS_PROJECT="$(mktemp -d)"
( cd "$HARNESS_PROJECT" && git init -q )
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh"

echo "[H1] timestamp 는 epoch 정수"
ts="$(timestamp)"
case "$ts" in ''|*[!0-9]*) assert_eq "정수" "비정수($ts)" "H1 epoch 정수" ;; *) assert_success 0 "H1 epoch 정수" ;; esac

echo "[H2] log_safe 가 400 byte 미만 truncate + append"
export LOG="$HARNESS_PROJECT/test.log"
long="$(head -c 5000 /dev/zero | tr '\0' 'A')"
log_safe "$long"
bytes="$(wc -c < "$LOG" | tr -d ' ')"
[ "$bytes" -le 401 ]; assert_success "$?" "H2 400byte 미만 ($bytes)"

echo "[H3] log_safe 큰 입력에도 exit 0 (SIGPIPE 흡수)"
huge="$(head -c 1000000 /dev/zero | tr '\0' 'B')"
log_safe "$huge"; assert_success "$?" "H3 SIGPIPE 흡수 (대용량)"

echo "[H4] summarize_input 는 200 byte 미만"
big_json='{"command":"'"$(head -c 1000 /dev/zero | tr '\0' 'x')"'"}'
sumlen="$(summarize_input "Bash" "$big_json" | wc -c | tr -d ' ')"
[ "$sumlen" -le 201 ]; assert_success "$?" "H4 200byte 미만 ($sumlen)"

test_summary
