# 리서치 팀: 리서처 3 병렬 조사
LAYOUT="tiled"
# 형식: "워커이름:역할[:벤더][:모델]"
#   - 2필드 "dev:dev" → HARNESS_VENDOR 상속 + 역할 기본 모델(vendor_default_model)
#   - 3필드 "dev:dev:codex" → 벤더 명시(화이트리스트면) / "dev:dev:sonnet" → 모델 명시
#   - 4필드 "dev:dev:codex:gpt-5.5" → 벤더+모델
# 모델 미지정 시 벤더 기본: claude=orch/reviewer opus·그외 sonnet, codex=gpt-5.5(+effort).
# HARNESS_VENDOR="claude"   # (미설정 시 claude) 세션 기본 벤더 — 미지정 워커/orch/desk 상속
# ORCH_VENDOR=""           # 빈값 → HARNESS_VENDOR 상속 (구 LEAD_VENDOR 도 인식)
# DESK_VENDOR=""           # (구 PM_VENDOR 도 인식)
WORKERS=(
  "research1:researcher"
  "research2:researcher"
  "research3:researcher"
)
REVIEWERS=("quality-rev:reviewer-quality")
