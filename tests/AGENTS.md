# tests — bash 테스트 + 통합 probe + 시나리오

`run-all.sh`가 `test-*.sh`를 일괄 실행하며 `RUN_INTEGRATION=1`이면 `probes/`(claude CLI 의존)까지 실행. 시나리오 하위(lead-arena/m3/probes/role5axis/stress)는 도메인별 별도 러너를 갖는다.

**Tradeoff**: 외부 테스트 프레임워크(bats 등) 미사용 → bash + `tests/assert.sh`만으로 어디서나 실행 가능, 단 fixture/setUp 추상화는 각 테스트가 직접 작성.

**5어휘 매핑**: drift-tracked ("드리프트 상시 추적") — Layer 1+2 차별화 점검 + 벤치마크

## 1. WHAT

AWA 하니스의 회귀 방지층 — 단위 테스트(test-*.sh) 87개, 통합 probe(probes/) 25+개, 도메인 시나리오(lead-arena/m3/role5axis/stress).

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

- **2층 구조 = Layer 1 (grep) + Layer 2 (동작)** — `check-differentiation-status.sh` · `test-plan-defect-e2e.sh` · `test-review-manager-drift.sh` 공통 패턴. Layer 1 은 파일 존재·grep 토큰 매치 (값싸고 빠름). Layer 2 는 awk 추출·함수 호출·fake 입력 → 실제 동작 검증 (행동 보증). 신규 테스트도 두 층을 분리 작성.
- **events.log fake 라인 = `printf '%s\t...\n'` 탭 5필드 명시** — `event_field` / `event_valid` 계약 정합. 예: `printf '%s\t%s\t%s\tplan-defect\t%s\n' "$ts" "$worker" "$task" "$desc"`. 하드코딩 awk 대신 `event_field` 함수 호출 권장.
- **TMPDIR 격리** — `mktemp -d` + `trap 'rm -rf "$TMPDIR"' EXIT`. yaml 시나리오 테스트 (`test-allow-deny-no-overlap.sh`) 는 `HARNESS_ROOT=$TMPDIR` 로 격리해 운영 yaml 보호.
- **`assert.sh` 계약 정합** — `assert_success` / `assert_eq` / `test_summary` 사용. raw `exit 0/1` 지양 (e924b2e refactor 결정).

## 4. ⛔ HOW NOT

- **동어반복 mock 금지** — case 패턴이 입력의 모든 가능한 값을 매치해 *항상 true* 가 되는 검증 ([예: `for d in "수정" "재개" "취소"; do case "$d" in "수정"|"재개"|"취소") :;; *) ok=0;; esac; done` — 항상 `ok=1`]). 검증 자체가 무의미. 실제 행동 검증으로 대체하거나 사용자/sanity check 로 위임.
- **`sed -i ''` (BSD/macOS 전용) 사용 금지** — GNU sed (`sed -i`) 와 호환 안 됨. 이식성 결함. 대안: `tmp 파일 mv` 패턴 또는 `perl -i -pe`.
- **`run-all.sh` 결과 무시 + 5-commit 단위 대기 금지** — 회귀 발견 단위 축소. 7bbe82e 의 *영어 슬래시 명령어 회귀* 가 5-commit 시점에 발견된 사례. commit 1건당 영향 영역 테스트 실행 권장 (예: `bash tests/test-<관련>.sh`).
- **test 안에서 운영 events.log / yaml 직접 조작 금지** — 항상 `mktemp -d` 격리. `cd7c908` (XDG_CONFIG_HOME 격리) 패턴 일반화 — 사용자 데이터 보호.

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

- **Layer 1 + Layer 2 분리** — *grep 매치 = 행동 보증 아님*. Layer 1 은 *진행도 추적기* 의도 (차별화 자동화 등). Layer 2 는 *실제 동작 검증* (회귀 차단). 두 층을 섞으면 Layer 1 만 PASS 한 항목을 *진짜 PASS* 로 오인 → 허위 PASS 자기참조 회로 (rename-guard G4 사례 — spec §9.4 의 함정).
- **bats 미사용** — `bash` + `tests/assert.sh` 만으로 어디서나 실행 가능. fixture/setUp 추상화는 각 테스트가 직접 작성하나, 외부 의존성 zero. 별도 brew/npm install 없이 신규 개발자 머신에서 즉시 실행.
- **GRACE 카운트 별도** — `grace = 임시 PASS` 가 `영구 PASS` 와 구분되어야 자기참조 차단 무결성 유지. grace 도 PASS 카운트에 포함하면 sanity-log.md 가 *자기 자신을 통과시킴* → 자기참조. 별도 카운트로 *임시성* 명시 (Task 2 C2 결정).

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
