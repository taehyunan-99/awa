# 기본 팀: 범용 구현(engineer) + 조사(researcher), 감시 리뷰어 alignment+quality 투표 + review-mgr 집계.
# 전부 claude (벤더 미지정 → HARNESS_VENDOR=claude 상속). codex 리뷰어는 전체 e2e 검증 후 추가.
LAYOUT="tiled"
# 형식: "워커이름:역할[:벤더][:모델]"
#   - 2필드 "engineer:engineer" → HARNESS_VENDOR 상속 + 역할 기본 모델(vendor_default_model)
#   - 3필드 "engineer:engineer:codex" → 벤더 명시 / "engineer:engineer:sonnet" → 모델 명시
#   - 4필드 "engineer:engineer:codex:gpt-5.5" → 벤더+모델
# 모델 미지정 시 벤더 기본: claude=lead/reviewer opus·그외 sonnet, codex=gpt-5.5(+effort).
# HARNESS_VENDOR="claude"   # (미설정 시 claude) 세션 기본 벤더
# reviewer 워커는 워커 풀에서 제거 — 감시 리뷰어(REVIEWERS)로 일원화.
WORKERS=(
  "engineer:engineer"
  "researcher:researcher"
)
# 투표인단 2명(alignment·quality) + 메타 집계 1명(review-mgr).
# 회로① 합의 게이트: 투표인단 N=2 전원 blocking → 자동차단(claude 단독 실증).
# review-mgr pane 명 고정(REVIEW_MANAGER_PANE 조회 의존 — profiles/AGENTS.md §4).
REVIEWERS=(
  "alignment-rev:reviewer-alignment"
  "quality-rev:reviewer-quality"
  "review-mgr:review-manager"
)
