#!/usr/bin/env bash
# 테스트용 가짜 워커: stdin 으로 "<boot파일> 를 읽고..." 와 "TASK <id>" 를 받음.
# TASK 라인을 만나면 결과 파일 쓰고 wait-for -S 신호.
# 인자: <워커이름> <세션명>
# 결과 파일/채널명은 T12 분리 규약을 따른다:
#   결과: $PWD/.agent-harness/results/<id>.md (워커 pane cwd=PROJECT_ROOT)
#   채널: done-<세션>-<워커>-<id>
set -uo pipefail
WORKER="$1"
SESSION="$2"
while IFS= read -r line; do
  case "$line" in
    "TASK "*)
      id="${line#TASK }"
      mkdir -p ".agent-harness/results"
      {
        echo "# 결과 $id"
        echo "상태: SUCCESS"
        echo "워커: $WORKER"
      } > ".agent-harness/results/$id.md"
      tmux wait-for -S "done-$SESSION-$WORKER-$id"
      ;;
  esac
done
