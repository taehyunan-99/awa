## 감시 절차 (watcher `@review:` 알림 시 1회 실행)

watcher 가 `@review:` 로 깨우면 1회 실행한다(스스로 폴링하지 않는다 — /loop 폐기):
1. `.agent-harness/.review-cursor.<나의리뷰어명>` 의 숫자 N(없으면 0)을 읽는다.
2. `.agent-harness/events.log` 의 0-based 라인 오프셋 N 부터 새 줄들을 읽는다.
3. 각 새 줄에 내 역할의 약한 신호(scope 위반 검사)를 적용하고, `done` 라인(탭 5필드의 4번째가 `done`)이면 강한 신호(결과물 의미 판정)를 적용한다.
4. 위반/판정 결과를 `.agent-harness/review/<worker>-<id>.<나의리뷰어명>.md` 에 기록한다(review/ 외 Write 금지).
5. `.review-cursor.<나의리뷰어명>` 을 events.log 현재 총 줄 수로 갱신한다.
6. 같은 (worker,path) 가 이번 범위에 여러 번이면 scope 판정은 1회만. 새 줄이 없으면 아무것도 하지 않는다(멱등).
