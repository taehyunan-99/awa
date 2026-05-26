# profiles — 팀 구성 정의

`bin/agenphony-up.sh`가 source하는 bash fragment — 한 팀의 워커·리뷰어 구성, 모델, 레이아웃, 세션 식별자를 변수로 선언한다.

**Tradeoff**: 동적 팀 빌더가 아닌 정적 fragment를 받아들이는 대신, git diff로 팀 구성 변경 이력을 추적하고 매번 동일 팀을 재생성한다.

## 1. WHAT

프로파일은 한 팀의 청사진이다. `bin/agenphony-up.sh <name>`가 `profiles/<name>.sh`를 source하면 필요한 변수가 환경에 노출되어 페인 분할·부트 프롬프트 선택이 결정된다.

## 2. CONTENTS

- `default.sh` — 워커 dev/test, 리뷰어 quality-rev
- `code-review.sh` — 워커 security, 리뷰어 spec-rev/quality-rev/arch-rev
- `research.sh` — 워커 researcher×3, 리뷰어 quality-rev
- `feature-team.sh` — 워커 dev/test/arch, 리뷰어 spec-rev/quality-rev/arch-rev (모델 차등)

각 파일은 다음을 선언한다(요건):
- `SESSION` — tmux 세션명(보통 `agenphony-<basename>` 자동, override 가능)
- `LAYOUT` — tmux 페인 분할 레이아웃
- `WORKERS=("이름:역할[:모델]" ...)` — 필수
- `REVIEWERS=(...)` — 선택
- `LEAD_MODEL` — 선택

기술 스택: bash (POSIX 호환 아님 — `array` 사용)

## 3. HOW

_(update 스킬에서 채워질 자리. 작업 중 패턴이 정립되면 `/update`로 인터뷰 진행)_

## 4. ⛔ HOW NOT

_(update 스킬에서 채워질 자리. 사용자 결정 사항이므로 init은 비워둔다)_

## 5. WHERE

- **의존**:
  - [`prompts/roles/`](../prompts/roles/) — `WORKERS` 항목의 `<역할>`은 `roles/NN-part/<역할>.md`로 해석되어야 한다 (없으면 `bin/lib.sh::resolve_role_file`가 fail-fast)
- **피의존**:
  - [`bin/agenphony-up.sh`](../bin/agenphony-up.sh) — 유일한 소비자
- **경계 / 어댑터**:
  - 새 역할 추가 시: `prompts/roles/NN-part/<역할>.md` 작성 + 여기에 `WORKERS+=("이름:<역할>:모델")` 한 줄
  - 새 권한군: `bin/lib.sh::generate_worker_settings` case + `templates/settings.<군>.json.tpl` 동반 수정

## 6. WHY

_(update 스킬에서 채워질 자리. 사용자 결정 사항이므로 init은 비워둔다)_

## 7. COMMANDS

```bash
# 프로파일은 직접 실행하지 않고 source된다
bin/agenphony-up.sh default
bin/agenphony-up.sh feature-team
bin/agenphony-up.sh --project ~/work/foo default
```

_(영역 고유 가드는 update에서 추가)_

## 8. ⚠️ LEARNED CAUTIONS

@./LEARNED_CAUTIONS.md

자세한 내용은 [LEARNED_CAUTIONS.md](./LEARNED_CAUTIONS.md) 참조.
