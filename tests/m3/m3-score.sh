#!/usr/bin/env bash
# M3 자동 채점 (토큰0). m3-setup.sh 가 띄운 세션의 LEAD 종합 결과(.harness-state)를
# 기대 매핑과 대조해 오배달 3모드를 결정론적으로 판정한다.
#
# 기대 매핑 (setup 의 MARKERS 와 동일 순서):
#   T1:ALPHA T2:BRAVO T3:CHARLIE T4:DELTA T5:ECHO T6:FOXTROT
#
# 판정 모드:
#   F-혼선 : 'T<n>:' 의 마커가 기대값과 다름 (task A 결과를 B 로 잘못 귀속)
#   F-누락 : 기대 6개 중 .harness-state 에 없는 task (done 일부 종합 누락)
#   F-환각 : .harness-state 에 기대에 없는 task/마커가 있음 (안 읽은 것 끼워넣음)
# 셋 다 0 → M3 PASS (LEAD 오배달 0 = 매니저 불필요가 신호배선+판단품질 양쪽으로 완결).
#
# 사용: bash m3-score.sh [PROJECT_ROOT]
#   인자 없으면 /tmp/m3-last-proj (setup 이 남김) 에서 읽음.
set -uo pipefail
cd "$(dirname "$0")"
source ../assert.sh

PROJ="${1:-}"
[ -z "$PROJ" ] && PROJ="$(cat /tmp/m3-last-proj 2>/dev/null || true)"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "오류: PROJECT_ROOT 미상. 인자로 경로 주거나 m3-setup.sh 를 먼저 실행." >&2
  exit 1
fi
WS="$PROJ/.agent-harness"
STATE="$WS/.harness-state"

EXPECTED="T1:ALPHA T2:BRAVO T3:CHARLIE T4:DELTA T5:ECHO T6:FOXTROT"

if [ ! -f "$STATE" ]; then
  echo "오류: $STATE 없음 — LEAD 가 아직 종합을 안 썼다(대기 더 필요) 또는 형식 미준수." >&2
  echo "  세션 확인: tmux attach -t $(cat "$WS/.session" 2>/dev/null || echo '?')" >&2
  exit 1
fi

# .harness-state 에서 'T<n>: <marker>' 라인만 추출 → 'Tn:MARKER' 정규화(공백제거·대문자).
# LEAD 가 머리말/설명을 섞어도 이 패턴 라인만 골라낸다(관대 파싱, 단 마커는 기대집합으로 검증).
got="$(grep -oE 'T[0-9]+[[:space:]]*:[[:space:]]*[A-Za-z]+' "$STATE" 2>/dev/null \
       | sed -E 's/[[:space:]]//g' | tr 'a-z' 'A-Z' | sort -u || true)"

confusion=""   # F-혼선: task 있으나 마커 틀림
missing=""     # F-누락: 기대 task 가 got 에 없음
for pair in $EXPECTED; do
  t="${pair%%:*}"; m="${pair##*:}"
  line="$(printf '%s\n' "$got" | grep -E "^${t}:" || true)"
  if [ -z "$line" ]; then
    missing="$missing $t"
  elif [ "$line" != "${t}:${m}" ]; then
    confusion="$confusion ${t}(기대 ${m}→실제 ${line#*:})"
  fi
done

# F-환각: got 의 task 중 기대 task 집합(T1..T6)에 없는 것.
expected_tasks="$(printf '%s\n' $EXPECTED | sed -E 's/:.*//' | sort -u)"
got_tasks="$(printf '%s\n' "$got" | sed -E 's/:.*//' | grep -E '^T[0-9]+$' | sort -u || true)"
hallucination="$(comm -13 <(printf '%s\n' "$expected_tasks") <(printf '%s\n' "$got_tasks") | tr '\n' ' ' | sed 's/ *$//')"

confusion="${confusion# }"; missing="${missing# }"

# --- 결과 파일 (heavy-task-offload: 요약만) ---
RESULT="${M3_RESULT:-$WS/m3-result.txt}"
{
  echo "# M3 LEAD 종합 귀속 채점 ($(date -u +%FT%TZ))"
  echo "PROJECT_ROOT: $PROJ"
  echo "기대 매핑: $EXPECTED"
  echo "LEAD .harness-state 추출:"
  printf '%s\n' "$got" | sed 's/^/  /'
  echo "## 판정"
  echo "F-혼선(잘못 귀속): [${confusion:-없음}]"
  echo "F-누락(종합 빠짐): [${missing:-없음}]"
  echo "F-환각(없는 것 끼임): [${hallucination:-없음}]"
} > "$RESULT"

# --- 회차 누적 기록 (2~3회 재현 추적) ---
# 각 채점 결과를 한 줄로 append → 여러 회차 재현을 한눈에 (M1·M4 의 "3회 재현" 수준 격상).
RUNS_LOG="${M3_RUNS_LOG:-/tmp/m3-runs.log}"
if [ -z "$confusion" ] && [ -z "$missing" ] && [ -z "$hallucination" ]; then
  verdict="PASS (오배달0)"
else
  verdict="FAIL (혼선:[${confusion:-}] 누락:[${missing:-}] 환각:[${hallucination:-}])"
fi
printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$verdict" "$PROJ" >> "$RUNS_LOG"

# --- assert ---
echo "=== M3 채점 결과 ==="
assert_eq "" "$confusion"     "F-혼선 0 (각 task 결과가 올바른 task 에 귀속)"
assert_eq "" "$missing"       "F-누락 0 (done 6개 모두 종합)"
assert_eq "" "$hallucination" "F-환각 0 (안 읽은 task 안 끼움)"
echo "결과 파일: $RESULT"
echo "--- 누적 회차 ($RUNS_LOG) ---"
cat "$RUNS_LOG" 2>/dev/null | sed 's/^/  /'
test_summary
