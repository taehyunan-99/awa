# prompts — 워커 부트 프롬프트

`_common.md` + `roles/NN-part/<역할>.md` 글롭으로 자동 카탈로그화되는 워커 부트 프롬프트. 코드 수정 없이 새 역할은 파일 추가만으로 등록된다.

**Tradeoff**: 코드 자동 등록을 받아들이는 대신, 역할명은 전 파트에서 고유해야 하고(불변식), 중복 시 `bin/lib.sh::resolve_role_file`가 fail-fast 한다.

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

_(update 스킬에서 채워질 자리. 작업 중 패턴이 정립되면 `/update`로 인터뷰 진행)_

## 4. ⛔ HOW NOT

_(update 스킬에서 채워질 자리. 사용자 결정 사항이므로 init은 비워둔다)_

## 5. WHERE

- **의존**: (없음 — 마크다운만)
- **피의존**:
  - [`bin/awa-up.sh`](../bin/awa-up.sh) — sed 치환 + stdin 주입
  - [`profiles/*.sh`](../profiles/) — `WORKERS=("이름:역할:..")`의 `역할` 토큰이 여기 파일명과 매칭
- **경계 / 어댑터**:
  - 토큰 계약 — `{{HARNESS_ROOT}}` / `{{SESSION}}` / `{{WORKER_NAME}}`은 가동 시 치환되므로 텍스트에 리터럴 사용 금지
  - 완료 신호 채널 — `done-{{SESSION}}-{{WORKER_NAME}}-<task-id>` 형식(앞 2개는 가동 시 박힘, task-id만 워커가 채움)

## 6. WHY

_(update 스킬에서 채워질 자리. 사용자 결정 사항이므로 init은 비워둔다)_

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
