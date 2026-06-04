# profiles — 팀 구성 정의

`bin/awa-up.sh`가 yaml 명세를 파서(`bin/spec-parse.sh`)로 로드 — 한 팀의 워커·리뷰어 구성, 레이아웃, 세션 식별자를 선언한다. 구 `.sh` fragment는 하위호환으로 유지(Task 8에서 폐기 시점 기록 예정).

**Tradeoff**: 코드 실행 가능 bash fragment 대신 선언형 yaml을 받아들이는 대신, 문법 화이트리스트 검증·불변식 검사로 안전성을 보장하고 git diff로 팀 구성 변경 이력을 추적한다.

**5어휘 매핑**: multi-reviewed ("다벤더 교차 리뷰") — REVIEWERS 배열 정의 (외부 노출 보류 §10.6)

## 1. WHAT

프로파일은 한 팀의 청사진이다. `bin/awa-up.sh <name>`가 `profiles/<name>.yaml`을 `spec_parse_load`(bin/spec-parse.sh)로 로드하면 WORKERS/REVIEWERS/LAYOUT 배열이 환경에 설정되어 페인 분할·부트 프롬프트 선택이 결정된다. yaml 없으면 구 `<name>.sh` source로 폴백(하위호환).

## 2. CONTENTS

yaml 명세 (우선):
- `default.yaml` — 워커 engineer/researcher, 투표 리뷰어 alignment-rev/quality-rev(claude)+security-rev(codex)(N=3 다벤더) + 집계 review-mgr
- `web.yaml` — 워커 frontend/backend/infra(claude), 투표 리뷰어 alignment-rev/quality-rev(claude)+security-rev(codex)(N=3 다벤더) + 집계 review-mgr (default 와 동일 회로·워커만 풀스택 3분업)
- `code-review.yaml` — 워커 security, 리뷰어 spec-rev/quality-rev/arch-rev + review-mgr
- `research.yaml` — 워커 researcher×3, 리뷰어 quality-rev + review-mgr
- `feature-team.yaml` — 워커 dev/test/arch, 리뷰어 spec-rev/quality-rev/arch-rev + review-mgr

구 bash fragment (하위호환, Task 8에서 폐기):
- `default.sh`, `web.sh`, `code-review.sh`, `research.sh`, `feature-team.sh`

yaml 스키마 (파서가 읽는 형식):
```yaml
layout: tiled
workers:
  - name: <이름>          # [A-Za-z0-9_-]
    role: <역할>          # [A-Za-z0-9_-]
    vendor: <벤더>        # 선택 (security-rev 만 codex)
reviewers:
  - name: <이름>
    role: <역할>
    vendor: <벤더>        # 선택
```

로드 후 배열 형식: `"name:role"` 또는 `"name:role:vendor"` (vendor 있을 때).

기술 스택: yaml (plain 2-depth 하위집합) + bash (파서 spec-parse.sh)

## 3. HOW

- **REVIEWERS 이름 컨벤션** — `<역할>-rev` 접미사 (예: `spec-rev:reviewer-spec`, `quality-rev:reviewer-quality`, `arch-rev:reviewer-arch`) 또는 review-<필드>. `review-manager` 는 pane 이름 `review-mgr` 로 *고정* (`bin/awa-up.sh` 의 `REVIEW_MANAGER_PANE` 결정 로직이 이 이름으로 pane 조회).

## 4. ⛔ HOW NOT

- **`review-mgr` pane 이름 임의 변경 금지** — `bin/awa-up.sh` 의 `REVIEW_MANAGER_PANE` 환경변수 주입 로직이 정확히 `review-mgr` 토큰으로 pane 식별. 변경 시 `watcher.sh` 의 drift-check 깨움 (line 97-100) 이 빈 PANE 으로 silent skip → review-manager 가 영원히 안 깨워짐.

## 5. WHERE

- **의존**:
  - [`prompts/roles/`](../prompts/roles/) — `WORKERS` 항목의 `<역할>`은 `roles/NN-part/<역할>.md`로 해석되어야 한다 (없으면 `bin/lib.sh::resolve_role_file`가 fail-fast)
- **피의존**:
  - [`bin/awa-up.sh`](../bin/awa-up.sh) — 유일한 소비자
- **경계 / 어댑터**:
  - 새 역할 추가 시: `prompts/roles/NN-part/<역할>.md` 작성 + 여기에 `WORKERS+=("이름:<역할>:모델")` 한 줄
  - 새 권한군: `bin/lib.sh::generate_worker_settings` case + `templates/settings.<군>.json.tpl` 동반 수정

## 6. WHY

_(update 스킬에서 채워질 자리. 사용자 결정 사항이므로 init은 비워둔다)_

## 7. COMMANDS

```bash
# 프로파일은 직접 실행하지 않고 source된다
bin/awa-up.sh default
bin/awa-up.sh feature-team
bin/awa-up.sh --project ~/work/foo default
```

_(영역 고유 가드는 update에서 추가)_

## 8. ⚠️ LEARNED CAUTIONS

@./LEARNED_CAUTIONS.md

자세한 내용은 [LEARNED_CAUTIONS.md](./LEARNED_CAUTIONS.md) 참조.
