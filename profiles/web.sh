# web 팀: 풀스택 분업(frontend·backend·infra) + 감시 리뷰어 N=3 다벤더 + review-mgr 집계.
# default 와 동일 리뷰어 회로(검증된 구성) — 워커만 풀스택 3분업으로 교체.
# 다벤더: 워커 3 + alignment + quality = claude, security = codex(리뷰어 전용 — 워커=claude 전제).
LAYOUT="tiled"
# 형식: "워커이름:역할[:벤더][:모델]"
#   - 2필드 "frontend:frontend" → HARNESS_VENDOR 상속 + 역할 기본 모델(vendor_default_model)
#   - 3필드 "frontend:frontend:codex" → 벤더 명시 / "frontend:frontend:sonnet" → 모델 명시
# 모델 미지정 시 벤더 기본: claude=lead/reviewer opus·그외 sonnet, codex=gpt-5.5(+effort).
# 워커는 claude 고정(codex 워커 배제 — P17 데드락). codex 는 security 리뷰어 전용.
# SESSION 미설정 → awa-up.sh 가 awa-web 자동 부여(default.sh 와 동일 관례 — 누락 아님).
WORKERS=(
  "frontend:frontend"
  "backend:backend"
  "infra:infra"
)
# 투표인단 3명(alignment·quality claude + security codex) + 메타 집계 1명(review-mgr).
# 회로① 합의 게이트: 투표인단 N=3 전원 blocking → 자동차단(다벤더 — claude×2 + codex×1).
# review-mgr pane 명 고정(REVIEW_MANAGER_PANE 조회 의존 — profiles/AGENTS.md §4).
REVIEWERS=(
  "alignment-rev:reviewer-alignment"
  "quality-rev:reviewer-quality"
  "security-rev:reviewer-security:codex"
  "review-mgr:review-manager"
)
