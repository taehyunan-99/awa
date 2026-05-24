#!/usr/bin/env bash
# claude settings.allow 의 Bash(prefix:*) 매칭이 단어경계를 두는지 실측.
#
# 우리 게이트(matrix-lookup.sh:42-43, :109-110)는 case glob `"$prefix"*` 로 prefix 매칭 →
# allow `Bash(touch marker:*)` 의 prefix "touch marker" 가 `touch markerfoo`(단어경계 없음)도 매칭.
# 이게 claude 자신의 `Bash(touch marker:*)` 의미론과 일치하면 정상(고치면 불일치), 어긋나면 결함.
# 7차 메모리는 "claude :* 문서 의미론 상속"이라 추정만 — 실제 markerfoo 케이스 미실측.
#
# ★ 1차 probe 실패 교훈: proof/prefix 를 cwd 밖 절대경로로 둬서 claude 작업디렉터리 샌드박스가
#   settings.allow 와 무관하게 전부 차단("허용된 경로는 cwd 하위만"). → 이번엔 단일 작업디렉터리(WORK)를
#   cwd 로 고정하고 그 안의 *상대 파일명* 으로 prefix·proof 를 잡아 샌드박스를 통과시킨다.
#   순수 권한 시스템만 격리: hook 없음(게이트 미개입). settings.allow 만.
#   prefix 토큰을 명령어가 아닌 *인자*("touch marker")로 두어 단어경계만 격리.
#
# 시나리오 (allow = "Bash(touch marker:*)", 모두 WORK 를 cwd 로):
#   S1. touch marker          → 정확 매칭 경계 (marker 생성 = 허용)
#   S2. touch marker extra    → prefix 뒤 공백+인자 (정상 :* 의미, marker+extra = 허용 기대)
#   S3. touch markerfoo       → prefix 뒤 단어경계 없이 이어붙음 (markerfoo 생성 = 단어경계 없음/느슨)
#   S4. touch marker-bar      → prefix 뒤 하이픈 연결 (marker-bar 생성 = 단어경계 없음/느슨)
#
# 판정:
#   S1·S2 = EXECUTED 여야 allow 작동(probe 유효). 아니면 무의미(샌드박스/모델거부 재점검).
#   S3·S4 = EXECUTED → claude 도 단어경계 없는 prefix(우리 게이트와 일치) → 고치면 불일치, 보류 권장.
#   S3·S4 = BLOCKED  → claude 는 단어경계 둠(우리 게이트가 더 느슨한 결함) → 게이트 단어경계 추가.
#
# ★ claude -p 토큰 과금 → 어시스턴트 실행 금지. 사용자가 `!` 로 1회 실행.
#   격리 임시 디렉터리. --dangerously-skip-permissions·kill-server 미사용(TCC 사고 회피).
#
# 출력: docs/probe-results/2026-05-24-prefix-word-boundary.md

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$HARNESS_ROOT/docs/probe-results"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/2026-05-24-prefix-word-boundary.md"

command -v claude >/dev/null 2>&1 || { echo "claude CLI 없음 — 중단"; exit 1; }

TMP_BASE="$(mktemp -d -t claude-prefix-probe.XXXXXX)"
trap 'rm -rf "$TMP_BASE"' EXIT

# 단일 작업 디렉터리: 모든 시나리오가 여기를 cwd 로. settings 도 여기 .claude 에.
# prefix·proof 는 이 안의 상대 파일명(marker 등) → 샌드박스 통과.
WORK="$TMP_BASE/work"
mkdir -p "$WORK/.claude"
cat > "$WORK/.claude/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(touch marker:*)"]
  }
}
EOF

# $1=label, $2=실행할 셸 명령(WORK 기준 상대), $3=proof 파일명(WORK 기준 상대)
run_scenario() {
  local label="$1" shell_cmd="$2" proof_rel="$3"
  local proof="$WORK/$proof_rel"
  rm -f "$proof"

  local prompt="I need to create a marker file for the build in the current directory. Use the Bash tool to run exactly this command (do not modify it): $shell_cmd"
  local stdin_file="$TMP_BASE/_prompt_$label.txt"
  printf '%s\n' "$prompt" > "$stdin_file"
  local output exit_code
  output="$(cd "$WORK" && eval "claude -p < '$stdin_file' 2>&1")"
  exit_code=$?

  # ★ verdict: proof 파일 존재가 유일한 실행 증거. allow 통과 = 묻지 않고 실행.
  local verdict
  if [ -f "$proof" ]; then
    verdict="EXECUTED"   # 권한 통과 (allow 매칭)
  else
    verdict="BLOCKED_OR_ASK"   # 매칭 안 됨 → ask/deny → 비대화 미실행
  fi

  printf '\n## %s\n\n' "$label"
  printf '**allow**: `Bash(touch marker:*)` (cwd=WORK)\n\n'
  printf '**명령**: `%s`\n\n' "$shell_cmd"
  printf '**proof(%s) 생성됨**: %s\n\n' "$proof_rel" "$([ -f "$proof" ] && echo yes || echo no)"
  printf '**verdict**: `%s` (exit=%d)\n\n' "$verdict" "$exit_code"
  printf '**output (truncated)**:\n```\n%s\n```\n\n' "$(printf '%s' "$output" | head -30)"
  printf '%s\n' '---'
}

{
  printf '# claude Bash(prefix:*) 단어경계 의미론 실측 — 2026-05-24\n\n'
  printf '환경: `%s`\n\n' "$(claude --version 2>&1 | head -1)"
  printf 'allow = `Bash(touch marker:*)` 고정, cwd=WORK 공유. hook 없음(순수 권한 시스템). proof 파일 = 실행 증거.\n\n'

  run_scenario "S1-exact"        "touch marker"          "marker"
  run_scenario "S2-space-extra"  "touch marker extra"    "extra"
  run_scenario "S3-glued-foo"    "touch markerfoo"       "markerfoo"
  run_scenario "S4-hyphen-bar"   "touch marker-bar"      "marker-bar"

  printf '\n## 결론\n\n'
  printf 'S1·S2 = EXECUTED 여야 allow 작동(probe 유효).\n'
  printf 'S3·S4 = EXECUTED → claude 도 단어경계 없는 prefix → 우리 게이트와 일치. 고치면 불일치, 보류 권장.\n'
  printf 'S3·S4 = BLOCKED_OR_ASK → claude 는 단어경계 둠 → 우리 게이트가 더 느슨한 결함, 단어경계 추가.\n'
} > "$OUT"

printf 'probe 완료. 결과: %s\n' "$OUT"
printf '\n핵심 결과:\n'
grep -E '^## |verdict|proof' "$OUT" | head -20
