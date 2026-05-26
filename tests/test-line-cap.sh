#!/usr/bin/env bash
# 모든 역할 md (prompts/roles/*/*.md) 는 100줄 이하. _partials/* 는 캡 대상 제외.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
cap=100

for f in "$ROOT"/prompts/roles/*/*.md; do
  [ -e "$f" ] || continue
  n="$(wc -l < "$f" | tr -d ' ')"
  rel="${f#$ROOT/}"
  if [ "$n" -le "$cap" ]; then
    assert_eq "ok" "ok" "$rel = $n 줄 (≤ $cap)"
  else
    assert_eq "≤$cap" "$n" "$rel 가 $cap 줄 초과 ($n)"
  fi
done

test_summary
