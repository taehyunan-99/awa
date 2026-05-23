#!/usr/bin/env bash
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --project 옵션 파서 (E7·F2). lib.sh source 이전 실행 — T6/T8/T9 와 동일.
_normalize_project_arg() {
  local raw="${1:-}"
  if [ -z "$raw" ]; then
    echo "오류: --project 인자 누락 (값 필요)" >&2
    return 1
  fi
  if [ ! -d "$raw" ]; then
    echo "오류: --project 경로 없음: $raw" >&2
    return 1
  fi
  ( cd "$raw" && pwd )
}
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      if ! HARNESS_PROJECT="$(_normalize_project_arg "${2:-}")"; then exit 1; fi
      export HARNESS_PROJECT; shift 2 ;;
    --project=*)
      if ! HARNESS_PROJECT="$(_normalize_project_arg "${1#--project=}")"; then exit 1; fi
      export HARNESS_PROJECT; shift ;;
    *) break ;;
  esac
done

source "$_DIR/lib.sh"
[ "$PROJECT_ROOT_VALID" = "1" ] || exit 1

SESSION="$(resolve_session)"

# 세션 종료 (있으면) — marker 유무와 무관하게 사용자가 종료 의도. R4: 중복 kill 제거.
if tmux has-session -t "$SESSION" 2>/dev/null; then
  # || true: kill-session 실패(권한 등) 가 set -e 로 이후 state 정리를 스킵하지 않도록.
  tmux kill-session -t "$SESSION" || true
  echo "세션 '$SESSION' 종료."
else
  echo "세션 '$SESSION' 없음 (이미 정리됨)."
fi

# E8·F8: marker 없는 PROJECT_ROOT 의 .agent-harness/·settings.json 보호.
# 우연히 만들어진 디렉터리·사용자 자료를 건드리지 않기 위함.
MARKER="$PROJECT_ROOT/.claude/.agent-harness-marker"
if [ ! -f "$MARKER" ]; then
  echo "경고: marker 없음 ($MARKER) — '$PROJECT_ROOT' 는 하네스로 가동된 적 없는 것으로 판단." >&2
  echo "  .agent-harness/·settings.json 은 건드리지 않음 (세션은 위에서 종료됨)." >&2
  _alive="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^agents-' || true)"
  if [ -n "$_alive" ]; then
    echo "  참고: 살아있는 agents-* 세션:" >&2
    echo "$_alive" | sed 's/^/    /' >&2
    echo "  특정 프로젝트 종료: '--project /path' 명시" >&2
  fi
  exit 0
fi

# marker 있으면 정상 정리. 부트스트랩 합본은 런타임 산출물 → 정리. tasks/results 보존.
if [ -d "$WORKSPACE/.boot" ]; then
  rm -f "$WORKSPACE/.boot"/*.md 2>/dev/null || true
  echo "$WORKSPACE/.boot 정리 완료."
fi

# 하네스 런타임 산출물(events.log·리뷰 커서·메인 상태·리뷰 결과)도 정리.
if [ -f "$WORKSPACE/events.log" ]; then
  rm -f "$WORKSPACE/events.log" || true
fi
if [ -f "$WORKSPACE/.harness-state" ]; then
  rm -f "$WORKSPACE/.harness-state" || true
fi
# .review-cursor.*/.harness-task.* 글롭: bash 3.2 환경에서 2>/dev/null || true 로 안전 처리.
rm -f "$WORKSPACE"/.review-cursor.* 2>/dev/null || true
rm -f "$WORKSPACE"/.harness-task.* 2>/dev/null || true
if [ -d "$WORKSPACE/review" ]; then
  rm -rf "${WORKSPACE:?WORKSPACE unset}/review" || true
fi

# 4차 P0: 워커별 settings 사본·권한 로그·lead 커서 정리.
if [ -d "$WORKSPACE/.boot-settings" ]; then
  rm -rf "${WORKSPACE:?WORKSPACE unset}/.boot-settings" || true
fi
rm -f "$WORKSPACE/permission-events.log" "$WORKSPACE/.lead-perm-cursor" 2>/dev/null || true

# 6차: state 디렉터리 정리 (marker 게이트 안 — 하네스 산출물만, 데몬 폐기).
STATE_DIR="${WORKSPACE}/state"
rm -rf "${STATE_DIR:?STATE_DIR unset}/pending-asks" \
       "${STATE_DIR}/incidents" \
       "${STATE_DIR}/removal-requests" 2>/dev/null || true
rm -f "${STATE_DIR}/permission-gate.log" 2>/dev/null || true
rmdir "${STATE_DIR}" 2>/dev/null || true

# settings.json + marker 정리 (marker 자체도 마지막에). 다음 team-up 이 재생성.
rm -f "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null || true
rm -f "$MARKER" 2>/dev/null || true

echo "하네스 런타임 산출물 정리 완료 (tasks/results 보존)."
