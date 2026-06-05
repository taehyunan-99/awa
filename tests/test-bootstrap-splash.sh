#!/usr/bin/env bash
# awa-up.sh splash 정적 검사 — 셸 splash 미주입(원복) + 팀 요약 append + 훅 설치.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/assert.sh"
. "$ROOT/tests/harness-paths.sh"
UP="$HARNESS_BIN/awa-up.sh"

# B1: 셸 splash 주입 제거 — bootstrap_pane 의 send-keys 줄에 awa-splash.sh 가 없어야 함.
splash_in_sendkeys="$(grep -n 'awa-splash.sh' "$UP" | grep -E 'send-keys' || true)"
assert_eq "" "$splash_in_sendkeys" "B1 셸 splash send-keys 주입 제거됨"

# B2: claude 분기는 원래의 export HARNESS_WORKER + \$cmd 송신으로 복원.
assert_contains "$(cat "$UP")" "export HARNESS_WORKER=" "B2 HARNESS_WORKER export 유지"

# B3: 팀 요약 append 헬퍼 정의 존재.
assert_contains "$(cat "$UP")" "splash_append_member" "B3 splash_append_member 헬퍼 정의"

# B4: 4 호출부(워커/LEAD/PM/리뷰어) 모두에서 멤버 append 호출 — 최소 4회.
append_calls="$(grep -c 'splash_append_member' "$UP")"
# 정의 1 + 호출 4 = 5 이상.
assert_eq "1" "$([ "$append_calls" -ge 5 ] && echo 1 || echo 0)" "B4 append 정의+호출 5회 이상(=$append_calls)"

# B5: popup 명령 정의(SPLASH_POPUP). run-shell 로 display-popup 을 감싼다 — 훅 컨텍스트의
# 직접 display-popup 은 attach 클라이언트를 못 잡아 조용히 무시되기 때문(실측).
popup_def="$(grep -n 'SPLASH_POPUP=' "$UP" | head -1 || true)"
assert_contains "$popup_def" "run-shell" "B5a SPLASH_POPUP 가 run-shell 래핑"
assert_contains "$popup_def" "display-popup" "B5b run-shell 안에 display-popup"
assert_contains "$popup_def" "awa-splash.sh" "B5c awa-splash.sh 호출"
# -k 미사용: display-popup 플래그 묶음에 단독 -k 플래그가 없어야 함.
# (-E -k / -Ek / -kE 등 순서·결합 무관하게 잡는다.)
flags="$(printf '%s\n' "$popup_def" | grep -oE 'display-popup[^"]*' | head -1)"
assert_not_contains " $flags " " -k " "B5d -k 미사용(공백구분 단독 플래그)"
assert_not_contains "$flags" "-Ek" "B5d2 -k 미사용(-Ek 결합형)"
assert_not_contains "$flags" "-kE" "B5d3 -k 미사용(-kE 결합형)"

# B5e: client-attached 훅이 SPLASH_POPUP 으로 세션 스코프(-t \$SESSION) 설치.
hook_line="$(grep -nE 'set-hook .*client-attached' "$UP" | head -1 || true)"
assert_contains "$hook_line" "client-attached" "B5e client-attached 훅 라인"
assert_contains "$hook_line" "SPLASH_POPUP" "B5f 훅이 SPLASH_POPUP 사용"
assert_contains "$hook_line" "-t \"\$SESSION\"" "B5g 세션 스코프 set-hook"

# B5h: splash 가 커서를 숨긴다 — popup 100% 여도 하드웨어 커서가 비치므로.
assert_contains "$(cat "$HARNESS_BIN/awa-splash.sh")" '\033[?25l' "B5h 커서 숨김(splash)"

# B6: 팀 요약 파일 경로가 splash 와 awa-up 에서 동일 기본값(HOME/.cache/awa/team-summary.txt).
assert_contains "$(cat "$UP")" "team-summary.txt" "B6 팀 요약 파일 경로"

test_summary
