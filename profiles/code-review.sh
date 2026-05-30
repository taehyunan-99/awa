# 코드 리뷰 팀: 보안 워커 + 관점별 감시 리뷰어
LAYOUT="tiled"
# 형식: "워커이름:역할[:벤더][:모델]"
#   - 2필드 "dev:dev" → HARNESS_VENDOR 상속 + 역할 기본 모델(vendor_default_model)
#   - 3필드 "dev:dev:codex" → 벤더 명시(화이트리스트면) / "dev:dev:sonnet" → 모델 명시
#   - 4필드 "dev:dev:codex:gpt-5.5" → 벤더+모델
# 모델 미지정 시 벤더 기본: claude=lead/reviewer opus·그외 sonnet, codex=gpt-5.5(+effort).
# HARNESS_VENDOR="claude"   # (미설정 시 claude) 세션 기본 벤더 — 미지정 워커/lead/pm 상속
# LEAD_VENDOR=""            # 빈값 → HARNESS_VENDOR 상속
# PM_VENDOR=""
# reviewer 워커는 워커 풀에서 제거 — 감시 리뷰어(REVIEWERS)로 일원화.
WORKERS=(
  "security:security"
)
REVIEWERS=("spec-rev:reviewer-spec" "quality-rev:reviewer-quality" "arch-rev:reviewer-arch")
