# lead 구조 비교 실험 결과

축소판 1바퀴: A·B·C × (plan-complex + stress-ambiguous) = 6셀.
각 셀 `arena-run.sh` 라이브(사용자 `!`) → `arena-score.sh` 1차 기계채점.

| 후보 | 자극 | 1차점수 | 비고(지표) |
|---|---|---|---|
| A | plan-complex | 3 | task수=3; allowed명시=3/3; state기록=O; header종합=O(3/3);  |
| B | plan-complex | 3 | task수=3; allowed명시=3/3; state기록=O; header종합=O(3/3);  |

## 정성 관찰 (기계 채점이 못 잡는 차이)

### plan-complex: A vs B 결정적 차이 — 확정 plan 자동 착수
- **A (신호 6절)**: boot 직후 자동으로 분해→배정 트리→승인 게이트까지 진행. 사용자 개입은 "승인" 한 번. `## ⓐ`의 "확정 plan 주입 시 boot 직후 1회 자동 착수" 트리거가 강하게 작동.
- **B (Anthropic 7섹션)**: plan 인지 후 **"착수 지시 대기 중"으로 멈춤**. 사용자가 `착수해줘` send-keys로 깨워야 분해 시작. `## STOP & guardrails`의 "확정 plan 착수만 예외" 문구가 A 만큼의 강한 트리거가 아니라 보수적 대기로 해석됨.
- **방향성 부합**: [[agent-harness-2phase-plan-execute]](lead 능동 착수, pm 정보 pull/lead 판단 push) → **A 가 의도에 정확히 부합**, B 는 사용자 개입을 1회 더 요구.
- **분해 품질**: 동등 — 둘 다 3 task, 의존·입력경로·품질게이트 명시. B 는 forbidden_paths 가 더 꼼꼼(`.agent-harness/**` 차단 등) — 약간 우위.
- **종합**: 둘 다 우수. A 는 결정 로그까지, B 는 "ALL DONE — pm 지시 대기 (다음 phase 자동 전이 안 함)" 로 금지 인지까지 표시.
- **결론(plan-complex)**: 기계 동점이지만 **자동 착수 요구사항에서 A 가 우위**.

| C | plan-complex | 3* | task수=1; allowed명시=1/1; state기록=O; header종합=O(1/1);  |

> \* C 의 3점은 **기계 채점 지표 결함** — 분모가 "lead 가 dispatch 한 task 수"라 T1 만 진행하면 1/1=100% 로 만점. 절대 분해(정답 3 task) 대비 누락 2개는 못 잡힘. 실제 plan 완료율은 33% (1/3). 이 셀은 정성으로 **실패** 처리(아래 정성 관찰).

### plan-complex: C 의 결정적 결함 — 단계 자동전이 예외 누락
- **C (미니멀)**: T1 dispatch → T1 done 후 **lead 가 "원칙 6 (단계 자동 전이 금지)에 따라 T2 dispatch 는 pm 지시 대기"로 plan 중간에 정지**. plan 안의 T1→T2→T3 순차 진행이 막힘. 사용자가 매 단계마다 깨워야 끝까지 갈 수 있는 상태 — 비효율.
- **원인**: C 프롬프트 원칙 6 = "단계 자동 전이(완료→다음은 pm 지시 대기)". **"확정 plan 안의 순차 dispatch 는 예외"가 누락**. A·B 는 "확정 plan 착수는 예외"를 명시해 이 문제 회피.
- **추가 결함**: 분해 단계에서 task 파일을 디스크에 안 쓰고 lead 화면 내부 메뉴로 곧장 승인 게이트. task 파일은 승인 후에야 작성(추적성 손실 — pm/사용자가 분해 단계에서 task 명세 못 봄). reviewer 가 **Agent(Explore) 서브에이전트 호출 시도** — scope 검색은 task 파일의 allowed_paths 로 충분하므로 불필요·과도(거부 처리).
- **결론(C plan-complex)**: 기계 3점은 지표 결함의 산물, 실제로는 **plan 완료율 33% + 자동 dispatch 단절 + 추적성 손실**로 사실상 실패. C 미니멀이 우리 방향성과 가장 거리 멀다.

## 누적 정성 비교 (plan-complex 1셀 기준)

| 항목 | A (신호 6절) | B (Anthropic 7섹션) | C (미니멀) |
|---|---|---|---|
| 확정 plan 자동 착수 | ✅ | ❌ (사용자 깨우기 필요) | ❌ (사용자 깨우기 필요) |
| plan 인지 명시 | ✅ | ✅ | ❌ |
| 분해 task 파일 작성 | ✅ (분해 즉시) | ✅ (분해 즉시) | ⚠ (승인 후 지연) |
| forbidden_paths 명시 | ✅ | ✅ (더 꼼꼼) | (T1만 작성) |
| T1→T2→T3 순차 자동 dispatch | ✅ | ✅ | ❌ (원칙6 오적용으로 정지) |
| plan 완료율 | 3/3 (100%) | 3/3 (100%) | 1/3 (33%) |
| 사용자 개입 (게이트 외) | 0회 | 1회 | 매 단계 (사실상 매뉴얼) |
| 우리 방향성 부합도 | 🥇 정확히 부합 | 🥈 자동 착수 약점 | 🥉 미니멀 약점 다발 |

---

## stress-ambiguous 셀

| 후보 | 자극 | 1차점수 | 비고(지표) |
|---|---|---|---|
| A | stress-ambiguous | 2 | task수=0; allowed명시=0/0; state기록=X; header종합=0/0; 모호=BLOCKED정답;  |
| B | stress-ambiguous | 2 | task수=0; allowed명시=0/0; state기록=X; header종합=0/0; 모호=BLOCKED정답;  |
| C | stress-ambiguous | 2 | task수=0; allowed명시=0/0; state기록=X; header종합=0/0; 모호=BLOCKED정답;  |

### stress-ambiguous: 기계 동점, 정성 차이 — 능동 push vs silent idle
- **A (신호 6절)**: 두 막힘(`그것` 불명·순환의존) 정확 식별 + **AskUserQuestion 능동 push**. 선택지: plan 재작성(권장)·스트레스 테스트 인지·순환 무시(권장 안 함). ⓔ "lead BLOCKED" 발동 정확.
- **B (Anthropic 7섹션)**: 두 막힘 정확 식별 + **silent idle**("LEAD 규약상 다음 신호 대기"). obstacle 인지는 했지만 사용자에게 push 안 함 → 정답 키의 `사용자에게 push(obstacle·tried·need)` 요구사항 미달. plan-complex 때 자동 착수 안 한 패턴과 동형(보수적 대기).
- **C (미니멀)**: plan 인지 명시 없어 깨우기 1회 필요했지만, 깨운 뒤엔 두 막힘 정확 식별 + **AskUserQuestion 능동 push** (A 와 동일 수준). 원칙 5 "막히면 멈춰라 — 사용자에게 push"가 미니멀이라 오히려 강력하게 작동.
- **흥미로운 반전**: plan-complex 에선 C 가 가장 약했지만, stress-ambiguous(멈춤 판단)에선 C 가 B 보다 우수. 미니멀이 단순 진행에선 약점이지만 멈춤·중단에선 강점(필터링 없이 원칙 직발동).
- **결론(stress-ambiguous)**: A=C > B. A·C 능동 push, B silent idle.

## 누적 정성 비교 (6셀 전체)

| 항목 | A (신호 6절) | B (Anthropic 7섹션) | C (미니멀) |
|---|---|---|---|
| 확정 plan 자동 착수 | ✅ | ❌ | ❌ |
| BLOCKED 능동 push | ✅ | ❌ (silent idle) | ✅ |
| 분해 task 파일 작성 | ✅ | ✅ | ⚠ (지연) |
| plan 안 순차 자동 dispatch | ✅ | ✅ | ❌ (단계전이 오해석) |
| plan-complex 완료율 | 100% | 100% | 33% |
| stress-ambiguous BLOCKED 정답 | ✅ | △ (push 누락) | ✅ |
| 우리 방향성 부합도 | 🥇 | 🥈 (자동착수·push 둘 다 약함) | 🥉 (순차dispatch 결정적 결함) |

## 결론 — 승자: 후보 A (신호→반응 6절)

**선정 근거:**
1. **확정 plan 자동 착수**: A 만 능동 착수, B·C 는 사용자 깨우기 필요. 우리 방향성([[agent-harness-2phase-plan-execute]]: lead 능동 착수)에 정확히 부합하는 유일한 후보.
2. **plan 안 순차 자동 dispatch**: A·B 가능, C 는 단계전이 예외 누락으로 plan 중간 정지(완료율 33%).
3. **BLOCKED 능동 push**: A·C 가능, B 는 silent idle 로 사용자가 와서 묻기 전까지 침묵.
4. **분해·종합 품질**: A·B 가 동등 우수, C 는 task 파일 작성 지연(추적성 손실).
5. **결정 요인**: A 는 **세 영역 모두 ✅**, B 는 자동착수·push 둘 다 약함, C 는 순차 dispatch 가 결정적 결함.

**부수 발견:**
- C 의 미니멀이 모호한 plan(stress-ambiguous)에선 오히려 강점(원칙 5 직발동)이나, 일반 plan 진행에선 단점 다발. → 미니멀은 "결정·중단"엔 좋고 "순차 실행"엔 나쁨.
- B 의 Anthropic 7섹션은 형식이 풍부하나 lead 가 보수적으로 해석해 능동성이 떨어짐. → 섹션 많다고 좋은 게 아니라 **트리거의 강도**가 관건.
- A 의 6절 중 ⓐ(자동 착수)·ⓕ(예외 명시)·ⓔ(BLOCKED 능동 push) 세 절이 핵심.

**본구현 채택:** `tests/lead-arena/candidates/A.md` → `prompts/roles/01-orchestration/lead.md` (Task 7).

