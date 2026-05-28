# tests — LEARNED CAUTIONS

<!--
이 파일은 작업 중 발견된 실수/주의사항을 누적하는 자리다.
- `learn` 스킬(`/learn` 또는 Codex의 `$learn`)이 이 파일에만 항목을 추가한다.
- 같은 폴더의 본문 가이드(AGENTS.md / CLAUDE.md)는 절대 수정하지 않는다.
- update 스킬도 이 파일은 자동 덮어쓰지 않는다 — 사용자 결정으로 만들어진 자산이므로 보존.
- 변경이 필요한 경우 반드시 사용자에게 확인을 받고 진행한다.
-->

## 2026-05-28 — Sanity check 무력화 패턴 substring 회피

`tests/check-differentiation-status.sh` 의 sanity check 1회 실행 시 *닫힘 항목 임시 무력화* 단계에서 **치환 결과 문자열이 원본 grep 패턴을 substring 포함하면 FAIL 감지 못한다**.

**결함 사례**: `@plan-defect` 신호를 `@plan-defect-DISABLED` 로 치환 → A2 항목의 grep 이 여전히 `@plan-defect` 매치 → FAIL 감지 실패. sanity check 의 핵심 의도 (자동화가 결함 감지하는지 검증) 가 무효화.

**올바른 패턴**: 원본 키워드를 *완전 분리된 placeholder* 로 치환. 예시 — `@SANITY-NEUTRALIZED`, `@DISABLED-FOR-SANITY`. 원본 패턴 (`@plan-defect`) 의 어떤 부분도 substring 으로 포함하지 말 것.

**적용 범위**: sanity check 절차 (sanity-log.md 첫 기록 2026-05-28) + 향후 모든 sanity 무력화 스크립트.

**원본**: docs/superpowers/plans/2026-05-28-awa-rollout-plan.md Task 11 Step 11.1 (plan 본문 결함 — gitignored 라 영구 박제 안 됨, 이 메모리가 단일 영속 출처).
