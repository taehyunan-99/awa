#!/usr/bin/env bash
# watcher 보조 함수 — source 전용(진입점 없음, lib.sh 계약과 동일).
# watcher.sh 메인 루프에서 source 해 @done ack 큐를 다룬다.
#
# ── @done ack 큐 (pending-done/) ────────────────────────────────────────────
# 결함 배경(2026-06-01 라이브): watcher 가 done 라인 감지 시 @done 을 LEAD pane 에
# send-keys 한 번만 쏘고 last_events 를 올린다. LEAD 가 점유(작업/모달) 중이면 그 입력이
# claude TUI 에서 소실 → 영영 재발화 안 함 → 종합 트리거 유실(회로① 침묵).
# 해결: done 발화 시 pending-done/<worker>__<task>.json 적재(ack 큐). LEAD 는 ⓒ 종합 완료
# 후 그 .json 을 rm(ack). watcher 는 매 사이클 미해소(미ack) 큐를 재발화 → LEAD 가 idle 로
# 돌아온 다음 폴링에 도달. dispatch-queue/pm-queue(파일 IPC)와 동형이되 방향만 watcher→LEAD.

# 파일명 안전화 — worker/task 의 '/' 등을 '_' 로 치환(디렉토리 깨짐·경로 탈출 방지).
_pd_sanitize() {
  # 영숫자·.·-·_ 만 허용, 나머지는 '_'. 빈 입력은 '_' 로.
  local s="$1"
  s="$(printf '%s' "$s" | tr -c 'A-Za-z0-9._-' '_')"
  [ -n "$s" ] || s="_"
  printf '%s' "$s"
}

# done 1건을 ack 큐에 적재(atomic tmp→mv, 멱등). 이미 있으면 mtime 갱신 안 함(디바운스 보존).
#   $1=STATE_DIR  $2=worker  $3=task
enqueue_pending_done() {
  local sd="$1" worker="$2" task="$3"
  [ -n "$sd" ] || return 1
  local dir="$sd/pending-done"
  mkdir -p "$dir" 2>/dev/null || return 1
  local fn; fn="$(_pd_sanitize "$worker")__$(_pd_sanitize "$task").json"
  local path="$dir/$fn"
  # 멱등: 이미 적재돼 있으면 그대로 둔다(mtime 유지 → 재발화 디바운스 누적 보존).
  [ -f "$path" ] && return 0
  local tmp="$path.tmp"
  printf '{"worker":"%s","task_id":"%s"}' "$worker" "$task" > "$tmp" 2>/dev/null || return 1
  mv "$tmp" "$path" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}

# 미해소(미ack) 큐 중 나이≥age_thresh 인 것들을 "<worker>/<task>" 줄로 emit(stdout).
# watcher 가 이 목록으로 LEAD 에 @done 을 재발화한다. emit 후 mtime 을 갱신(touch)해
# 다음 재발화까지 age_thresh 만큼 디바운스(매 사이클 폭주 방지).
#   $1=STATE_DIR  $2=age_thresh(초, 기본 20)
requeue_pending_done() {
  local sd="$1" age_thresh="${2:-20}"
  local dir="$sd/pending-done"
  [ -d "$dir" ] || return 0
  case "$age_thresh" in ''|*[!0-9]*) age_thresh=20 ;; esac
  local now; now="$(date +%s)"
  local f
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    local mt age
    mt="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)"
    case "$mt" in ''|*[!0-9]*) mt=0 ;; esac
    age=$(( now - mt ))
    [ "$age" -ge "$age_thresh" ] || continue
    local worker task
    worker="$(sed -n 's/.*"worker":"\([^"]*\)".*/\1/p' "$f" 2>/dev/null)"
    task="$(sed -n 's/.*"task_id":"\([^"]*\)".*/\1/p' "$f" 2>/dev/null)"
    [ -n "$worker" ] && [ -n "$task" ] || continue
    printf '%s/%s\n' "$worker" "$task"
    # 재발화 디바운스: mtime 을 현재로 밀어 다음 재발화를 age_thresh 만큼 미룬다.
    touch "$f" 2>/dev/null || true
  done
}
