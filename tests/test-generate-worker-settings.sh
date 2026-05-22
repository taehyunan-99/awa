#!/usr/bin/env bash
# generate_worker_settings 매핑·치환·검증 단위 테스트.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# lib.sh 가 PROJECT_ROOT 를 cwd 의 git toplevel 로 잡으므로 TMP 를 git repo 로.
( cd "$TMP" && git init -q )
export HARNESS_PROJECT="$TMP"
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh"

echo "[G1] 매핑 dev → settings.dev.json.tpl (2인자)"
out="$(generate_worker_settings dev devbot)"
rc=$?
assert_eq "0" "$rc" "G1 rc=0"
assert_eq "$TMP/.agent-harness/.boot-settings/dev.json" "$out" "G1 경로"
[ -f "$out" ]; assert_success "$?" "G1 파일 생성"
content="$(cat "$out")"
assert_contains "$content" "$TMP/.agent-harness/permission-events.log" "G1 PROJECT_ROOT 치환"
assert_contains "$content" "$ROOT/bin/log-deny.sh" "G1 HARNESS_ROOT 치환"
assert_contains "$content" "Bash(git push *)" "G1 dev deny 포함"
assert_contains "$content" 'WORKER=\"devbot\"' "G1 ENTRY_NAME 토큰 치환 (WORKER env)"

echo "[G2] 매핑 tester → settings.test.json.tpl (2인자)"
out="$(generate_worker_settings tester testbot)"
assert_eq "$TMP/.agent-harness/.boot-settings/tester.json" "$out" "G2 경로"
content="$(cat "$out")"
assert_contains "$content" "Bash(rm *)" "G2 test deny 포함"
assert_contains "$content" 'WORKER=\"testbot\"' "G2 ENTRY_NAME 토큰 치환"
if printf '%s' "$content" | grep -q "git push"; then
  assert_eq "no" "yes" "G2 tester 에 git push deny 부재"
fi

echo "[G3] 매핑 reviewer-quality → settings.reviewer.json.tpl (2인자)"
out="$(generate_worker_settings reviewer-quality qrev)"
assert_eq "$TMP/.agent-harness/.boot-settings/reviewer-quality.json" "$out" "G3 경로"
content="$(cat "$out")"
assert_contains "$content" "log-deny.sh" "G3 hook 포함"
assert_contains "$content" 'WORKER=\"qrev\"' "G3 ENTRY_NAME 토큰 치환"
assert_contains "$content" '"Read"' "G3 reviewer seed allow (T4)"

echo "[G4] 매핑 security/researcher → dev 템플릿 (2인자)"
out="$(generate_worker_settings security sec)"
content="$(cat "$out")"
assert_contains "$content" "Bash(git push *)" "G4 security 가 dev 템플릿"
assert_contains "$content" 'WORKER=\"sec\"' "G4 ENTRY_NAME 토큰 치환"

echo "[G5] lead → settings.lead.json.tpl (2인자, non-empty path)"
out="$(generate_worker_settings lead LEAD)"
rc=$?
assert_eq "0" "$rc" "G5 lead rc=0"
assert_eq "$TMP/.agent-harness/.boot-settings/lead.json" "$out" "G5 lead 경로"
[ -f "$out" ]; assert_success "$?" "G5 lead.json 생성"
content="$(cat "$out")"
assert_contains "$content" "Bash(rm:*)" "G5 lead allow rm"
assert_contains "$content" "Bash(jq:*)" "G5 lead allow jq"

echo "[G5b] LEAD (대문자) 도 lead 분기"
out="$(generate_worker_settings LEAD LEAD)"
assert_eq "$TMP/.agent-harness/.boot-settings/LEAD.json" "$out" "G5b LEAD 경로"
[ -f "$out" ]; assert_success "$?" "G5b LEAD.json 생성"

echo "[G5c] unknown 역할 → settings.default.json.tpl (2인자)"
out="$(generate_worker_settings unknown_role somebot)"
rc=$?
assert_eq "0" "$rc" "G5c unknown rc=0"
assert_eq "$TMP/.agent-harness/.boot-settings/unknown_role.json" "$out" "G5c unknown 경로"
[ -f "$out" ]; assert_success "$?" "G5c unknown_role.json 생성 (default 템플릿)"
content="$(cat "$out")"
assert_contains "$content" "Bash(ls:*)" "G5c default allow ls"
assert_contains "$content" 'WORKER=\"somebot\"' "G5c default ENTRY_NAME 토큰"

echo "[G6] 템플릿 부재 — return 1 + stderr (2인자)"
mv "$ROOT/templates/settings.dev.json.tpl" "$ROOT/templates/settings.dev.json.tpl.bak"
err="$(generate_worker_settings dev devbot 2>&1 >/dev/null)"
rc=$?
mv "$ROOT/templates/settings.dev.json.tpl.bak" "$ROOT/templates/settings.dev.json.tpl"
assert_fail "$rc" "G6 rc!=0"
assert_contains "$err" "settings 템플릿 없음" "G6 stderr"

echo "[G7] 토큰 잔존 (손상된 템플릿) — return 1 + stderr (2인자)"
mv "$ROOT/templates/settings.dev.json.tpl" "$ROOT/templates/settings.dev.json.tpl.bak"
cat > "$ROOT/templates/settings.dev.json.tpl" <<'EOF'
{"permissions":{"deny":["Bash(rm *)"]},"hooks":{"x":"{{UNKNOWN_TOKEN}}"}}
EOF
err="$(generate_worker_settings dev devbot 2>&1 >/dev/null)"
rc=$?
mv "$ROOT/templates/settings.dev.json.tpl.bak" "$ROOT/templates/settings.dev.json.tpl"
assert_fail "$rc" "G7 rc!=0 (광범위 토큰 검증)"
assert_contains "$err" "토큰 미치환 잔존" "G7 stderr"
assert_contains "$err" "{{UNKNOWN_TOKEN}}" "G7 stderr 에 잔존 토큰 명시"

test_summary
