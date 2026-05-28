# config — permission-gate 자동 허용 카탈로그

`bin/permission-gate.sh`의 classify 단계 — danger→matrix→**auto(여기)**→gray — 중 **auto** 단을 담당하는 카테고리별 안전 패턴 모음.

**Tradeoff**: 단순 awk 파서 호환 형식만 받는 제약 → 별도 YAML 라이브러리 없이 어디서나 동작.

**5어휘 매핑**: permission-gated + deny-bounded ("권한 학습 게이트" + "안전 한계선 보장") — yaml 카탈로그 다층 방어

## 1. WHAT

`lead-auto-allow.yaml`은 카테고리(read-only / git-readonly / ...) 단위로 자동 허용할 도구 패턴(`Tool(prefix:*)` 또는 `Tool(exact)`)을 선언한다. danger_check 통과 후에만 도달하므로 위험 패턴 포함 금지 — 다층 방어.

## 2. CONTENTS

- `lead-auto-allow.yaml` — 카테고리 + 패턴 목록 (read-only, git-readonly, learned 등). `learned:` 는 `confirm_allow_yaml accepted` 가 누적하는 영역.
- `lead-auto-allow-blocklist.yaml` — 사용자 unsubscribe (Phase C 우회). `patterns:` 단일 노드 + `- "패턴"`. `confirm_allow_yaml never` 가 누적.
- `lead-auto-allow-stats.yaml` — Phase A 학습 통계 카운터. `patterns.<패턴>.<필드>: <수>` 3단 트리. `bump_stats_counter` 가 confirm/accepted/rejected/never 4 필드 누적.

세 yaml 의 구조가 의도적으로 다르다:
- `lead-auto-allow`: 카테고리 다중 (read-only / git-readonly / safe-test / ... + learned)
- `blocklist`: `patterns:` 단일 노드 (카테고리 분류 불필요 — 모두 사용자 거부 의미)
- `stats`: 3단 트리 (`patterns.<패턴>.<필드>`) — 패턴별 다필드 카운터

파일 형식 = 계약 (lead-auto-allow / blocklist 공통):
- `category:` 또는 `patterns:` (콜론으로 끝나는 노드 라인)
- 2칸 들여쓰기 + `- "패턴"`
- 그 외 형식(앵커, alias, 중첩 등)은 `bin/matrix-lookup.sh` 의 awk 파서·`append_to_yaml` awk fallback 이 받지 않는다

## 3. HOW

- **3 yaml 의 구조 목적** — 위 CONTENTS 의 분리 근거를 *사용자가 직접 편집* 하기 전에 확인. allow 는 다중 카테고리·blocklist 는 단일 노드·stats 는 3단 트리. 임의 구조 변경 시 awk 파서·`append_to_yaml` 의 가정 깨짐.
- **awk 파서 호환 형식만** — `category:` (또는 `patterns:`) + 2칸 들여쓰기 + `- "패턴"`. yq 가 만들어내는 일반 yaml (앵커·alias·중첩) 은 받지 않는다.
- **`learned:` 카테고리 관리** — `confirm_allow_yaml accepted` 만 누적. 사용자 수동 수정 지양 — `append_to_yaml` 의 멱등성 grep (`^  - "$pattern"$`) 이 카테고리 무관이라 다른 카테고리에 이미 있으면 silent skip 됨.

## 4. ⛔ HOW NOT

- **위험 패턴 추가 금지** (`sudo`, `rm -rf`, `git push --force`, `dd of=`, `curl | sh` 등) — `danger-check.sh` 통과 조건 위반. 다층 방어 원칙 (lead-auto-allow 는 *danger 통과 후에만 도달* 하는 안전 계층).
- **작업 파괴 패턴 학습 금지** (`Bash(git checkout:*)` / `Bash(git reset:*)` / `Bash(git clean:*)`) — `danger_check` 가 *전체* 를 잡지 않고 *옵션 조합 (--hard / -f / -fdx)* 만 잡음. `git checkout -- file` 의 작업 파괴 같은 *데이터 손실 잠재 위험* 은 자동 허용 카탈로그 진입 금지 (`lead-auto-allow.yaml` 의 `git-write` 카테고리 주석 참조).
- **3 yaml 구조 임의 변경 금지** — `bin/matrix-lookup.sh` 의 awk 파서, `lib.sh::append_to_yaml` 의 awk fallback, `lib.sh::bump_stats_counter` 의 awk fallback 가 모두 *현 구조 가정* 으로 동작. 구조 변경 시 3곳 awk 동시 수정.
- **`stats.yaml` 수동 편집 금지** — `bump_stats_counter` 의 awk fallback 이 `patterns.<패턴>.<필드>: N` 형식 가정. 사용자가 들여쓰기·구분자 변경 시 카운터 누적 실패 + silent corruption. 통계 초기화 필요 시 파일 전체 삭제 후 빈 `patterns:` 만 남기는 형태로.

## 5. WHERE

- **의존**: (없음 — 정적 데이터)
- **피의존**:
  - [`bin/matrix-lookup.sh`](../bin/matrix-lookup.sh) — awk 파서로 직접 읽음
  - [`bin/permission-gate.sh`](../bin/permission-gate.sh) — classify의 auto 단
- **경계 / 어댑터**:
  - 패턴 문법은 Claude Code `settings.json`의 `allow`와 동일
  - 위험 패턴 절대 추가 금지 (`rm -rf`, `sudo`, `dd of=`, `git push --force` 등) — `bin/danger-check.sh`와 중복 차단

## 6. WHY

- **3 yaml 분리 이유** — 읽기/쓰기 권한·수명·필드 의미가 서로 다르다.
  - `lead-auto-allow.yaml`: *운영 데이터*. 사람·`confirm_allow_yaml` 양쪽이 쓰기. 영구 보존.
  - `lead-auto-allow-blocklist.yaml`: *사용자 명시 결정*. `confirm_allow_yaml never` + 사용자 직접만 쓰기. 영구 보존.
  - `lead-auto-allow-stats.yaml`: *멀티 워커 누적 카운터*. `bump_stats_counter` 전용 쓰기. Phase B/C 진입 후 초기화 가능.
  세 가지 의미를 하나의 yaml 에 섞으면 사용자 편집·자동 갱신·통계 누적 책임 충돌.
- **다층 방어 (danger-check + lead-auto-allow)** — `lead-auto-allow` 가 *danger 를 통과한 명령에만* 적용. 즉 lead-auto-allow 에 위험 패턴 추가해도 *이미 danger-check 가 차단해서 도달 안 함*. 그러나 두 곳 정합이 깨지면 *조용한 우회* 가능 — 두 곳을 항상 일치시키기 위한 검증이 `danger-check.sh --check-allow-yaml` 가드 (Task 7 신규).
- **awk 파서 명령 선택 이유** — `yq` / `python` 의존 제로. 설치 없이 어디서나 동작 (macOS 기본 / CI / 신규 개발자 머신). `yq` 가 있으면 우선 사용 (USE_YQ 캐시), 없으면 awk fallback (정확도 ↓ 인정).

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
