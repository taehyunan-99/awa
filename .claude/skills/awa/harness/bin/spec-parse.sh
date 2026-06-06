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
  [ -f "$yaml" ] && [ -r "$yaml" ] || { echo "오류: 명세 파일 없음/읽기불가 → $yaml" >&2; return 1; }
  local bad
  bad="$(awk '
    /^[[:space:]]*#/ { next }
    /(^|[[:space:]])[&*]/                 { print "anchor/alias"; exit }
    /:[[:space:]]*[|>]([[:space:]]|$)/    { print "multiline"; exit }
    /:[[:space:]]*[[{]/                   { print "flow"; exit }
    /^[[:space:]]*-[[:space:]]*[[{]/      { print "flow"; exit }
    /!!/                                  { print "tag"; exit }
    /^[[:space:]]{6,}[^[:space:]]/        { print "depth>2"; exit }
  ' "$yaml")"
  if [ -n "$bad" ]; then
    echo "오류: team 명세에 허용되지 않는 yaml 문법($bad) → $yaml" >&2
    return 1
  fi
  return 0
}

# 리뷰어 불변식 — 투표 리뷰어(reviewer-alignment/quality/security) 는 0 또는 2+ 만 허용.
#   1) voters==1 금지 — multi-reviewed 정체성상 1명은 합의가 아니라 단독거부권(반쪽 합의)
#      → 교차검증·drift 불성립. 무리뷰(0)는 정당(자유 조합 시 사용자 선택).
#   2) voters>=2 이면 review-manager 역할 필수(없으면 drift-check silent skip).
#   둘 다 rc=1 + stderr.
spec_parse_invariants() {
  local yaml="$1"
  [ -f "$yaml" ] && [ -r "$yaml" ] || { echo "오류: 명세 파일 없음/읽기불가 → $yaml" >&2; return 1; }
  local flat; flat="$(spec_parse_flatten "$yaml")"
  local voters mgr
  read -r voters mgr <<< "$(printf '%s\n' "$flat" | awk -F'\t' '
    { r=tolower($3) }
    $1=="reviewer" && (r=="reviewer-alignment"||r=="reviewer-quality"||r=="reviewer-security") { v++ }
    $1=="reviewer" && r=="review-manager" { m++ }
    END { print v+0, m+0 }
  ')"
  if [ "$voters" -eq 1 ]; then
    echo "오류: 투표 리뷰어 1명은 합의가 아닌 단독거부권 — 0(무리뷰) 또는 2명+ 만 허용(multi-reviewed)" >&2
    return 1
  fi
  if [ "$voters" -ge 2 ] && [ "$mgr" -eq 0 ]; then
    echo "오류: 투표 리뷰어 ${voters}명 있으나 review-manager 없음 — drift-check 무력화(spec §4)" >&2
    return 1
  fi
  return 0
}

# yaml → WORKERS/REVIEWERS/SESSION/LAYOUT 환산. validate+invariants 선행.
# 빈 vendor/model 은 절삭. 출력: "name:role" / "name:role:vendor" / "name:role:vendor:model" /
#   "name:role:model"(vendor 없이 model 만). awa-up.sh 의 "이름:역할[:벤더][:모델]" 파싱과 정합.
# ★ WORKERS/REVIEWERS 는 bash 배열 — export 불가. 반드시 호출 셸과 같은 스코프에서 실행
#   (서브셸 `$(spec_parse_load ...)` 금지). awa-up 은 source 된 함수를 직접 호출하므로 정합.
spec_parse_load() {
  local yaml="$1"
  spec_parse_validate "$yaml" || return 1
  spec_parse_invariants "$yaml" || return 1
  WORKERS=(); REVIEWERS=()
  SESSION="$(spec_parse_scalar "$yaml" session)"
  LAYOUT="$(spec_parse_scalar "$yaml" layout)"
  local kind name role vendor model entry line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    kind="${line%%	*}";   line="${line#*	}"
    name="${line%%	*}";   line="${line#*	}"
    role="${line%%	*}";   line="${line#*	}"
    vendor="${line%%	*}"; line="${line#*	}"
    model="$line"
    [ -n "$name" ] || continue
    # 버그2: name 문자셋 검증 — awa-up parse_entry 와 동일 규칙 [A-Za-z0-9_-]
    case "$name" in *[!A-Za-z0-9_-]*) echo "오류: 워커/리뷰어 이름에 허용되지 않는 문자 → '$name'" >&2; return 1 ;; esac
    # 버그3: role 누락/허용되지 않는 문자 검증
    case "$role" in ""|*[!A-Za-z0-9_-]*) echo "오류: 역할 누락/허용되지 않는 문자 → name='$name' role='$role'" >&2; return 1 ;; esac
    entry="$name:$role"
    # vendor 있으면 "name:role:vendor[:model]". vendor 없이 model 만 있으면 "name:role:model"
    #   — awa-up parse_entry 의 3필드 §2.2 규칙(알려진 벤더 아니면 model 해석)과 정합.
    if [ -n "$vendor" ]; then
      entry="$entry:$vendor"
      [ -n "$model" ] && entry="$entry:$model"
    elif [ -n "$model" ]; then
      entry="$entry:$model"
    fi
    case "$kind" in
      worker)   WORKERS+=("$entry") ;;
      reviewer) REVIEWERS+=("$entry") ;;
    esac
  done < <(spec_parse_flatten "$yaml")
  export SESSION LAYOUT
  return 0
}
