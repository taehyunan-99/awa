# lead/pm 축 라이브 수동 체크리스트

자동 하니스 없음 — 사용자가 `!` 로 1회 부트 후 육안 확인. (실험은 lead-arena 에서 완료; 이건 본구현 sanity.)

## 부트
`! bash bin/agenphony-up.sh <profile>` (격리 PROJECT_ROOT 권장).

## lead 트리거 확인 (승자 구조 기준)
- [ ] 부트 직후 lead idle — 스스로 출력·폴링 안 함.
- [ ] `@pm: <간단 작업>` → 분해·배정 트리·dispatch.
- [ ] 워커 `@done:` → lead 가 results 종합, `.harness-state` 기록(화면엔 한 줄). 판단 필요할 때만 풀 출력.
- [ ] 회색 명령 → `@gate:` → AskUserQuestion 후 `.response`.
- [ ] 리뷰 VIOLATION → 워커 pane send-keys 개입. / 워커 `@lead: rm` → removal-requests 처리.
- [ ] "다음 단계 시작?" → 자동전이 안 하고 pm 지시 대기.

## pm 확인
- [ ] "어떻게 돼가?" → events.log·results·.harness-state 읽어 답. 기록 없는 건 "아직 없음"(추측 단정 안 함).
- [ ] 사용자 요청 → `@pm:` 로 lead 에 전달(파일 안 씀).
