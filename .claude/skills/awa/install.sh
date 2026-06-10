#!/usr/bin/env bash
# AWA 설치 — 의존성 체크 + 영역 가이드 제외 cp + 검증.
# 사용: bash install.sh            (clone 위치에서 ~/.claude/skills/awa 로 설치)
#       AWA_INSTALL_* env 로 테스트 override.
# pipefail — tar 파이프 좌측(SRC tar -c) 실패가 마스킹되지 않게(우측만 검사하던 footgun 차단).
set -euo pipefail

SRC="${AWA_INSTALL_SRC:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
DEST="${AWA_INSTALL_DEST:-$HOME/.claude/skills/awa}"
# MODE 는 현재 copy 단일 — 향후 심링크 설치 분기용 예약(지금은 미사용). --copy 는 수용·무시 플래그.
MODE="${AWA_INSTALL_MODE:-copy}"
NO_DEPS=0
for a in "$@"; do
  case "$a" in
    --no-deps-check) NO_DEPS=1 ;;
    --copy) MODE="copy" ;;
  esac
done

# 1) 의존성 체크 (uuidgen 포함 — awa-up.sh 가 가드 없이 사용)
if [ "$NO_DEPS" = "0" ]; then
  _missing=""
  for dep in tmux jq claude uuidgen; do
    if [ "${AWA_FAKE_MISSING:-}" = "$dep" ] || ! command -v "$dep" >/dev/null 2>&1; then
      _missing="$_missing $dep"
    fi
  done
  if [ -n "$_missing" ]; then
    echo "오류: 필수 의존성 부재 →$_missing" >&2
    echo "  설치 후 AWA 가 런타임에 침묵 실패합니다. 위 도구를 먼저 설치하세요." >&2
    exit 1
  fi
fi

# 2) 기존 심링크 경고 (개발자 심링크 위 cp 덮어쓰기 방지)
if [ -L "$DEST" ]; then
  echo "경고: $DEST 가 심링크입니다(개발자 설치). cp 설치를 중단합니다." >&2
  echo "  심링크를 먼저 제거하거나 다른 DEST 를 지정하세요." >&2
  exit 1
fi

# 3) cp + 영역 가이드 제외 (tar 파이프 — 중첩 깊이 무관 제외)
mkdir -p "$DEST"
( cd "$SRC" && tar -c \
    --exclude='*/AGENTS.md' --exclude='*/CLAUDE.md' \
    --exclude='*/LEARNED_CAUTIONS.md' --exclude='./AGENTS.md' \
    --exclude='./CLAUDE.md' --exclude='./README.md' \
    --exclude='.git*' --exclude='.DS_Store' . ) | ( cd "$DEST" && tar -x )

# 4) 제외 검증 (silent 실패 차단)
_leaked="$(find "$DEST" \( -name 'AGENTS.md' -o -name 'CLAUDE.md' -o -name 'LEARNED_CAUTIONS.md' \) | wc -l | tr -d ' ')"
if [ "$_leaked" != "0" ]; then
  echo "오류: 영역 가이드 $_leaked 개가 설치본에 유출됨 — tar 제외 실패." >&2
  exit 1
fi

# 5) dry-check 검증 (실행 엔진 무결성)
if [ "$NO_DEPS" = "0" ]; then
  if ! bash "$DEST/harness/bin/awa-up.sh" --workers "dev:engineer" --dry-check >/dev/null 2>&1; then
    echo "오류: 설치본 dry-check 실패 — 실행 엔진 누락 가능." >&2
    exit 1
  fi
fi

# 6) 상태 디렉토리 시드
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/awa"

echo "AWA 설치 완료: $DEST"
