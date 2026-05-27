# preset 추천 근거 (agpn stage 단계 3)

plan task 분석 → 적정 preset 매핑. task 종류 라벨은 plan 에 없으므로 휴리스틱 추론.

## preset 인벤토리
| preset | 구성 | 적합 작업 |
|---|---|---|
| default | dev1 test1 + quality-rev | 일반 기능, 소규모 |
| feature-team | dev1 test1 arch1(researcher) + spec/quality/arch 리뷰어 | 설계 비중 큰 기능, 다관점 |
| research | researcher3 + quality-rev | 조사·탐색 위주 |
| code-review | security1 + spec/quality/arch 리뷰어 | 기존 코드 감사·보안 |

## task 종류 추론 (휴리스틱 — 정밀분류 아님)
- `Test:` 필드·경로 `tests/`·`test_*`·`*_test.*` → 테스트 비중
- 이름·설명에 "조사/비교/research/탐색" → research
- "보안/audit/취약점" → code-review
- `Create:` 코드 파일 위주 → 구현(default/feature-team)
- task 총수·arch 언급 빈도로 default↔feature-team 구분

## 매핑
- 구현 위주 소수 → default
- 구현+설계+테스트 혼합 → feature-team
- 조사 위주 → research
- 코드점검·보안 → code-review
- 애매 → default + 커스텀 안내

추천은 힌트 — 사용자가 채택/다른preset/커스텀으로 최종 결정.
