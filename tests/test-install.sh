#!/usr/bin/env bash
# install.sh — 의존성 체크·tar 제외·검증
set -u
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
DEST="$TMPDIR/skills/awa"

# I1 — cp 모드 설치 후 가이드 제외, 실행 엔진 포함
AWA_INSTALL_DEST="$DEST" AWA_INSTALL_MODE="copy" AWA_INSTALL_SRC="$ROOT/.claude/skills/awa" \
  bash "$ROOT/.claude/skills/awa/install.sh" --no-deps-check >/dev/null 2>&1
assert_eq "1" "$([ -f "$DEST/harness/bin/lib.sh" ] && echo 1 || echo 0)" "I1a 실행 엔진 포함"
assert_eq "0" "$(find "$DEST" \( -name 'AGENTS.md' -o -name 'CLAUDE.md' -o -name 'LEARNED_CAUTIONS.md' \) | wc -l | tr -d ' ')" "I1b 영역 가이드 제외"
assert_eq "1" "$([ -f "$DEST/harness/config/orch-auto-allow.yaml" ] && echo 1 || echo 0)" "I1c config 시드 포함"

# I2 — 의존성 부재 모의 시 fail-fast (uuidgen 가짜 부재)
out="$(AWA_INSTALL_DEST="$TMPDIR/d2" AWA_INSTALL_SRC="$ROOT/.claude/skills/awa" \
  AWA_FAKE_MISSING="uuidgen" bash "$ROOT/.claude/skills/awa/install.sh" --copy 2>&1; echo "rc=$?")"
assert_contains "$out" "uuidgen" "I2 의존성 부재 에러 메시지에 uuidgen"
assert_contains "$out" "rc=1" "I2b fail-fast rc=1"

# I3 — dry-check 게이트 실증 (I1/I2 는 --no-deps-check 로 step5 를 건너뛰어 미커버).
#   깨진 SRC(awa-up.sh 누락)를 deps-check 있는 정상 경로로 설치 → dry-check 가 fail-fast 해야.
#   의존성(tmux/jq/claude/uuidgen)이 머신에 있어야 dry-check 단계 도달 → 부재 시 skip(아래 가드).
if command -v tmux >/dev/null && command -v jq >/dev/null && command -v claude >/dev/null && command -v uuidgen >/dev/null; then
  BROKEN_SRC="$TMPDIR/broken-src"; mkdir -p "$BROKEN_SRC"
  ( cd "$ROOT/.claude/skills/awa" && tar -c . ) | ( cd "$BROKEN_SRC" && tar -x )
  rm -f "$BROKEN_SRC/harness/bin/awa-up.sh"   # 실행 엔진 핵심 제거 → dry-check 실패 유도
  out3="$(AWA_INSTALL_DEST="$TMPDIR/d3" AWA_INSTALL_SRC="$BROKEN_SRC" \
    bash "$ROOT/.claude/skills/awa/install.sh" 2>&1; echo "rc=$?")"
  assert_contains "$out3" "rc=1" "I3 dry-check 깨진 엔진 → fail-fast rc=1"
else
  echo "  skip: I3 dry-check (의존성 부재 — tmux/jq/claude/uuidgen 필요)"
fi

test_summary
