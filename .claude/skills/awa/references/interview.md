# 동적 팀 조합 인터뷰

목적: 사용자 니즈를 파악해 .awa/team.yaml 을 제안·승인·저장한다.

## 질문 (AskUserQuestion, 한 번에 하나)
1. 작업 종류: 구현 / 조사 / 코드 점검·보안 / 풀스택 / 혼합
2. (시드) 위 종류 → profiles/<seed>.yaml 을 초안으로 읽어 제시 (구현→default, 조사→research, 보안→code-review, 풀스택→web, 혼합→feature-team)
3. 워커 가감: 역할·인원·벤더·모델 조정
4. 리뷰 수위: full-vote(alignment+quality+security 3종) / quality-only / 무리뷰(research 류)

## 불변식 (spec §4 — 반드시 강제)

**파서가 자동 검증(review-mgr 강제)하는 항목:**
- 투표 리뷰어(reviewer-alignment/quality/security) ≥1 이면 review-manager(name: review-mgr) 자동 포함.
- 저장 전 `bash -c 'source bin/spec-parse.sh && spec_parse_invariants <path>'` 로 검증(rc=0 확인).

**인터뷰가 직접 판단해 사용자에게 경고·확인하는 항목 (파서 불변식 아님):**
- 무리뷰(투표 0)는 "합의 게이트 없이 진행"을 사용자에게 명시 확인.
- 투표 리뷰어 1명뿐이면 단독 거부권이 됨 — 인터뷰가 사용자에게 경고(파서 불변식이 아닌 인터뷰 책임).

## 저장 (.awa/team.yaml)
- 대상 프로젝트 PROJECT_ROOT/.awa/team.yaml 작성.
- git 추적 여부 안내: 기본 추적되며, 개인 설정으로 끄려면 .gitignore 에 `.awa/` 한 줄 추가.
- plan 참조 시: 그 plan 이 git 미추적(docs/)이면 "로컬 전용, 공유 안 됨" 고지(plan 은 soft reference — 재호출 시 없으면 경고 후 plan 없이 진행).

## 스키마
layout / workers[].{name,role,vendor,model} / reviewers[].{name,role,vendor} / plan(경로 참조, 선택)
