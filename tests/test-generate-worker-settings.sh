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

echo "[G1] 매핑 dev → settings.dev.json.tpl"
out="$(generate_worker_settings dev)"
rc=$?
assert_eq "0" "$rc" "G1 rc=0"
assert_eq "$TMP/.agent-harness/.boot-settings/dev.json" "$out" "G1 경로"
[ -f "$out" ]; assert_success "$?" "G1 파일 생성"
content="$(cat "$out")"
assert_contains "$content" "$TMP/.agent-harness/permission-events.log" "G1 PROJECT_ROOT 치환"
assert_contains "$content" "$ROOT/bin/log-deny.sh" "G1 HARNESS_ROOT 치환"
assert_contains "$content" "Bash(git push *)" "G1 dev deny 포함"

echo "[G2] 매핑 tester → settings.test.json.tpl"
out="$(generate_worker_settings tester)"
assert_eq "$TMP/.agent-harness/.boot-settings/tester.json" "$out" "G2 경로"
content="$(cat "$out")"
assert_contains "$content" "Bash(rm *)" "G2 test deny 포함"
# tester 는 git push deny 없음
if printf '%s' "$content" | grep -q "git push"; then
  assert_eq "no" "yes" "G2 tester 에 git push deny 부재"
fi

echo "[G3] 매핑 reviewer-quality → settings.reviewer.json.tpl"
out="$(generate_worker_settings reviewer-quality)"
assert_eq "$TMP/.agent-harness/.boot-settings/reviewer-quality.json" "$out" "G3 경로"
content="$(cat "$out")"
# reviewer 는 deny 없음
if printf '%s' "$content" | grep -q '"deny"'; then
  assert_eq "no" "yes" "G3 reviewer 에 deny 부재"
fi
assert_contains "$content" "log-deny.sh" "G3 hook 포함"

echo "[G4] 매핑 security/researcher → dev 템플릿"
out="$(generate_worker_settings security)"
content="$(cat "$out")"
assert_contains "$content" "Bash(git push *)" "G4 security 가 dev 템플릿"

echo "[G5] 매핑 없는 역할 (lead/unknown) → 빈 echo + rc=0"
out="$(generate_worker_settings LEAD)"
rc=$?
assert_eq "0" "$rc" "G5 LEAD rc=0"
assert_eq "" "$out" "G5 LEAD 빈 echo"

out="$(generate_worker_settings unknown_role)"
rc=$?
assert_eq "0" "$rc" "G5 unknown rc=0"
assert_eq "" "$out" "G5 unknown 빈 echo"

echo "[G6] 템플릿 부재 — return 1 + stderr"
mv "$ROOT/templates/settings.dev.json.tpl" "$ROOT/templates/settings.dev.json.tpl.bak"
err="$(generate_worker_settings dev 2>&1 >/dev/null)"
rc=$?
mv "$ROOT/templates/settings.dev.json.tpl.bak" "$ROOT/templates/settings.dev.json.tpl"
assert_fail "$rc" "G6 rc!=0"
assert_contains "$err" "settings 템플릿 없음" "G6 stderr"

echo "[G7] 토큰 잔존 (손상된 템플릿) — return 1 + stderr"
# 광범위 패턴 \{\{[A-Z_]+\}\} 이라 화이트리스트 외 토큰도 fail.
mv "$ROOT/templates/settings.dev.json.tpl" "$ROOT/templates/settings.dev.json.tpl.bak"
cat > "$ROOT/templates/settings.dev.json.tpl" <<'EOF'
{"permissions":{"deny":["Bash(rm *)"]},"hooks":{"x":"{{UNKNOWN_TOKEN}}"}}
EOF
# {{UNKNOWN_TOKEN}} — sed 가 PROJECT_ROOT/HARNESS_ROOT 만 치환 → UNKNOWN_TOKEN 잔존 → 광범위 grep 가 fail.
err="$(generate_worker_settings dev 2>&1 >/dev/null)"
rc=$?
mv "$ROOT/templates/settings.dev.json.tpl.bak" "$ROOT/templates/settings.dev.json.tpl"
assert_fail "$rc" "G7 rc!=0 (광범위 토큰 검증)"
assert_contains "$err" "토큰 미치환 잔존" "G7 stderr"
assert_contains "$err" "{{UNKNOWN_TOKEN}}" "G7 stderr 에 잔존 토큰 명시"

test_summary
