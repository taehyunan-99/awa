#!/usr/bin/env bash
# 테스트용 가짜 워커: stdin 으로 "<boot파일> 를 읽고..." 와 "TASK <id>" 를 받음.
# TASK 라인을 만나면 결과 파일 쓰고 wait-for -S 신호.
# 워커 이름은 인자로 받는다.
set -uo pipefail
WORKER="$1"
ROOT="$2"
while IFS= read -r line; do
  case "$line" in
    "TASK "*)
      id="${line#TASK }"
      echo "# 결과 $id" > "$ROOT/workspace/results/$id.md"
      echo "상태: SUCCESS" >> "$ROOT/workspace/results/$id.md"
      echo "워커: $WORKER" >> "$ROOT/workspace/results/$id.md"
      tmux wait-for -S "done-$WORKER-$id"
      ;;
  esac
done
