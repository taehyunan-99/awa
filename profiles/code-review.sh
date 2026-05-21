# 코드 리뷰 팀: 보안 워커 + 관점별 감시 리뷰어
LAYOUT="tiled"
# reviewer 워커는 워커 풀에서 제거 — 감시 리뷰어(REVIEWERS)로 일원화.
WORKERS=(
  "security:security"
)
REVIEWERS=("spec-rev:reviewer-spec:sonnet" "quality-rev:reviewer-quality:haiku" "arch-rev:reviewer-arch:opus")
LEAD_MODEL="opus"
