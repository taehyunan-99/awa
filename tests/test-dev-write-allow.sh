#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"

TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
cleanup() { rm -rf "$TMP_PROJ"; }
trap cleanup EXIT

# dev 템플릿 치환 산출물 검증.
OUT="$(HARNESS_PROJECT="$TMP_PROJ" bash -c '
  source '"$ROOT"'/bin/lib.sh
  generate_worker_settings dev dev
')"
assert_success "$?" "dev settings 생성"
DEVSET="$(cat "$OUT")"

# 치환된 PROJECT_ROOT 절대경로로 Write/Edit allow 존재
assert_contains "$DEVSET" "Write($TMP_PROJ/**)" "dev Write PROJECT_ROOT 스코프 allow"
assert_contains "$DEVSET" "Edit($TMP_PROJ/**)" "dev Edit PROJECT_ROOT 스코프 allow"
# 토큰 미치환 없음
assert_not_contains "$DEVSET" "{{PROJECT_ROOT}}" "dev settings 토큰 치환됨"
# 기존 hook 보존 (회귀)
assert_contains "$DEVSET" "permission-gate.sh" "dev PreToolUse 게이트 보존"

# reviewer 템플릿엔 Write allow 없음 (격리 회귀)
RVOUT="$(HARNESS_PROJECT="$TMP_PROJ" bash -c '
  source '"$ROOT"'/bin/lib.sh
  generate_worker_settings reviewer-quality quality-rev
')"
assert_success "$?" "reviewer settings 생성"
RVSET="$(cat "$RVOUT")"
# RVSET 이 비어있지 않아야 assert_not_contains 가 의미를 가짐 (빈 문자열 거짓양성 방지)
assert_contains "$RVSET" "permissions" "reviewer settings 내용 존재"
assert_not_contains "$RVSET" "Write(" "reviewer 는 Write allow 없음 (격리 유지)"

# ── C2: 실제 게이트 동작 검증 (결함 B 회귀 가드) ──────────────────────────
# 이전 버전은 템플릿 문자열에 Write(...) 가 있는지만 검사해 버그를 통과시켰다.
# 여기서는 classify 가 실제 verdict 를 산출하도록 PROJECT_ROOT 환경을 구성한다.
# generate_worker_settings 가 dev settings 를 boot-settings/dev.json 에 이미 기록함
# (= matrix_lookup 이 읽는 경로). lead-auto-allow.yaml 도 설치한다.
mkdir -p "$TMP_PROJ/config"
cat > "$TMP_PROJ/config/lead-auto-allow.yaml" <<'YAML'
read-only:
  - "Bash(find:*)"
YAML

# classify 평가용 함수들을 PROJECT_ROOT 컨텍스트에서 source 후 verdict 만 추출하는 헬퍼.
TAB="$(printf '\t')"
gate_verdict() {  # $1=role $2=tool $3=input_json → stdout: verdict 만
  PROJECT_ROOT="$TMP_PROJ" HARNESS_PROJECT="$TMP_PROJ" bash -c '
    set -uo pipefail
    source '"$ROOT"'/bin/lib.sh
    source '"$ROOT"'/bin/matrix-lookup.sh
    source '"$ROOT"'/bin/danger-check.sh
    source '"$ROOT"'/bin/classify.sh
    classify "$1" "$2" "$3"
  ' _ "$1" "$2" "$3" | cut -f1
}

# dev 가 프로젝트 파일을 Write → matrix (gray 아님). 결함 B 핵심 회귀.
v="$(gate_verdict dev Write "{\"file_path\":\"$TMP_PROJ/foo.py\"}")"
assert_eq "matrix" "$v" "dev Write 프로젝트파일 → matrix (gray 정체 아님)"

# dev 가 하위 디렉터리 파일을 Edit → matrix (/** 재귀 glob 검증).
v="$(gate_verdict dev Edit "{\"file_path\":\"$TMP_PROJ/sub/x.py\"}")"
assert_eq "matrix" "$v" "dev Edit 하위경로 → matrix (/** 재귀)"

# 보안 회귀 가드: 위험 시스템경로는 matrix glob 을 통과하지 못하고 danger 가 먼저 차단.
v="$(gate_verdict dev Write '{"file_path":"/etc/passwd"}')"
assert_eq "danger" "$v" "dev Write /etc/passwd → danger (matrix glob 우회 불가)"

# 보안 회귀 가드: 프로젝트 내부라도 .env 는 cred-file-edit danger.
v="$(gate_verdict dev Write "{\"file_path\":\"$TMP_PROJ/.env\"}")"
assert_eq "danger" "$v" "dev Write 프로젝트 .env → danger (cred-file-edit)"

# 프로젝트 밖 임의 경로는 matrix glob 에 안 걸리고 gray (정체 → lead 판단).
v="$(gate_verdict dev Write '{"file_path":"/tmp/other-elsewhere/foo.py"}')"
assert_eq "gray" "$v" "dev Write 프로젝트 밖 → gray (matrix 확대 안 됨)"

test_summary
