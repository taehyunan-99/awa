# prompts — 워커 부트 프롬프트

`_common.md` + `roles/NN-part/<역할>.md` 글롭으로 자동 카탈로그화되는 워커 부트 프롬프트. 코드 수정 없이 새 역할은 파일 추가만으로 등록된다.

**Tradeoff**: 코드 자동 등록을 받아들이는 대신, 역할명은 전 파트에서 고유해야 하고(불변식), 중복 시 `bin/lib.sh::resolve_role_file`가 fail-fast 한다.

**5어휘 매핑**: plan-anchored ("plan 정박") — acceptance criteria 기록·검증·갱신 회로

## 1. WHAT

워커가 가동 시 stdin으로 받는 부트 프롬프트 모음. `{{HARNESS_ROOT}}` / `{{SESSION}}` / `{{WORKER_NAME}}` 토큰은 가동 시 sed 치환된다.

## 2. CONTENTS

- `_common.md` — 모든 워커 공통 부트(작업 사이클·금지·하니스 규약·도구 위치·rm 정책)
- `_partials/lead-gate.md` — lead 전용 권한 게이트 partial
- `roles/01-orchestration/{lead.md,pm.md}`
- `roles/02-development/{dev.md,researcher.md}`
- `roles/03-quality/{reviewer-arch.md,reviewer-common.md,reviewer-quality.md,reviewer-spec.md,review-manager.md,tester.md}`
- `roles/04-security/security.md`

기술 스택: 마크다운(첫 줄 = 한 줄 desc — 5축 형식, `_common.md` 참조)

## 3. HOW

- **신호 N종 진화 = 4곳 동시 갱신** — 신호 1종 추가 시 `lead.md` 신호 목록 + 처리 절(ⓐ~ⓘ) + `_common.md` 신호 토큰 + `bin/watcher.sh` awk 분기 + `tests/test-*-e2e.sh` 검증 네 곳을 한 commit 에 모두 손댄다. 한 곳만 빠지면 *벙어리 신호* 가 된다.
- **events.log 5필드 의미 표 유지** (`_common.md` 의 5필드 의미 행) — action 별로 필드5 의미가 다르다 (`modify=path` / `done=-` / `plan-defect=설명` / `drift-check`·`allow-confirm=key=value`). action 추가 시 표 행 추가 의무. 표 없는 신호는 reviewer 가 path 로 오해.

## 4. ⛔ HOW NOT

- **`{{HARNESS_ROOT}}` / `{{SESSION}}` / `{{WORKER_NAME}}` 리터럴 텍스트 사용 금지** — 가동 시 sed 치환되는 토큰이라 본문에 그대로 박으면 워커가 토큰을 *문자열로* 해석. 토큰을 *설명* 해야 한다면 코드 펜스 (`` ` ``) 로 감싸 sed 가 못 잡게 한다.
- **events.log payload 에 탭/개행 미사전 사용 금지** — watcher awk 가 `\t` 로 5필드 분리. 자유 텍스트 (`plan-defect` 의 설명 등) 에 탭/개행 들어가면 5필드 깨져 뒤 필드 잘림. 워커 부트 프롬프트 *사전 sanitize 명시 의무* (자동 sanitize 없음).
- **신호 추가 시 4곳 갱신 누락 금지** — HOW 의 동시 갱신 의무의 반대면. 한 곳만 추가하면 라우팅·검증·문서 정합 깨짐.
- **reviewer 가 `@plan-defect:` / `@gate:` / `@done:` 출력 금지** — 워커 전용 채널. reviewer 가 잘못 출력하면 watcher 라우팅이 worker 로 오해 → lead 가 reviewer 를 worker 로 종합. `_common.md` 신호 토큰 절의 *워커 전용* 명시를 reviewer 부트 프롬프트에도 재진입.

## 5. WHERE

- **의존**: (없음 — 마크다운만)
- **피의존**:
  - [`bin/awa-up.sh`](../bin/awa-up.sh) — sed 치환 + stdin 주입
  - [`profiles/*.sh`](../profiles/) — `WORKERS=("이름:역할:..")`의 `역할` 토큰이 여기 파일명과 매칭
- **경계 / 어댑터**:
  - 토큰 계약 — `{{HARNESS_ROOT}}` / `{{SESSION}}` / `{{WORKER_NAME}}`은 가동 시 치환되므로 텍스트에 리터럴 사용 금지
  - 완료 신호 채널 — `done-{{SESSION}}-{{WORKER_NAME}}-<task-id>` 형식(앞 2개는 가동 시 박힘, task-id만 워커가 채움)

## 6. WHY

- **lead.md cap 100줄 제한** — LLM 컨텍스트 비용 + 신호 진화 여유. 한 신호당 평균 3~5줄 추가 (절 ⓐ~ⓘ), 7종 신호 + 부가 절 까지 잡아도 ~60줄 → cap 100 은 *향후 3종 추가* 여유. cap 초과 시 신호 절 압축 (예: ⓖ 3줄 형식) 또는 partial 분리.
- **review-manager 자가 폴링 금지 (watcher 깨움 의존)** — feedback-lead-event-driven-not-loop 일반화. 자가 폴링은 (1) 비용 (LLM idle 토큰) (2) 동기화 결함 (다른 워커와 events.log race) (3) 신호 일관성 (모든 다른 워커는 이벤트 반응형) 세 가지 이유로 금지. review-manager 도 idle + watcher 깨움 패턴 동일.
- **역할 이름 전역 고유 제약** — `bin/lib.sh::resolve_role_file` 의 fail-fast 동작. 코드 자동 등록 (파일 추가 = 새 워커 등록) 의 트레이드오프 — 자동 등록 받는 대신 이름 충돌 위험을 fail-fast 로 차단. 이름 중복 시 어느 파일이 우선인지 *모호* 해지므로 boot 거부가 정답.

## 7. COMMANDS

```bash
# 마크다운만이므로 별도 빌드/린트 없음
# 부트 프롬프트 변경 검증은 tests/ 의 boot-tokens / role 관련 테스트로
bash tests/test-boot-tokens.sh
bash tests/role5axis/r5-score.sh
```

_(영역 고유 가드는 update에서 추가)_

## 8. ⚠️ LEARNED CAUTIONS

@./LEARNED_CAUTIONS.md

자세한 내용은 [LEARNED_CAUTIONS.md](./LEARNED_CAUTIONS.md) 참조.
