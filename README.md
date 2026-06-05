# AWA — Agents Watching Agents

**Plan-anchored, permission-gated, drift-tracked.**

> `multi-reviewed` 어휘는 다벤더 통합 사이클 후 부제 추가 (광고/구현 분리 차단 — `docs/identity-AWA.md` §10.6).

AWA 는 멀티 에이전트 오케스트레이션 도구가 아니라 **감독된 자율성(Supervised Autonomy) 플랫폼** 이다. 에이전트가 자율적으로 일하되, *plan 을 닻으로 검증·갱신* 하고, *드리프트를 상시 추적* 하고, *권한 게이트가 학습되며 안전 한계선을 시스템적으로 보장* 한다.

## 5조건

| # | 조건 | 어휘 | 구현 |
|---|---|---|---|
| 1 | Plan 검증 가능성 | `plan-anchored` | `.claude/skills/awa/SKILL.md` 검증가능성 abort 분기 + `harness/prompts/roles/01-orchestration/orch.md` ⓑ acceptance criteria push |
| 2 | Plan 갱신 루프 | `plan-anchored` | `orch.md` ⓖ `@plan-defect` 채널 + `_common.md` 워커 한 줄 |
| 3 | 다벤더 리뷰어 | `multi-reviewed` | (다벤더 통합 사이클 후 — `docs/superpowers/specs/2026-05-27-identity-redefinition-design.md` §12) |
| 4 | 상시 추적 | `drift-tracked` | `harness/prompts/roles/03-quality/review-manager.md` plan-diff 시계열 + `tests/check-differentiation-status.sh` |
| 5 | 권한 게이트 학습 | `permission-gated` + `deny-bounded` | `harness/bin/permission-gate.sh` + `harness/config/orch-auto-allow.yaml` + `harness/bin/classify.sh` + `harness/bin/danger-check.sh` |

## 권한 모델 (deny-bounded — 안전 한계선)

`harness/bin/danger-check.sh` 의 deny 카탈로그는 *사람·orch 우회 불가*. allow/deny/escalate 3단 권한 게이트 + Phase A/B/C 학습 (`harness/config/orch-auto-allow-stats.yaml`).

## Quick Start

```bash
.claude/skills/awa/harness/bin/awa-up.sh feature-team
```

상세는 [`docs/identity-AWA.md`](docs/identity-AWA.md) 및 `AGENTS.md` 참조.
