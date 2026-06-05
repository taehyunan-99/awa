#!/usr/bin/env bash
# engineer 자가검증 Bash 게이트 통과 회귀.
# 결함(2026-06-01): engineer 가 자기 구현을 검증하려고 source-then-call 이나 스크립트 실행
#   (`. ./src/x.sh && fn`, `bash ./src/x.sh args`)을 돌리면 — danger SAFE·matrix NO_MATCH·
#   auto NO_MATCH → gray → 격리/자동 환경서 USER-ASK 응답없어 타임아웃 DENY → engineer 가
#   자기 구현 검증 못 하고 done 못 냄(운영 봉쇄). `bash -c` 는 danger(bash-c-wrapper) 거부.
# 수정 2단:
#   (1) danger-check 신규 `exec-sensitive`: `.`/source/bash/sh/zsh/dash 로 *절대 시스템·민감
#       경로* 스크립트 실행 거부(`. /etc/x`, `bash /usr/bin/evil.sh`). bash-c-wrapper 동류.
#   (2) orch-auto-allow 신규 `self-verify` 카테고리: Bash(. :*)/Bash(source :*)/Bash(bash :*)/
#       Bash(sh :*). danger 통과(=시스템경로 아닌 프로젝트 스크립트)만 auto-allow.
#   평가순서 danger→matrix→auto 라 위험 경로는 auto 닿기 전 차단.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"
# Task 2 후 lookup 은 PROJECT_ROOT/.agent-harness/config 를 봄 — 시드를 거기로 cp(repo 안이라 trap 정리)
trap 'rm -rf "$ROOT/.agent-harness/config"' EXIT
mkdir -p "$ROOT/.agent-harness/config"
cp "$HARNESS_CONFIG/orch-auto-allow.yaml" "$ROOT/.agent-harness/config/orch-auto-allow.yaml"
# shellcheck disable=SC1091
source "$HARNESS_BIN/danger-check.sh"
# shellcheck disable=SC1091
source "$HARNESS_BIN/lib.sh"
# shellcheck disable=SC1091
source "$HARNESS_BIN/matrix-lookup.sh"
# shellcheck disable=SC1091
source "$HARNESS_BIN/classify.sh"

# ── Layer 1: grep 토큰 (정의 존재) ────────────────────────────────────────
echo "[L1] danger-check exec-sensitive 가드 + orch-auto-allow self-verify 카테고리 정의"
assert_success "$(grep -q 'exec-sensitive' "$HARNESS_BIN/danger-check.sh"; echo $?)" \
  "L1-a danger-check.sh 에 exec-sensitive 카테고리"
assert_success "$(grep -q '^self-verify:' "$HARNESS_CONFIG/orch-auto-allow.yaml"; echo $?)" \
  "L1-b orch-auto-allow.yaml 에 self-verify 카테고리"
assert_success "$(grep -qE 'Bash\(\. :\*\)' "$HARNESS_CONFIG/orch-auto-allow.yaml"; echo $?)" \
  "L1-c self-verify 에 Bash(. :*) 패턴"
assert_success "$(grep -qE 'Bash\(bash :\*\)' "$HARNESS_CONFIG/orch-auto-allow.yaml"; echo $?)" \
  "L1-d self-verify 에 Bash(bash :*) 패턴"

# ── Layer 2: 동작 (danger_check + classify) ──────────────────────────────
dc() {  # $1=command → 카테고리 또는 SAFE
  local input out rc
  input="$(jq -nc --arg c "$1" '{command:$c}')"
  out="$(danger_check Bash "$input")"; rc=$?
  if [ "$rc" -eq 0 ]; then printf '%s' "$out"; else printf 'SAFE'; fi
}
# classify 의 첫 필드(verdict)만 추출. PROJECT_ROOT/entry_role 은 호출자가 export.
cls() {  # $1=entry_role $2=command → verdict (danger/matrix/auto/gray)
  local input
  input="$(jq -nc --arg c "$2" '{command:$c}')"
  classify "$1" Bash "$input" | cut -f1
}

echo "[S1] exec-sensitive: 시스템·민감 경로 스크립트 실행 → danger 거부 (과허용 방어)"
assert_eq "exec-sensitive" "$(dc '. /etc/profile')"        "S1 . /etc/profile"
assert_eq "exec-sensitive" "$(dc 'source /etc/bashrc')"    "S1 source /etc/bashrc"
assert_eq "exec-sensitive" "$(dc 'bash /usr/bin/evil.sh')" "S1 bash /usr/bin/evil.sh"
assert_eq "exec-sensitive" "$(dc 'sh /System/x.sh')"       "S1 sh /System"
assert_eq "exec-sensitive" "$(dc '. ~/.ssh/agent.sh')"     "S1 . ~/.ssh"

echo "[S2] bash -c 는 여전히 bash-c-wrapper 거부 (기존 가드 무손상)"
assert_eq "bash-c-wrapper" "$(dc 'bash -c "range_sum 1 5"')" "S2 bash -c"
assert_eq "bash-c-wrapper" "$(dc 'sh -c "fn"')"             "S2 sh -c"

echo "[S3] 프로젝트 내부 스크립트 자가검증 → danger SAFE (통과 가능 경로)"
assert_eq "SAFE" "$(dc '. ./src/range.sh && range_sum 1 5')" "S3 . ./src 상대"
assert_eq "SAFE" "$(dc 'bash ./src/range.sh 1 5')"          "S3 bash ./src 상대"
assert_eq "SAFE" "$(dc 'source ./tests/x.sh')"              "S3 source ./tests"

echo "[S4] classify 종단: 자가검증 → auto(self-verify), 위험 → danger"
# self-verify 카테고리는 entry_role 무관 orch_auto_allow_lookup 이 잡음(PROJECT_ROOT 만 필요).
export PROJECT_ROOT="$ROOT"
assert_eq "auto"   "$(cls engineer '. ./src/range.sh && range_sum 1 5')" "S4 자가검증 . → auto"
assert_eq "auto"   "$(cls engineer 'bash ./src/range.sh 1 5')"           "S4 자가검증 bash → auto"
assert_eq "auto"   "$(cls engineer 'source ./x.sh')"                     "S4 자가검증 source → auto"
assert_eq "danger" "$(cls engineer '. /etc/profile')"                    "S4 시스템경로 → danger"
assert_eq "danger" "$(cls engineer 'bash -c evil')"                      "S4 bash -c → danger"

echo "[S5] 자가검증 형식이지만 위험 인자 결합 → danger 우선 (권한상승 차단)"
# self-verify auto-allow 가 있어도 danger 평가가 *먼저* — bash 가 rm 류를 품으면 막혀야.
assert_eq "danger" "$(cls engineer 'bash ./x.sh; rm -rf /tmp/y')"  "S5 bash + rm → danger"

echo "[S6] ★ 라이브 발견(2026-06-01): cd <dir> && 프리픽스 자가검증 → auto"
# 실측: Sonnet engineer 가 자가검증을 'cd /abs/proj && bash ./x.sh 5 && bash ./x.sh 15' 로 감쌈
#   (작업 dir 명시 LLM 습관). classify field 가 'cd' 로 시작 → prefix_match(bash) 못 잡아 gray 봉쇄.
# 수정: classify 가 'cd <dir> && ' 선행 조각을 벗겨내고 뒤 명령으로 매칭. cd 는 경로 이동일 뿐
#   명령 실행이 아니라 벗겨내도 의미론 안전(danger 평가는 *원본* 전체에 먼저 적용 — 안전 유지).
assert_eq "auto" "$(cls engineer 'cd /tmp/proj && bash ./src/fizzbuzz.sh 5')"            "S6 cd && bash → auto"
assert_eq "auto" "$(cls engineer 'cd /tmp/proj && bash ./x.sh 5 && bash ./x.sh 15')"     "S6 cd && bash && bash → auto"
assert_eq "auto" "$(cls engineer 'cd /tmp/proj && . ./src/x.sh && fizzbuzz 5')"          "S6 cd && . source → auto"
# ★ cd && 뒤에 위험 명령이 와도 danger 가 *원본 전체* 로 먼저 평가돼 차단 (벗겨내기가 안전 안 푼다).
assert_eq "danger" "$(cls engineer 'cd /tmp && rm -rf /tmp/y')"                          "S6 cd && rm → danger (원본 평가)"
assert_eq "danger" "$(cls engineer 'cd /tmp && bash -c evil')"                           "S6 cd && bash -c → danger"
# ★ cd 가 아닌 다른 프리픽스(FOO=1 bash)는 보수적으로 gray 유지 — cd 만 한정(부작용 프리픽스 배제).
assert_eq "gray" "$(cls engineer 'FOO=1 bash ./x.sh')"                                   "S6 비-cd 프리픽스 → gray 유지(보수)"

test_summary
