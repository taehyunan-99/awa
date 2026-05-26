# tests — bash 테스트 + 통합 probe + 시나리오

`run-all.sh`가 `test-*.sh`를 일괄 실행하며 `RUN_INTEGRATION=1`이면 `probes/`(claude CLI 의존)까지 실행. 시나리오 하위(lead-arena/m3/probes/role5axis/stress)는 도메인별 별도 러너를 갖는다.

**Tradeoff**: 외부 테스트 프레임워크(bats 등) 미사용 → bash + `tests/assert.sh`만으로 어디서나 실행 가능, 단 fixture/setUp 추상화는 각 테스트가 직접 작성.

## 1. WHAT

agenphony 하니스의 회귀 방지층 — 단위 테스트(test-*.sh) 87개, 통합 probe(probes/) 25+개, 도메인 시나리오(lead-arena/m3/role5axis/stress).

## 2. CONTENTS

- `run-all.sh` — 진입 러너. `test-*.sh` 순회 + `RUN_INTEGRATION=1`이면 `probes/`도 실행. 종료코드로 통과/실패 전달
- `assert.sh` — 공통 어서션 헬퍼
- `dummy-worker.sh`, `e2e-dryrun.sh` — fixture/드라이런 도우미
- `test-*.sh` — 단위 테스트 87개(분류·dispatch·debounce·prompt token·권한·세션·rm 정책 등)
- `probes/` — claude CLI 의존 통합 probe (deny pattern, hook merge, permission-gate, plan injection 등)
- `lead-arena/` — lead 후보 비교 실험(`arena-run.sh`/`arena-score.sh` + RESULTS.md + 자극/응답 키)
- `m3/` — m3 시나리오 setup/teardown/score
- `role5axis/` — 5축 역할 평가 시나리오
- `stress/` — 스트레스 러너(`stress-run.sh` + `stress-lib.sh`)
- `unit/` — 추가 단위 테스트 디렉토리(run-all이 후순으로 순회)

기술 스택: bash, claude CLI(통합 시), tmux(일부 probe)

## 3. HOW

_(update 스킬에서 채워질 자리. 작업 중 패턴이 정립되면 `/update`로 인터뷰 진행)_

## 4. ⛔ HOW NOT

_(update 스킬에서 채워질 자리. 사용자 결정 사항이므로 init은 비워둔다)_

## 5. WHERE

- **의존**: 거의 모든 영역(테스트 대상)
  - [`bin/`](../bin/) — 도구·함수 단위 검증
  - [`prompts/`](../prompts/) — boot-tokens / role5axis
  - [`templates/`](../templates/) — settings 머지/디폴트
  - [`config/`](../config/) — matrix 파서 / permission-gate
- **피의존**: (없음 — 최하위 검증층)
- **경계 / 어댑터**:
  - 각 `test-*.sh`는 마지막에 `test_summary` 호출(`assert.sh` 제공)로 종료코드 전달
  - `RUN_INTEGRATION=1` 환경변수가 통합 probe 게이트
  - lead-arena 결과: `RESULTS.md` 헤더 `status:` 검사로 채점(아니라 `.harness-state` 아님 — 최근 commit 참고)

## 6. WHY

_(update 스킬에서 채워질 자리. 사용자 결정 사항이므로 init은 비워둔다)_

## 7. COMMANDS

```bash
# 단위 테스트 일괄
bash tests/run-all.sh

# 통합 probe까지
RUN_INTEGRATION=1 bash tests/run-all.sh

# 개별 테스트
bash tests/test-dispatch.sh
bash tests/probes/probe-permission-gate.sh

# 시나리오
bash tests/lead-arena/arena-run.sh && bash tests/lead-arena/arena-score.sh
bash tests/stress/stress-run.sh
```

_(영역 고유 가드는 update에서 추가)_

## 8. ⚠️ LEARNED CAUTIONS

@./LEARNED_CAUTIONS.md

자세한 내용은 [LEARNED_CAUTIONS.md](./LEARNED_CAUTIONS.md) 참조.
