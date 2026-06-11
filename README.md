# AWA — Agents Watching Agents

![platform](https://img.shields.io/badge/platform-Claude%20Code-orange)
![shell](https://img.shields.io/badge/bash-3.2%2B-89e051)
![tmux](https://img.shields.io/badge/tmux-3.6%2B-1BB91F)
![status](https://img.shields.io/badge/status-beta-yellow)

> 멀티 에이전트 팀이 plan을 닻 삼아 일하고, **에이전트가 에이전트를 감시한다.**

자율은 에이전트에게, 검증·권한·안전은 시스템에게 — **감독된 자율성(Supervised Autonomy)** 플랫폼.

---

## 에이전트에게 큰 작업을 맡기면 생기는 일

| | 문제 | AWA의 답 |
|---|---|---|
| 🟥 | **False green** — 에이전트가 쓴 테스트는 에이전트가 쓴 코드의 맹점을 공유한다 | 독립 리뷰어 3종(plan 정합·품질·보안)이 **투표** — 만장일치 차단이면 자동 수정 |
| 🟧 | **권한 폭주** — 매번 물으면 사람이 병목(실측 58회), 전부 허용하면 `rm -rf` 한 번에 끝 | 승인한 패턴은 **학습**해 다시 안 묻고, 위험 명령은 **누구도 우회 불가**로 자동 거부 |
| 🟨 | **컨텍스트 절단** — auto-compact가 task 중간에 끼어들어 흐름을 끊는다 | task 경계마다 **선제 정리** — 흐름은 컨텍스트가 아니라 파일에 저장 |

## 구조

```
tmux 세션 awa-<project>
┌──────────────────┬──────────────────┐
│       ORCH       │       DESK       │   사용자는 DESK와 대화("무엇을")
│  (오케스트레이터)  │   (사용자 창구)   │   ORCH가 분해·배정·종합("어떻게")
├──────────────────┴──────────────────┤
│   backend-1   backend-2   tester-1  │   워커 — 역할별 권한 격리
├─────────────────────────────────────┤
│  alignment   quality    security    │   투표 리뷰어 — 합의 게이트
│             review-mgr              │   메타 리뷰 — 드리프트 추적
└─────────────────────────────────────┘
          ▲  파일 IPC (화면 파싱 없음)
          │  watcher 데몬이 폴링 → 해당 pane만 깨움
```

| 어휘 | 한 줄 |
|---|---|
| `plan-anchored` | plan은 읽고 버리는 문서가 아니라 전 구간의 닻 — task마다 기준 명시·검증 |
| `drift-tracked` | 의도에서 벗어나는 순간을 시계열로 상시 추적 |
| `permission-gated` | 권한은 매번 묻지 않고 학습 — 질문이 0으로 수렴 |
| `deny-bounded` | 위험 명령은 사람·ORCH도 우회 불가한 한계선에서 자동 거부 |

## 숫자로

동일 plan(재고·주문 트랜잭션 API, 불변식 5종)을 단일 에이전트 1회 + AWA 3회 실행한 자체 실측:

| 실행 | 사람 개입 | 토큰 (5h) | 시간 | 결과 |
|---|---|---|---|---|
| 단일 에이전트 | **58회** | 17% | 39분 | 완주 — 권한 질문이 병목 |
| AWA 1차 | **2회** (28배↓) | 15% | 40분 | 완주 + IDOR 결함 3라운드 차단 |
| AWA 2차 | 3회 | 17% | 45분 | 완주 + 합의 게이트 만장일치 작동 |
| AWA 3차 | 7회* | 19% | 40분 | 9 task 클린 완주 + **false-green 2건 실차단** |

> **감독 회로를 얹어도 비용은 단일 에이전트와 동급.** *3차의 7회는 결함 차단→수정 승인 등 게이트의 정당 개입.
>
> 게이트가 잡은 false green: 테스트 64개가 전부 통과했지만 — ① JWT 키 불일치로 실 인증에선 전 요청 500 ② 테스트가 구현에 맞춰 작성돼 spec 계약 위반. **둘 다 자기보고로는 못 잡는다.**

권한 질문은 학습으로 0에 수렴:

![Permission learning curve](docs/charts/h1_curve_batch.png)

## 설치

```bash
# 의존성: tmux · jq · claude (Claude Code CLI) · uuidgen
git clone https://github.com/taehyunan-99/awa.git
cd awa/.claude/skills/awa && bash install.sh
```

## 사용

```bash
cd <프로젝트> && claude
> /awa        # 인터뷰가 팀을 조립해 .awa/team.yaml 저장 + tmux 가동
```

1. **DESK**에 작업을 말한다 → ORCH가 분해·배정 트리를 보여주고 승인 1회
2. 이후 자율 진행 — 판단 필요할 때만 등급(🔴위험 🟠판단 🔵권한 🟢승인)으로 사람을 부름

```bash
> 오늘은 여기까지                      # 드레인 — 진행 중 task만 마치고 정지
$ harness/bin/awa-down.sh             # 정리 (산출물 보존)
$ harness/bin/awa-up.sh --spec .awa/team.yaml   # 재가동 — 완료분 건너뛰고 이어서
```

## 안전 모델

명령은 실행 전 4단계 분류 — LLM 판단이 개입할 수 없는 hook 레벨:

```
danger  →  자동 거부        rm -rf · sudo · dd · curl|sh … (우회 불가)
matrix  →  역할별 자동 허용   읽기·빌드·테스트류
auto    →  학습된 패턴       이전에 영구 승인한 것
gray    →  사람에게 질문     승인 시 영구 학습
```

---

**Contact** — [@taehyunan-99](https://github.com/taehyunan-99)
