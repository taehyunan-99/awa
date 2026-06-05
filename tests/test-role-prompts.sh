#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"
source "$HARNESS_BIN/lib.sh" >/dev/null 2>&1 || true
rf() { cat "$(resolve_role_file "$HARNESS_PROMPTS" "$1")"; }   # 역할명 → 내용

orch_content="$(rf orch)"
assert_contains "$orch_content" "단계" "orch 단계전이 금지 규약"
assert_contains "$orch_content" ".harness-state" "orch harness-state 규약"
assert_contains "$orch_content" "카탈로그" "orch 워커 카탈로그 사용"
# P3(2026-05-30): forbidden_paths 불변식 — 워커 산출 경로(.agent-harness/results 등)를
#   forbidden 에 넣지 마라(리뷰 VIOLATION 오탐 차단).
assert_contains "$orch_content" "forbidden_paths 불변식" "orch P3 forbidden 산출경로 예외 규약"
# P8(2026-05-30): 승인 게이트 벤더중립 — AskUserQuestion 부재(codex) 시 텍스트 폴백.
assert_contains "$orch_content" "벤더중립" "orch P8 게이트 벤더중립 규약"
assert_contains "$orch_content" "텍스트 응답을 대기" "orch P8 텍스트 폴백 명시"
# P3 워커측·리뷰어측 예외 정합 (3곳 동시 갱신 보증).
common_c="$(cat "$HARNESS_PROMPTS/_common.md")"
assert_contains "$common_c" "산출은 하니스 규약상 항상 허용" "_common P3 워커측 산출 예외"
revc_c="$(rf reviewer-common)"
assert_contains "$revc_c" "scope VIOLATION 으로 판정하지 마라" "reviewer-common P3 오탐 차단"

revl="$(rf reviewer-common)"
assert_contains "$revl" "events.log" "reviewer 공통절차가 events.log 감시"
assert_contains "$revl" ".review-cursor" "reviewer 공통절차 커서 사용"

orch_loop="$(rf orch)"
assert_contains "$orch_loop" "review/" "orch 가 review/ 감시"

for r in spec quality arch; do
  if resolve_role_file "$HARNESS_PROMPTS" "reviewer-$r" >/dev/null 2>&1; then
    assert_eq "ok" "ok" "reviewer-$r.md 존재"
  else
    assert_eq "exists" "missing" "reviewer-$r.md 존재해야 함"
  fi
done

if resolve_role_file "$HARNESS_PROMPTS" reviewer >/dev/null 2>&1; then
  assert_eq "deleted" "still-exists" "1차 roles/reviewer.md 삭제돼야 함"
else
  assert_eq "ok" "ok" "1차 roles/reviewer.md 삭제됨"
fi

# 9차: reviewer-common.md 런타임 단일출처 존재 (부트 합본 의존)
resolve_role_file "$HARNESS_PROMPTS" reviewer-common >/dev/null 2>&1
assert_success "$?" "reviewer-common.md 존재 (reviewer 부트 합본 의존)"

# --- orch 구조 (승자=A 6절; 신호→반응) ---
ORCH="$(rf orch)"
assert_contains "$ORCH" "## ⓐ 동작 모델" "orch ⓐ 동작 모델"
assert_contains "$ORCH" "## ⓑ @desk" "orch ⓑ 위임 계약"
assert_contains "$ORCH" "## ⓒ @done" "orch ⓒ 종합"
assert_contains "$ORCH" "## ⓓ @gate" "orch ⓓ 권한 게이트"
assert_contains "$ORCH" "## ⓔ 개입" "orch ⓔ 개입·escalation"
assert_contains "$ORCH" "## ⓕ 금지" "orch ⓕ 금지+근거"
# 구조 무관 보존(본문 — partial 아님):
assert_contains "$ORCH" "출력=토큰=신호" "orch 출력=신호 방향성"
assert_contains "$ORCH" "stale" "orch stale tasks(#10)"
assert_contains "$ORCH" "--project" "orch 호출 위치(#9, _common 미상속)"
assert_contains "$ORCH" "입력경로" "orch 산출물 연결(#5)"
assert_contains "$ORCH" "orch BLOCKED" "orch BLOCKED(ⓔ 변형 포함)"
assert_contains "$ORCH" "@orch: rm" "orch rm 위임 신호(C-1)"
assert_not_contains "$ORCH" "### 1단계. state/pending-asks/" "orch 본문엔 게이트 절차 본체 없음(partial)"

# --- desk 3절 ---
DESK="$(rf desk)"
assert_contains "$DESK" "## ⓐ 정체성" "desk ⓐ 정체성"
assert_contains "$DESK" "## ⓑ pull-read" "desk ⓑ pull 관찰"
assert_contains "$DESK" "## ⓒ 전달" "desk ⓒ 전달+금지"
assert_contains "$DESK" "사실과 추측을 구분" "desk 사실/추측 구분"
assert_contains "$DESK" "@desk:" "desk 전달 prefix"
assert_contains "$DESK" "읽기 전용" "desk 읽기전용"
# 안전망 (구 회귀 유지): desk 은 사용자 창구 + dispatch 직접 안 함.
assert_contains "$DESK" "사용자" "desk 은 사용자 창구"
assert_not_contains "$DESK" "dispatch.sh" "desk 은 dispatch 안 함(orch 의 일)"

# --- 5축 공통 토대 (_common.md) ---
COMMON="$(cat "$HARNESS_PROMPTS/_common.md")"
assert_contains "$COMMON" 'status: DONE|PARTIAL|BLOCKED' "_common ②출력계약 status 헤더"
assert_contains "$COMMON" 'EVIDENCE' "_common ③ EVIDENCE 섹션"
assert_contains "$COMMON" 'HYPOTHESIS' "_common ③ HYPOTHESIS 섹션"
assert_contains "$COMMON" 'confirmed|likely|speculative' "_common ③ confidence 버킷(숫자% 금지)"
assert_contains "$COMMON" 'BLOCKED' "_common ④ BLOCKED 프로토콜"
assert_contains "$COMMON" 'ASSUMED:' "_common ⑤ assume-and-flag"
# P11 탈-tmux: 완료 신호 = events.log done 라인(워커 tmux 직접호출 0). wait-for 제거 확인 + done 라인 규약 보존.
assert_contains "$COMMON" 'done 라인' "_common 완료신호=events.log done 라인(회귀)"
case "$COMMON" in *"tmux wait-for -S done-"*) assert_eq 1 0 "_common 에 워커 wait-for 잔존(P11 위반)";; *) assert_eq 0 0 "_common 워커 wait-for 제거 확인";; esac

res_c="$(cat "$(resolve_role_file "$HARNESS_PROMPTS" researcher)")"
assert_contains "$res_c" "budget" "researcher.md ⑤ budget"
assert_contains "$res_c" "추측" "researcher.md ① 추측 단정 금지"

sec_c="$(cat "$(resolve_role_file "$HARNESS_PROMPTS" security)")"
assert_contains "$sec_c" "budget" "security.md ⑤ budget"
assert_contains "$sec_c" "file:line" "security.md ③ 취약점 위치 file:line"

test_summary
