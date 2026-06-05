#!/usr/bin/env bash
# SKILL.md discovery 가 harness/ 를 가리키는지 (심링크 절대경로·복사 분기)
set -u
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# discovery 스니펫을 임시 .sh 로 작성 (heredoc 안 \&\& 함정 회피 — 일반 && 그대로).
#   SKILL.md 심링크 분기와 동일 로직(D3 가 drift 차단). 링크 디렉토리에 먼저 cd → 상대 심링크 방어.
cat > "$TMPDIR/disc.sh" <<'DISC'
_raw=~/.claude/skills/awa
_t="$(readlink "$_raw")"
_link="$(cd "$(dirname "$_raw")" && cd "$(dirname "$_t")" && pwd -P)/$(basename "$_t")"
HARNESS_ROOT="$(cd "$_link/harness" && pwd)"
echo "$HARNESS_ROOT"
DISC

# D1 — 절대 심링크 (cwd 무관 절대화 검증)
mkdir -p "$TMPDIR/home/.claude/skills"
ln -sf "$ROOT/.claude/skills/awa" "$TMPDIR/home/.claude/skills/awa"
out="$(cd / && HOME="$TMPDIR/home" bash "$TMPDIR/disc.sh")"
assert_eq "1" "$([ -f "$out/bin/lib.sh" ] && echo 1 || echo 0)" "D1 절대 심링크 discovery → harness/bin/lib.sh"

# D1b — 상대 심링크 (링크 디렉토리 기준 — cwd=/ 에서도 안 깨져야).
#   relhome 안에 실제 harness 마커를 깔고, 링크 디렉토리(.claude/skills)에서 상대경로로 링크 →
#   상대 readlink 가 링크 디렉토리 기준으로 해석돼야 lib.sh 를 찾는다(cwd 기준이면 깨짐).
mkdir -p "$TMPDIR/relhome/.claude/skills" "$TMPDIR/relhome/realtarget/harness/bin"
touch "$TMPDIR/relhome/realtarget/harness/bin/lib.sh"
( cd "$TMPDIR/relhome/.claude/skills" && ln -sf ../../realtarget awa )
relout="$(cd / && HOME="$TMPDIR/relhome" bash "$TMPDIR/disc.sh")"
assert_eq "1" "$([ -f "$relout/bin/lib.sh" ] && echo 1 || echo 0)" "D1b 상대 심링크 discovery → harness/bin/lib.sh (cwd 무관)"

# 복사 시나리오 — 스킬 디렉토리 아래 harness 마커
mkdir -p "$TMPDIR/home2/.claude/skills/awa/harness/bin"
touch "$TMPDIR/home2/.claude/skills/awa/harness/bin/lib.sh"
copy_out="$(HOME="$TMPDIR/home2" bash -c '
  [ -d ~/.claude/skills/awa ] && [ -f ~/.claude/skills/awa/harness/bin/lib.sh ] && echo "$HOME/.claude/skills/awa/harness"
')"
assert_eq "1" "$([ -f "$copy_out/bin/lib.sh" ] && echo 1 || echo 0)" "D2 복사 discovery → harness/bin/lib.sh"

# D3 — Layer 1 drift 가드: 위 스니펫(D1)이 SKILL.md 실제 discovery 블록과 일치하는지.
#   이 테스트는 SKILL.md 를 직접 파싱하지 않고 스니펫 사본을 돌리므로, SKILL.md 가 바뀌면
#   사본이 낡아도 D1 은 통과한다. 그 drift 를 grep 으로 차단(harness/ 한 겹·pwd -P 절대화 핵심 토큰).
SKILL="$ROOT/.claude/skills/awa/SKILL.md"
grep -q 'cd "\$_link/harness"' "$SKILL"
assert_success "$?" "D3a SKILL.md 심링크 분기 harness/ 한 겹"
grep -q 'cd "\$(dirname "\$_raw")" && cd "\$(dirname "\$_t")"' "$SKILL"
assert_success "$?" "D3b SKILL.md 링크 디렉토리 anchor 후 절대화 (상대 심링크 방어)"
grep -q 'harness/bin/lib.sh' "$SKILL"
assert_success "$?" "D3c SKILL.md 복사 분기 harness/bin/lib.sh 마커"

test_summary
