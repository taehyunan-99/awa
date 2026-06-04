#!/usr/bin/env bash
# team 명세 yaml 파서 — 평면 2-depth 하위집합만. 코드 실행 0의 선언형.
# matrix-lookup.sh 의 awk 평탄화 컨벤션(키 줄 + 2칸 들여쓰기) 을 따른다.

# 스칼라 키 추출: "key: value" (최상위, 들여쓰기 0). $1=yaml $2=key
spec_parse_scalar() {
  local yaml="$1" key="$2"
  awk -v k="$key" '
    /^[[:space:]]/ { next }
    $0 ~ "^"k":" {
      sub("^"k":[[:space:]]*", "")
      sub(/[[:space:]]+$/, "")
      print; exit
    }
  ' "$yaml"
}

# workers:/reviewers: 블록 평탄화 → "kind<TAB>name<TAB>role<TAB>vendor<TAB>model"
spec_parse_flatten() {
  local yaml="$1"
  awk '
    BEGIN { kind=""; name=""; role=""; vendor=""; model="" }
    function emit() {
      if (name != "") printf "%s\t%s\t%s\t%s\t%s\n", kind, name, role, vendor, model
      name=""; role=""; vendor=""; model=""
    }
    /^workers:[[:space:]]*$/  { emit(); kind="worker";   next }
    /^reviewers:[[:space:]]*$/ { emit(); kind="reviewer"; next }
    /^[^[:space:]]/ { emit(); kind=""; next }
    kind == "" { next }
    /^[[:space:]]+-[[:space:]]+name:/ { emit(); sub(/^[[:space:]]+-[[:space:]]+name:[[:space:]]*/,""); sub(/[[:space:]]+$/,""); name=$0; next }
    /^[[:space:]]+role:/   { sub(/^[[:space:]]+role:[[:space:]]*/,"");   sub(/[[:space:]]+$/,""); role=$0;   next }
    /^[[:space:]]+vendor:/ { sub(/^[[:space:]]+vendor:[[:space:]]*/,""); sub(/[[:space:]]+$/,""); vendor=$0; next }
    /^[[:space:]]+model:/  { sub(/^[[:space:]]+model:[[:space:]]*/,"");  sub(/[[:space:]]+$/,""); model=$0;  next }
    END { emit() }
  ' "$yaml"
}
