#!/usr/bin/env bash
# agenphony-up 후 .boot-settings/<role>.json 6 파일 생성 + 매핑 검증.
# AGENT_CMD=cat 으로 더미 실행 — claude 부재 환경에서도 동작.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
TMP="$(mktemp -d)"
SAFE="$(printf '%s' "$(basename "$TMP")" | sed 's/[^A-Za-z0-9_-]/_/g')"
SESSION="agenphony-$SAFE"

cleanup() {
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT
( cd "$TMP" && git init -q )

# feature-team 프로파일: dev/test/researcher 워커 + 3 reviewer.
HARNESS_PROJECT="$TMP" AGENT_CMD=cat bash "$ROOT/bin/agenphony-up.sh" feature-team >/dev/null 2>&1
rc=$?
assert_eq "0" "$rc" "agenphony-up 성공"

BOOTSET="$TMP/.agent-harness/.boot-settings"
[ -d "$BOOTSET" ]; assert_success "$?" ".boot-settings 디렉터리 생성"

# feature-team WORKERS=(dev:dev tester:test arch:researcher), REVIEWERS=(spec-rev:reviewer-spec ...).
# generate_worker_settings 매핑:
#  - dev/researcher → dev 템플릿 → dev.json, researcher.json
#  - tester → test 템플릿 → tester.json
#  - reviewer-* → reviewer 템플릿 → reviewer-{spec,quality,arch}.json
# 6 파일 모두 *필수* 검증 — 매핑 회귀 신호 강하게.
[ -f "$BOOTSET/dev.json" ]; assert_success "$?" "dev.json 존재"
[ -f "$BOOTSET/tester.json" ]; assert_success "$?" "tester.json 존재"
[ -f "$BOOTSET/researcher.json" ]; assert_success "$?" "researcher.json 존재 (dev 템플릿)"
[ -f "$BOOTSET/reviewer-quality.json" ]; assert_success "$?" "reviewer-quality.json 존재"
[ -f "$BOOTSET/reviewer-spec.json" ]; assert_success "$?" "reviewer-spec.json 존재"
[ -f "$BOOTSET/reviewer-arch.json" ]; assert_success "$?" "reviewer-arch.json 존재"

# dev 검증
content="$(cat "$BOOTSET/dev.json")"
assert_contains "$content" "Bash(git push *)" "dev.json git push deny"
assert_contains "$content" "PROJECT_ROOT=\\\"$TMP\\\"" "dev.json PROJECT_ROOT 치환"
assert_contains "$content" 'WORKER=\"dev\"' "dev.json WORKER=entry_name(dev)"
# 잔존 토큰 부재
if printf '%s' "$content" | grep -qE '\{\{[A-Z_]+\}\}'; then
  assert_eq "no" "yes" "dev.json 토큰 잔존 부재"
fi

# researcher 검증 — dev 와 동일 매핑이므로 deny 동일해야.
content="$(cat "$BOOTSET/researcher.json")"
assert_contains "$content" "Bash(git push *)" "researcher.json dev 템플릿 매핑 (git push deny)"
assert_contains "$content" 'WORKER=\"arch\"' "researcher.json WORKER=entry_name(arch)"

# tester 검증
content="$(cat "$BOOTSET/tester.json")"
assert_contains "$content" "Bash(rm *)" "tester.json rm deny"
assert_contains "$content" 'WORKER=\"test\"' "tester.json WORKER=entry_name(test)"
if printf '%s' "$content" | grep -q "git push"; then
  assert_eq "no" "yes" "tester.json 에 git push deny 부재"
fi

# reviewer-quality 검증
content="$(cat "$BOOTSET/reviewer-quality.json")"
# deny 부재 (기술적 차단 불가)
if printf '%s' "$content" | grep -q '"deny"'; then
  assert_eq "no" "yes" "reviewer-quality.json deny 부재"
fi
assert_contains "$content" "permission-gate.sh" "reviewer-quality.json hook"
assert_contains "$content" '"Read"' "reviewer-quality.json seed allow Read"
assert_contains "$content" 'WORKER=\"quality-rev\"' "reviewer-quality.json WORKER=entry_name"

# reviewer-spec / reviewer-arch 도 동일 reviewer 템플릿 — deny 부재 + hook 존재.
for rev in reviewer-spec reviewer-arch; do
  content="$(cat "$BOOTSET/$rev.json")"
  if printf '%s' "$content" | grep -q '"deny"'; then
    assert_eq "no" "yes" "$rev.json deny 부재"
  fi
  assert_contains "$content" "permission-gate.sh" "$rev.json hook"
  assert_contains "$content" '"Read"' "$rev.json seed allow Read"
done

# AGENT_CMD=cat 경로에선 --settings 가 cmd 에 추가되지 않음 (claude 분기에서만 추가).
# 본 테스트는 *파일 생성* 만 검증. claude 인자 적용은 integration probe (T10) 가 담당.

test_summary
