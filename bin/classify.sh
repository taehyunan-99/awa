#!/usr/bin/env bash
# classify <entry_role> <tool> <input_json> → stdout "verdict<TAB>detail", 항상 rc=0.
#   danger <TAB> <category>
#   matrix <TAB> <pattern>
#   auto   <TAB> <category><TAB><pattern>     (detail 이 다시 TAB 2단 — colon 충돌 회피)
#   gray   <TAB> ""
# ★ 평가 순서 = danger → matrix → auto → gray (3차 리뷰 권한상승 차단).
#   danger 를 *맨 먼저* — 학습된 settings.allow(matrix) 에 위험 패턴이 끼어들어도
#   (예: 실수로 Bash(sudo:*) 학습) danger_check 가 먼저 deny. matrix 우선이면 위험명령이
#   학습 allow 로 우회되는 권한상승 경로가 생긴다. danger 는 어떤 allow 보다 우선.
# ★ 구분자 TAB 고정: claude pattern(Bash(ls:*))·command 에 colon 흔함 → colon 구분 금지.
# source 시 부수효과 0 (함수 정의만). matrix-lookup.sh + danger-check.sh 를 호출자가 source.
classify() {
  local entry_role="$1" tool="$2" input="$3" m c cp T
  T=$'\t'
  if c="$(danger_check "$tool" "$input")"; then printf 'danger%s%s' "$T" "$c"; return 0; fi
  if m="$(matrix_lookup "$entry_role" "$tool" "$input")"; then printf 'matrix%s%s' "$T" "$m"; return 0; fi
  if cp="$(lead_auto_allow_lookup "$tool" "$input")"; then
    # lead_auto_allow_lookup 은 "category:pattern" 반환. category 는 colon 없는 yaml 키 →
    # 첫 colon 으로만 분리, pattern 내부 colon 보존. TAB 으로 재포맷.
    printf 'auto%s%s%s%s' "$T" "${cp%%:*}" "$T" "${cp#*:}"; return 0
  fi
  printf 'gray%s' "$T"; return 0
}
