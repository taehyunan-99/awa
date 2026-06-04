# bin — 하니스 실행 스크립트

tmux 세션 생애주기(up/down)와 워커 dispatch·watcher·classify·permission-gate를 구현하는 bash 도구 모음. 워커는 `{{HARNESS_ROOT}}/bin/<name>.sh` 절대경로로 이 도구들을 호출한다.

**Tradeoff**: bash + tmux 의존을 받아들이는 대신, 별도 런타임 없이 PROJECT_ROOT 분리·세션 재생성 가능성을 얻는다.

**5어휘 매핑**: (실행 인프라 — 5어휘 직접 책임 없음 / 라이프사이클·permission-gate·danger-check 실행 담당)

## 1. WHAT

AWA 하니스의 실행층 — tmux 페인 배치·워커 부트·작업 dispatch·완료 감지·권한 분류를 담당하는 bash 모듈들. 사용자 창구(desk) + 순수 오케스트레이터(orch) 분리 + watcher 데몬 이벤트 반응형 감시 + scope 사전차단 + 모델 차등 아키텍처 (2차 하니스 설계).

## 2. CONTENTS

- `awa-up.sh` — 프로파일 기반 tmux 세션 가동(워커 페인·부트 프롬프트 주입)
- `awa-down.sh` — 런타임 정리(tasks/results는 보존)
- `awa-main.sh` — `/awa` 비대화 명령 백엔드 (resume/attach/launch/resolve-path)
- `awa-down-menu.sh` — `/awa down` 진입점 (N=0/1/multi 분기 + down.sh 위임)
- `awa-dashboard.sh` — _DASHBOARD 멀티뷰 관제탑: 각 프로젝트 orch/desk pane 만 한 윈도우 grid 로 집결(골격 split + swap-pane, dash_render 중앙 재구성). 프로젝트당 1행(좌 orch·우 desk), 윈도우당 3프로젝트, 4번째부터 grid-2. 액션 merge/add/detach/split/kill (detach·kill 인자=프로젝트명)
- `awa-splash.sh` — attach 첫 화면 splash (client-attached 훅의 display-popup 모달로 실행, 팀 요약 파일 읽어 브랜딩+팀 표 렌더, read -t N 키/타임아웃 닫힘)
- `awa-bookmarks.sh` — bookmarks wrapper (list/set-alias/remove/prune)
- `dispatch.sh` — orch/외부가 `<role> <task-id>` 형식으로 워커에 작업 주입
- `watcher.sh` — events.log/pending-asks 폴링 데몬, orch/reviewer 페인을 깨움
- `classify.sh` — 명령어를 danger→matrix→auto→gray로 분류
- `danger-check.sh` — 위험 명령(`rm -rf`, `sudo`, `dd of=`, `curl|sh`, `git push --force` 등) 거부
- `matrix-lookup.sh` — `config/orch-auto-allow.yaml`의 카테고리 패턴 매칭(awk 파서)
- `permission-gate.sh` — PreToolUse hook 진입점, classify 결과로 allow/deny 결정
- `log-event.sh` — events.log 포맷 라인 append 헬퍼
- `lib.sh` — 공통 함수(`generate_worker_settings`·`worker_turn_count`·`confirm_allow_yaml`·`bump_stats_counter` 등), 다른 스크립트가 source

`awa-up.sh` 주요 옵션:
- `--profile <name>` — 프로파일 fragment 선택 (`profiles/<name>.sh`)
- `--project <path>` — PROJECT_ROOT 명시 (cwd 자동 도출 우회)
- `--dry-check` — yaml 가드 (`danger-check.sh --check-allow-yaml`) 만 실행 후 즉시 종료 (boot 안 함, Task 7)
- `--plan <file>` — 확정 plan 자동주입 (반복 가능, 합본 후 `--append-system-prompt-file` 로 ORCH 주입, 11차)

기술 스택: bash 3.2+/zsh (macOS 기본 호환), tmux 3.6+, awk, sed, claude CLI

## 3. HOW

- **watcher.sh awk 분기 패턴** — 새 신호 라우팅 추가 시 done 분기 (L74-81) 100% 모방: `sed -n "$((last_events+1)),${cur}p" "$EVENTS"` 구간 추출 → `awk -F'\t' '$4=="<action>"{...}'` 필터 → `while IFS= read` + `pane_alive` 가드 + `send-keys -l <text>` + `send-keys Enter` 분리. drift-check (L85-102) / plan-defect (L104-111) / allow-confirm (L113-120) 모두 동일 형태.
- **`lib.sh` 는 source 전용** — 진입점 없음. 직접 실행 (`bash lib.sh`) 하면 함수 정의만 만들고 종료. orch LLM 이 함수 호출해야 할 때는 `bash -c "source $HARNESS_ROOT/bin/lib.sh && confirm_allow_yaml '<pattern>' '<decision>'"` 형식으로 명시.
- **events.log 5필드 조작 시 `event_field` / `event_valid` 호출** — `lib.sh` 의 `event_field` / `event_valid` 함수. 하드코딩 `awk -F'\t' '{print $N}'` 재사용 금지 — 5필드 규약 변경 시 전 수정 필요.

## 4. ⛔ HOW NOT

- **`lib.sh` 에 진입점 추가 금지** — source 전용 계약. main 분기 (`if [ "$0" = "${BASH_SOURCE[0]}" ]`) 추가 시 source 시 부수효과 발생 가능. CLI 도구는 별도 스크립트로 분리 (예: `danger-check.sh --check-allow-yaml` 처럼 *기존 함수의 source-then-call* 가 아니라 *전용 진입점 분기*).
- **events.log 에 직접 `printf` 쓰기 금지 (운영 코드)** — 항상 `add_to_allow` / `log_safe` 같은 보호 함수 경유. 직접 쓰기 시 mkdir 락 우회·blocklist 검사 우회·SIGPIPE 가드 우회 발생. (예외: watcher.sh 의 `drift-check` payload — 워커 손이 안 닿는 위치만 허용).
- **yaml 쓰기 함수에 mkdir 락 누락 금지** — `add_to_allow` 함수가 표준 패턴. 새 yaml 쓰기 함수 (예: `bump_stats_counter`) 도 *반드시* 동일 mkdir 락 + stale lock 15s 회수 패턴 복제. 락 없으면 멀티 워커 lost update.
- **`tmux send-keys` 에 `-l` 없이 텍스트+Enter 체이닝 금지** — `send-keys -l "text" Enter` 형태는 텍스트 안의 메타키 해석 위험. 항상 두 호출로 분리 (`send-keys -t pane -l "text"` + `send-keys -t pane Enter`). `&&` 체이닝도 금지 — `-l` 성공·Enter 실패 시 half-sent 발생 (watcher.sh L52 주석 참조).

## 5. WHERE

<!-- 모두 약결합(마크다운 링크) — 강결합 승격은 /update에서 판단 -->

- **의존**:
  - [`profiles/`](../profiles/) — `awa-up.sh`가 `.yaml` 우선 로드(`spec_parse_load`), yaml 없으면 구 `.sh` source 폴백(`WORKERS`/`REVIEWERS`/`SESSION`/`LAYOUT`)
  - [`prompts/`](../prompts/) — `_common.md` + `roles/NN-part/<역할>.md` 글롭으로 자동 카탈로그, `{{HARNESS_ROOT}}` 토큰을 sed 치환 후 워커 stdin에 주입
  - [`templates/`](../templates/) — `lib.sh::generate_worker_settings`가 역할군에 맞는 `settings.<군>.json.tpl` 선택
  - [`config/orch-auto-allow.yaml`](../config/orch-auto-allow.yaml) — `matrix-lookup.sh`의 awk 파서가 카테고리 패턴 읽음 (`category:` + 2칸 들여쓰기 + `- "패턴"` 단순 형식만)
- **피의존**:
  - 워커(`prompts/roles/*`)가 `{{HARNESS_ROOT}}/bin/<도구>.sh` 절대경로로 호출
  - [`tests/`](../tests/) — `test-*.sh` 다수가 이 디렉토리의 함수/스크립트 단위 검증
- **경계 / 어댑터**:
  - tmux ↔ bash: `send-keys -l`(텍스트/Enter 분리), `wait-for`, `capture-pane`
  - claude CLI ↔ 워커: stdin 부트 프롬프트 주입, allow-set-title off로 pane title 보존

## 6. WHY

- **watcher.sh `set -u` (set -e 미적용)** — 데몬은 *일시 실패로 죽으면 안 된다*. 서브셸 awk 파이프라인이 한 폴링 사이클에서 실패해도 다음 사이클이 정상 처리 가능하도록 `-e` 미적용. `-u` 만 두어 미설정 변수 사용은 즉시 잡되, 명령 실패는 무시 → 데몬 생존성 우선.
- **mkdir 락 선택 이유 = macOS flock 부재** — POSIX `mkdir` 의 원자성 보장 (이미 존재하면 실패) 을 이식성 락으로 활용. flock 은 macOS 기본 부재 → 별도 brew 의존 회피.
- **stale lock 15초 + mtime>0 가드 이유 = 5차 실측 결함 수정** — `mt=0` (stat 실패, lock 이 막 사라짐) 일 때 `age=now-0` = 거대값으로 *방금 다른 워커가 만든 정상 lock* 을 stale 로 오판 → 강제 삭제 → 임계구역 동시 진입 → lost update 재발. mt>0 가드로 차단 (`add_to_allow` 함수 주석).
- **`add_to_allow` 의 events.log 가드 = 단위 테스트 격리** — 테스트 환경 (events.log 없음) 에서 `add_to_allow` 호출 시 운영 stats.yaml 오염 차단. 운영 환경 (boot 후 events.log 존재) 에서만 신호·통계 발화.

## 환경변수

| 이름 | 기본 | 의미 |
|---|---|---|
| `SHELL_READY_TIMEOUT` | 15 (초) | pane 셸 ready 폴링 timeout. conda init 등 느린 환경에서 늘림. |
| `BOOT_REPL_CHECK_DELAY` | 5 (초) | claude 명령 송신 후 trust/REPL 검출 매치 윈도우. (timeout 아님 — 검사 대기.) |
| `HARNESS_PROJECT` | (없음) | PROJECT_ROOT 강제 지정. 기본은 git toplevel 또는 PWD 폴백. |
| `PROMPTS_DIR` | `$HARNESS_ROOT/prompts` | 부트 프롬프트 디렉터리 override (주로 테스트 fixture 용). |

## 벤더 정책 (2026-05-31 확정)

**베이스(ORCH/DESK)는 claude 전용. codex 는 워커/리뷰어로만.** `awa-up.sh` 는 ORCH/DESK 부트 직전 `resolve_orchestrator_vendor`(lib.sh)로 비-claude 벤더를 claude 로 강제(+경고). 워커/리뷰어는 `<role>:codex` 또는 `ENTRY_VENDOR=codex` 로 자유 지정.

- **사유 = P17**: watcher 가 `send-keys` 로 ORCH/DESK 입력창에 알림(@gate/@done 등)을 쏘는데, codex TUI 는 작업 중이면 입력을 큐잉만 하고 제출 안 함 → 알림 잔상 + 게이트 타임아웃 → dispatch 반복 실패(실측). 워커는 알림 받는 쪽이 아니라(events.log/results 쓰는 쪽) 무관 → codex 워커/리뷰어는 정상.
- **codex 워커 게이트 = 해결됨**: P12(trusted_hash)·P14(env 자기도출+fail-closed)·P15(sed -n auto-allow)·P16(allow=빈출력+exit0). 1사이클 완주 실측.
- **antigravity = 통째 보류**: 헤드리스 부트 자체 불가(conversation ID 미노출·workspace 미루팅·API key 인증 미지원 — 상류 OPEN). 워커조차 불가. `bin/vendors/antigravity.sh` 자리만 정의.
- 재진입: codex ORCH/DESK 은 P17(send-keys↔TUI 큐잉) 재설계 후. 상세 → 메모리 `codex-vendor-worker-reviewer-only-2026-05-31`.

## 멀티 프로젝트 동시 가동

basename 다를 시 `awa-<basename>` 세션 동시 가동 가능. basename 충돌 시 후행 가동 거부 — `SESSION_OVERRIDE="awa-auth2" bin/awa-up.sh default` 로 회피.

## 7. COMMANDS

```bash
# 정적 검사
shellcheck bin/*.sh                # 설치된 경우

# 단위 테스트 (이 디렉토리 변경 시)
bash tests/run-all.sh
RUN_INTEGRATION=1 bash tests/run-all.sh    # claude CLI 의존 probe 포함
```

_(영역 고유 가드는 update에서 추가)_

## 8. ⚠️ LEARNED CAUTIONS

@./LEARNED_CAUTIONS.md

자세한 내용은 [LEARNED_CAUTIONS.md](./LEARNED_CAUTIONS.md) 참조.
