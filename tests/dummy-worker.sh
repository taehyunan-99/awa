#!/usr/bin/env bash
# 테스트용 가짜 워커: stdin 으로 "<boot파일> 를 읽고..." 와 "TASK <id>" 를 받음.
# TASK 라인을 만나면 결과 파일 쓰고 events.log 에 done 라인 append(= 완료 신호).
# 인자: <워커이름> <세션명>
# 결과 파일/완료신호는 탈-tmux 파일 IPC 규약을 따른다(P11 — 워커 tmux 직접호출 0):
#   결과: $PWD/.agent-harness/results/<id>.md (워커 pane cwd=PROJECT_ROOT)
#   완료신호: $PWD/.agent-harness/events.log 에 탭 5필드 done 라인. watcher 가 폴링해 lead 깨움.
set -uo pipefail
WORKER="$1"
SESSION="$2"   # 채널 토큰 호환 유지(미사용 — done 라인이 완료 신호)
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
      # done 라인 = 유일한 완료 신호(tmux 미사용). 필드=탭, 5필드: ts/이름/task/action/필드5.
      printf '%s\t%s\t%s\tdone\t-\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$WORKER" "$id" \
        >> ".agent-harness/events.log"
      ;;
  esac
done
