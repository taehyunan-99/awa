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
