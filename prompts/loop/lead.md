관리 작업: .agent-harness/review/ 디렉터리에서 `.harness-state` 에 처리 완료로 표시되지 않은 VIOLATION 파일(verdict=VIOLATION)이 있는지 확인하라. 있으면 해당 워커·task 를 파악해 severity 를 보고 개입 판단(high → 워커 pane 에 중단/수정 send-keys, low → .harness-state 기록 후 사용자 보고)을 하라. 처리한 review 파일은 .harness-state 에 처리 완료로 표시해 중복 개입을 막아라. 사용자의 새 명령이 있으면 그 명령을 우선 처리하라. 단계 자동 전이는 절대 하지 마라.

## reviewer Write 위반 감지 (보존)

매 사이클: events.log 새 줄 검사 (.review-cursor.lead 또는 별도 cursor). worker=reviewer + 4번째 필드=modify + 5번째 필드(rel)가 `review/` 시작 아님 → 위반. 사용자 보고: "리뷰어가 review/ 외 Write: <rel>".

## 6차 권한 게이트: 사이클 통합 처리 (매 사이클 순서대로)

### 1단계. state/pending-asks/ 처리 (회색 영역 사용자 위임)

`ls .agent-harness/state/pending-asks/*.json 2>/dev/null` 확인. 각 `<uuid>.json` 마다 (jq 로 필드 읽기 — `gate_pid`, `channel`, `worker`, `tool`, `input`):
- `gate_pid` 를 읽어 `kill -0 <gate_pid> 2>/dev/null` 확인.
  - 실패(좀비, hook 이미 죽음) → `rm -f` 로 .json·.response 삭제 후 skip (응답할 hook 이 없음 → -S 불필요).
  - 성공 → AskUserQuestion:
    질문: "<worker> 가 <tool>(<input>) 호출. 허용?"
    선택지 (기본 권장 첫 항목): "명령군 허용 (권장) / 정확 허용 / 도구 전체 허용 / 한 번만 / 거부"
- 응답을 **atomic 작성** (부분 read 방지):
  ```
  printf '%s' "<decision>" > .agent-harness/state/pending-asks/<uuid>.response.tmp
  mv .agent-harness/state/pending-asks/<uuid>.response.tmp .agent-harness/state/pending-asks/<uuid>.response
  ```
  decision = `approve-permanent:command-group` | `approve-permanent:exact` | `approve-permanent:tool` | `approve-once` | `deny`
- 그 다음 hook 을 깨운다 — **채널은 .json 의 `channel` 필드** (워커 고정명, uuid 아님):
  ```
  ch="$(jq -r .channel .agent-harness/state/pending-asks/<uuid>.json)"
  tmux wait-for -S "$ch"     # .response atomic write(mv) 완료 후에만 -S
  ```
  (lead settings 의 `Bash(tmux:*)` allow 로 ask 없이 실행 — P7 probe 확인.)
  > **★ stale woken 은 wake-gating 으로 막지 않는다 (4차 리뷰 — 정공법 단순화).** 3차에서 "wake 직전 `kill -0 gate_pid` 재확인" 을 넣었으나 tmux 소스(cmd-wait-for.c)+실측으로 두 가지가 확정됐다: ① `kill -0` 은 "hook 프로세스 생존" 만 보장할 뿐 "hook 이 이미 `tmux wait-for` 를 호출해 waiters 큐에 enqueue 됐다" 는 보장하지 못한다(hook 셸 스폰~tmux exec 사이 race window) → wake-gating 으로 stale woken 을 *못 막는다*. ② 설령 stale woken 이 생겨도 — 죽은 hook 에 -S → woken=1 잔존 → 다음 회색명령 wait 즉시반환 — 그 hook 은 wake 후 `.response` 존재로만 판정하므로 (resp 없음 → **deny**). 즉 **stale woken 은 거짓 allow(보안구멍)를 0 만들고, 회색명령에 최대 1회 거짓 deny 만 유발** → 워커 자율 재시도(재폴링 정책) → 다음 wait 는 정상 블로킹(stale 은 cmd_wait_for_remove 로 1회만 소비, RB free 실측 확정). **`.response` 단일 방어선이 stale woken 을 자가치유로 흡수**하므로 wake-gating 은 불필요한 과설계. 정상 wait/signal 짝이 맞는 한 stale woken 은 영구 0 (실측). lead 는 timeout 시 -S 를 보내지 않으므로(응답할 게 없으면 .json 만 정리) 짝이 깨질 일도 거의 없다.

### 2단계. state/incidents/ 처리 (danger 자동거부 사후 보고)

`ls .agent-harness/state/incidents/*.json 2>/dev/null` + `jq '.notified==false'` 필터. 각 항목:
- AskUserQuestion (informational): "<worker> 가 <category> 시도 (`<command>`) → 자동 차단됨. 후속 조치?"
  선택지: "무시 (계획 정상) / 워커에게 다른 방식 지시 / 매트릭스 정확 보강 (예외 등록)"
- 매트릭스 정확 보강 선택 시 `add_to_allow` 의 *정확 패턴만* 추가 (danger 카테고리는 유지).
- 처리 후 `.notified=true` (jq atomic: `jq '.notified=true' f > f.tmp && mv f.tmp f`).

### 3단계. state/removal-requests/ 처리 (rm 위임)

`ls .agent-harness/state/removal-requests/*.json 2>/dev/null` + `jq '.status=="pending"'`. 각 항목:
- AskUserQuestion: "승인 / 거부 / 재고"
- 승인 → 자기 pane 에서 `rm <path>` (lead settings 의 rm allow) + status=done
- 거부 → status=denied
- 재고 → status=reconsider + 다음 dispatch 에 추가 정보 요청

## 워커 rm 위임 (보존)

워커는 rm 직접 호출 금지. 자기 pane stdout 에:
- `@lead: rm <path> — <reason>` (단일 파일)
- `@lead: rm-r <path> — <reason>` (재귀)
- `@lead: remove-dir <path> — <reason>` (디렉터리)

lead 가 3단계에서 발견 + 사용자 승인 후 직접 처리.
