#!/usr/bin/env bash
# 13차+: 스트레스 측정 순수 함수. 세션 의존 0 — 단위 테스트 가능.
# capture-pane 덤프(cat echo 중복 포함)에서 고유 식별자 집합을 뽑아 발생-처리 대조.

# @done 알림 라인에서 'worker/task' 식별자만 뽑아 고유 정렬.
# watcher 송신 형식: "@done: <worker>/<task> 완료. ..."
extract_done_ids() {  # $1=capture 덤프 → 줄당 worker/task, sort -u
  printf '%s\n' "$1" \
    | { grep -oE '@done: [A-Za-z0-9_-]+/[A-Za-z0-9_-]+' || true; } \
    | sed 's/^@done: //' \
    | sort -u
  # grep no-match rc1 흡수 — set -e 호출자(stress-run) 0건 측정 시 사망 방지
}

# @gate 알림 라인에서 uuid 만 뽑아 고유 정렬.
# watcher 송신 형식: "@gate: 워커 승인 대기 (uuid=<uuid>). ..."
extract_gate_ids() {  # $1=capture 덤프 → 줄당 uuid, sort -u
  printf '%s\n' "$1" \
    | { grep -oE 'uuid=[A-Za-z0-9_-]+' || true; } \
    | sed 's/^uuid=//' \
    | sort -u
  # grep no-match rc1 흡수 — set -e 호출자(stress-run) 0건 측정 시 사망 방지
}

# 발생 집합(줄단위) 중 처리 집합에 없는 식별자 (유실). 둘 다 정렬돼 들어온다고 가정 안 함 — 내부 정렬.
# 빈 입력 방어: printf '%s\n' "" 는 빈 줄 1개를 만들어 comm 이 빈줄을 식별자로 오인할 수 있음.
#   grep -v '^$' 로 빈 줄 제거 후 비교 (발생/처리 둘 다 진짜 식별자만).
missing_ids() {  # $1=발생(개행구분) $2=처리(개행구분) → 유실 식별자(개행구분)
  comm -23 \
    <(printf '%s\n' "$1" | grep -v '^$' | sort -u) \
    <(printf '%s\n' "$2" | grep -v '^$' | sort -u)
}

# events.log 에 워커별 done 라인을 append. 워커 i 의 task 는 <prefix><i> (1-based).
# watcher.sh 가 $4=="done" 로 감지하는 탭5필드 형식(ts\tworker\ttask\tdone\t-).
inject_done_lines() {  # $1=events.log $2=워커명(공백구분) $3=task prefix
  local ev="$1" prefix="$3" i=0 w
  for w in $2; do
    i=$((i+1))
    printf '%s\t%s\t%s%s\tdone\t-\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$w" "$prefix" "$i" >> "$ev"
  done
}

# state/pending-asks/ 에 uuid 별 .json 을 생성 (gate 부하).
# watcher.sh 가 *.json 을 감지해 @gate: 주입. 최소 필드만(uuid). uuid 에 점(.) 금지 — extract_gate_ids 패턴과 정합.
inject_pending_asks() {  # $1=pending-asks 디렉터리 $2=uuid(공백구분)
  local dir="$1" u
  mkdir -p "$dir"
  for u in $2; do
    printf '{"uuid":"%s"}\n' "$u" > "$dir/$u.json"
  done
}
