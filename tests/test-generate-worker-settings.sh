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
assert_contains "$content" "PROJECT_ROOT=\\\"$TMP\\\"" "G1 PROJECT_ROOT 치환"
assert_contains "$content" "$ROOT/bin/permission-gate.sh" "G1 HARNESS_ROOT 치환"
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
assert_contains "$content" "permission-gate.sh" "G3 hook 포함"
assert_contains "$content" 'WORKER=\"qrev\"' "G3 ENTRY_NAME 토큰 치환"
assert_contains "$content" '"Read"' "G3 reviewer seed allow (T4)"

echo "[G4] 매핑 security/researcher → dev 템플릿 (2인자)"
out="$(generate_worker_settings security sec)"
content="$(cat "$out")"
assert_contains "$content" "Bash(git push *)" "G4 security 가 dev 템플릿"
assert_contains "$content" 'WORKER=\"sec\"' "G4 ENTRY_NAME 토큰 치환"

echo "[G5] orch → settings.orch.json.tpl (2인자, non-empty path)"
out="$(generate_worker_settings orch ORCH)"
rc=$?
assert_eq "0" "$rc" "G5 orch rc=0"
assert_eq "$TMP/.agent-harness/.boot-settings/orch.json" "$out" "G5 orch 경로"
[ -f "$out" ]; assert_success "$?" "G5 orch.json 생성"
content="$(cat "$out")"
assert_contains "$content" "Bash(rm:*)" "G5 orch allow rm"
assert_contains "$content" "Bash(jq:*)" "G5 orch allow jq"

echo "[G5b] 구 역할명 lead|LEAD 도 orch 템플릿으로 (하위호환)"
out="$(generate_worker_settings lead LEAD)"
assert_eq "$TMP/.agent-harness/.boot-settings/lead.json" "$out" "G5b lead 하위호환 경로"
[ -f "$out" ]; assert_success "$?" "G5b lead 하위호환 생성"
content="$(cat "$out")"
assert_contains "$content" "Bash(rm:*)" "G5b lead 하위호환도 orch 템플릿(rm allow)"

echo "[G5c] unknown 역할 → settings.readonly.json.tpl (2인자, fallback=readonly)"
out="$(generate_worker_settings unknown_role somebot)"
rc=$?
assert_eq "0" "$rc" "G5c unknown rc=0"
assert_eq "$TMP/.agent-harness/.boot-settings/unknown_role.json" "$out" "G5c unknown 경로"
[ -f "$out" ]; assert_success "$?" "G5c unknown_role.json 생성 (readonly 템플릿)"
content="$(cat "$out")"
assert_contains "$content" "Bash(ls:*)" "G5c readonly allow ls"
assert_contains "$content" 'WORKER=\"somebot\"' "G5c readonly ENTRY_NAME 토큰"

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

echo "[G8] ENTRY_ROLE 토큰 치환 + permission-gate.sh 경로"
out="$(generate_worker_settings "dev" "dev-1")"
grep -q 'permission-gate.sh' "$out"; assert_success "$?" "G8 permission-gate.sh 참조"
# JSON 내부 따옴표는 \" 로 이스케이프되므로 fixed-string + 백슬래시 리터럴로 매칭.
grep -qF 'ENTRY_ROLE=\"dev\"' "$out"; assert_success "$?" "G8 ENTRY_ROLE 치환"
! grep -q '{{ENTRY_ROLE}}' "$out"; assert_success "$?" "G8 ENTRY_ROLE 토큰 잔존 없음"

echo "[G9] dev 통합 matcher 존재 (Bash|Edit|Write|Agent|WebFetch, MultiEdit 제외)"
grep -q 'Bash|Edit|Write|Agent|WebFetch' "$out"; assert_success "$?" "G9 dev 통합 matcher"
! grep -q 'MultiEdit' "$out"; assert_success "$?" "G9b MultiEdit 미포함 (죽은 도구)"

echo "[G10] default 는 전수 게이트 matcher \"*\" 유지 (미지 역할 사각지대 0 — 5차)"
outd="$(generate_worker_settings "unknown-role-xyz" "u-1")"   # 매핑 없는 역할 → default 템플릿
grep -q '"matcher": "\*"' "$outd"; assert_success "$?" "G10 default matcher * 유지"
grep -q 'permission-gate.sh' "$outd"; assert_success "$?" "G10 default 도 permission-gate command"
! grep -q 'log-deny' "$outd"; assert_success "$?" "G10 default log-deny 잔존 없음"

echo "[G11] PostToolUse(log-event) 공존 — 6차 hook 병합 결함 수정 (--settings 단일 스코프에 둘 다)"
# claude 는 hooks 를 스코프 간 병합 안 함 → PreToolUse + PostToolUse 가 워커 --settings 한 파일에
# 함께 있어야 events.log 가 기록됨 (probe-hook-merge.sh 실측). 회귀 방지.
for r in dev tester reviewer-quality unknown-role-xyz; do
  o="$(generate_worker_settings "$r" "w-1")"
  pre="$(jq -r '.hooks.PreToolUse[0].hooks[0].command // ""' "$o" 2>/dev/null)"
  post="$(jq -r '.hooks.PostToolUse[0].hooks[0].command // ""' "$o" 2>/dev/null)"
  printf '%s' "$pre" | grep -q 'permission-gate.sh'; assert_success "$?" "G11 $r PreToolUse permission-gate"
  printf '%s' "$post" | grep -q 'log-event.sh'; assert_success "$?" "G11 $r PostToolUse log-event 공존"
done

echo "[G12] orch 는 PostToolUse 없음 (감시 대상 아님)"
outl="$(generate_worker_settings orch ORCH)"
! grep -q 'PostToolUse' "$outl"; assert_success "$?" "G12 orch PostToolUse 부재"
! grep -q 'PreToolUse' "$outl"; assert_success "$?" "G12 orch PreToolUse 부재 (게이트 대상 아님)"

# === 역할 카탈로그 매핑 (2026-06-01 재배선) ===
TMP_PROJ="$TMP"
# engineer → dev 군 (코드 쓰기 권한)
ENG="$(HARNESS_PROJECT="$TMP_PROJ" bash -c '
  source '"$ROOT"'/bin/lib.sh
  generate_worker_settings engineer engineer
')"
assert_success "$?" "engineer settings 생성"
assert_contains "$(cat "$ENG")" "Write($TMP_PROJ/**)" "engineer 는 dev 군(코드 전역 쓰기)"

# researcher → readonly 군 (코드 쓰기 없음)
RES="$(HARNESS_PROJECT="$TMP_PROJ" bash -c '
  source '"$ROOT"'/bin/lib.sh
  generate_worker_settings researcher researcher
')"
assert_success "$?" "researcher settings 생성"
assert_not_contains "$(cat "$RES")" "Write($TMP_PROJ/**)" "researcher 는 코드 전역 쓰기 없음(읽기전용)"
assert_contains "$(cat "$RES")" '"Read"' "researcher 읽기 권한 보유"

# review-manager → readonly 군
RVM="$(HARNESS_PROJECT="$TMP_PROJ" bash -c '
  source '"$ROOT"'/bin/lib.sh
  generate_worker_settings review-manager review-mgr
')"
assert_success "$?" "review-manager settings 생성"
assert_not_contains "$(cat "$RVM")" "Write($TMP_PROJ/**)" "review-manager 읽기전용(공통산출은 gate 특례)"

# 미지정 역할 → readonly fallback (최소권한, deny-bounded)
UNK="$(HARNESS_PROJECT="$TMP_PROJ" bash -c '
  source '"$ROOT"'/bin/lib.sh
  generate_worker_settings some-unknown-role x
')"
assert_success "$?" "미지정 역할도 settings 생성(fail-safe)"
assert_not_contains "$(cat "$UNK")" "Write($TMP_PROJ/**)" "미지정 역할 fallback=readonly(최소권한)"

# === web 프로파일 역할 매핑 (spec §6·결함12 수정) ===
# frontend/backend/infra → dev 군 (코드 쓰기 권한, 결함12 선재 수정)
for web_role in frontend backend infra; do
  WEB="$(HARNESS_PROJECT="$TMP_PROJ" bash -c '
    source '"$ROOT"'/bin/lib.sh
    generate_worker_settings '"$web_role"' '"$web_role"'-1
  ')"
  assert_success "$?" "$web_role settings 생성"
  assert_contains "$(cat "$WEB")" "Write($TMP_PROJ/**)" "$web_role 은 dev 군(코드 전역 쓰기 — 결함12)"
  assert_contains "$(cat "$WEB")" "Bash(git push *)" "$web_role dev 템플릿 deny(git push) 포함"
done

test_summary
