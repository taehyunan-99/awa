#!/usr/bin/env bash
# 테스트 더미 어댑터 — AGENT_CMD=cat 정식화. source 전용.
vendor_boot_cmd() { printf '%s' "${AGENT_CMD:-cat}"; }
vendor_wait_ready() { return 0; }
vendor_gen_settings() {
  local role="$1" entry_name="${2:-$1}"
  # awa-up 부트 경로(lib.sh source 됨)에서는 실제 settings 를 생성해야 함 — _test 는 boot
  # 명령만 더미(cat)로 바꾸는 어댑터지 settings 까지 stub 하지 않는다. claude 와 동형.
  # generate_worker_settings 가 보이면(=lib.sh 로드됨) 그것을 위임, 아니면 단독 stub 폴백.
  if command -v generate_worker_settings >/dev/null 2>&1; then
    generate_worker_settings "$role" "$entry_name"
    return $?
  fi
  local out_dir="${PROJECT_ROOT:-/tmp}/.agent-harness/.boot-settings"
  mkdir -p "$out_dir" 2>/dev/null || true
  local out="$out_dir/${role}.json"
  printf '{}' > "$out" 2>/dev/null || { printf ''; return 0; }
  printf '%s' "$out"
}
vendor_inject_role() { :; }
vendor_orch_plan_directive() { :; }
vendor_default_model() { echo "sonnet"; }
