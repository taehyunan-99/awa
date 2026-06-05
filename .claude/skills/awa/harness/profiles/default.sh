# 기본 팀: 범용 구현(engineer) + 조사(researcher), 감시 리뷰어 alignment+quality(claude)+security(codex) 투표 + review-mgr 집계.
# 다벤더: 워커·alignment·quality = claude, security = codex(리뷰어 전용 — 워커=claude 전제, codex P17 데드락 무관).
LAYOUT="tiled"
# 형식: "워커이름:역할[:벤더][:모델]"
#   - 2필드 "engineer:engineer" → HARNESS_VENDOR 상속 + 역할 기본 모델(vendor_default_model)
#   - 3필드 "engineer:engineer:codex" → 벤더 명시 / "engineer:engineer:sonnet" → 모델 명시
#   - 4필드 "engineer:engineer:codex:gpt-5.5" → 벤더+모델
# 모델 미지정 시 벤더 기본: claude=orch/reviewer opus·그외 sonnet, codex=gpt-5.5(+effort).
# HARNESS_VENDOR="claude"   # (미설정 시 claude) 세션 기본 벤더
# reviewer 워커는 워커 풀에서 제거 — 감시 리뷰어(REVIEWERS)로 일원화.
WORKERS=(
  "engineer:engineer"
  "researcher:researcher"
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
