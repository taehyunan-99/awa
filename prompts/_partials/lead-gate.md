## 권한 게이트 처리 (`@gate:` 알림 시 — 매번 pending-asks 전수 처리)

watcher 가 `@gate:` 로 깨우면, 단건이 아니라 `pending-asks/*.json` **전체**를 훑어 처리한다(단건 유실이 정체로 안 번지게).

### 1단계. state/pending-asks/ 처리 (회색 영역)
`ls .agent-harness/state/pending-asks/*.json 2>/dev/null` 확인. 각 `<uuid>.json` 마다 (jq 로 `gate_pid`,`channel`,`worker`,`tool`,`input` 읽기. `<uuid>` = .json basename 에서 확장자 뗀 값):
- `gate_pid` 를 `kill -0 <gate_pid> 2>/dev/null` 확인.
  - 실패(좀비) → `rm -f` 로 .json·.response 삭제 후 skip(-S 불필요).
  - 성공 → AskUserQuestion:
    질문: "<worker> 가 <tool>(<input>) 호출. 허용?"
    선택지(기본 권장 첫 항목): "명령군 허용 (권장)" → `approve-permanent:command-group` / "정확 허용" → `approve-permanent:exact` / "도구 전체 허용" → `approve-permanent:tool` / "한 번만" → `approve-once` / "거부" → `deny`
- 응답 **atomic 작성**:
  ```
  printf '%s' "<decision>" > .agent-harness/state/pending-asks/<uuid>.response.tmp
  mv .agent-harness/state/pending-asks/<uuid>.response.tmp .agent-harness/state/pending-asks/<uuid>.response
  ```
- hook 깨우기 **불필요**(P11 탈-tmux): `.response` 를 atomic 작성하면 hook 이 그 파일 출현을 직접 폴링해 즉시 판정한다. lead 는 tmux 를 건드리지 마라(격리 경계 안 — tmux 소켓 접근 차단 가능). timeout 으로 처리 불가한 항목은 `.json` 만 정리하면 hook 이 응답없음→deny 로 자가치유.
  > `.response` 단일 방어선: 파일 있으면 그 결정, 없으면 hook 이 deny. 거짓 allow 0. tmux 채널 자체를 안 쓰므로 채널 누수·stale woken 문제도 소멸.

### 2단계. state/incidents/ 처리 (danger 자동거부 사후 보고)
`ls .agent-harness/state/incidents/*.json` + `jq '.notified==false'`. 각 항목:
- AskUserQuestion (informational): "<worker> 가 <category> 시도 (`<command>`) → 자동 차단됨. 후속?" 선택지: "무시 / 워커에 다른 방식 지시 / 매트릭스 정확 보강".
- 정확 보강 선택 시 `add_to_allow` 의 정확 패턴만 추가(danger 카테고리 유지).
- 처리 후 `.notified=true` (atomic: `jq '.notified=true' f > f.tmp && mv f.tmp f`).

### 3단계. state/removal-requests/ 처리 (rm 위임)
`ls .agent-harness/state/removal-requests/*.json` + `jq '.status=="pending"'`. 각 항목:
- AskUserQuestion: "승인 / 거부 / 재고"
- 승인 → 자기 pane 에서 `rm <path>`(lead settings 의 rm allow) + status=done
- 거부 → status=denied / 재고 → status=reconsider
- (status 갱신 atomic: `jq '.status="done"' f > f.tmp && mv f.tmp f`)
