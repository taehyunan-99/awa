#!/usr/bin/env bash
# team 명세 yaml 파서 — 평면 2-depth 하위집합만. 코드 실행 0의 선언형.
# matrix-lookup.sh 의 awk 평탄화 컨벤션(키 줄 + 2칸 들여쓰기) 을 따른다.

# 스칼라 키 추출: "key: value" (최상위, 들여쓰기 0). $1=yaml $2=key
spec_parse_scalar() {
  local yaml="$1" key="$2"
  awk -v k="$key" '
    /^[[:space:]]/ { next }
    # key 는 호출처에서 알파벳만 전달(session/layout/plan 등) — 정규식 메타문자 미가정.
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
      # kind 는 의도적으로 리셋 안 함 — 블록 내 연속 항목이 같은 kind 유지.
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

# 문법 화이트리스트 검증 — 위험 문법 발견 시 rc=1 + stderr 메시지.
# 거부: yaml 앵커(&)·별칭(*)·멀티라인(|/>)·플로우({}/[])·!! 태그·3-depth(6칸+ 들여쓰기).
spec_parse_validate() {
  local yaml="$1"
  [ -f "$yaml" ] || { echo "오류: 명세 파일 없음 → $yaml" >&2; return 1; }
  local bad
  bad="$(awk '
    /^[[:space:]]*#/ { next }
    /(^|[[:space:]])[&*]/                 { print "anchor/alias"; exit }
    /:[[:space:]]*[|>]([[:space:]]|$)/    { print "multiline"; exit }
    /[[{][^}]*[}\]]/                      { print "flow"; exit }
    /[][{}]/                              { print "flow"; exit }
    /!!/                                  { print "tag"; exit }
    /^[[:space:]]{6,}[^[:space:]]/        { print "depth>2"; exit }
  ' "$yaml")"
  if [ -n "$bad" ]; then
    echo "오류: team 명세에 허용되지 않는 yaml 문법($bad) → $yaml" >&2
    return 1
  fi
  return 0
}
