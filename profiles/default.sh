# 기본 팀: 개발/테스트
SESSION="agents"
LAYOUT="tiled"
# 형식: "워커이름:역할"  (역할 → prompts/roles/<역할>.md)
# reviewer 워커는 워커 풀에서 제거 — 감시 리뷰어(REVIEWERS)로 일원화.
WORKERS=(
  "dev:dev"
  "test:tester"
)
REVIEWERS=("quality-rev:reviewer-quality:haiku")
ORCHESTRATOR_MODEL="opus"
