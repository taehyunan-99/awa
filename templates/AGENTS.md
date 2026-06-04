# templates — Claude settings.json 권한 템플릿

역할군별 Claude `settings.json` 권한 템플릿 — `bin/lib.sh::generate_worker_settings`가 워커 역할에 맞는 `.tpl`을 선택해 적용한다.

**Tradeoff**: 역할군마다 별도 템플릿을 유지하는 비용 → 워커가 자기 역할에 필요한 최소 권한만 가져 위험 명령 차단력을 높임.

**5어휘 매핑**: permission-gated ("권한 학습 게이트") — Claude settings.json 권한 템플릿 군

## 1. WHAT

각 역할군(default/dev/test/desk/orch/reviewer)에 대응하는 Claude Code `settings.json` 권한 템플릿. 토큰 치환 후 워커 페인 cwd의 `.claude/settings.json`으로 배치된다.

## 2. CONTENTS

- `settings.readonly.json.tpl` — 읽기전용 군 (researcher/review-manager/미지정 fallback) + 미지정 역할 fallback
- `settings.dev.json.tpl` — dev 워커 (engineer/dev/security)
- `settings.orch.json.tpl` — orch (게이트 + 허용 폭 넓음)
- `settings.desk.json.tpl` — desk
- `settings.reviewer.json.tpl` — reviewer-* (글롭으로 자동 매칭)
- `settings.test.json.tpl` — test 워커
- `settings.json.tpl` — 일반 settings 기본 틀

기술 스택: JSON + 토큰(`{{...}}`) — bash sed로 치환

## 3. HOW

_(update 스킬에서 채워질 자리. 작업 중 패턴이 정립되면 `/update`로 인터뷰 진행)_

## 4. ⛔ HOW NOT

_(update 스킬에서 채워질 자리. 사용자 결정 사항이므로 init은 비워둔다)_

## 5. WHERE

- **의존**:
  - [`config/orch-auto-allow.yaml`](../config/orch-auto-allow.yaml) — 런타임 자동 허용은 여기서 정의되므로 템플릿은 base 권한만 담음(중복 회피)
- **피의존**:
  - [`bin/lib.sh`](../bin/lib.sh) — `generate_worker_settings` case가 템플릿 선택
- **경계 / 어댑터**:
  - reviewer-* 는 글롭 매칭 — 새 reviewer 추가 시 templates 수정 불필요
  - 새 권한군 추가 시 `bin/lib.sh` case 1줄 + 이 디렉토리에 `.tpl` 1개

## 6. WHY

_(update 스킬에서 채워질 자리. 사용자 결정 사항이므로 init은 비워둔다)_

## 7. COMMANDS

```bash
# JSON 유효성 검증(템플릿 토큰을 더미로 치환 후)
for f in templates/*.tpl; do
  sed -e 's|{{[^}]*}}|null|g' "$f" | python3 -m json.tool >/dev/null && echo "ok: $f"
done

# settings 관련 테스트
bash tests/test-default-settings.sh
bash tests/probes/probe-settings-merge.sh
```

_(영역 고유 가드는 update에서 추가)_

## 8. ⚠️ LEARNED CAUTIONS

@./LEARNED_CAUTIONS.md

자세한 내용은 [LEARNED_CAUTIONS.md](./LEARNED_CAUTIONS.md) 참조.
