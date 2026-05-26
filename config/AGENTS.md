# config — permission-gate 자동 허용 카탈로그

`bin/permission-gate.sh`의 classify 단계 — danger→matrix→**auto(여기)**→gray — 중 **auto** 단을 담당하는 카테고리별 안전 패턴 모음.

**Tradeoff**: 단순 awk 파서 호환 형식만 받는 제약 → 별도 YAML 라이브러리 없이 어디서나 동작.

## 1. WHAT

`lead-auto-allow.yaml`은 카테고리(read-only / git-readonly / ...) 단위로 자동 허용할 도구 패턴(`Tool(prefix:*)` 또는 `Tool(exact)`)을 선언한다. danger_check 통과 후에만 도달하므로 위험 패턴 포함 금지 — 방어선 다층화.

## 2. CONTENTS

- `lead-auto-allow.yaml` — 카테고리 + 패턴 목록 (read-only, git-readonly 등)

파일 형식 = 계약:
- `category:` (콜론으로 끝나는 카테고리 라인)
- 2칸 들여쓰기 + `- "패턴"`
- 그 외 형식(앵커, alias, 중첩 등)은 `bin/matrix-lookup.sh`의 awk 파서가 받지 않는다

## 3. HOW

_(update 스킬에서 채워질 자리. 작업 중 패턴이 정립되면 `/update`로 인터뷰 진행)_

## 4. ⛔ HOW NOT

_(update 스킬에서 채워질 자리. 사용자 결정 사항이므로 init은 비워둔다)_

## 5. WHERE

- **의존**: (없음 — 정적 데이터)
- **피의존**:
  - [`bin/matrix-lookup.sh`](../bin/matrix-lookup.sh) — awk 파서로 직접 읽음
  - [`bin/permission-gate.sh`](../bin/permission-gate.sh) — classify의 auto 단
- **경계 / 어댑터**:
  - 패턴 문법은 Claude Code `settings.json`의 `allow`와 동일
  - 위험 패턴 절대 추가 금지 (`rm -rf`, `sudo`, `dd of=`, `git push --force` 등) — `bin/danger-check.sh`와 중복 차단

## 6. WHY

_(update 스킬에서 채워질 자리. 사용자 결정 사항이므로 init은 비워둔다)_

## 7. COMMANDS

```bash
# 파서 호환 형식 점검
awk -f bin/matrix-lookup.sh config/lead-auto-allow.yaml   # 호출 시그니처는 실제 스크립트 확인

# 관련 테스트
bash tests/probes/probe-matcher-format.sh
bash tests/probes/probe-permission-gate.sh
```

_(영역 고유 가드는 update에서 추가)_

## 8. ⚠️ LEARNED CAUTIONS

@./LEARNED_CAUTIONS.md

자세한 내용은 [LEARNED_CAUTIONS.md](./LEARNED_CAUTIONS.md) 참조.
