관리 작업: .agent-harness/review/ 디렉터리에서 `.harness-state` 에 처리 완료로 표시되지 않은 VIOLATION 파일(verdict=VIOLATION)이 있는지 확인하라. 있으면 해당 워커·task 를 파악해 severity 를 보고 개입 판단(high → 워커 pane 에 중단/수정 send-keys, low → .harness-state 기록 후 사용자 보고)을 하라. 처리한 review 파일은 .harness-state 에 처리 완료로 표시해 중복 개입을 막아라. 사용자의 새 명령이 있으면 그 명령을 우선 처리하라. 단계 자동 전이는 절대 하지 마라.

## 권한 이벤트 감지 (P0 신규)

매 사이클 다음을 추가 처리:

### permission-events.log 감지
1. `.agent-harness/.lead-perm-cursor` 의 숫자 N (없으면 0) 읽음.
2. `.agent-harness/permission-events.log` 의 0-based 라인 오프셋 N 부터 새 줄 검사.
3. 각 줄 6 필드 `ts\tworker\t-\tPRE\ttool\tcmd`:
   - worker=dev|test|reviewer + tool=Bash
   - cmd 가 settings.deny 패턴 매치 시도 (`^rm `, `^git push `, `^/usr/bin/rm `, `^/bin/rm `, `^gh pr `)
     → 사용자 한 줄 보고: "<worker> 위험 명령 시도 차단: <cmd 첫 80자>"
   - worker=reviewer (어떤 명령이든) → 사용자 한 줄 보고: "리뷰어가 Bash 호출 시도 (prompt 위반): <cmd 첫 80자>"
4. .lead-perm-cursor 를 처리 후 라인 수로 갱신.

### events.log 의 reviewer Write 위반 감지
1. events.log 새 줄 검사 (.review-cursor.lead 또는 별도 cursor).
2. worker=reviewer + 4번째 필드=modify + 5번째 필드 (rel) 가 `review/` 시작 아님 → 위반.
3. 사용자 보고: "리뷰어가 review/ 외 Write: <rel>".

### 처리 원칙
- 단순 보고만 — 자동 개입 (send-keys 등) 안 함. 사용자가 결정.
- PRE 줄에서 deny 미매치 (단순 Bash 호출, 예: ls) 는 *무시*. 폭주 방지.
- 후속 사이클에서 빈도 분석·자동 차단 검토.

## 5차 lead gateway: 사이클 통합 처리 순서

매 사이클 시작 시 *순서대로* 실행. dedup 메모리는 사이클 안 임시 (영구 저장 X):

### 1단계. state/pending-asks/ 처리 (회색 영역 사용자 위임)
`ls .agent-harness/state/pending-asks/*.json 2>/dev/null` 확인
- 각 항목마다 AskUserQuestion:
  질문: "<worker> 가 <tool>(<input>) 호출. 허용?"
  선택지 (기본 권장 첫 항목): "명령군 허용 (권장) / 정확 허용 / 도구 전체 허용 / 한 번만 / 거부"
- `.response` 파일에 `approve-permanent:command-group` (또는 exact/tool, `approve-once`, `deny`) 기록
  (경로: `.agent-harness/state/pending-asks/<uuid>.response`)

### 2단계. permission-events.log 폴링 (4차 P0 흐름 유지 — 변경 없음)
4차 P0 의 "permission-events.log 감지" 그대로 수행 (`.lead-perm-cursor` 사용). 각 보고 항목의 식별 tuple `(ts_epoch, worker, cmd 첫 80 bytes)` 를 사이클 임시 메모리(`processed_tuples` 배열)에 기록. permission-events.log 의 ts 는 ISO 8601 → `iso_to_epoch` 로 변환.

### 3단계. state/incidents/ 처리 (5차 danger-check 자동 거부 보고) — dedup
`ls .agent-harness/state/incidents/*.json 2>/dev/null` + `jq '.notified==false'` 필터
- 각 항목의 tuple `(timestamp[epoch], worker, input 첫 80 bytes)` 를 2단계 메모리와 비교
  - 매칭됨 → skip + `.notified=true` (jq atomic: `jq '.notified=true' f > f.tmp && mv f.tmp f`)
  - 매칭 안 됨 → AskUserQuestion (informational):
    "<worker> 가 <category> 시도 (`<command>`) → 자동 차단됨. 후속 조치?"
    선택지: "무시 (계획 정상) / 워커에게 다른 방식 지시 / 매트릭스 정확 보강 (예외 등록)"
  - 매트릭스 정확 보강 선택 시 `add_to_allow` 의 *정확 패턴만* 추가 (danger 카테고리 유지)
  - 처리 후 `.notified=true`

**dedup tuple 형식**:
- ts: epoch seconds 정수 통일. permission-events.log 의 ISO → `iso_to_epoch`. incident 의 timestamp 는 이미 epoch.
- worker: 두 소스 모두 entry_name (settings WORKER 토큰화로 통일).
- cmd prefix: `head -c 80` (80 bytes).

**ISO→epoch 변환 (BSD/macOS) + 가드**:
```bash
iso_to_epoch() {
  local iso="$1" result
  result=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$iso" +%s 2>/dev/null)
  [ -z "$result" ] && return 1
  printf '%s' "$result"
}

perm_epoch=$(iso_to_epoch "$perm_ts") || {
  printf 'warn: permission-events.log ts 변환 실패: %s\n' "$perm_ts" >> .agent-harness/state/watch-asks.log
  continue
}
incident_epoch=$(jq -r .timestamp "${incident_file}")
abs_diff=$(( perm_epoch > incident_epoch ? perm_epoch - incident_epoch : incident_epoch - perm_epoch ))
perm_cmd_80=$(printf '%s' "${perm_cmd}" | head -c 80)
incident_cmd_80=$(printf '%s' "${incident_cmd}" | head -c 80)
if [ "$abs_diff" -le 60 ] && [ "$perm_worker" = "$incident_worker" ] && [ "${perm_cmd_80}" = "${incident_cmd_80}" ]; then
  skip=true
fi
```
ts 윈도우 60s (log-deny PreToolUse 와 watch-asks incident 폴링 지연 + 사이클 간격 흡수). 사이클 임시 유지 (F35).

### 4단계. state/removal-requests/ 처리 (rm 위임)
`ls .agent-harness/state/removal-requests/*.json 2>/dev/null` + `jq '.status=="pending"'`
- 각 항목마다 AskUserQuestion: "승인 / 거부 / 재고"
- 승인 시 자기 pane 에서 `rm <path>` 실행 (lead settings 의 `Bash(rm:*)` allow) + status=done
- 거부 시 status=denied
- 재고 시 status=reconsider + 다음 워커 dispatch 메시지에 추가 정보 요청 포함

### dedup 메모리 구현
사이클 시작 시 빈 배열 `processed_tuples=()`. 2단계 각 보고 후 append. 3단계 각 incident 처리 전 순회 비교. 사이클 종료 시 폐기.

## watch-asks 살아있는지 점검 (사이클 시작 시)

`kill -0 $(cat .agent-harness/state/watch-asks.pid) 2>/dev/null` 실패 시:
- 사용자에게 AskUserQuestion: "watch-asks 데몬 사망. 재기동?"
- Yes → 자기 settings 의 watch-asks.sh allow 패턴에 적힌 절대경로로 `PROJECT_ROOT=<루트> HARNESS_ROOT=<하네스> nohup bash <그 절대경로> &` 실행
- No → 사용자가 수동 처리할 때까지 워커 자동 응답 없음 (사용자가 워커 pane 직접 응답 가능)

## 워커 rm 위임

워커는 rm 직접 호출 금지. 자기 pane stdout 에:
- `@lead: rm <path> — <reason>` (단일 파일)
- `@lead: rm-r <path> — <reason>` (재귀)
- `@lead: remove-dir <path> — <reason>` (디렉터리)

lead 가 위 4단계에서 발견 + 사용자 승인 후 직접 처리.
