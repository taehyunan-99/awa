#!/usr/bin/env bash
# matrix_lookup + lead_auto_allow_lookup. source 시 부수효과 없음 (함수 정의만).
# bash 3.2 호환.

# 경로를 실물경로(심링크 해소)로 정규화. 신규 Write 라 파일 자체는 미존재 가능 →
# *부모 디렉토리*를 cd && pwd -P 로 해소 후 basename 재결합. 상대경로는 cwd 기준.
# cd 실패(부모 미존재)면 원본 유지(정규화 불가 — scope_match 가 안전하게 처리).
# 빈 값은 그대로. (공통산출 특례 permission-gate.sh 와 동일 원리, DRY 불가라 국소 복제)
_realpath_field() {
  local p="$1" d b rd
  [ -n "$p" ] || { printf '%s' "$p"; return 0; }
  d="$(dirname "$p")"; b="$(basename "$p")"
  if rd="$(cd "$d" 2>/dev/null && pwd -P)"; then
    printf '%s/%s' "$rd" "$b"
    return 0
  fi
  # leaf 의 부모가 *아직 없으면*(신규 파일 Write 의 미존재 하위경로) cd 실패 → 원본 반환 시
  # 패턴 쪽만 정규화돼 비대칭 봉쇄. 존재하는 *최상위 조상*까지 정규화하고 미존재 tail 을 부착해
  # 패턴(glob 앞 dir 정규화)과 같은 정규형으로 맞춘다. (R8/R9 회귀)
  local rest="$b" anc="$d" anc_rd
  while [ -n "$anc" ] && [ "$anc" != "/" ] && [ "$anc" != "." ]; do
    if anc_rd="$(cd "$anc" 2>/dev/null && pwd -P)"; then
      printf '%s/%s' "$anc_rd" "$rest"
      return 0
    fi
    rest="$(basename "$anc")/$rest"
    anc="$(dirname "$anc")"
  done
  printf '%s' "$p"   # 조상 어디도 존재 안 함(절대경로 아니거나 완전 미존재) → 원본 보존
}

# allow 패턴 inner(예: /var/proj/review/** 또는 /var/proj/.review-cursor.*)의
# glob(* 또는 **) *앞* 고정 디렉토리 prefix 만 실물경로화. glob 이하는 보존.
# glob 없으면 전체를 _realpath_field 처리. field 와 같은 정규형으로 맞춰 심링크 어긋남 차단.
_realpath_pattern() {
  local pat="$1" head tail rd
  case "$pat" in
    /*) : ;;            # 절대경로 패턴만 정규화 대상
    *) printf '%s' "$pat"; return 0 ;;  # 비경로/상대 패턴은 그대로
  esac
  case "$pat" in
    *'*'*)
      # 첫 '*' 앞까지를 head 로, 그 이후를 tail 로 분리. head 의 마지막 / 까지가 고정 dir.
      head="${pat%%\**}"; tail="${pat#"$head"}"
      local dir="${head%/*}"
      if [ -n "$dir" ]; then
        # 고정 dir 을 _realpath_field 로 정규화 — *미존재 dir 도 조상까지 정규화*해
        # field 측(미존재 leaf 조상 정규화)과 같은 정규형으로 통일(역방향 비대칭 차단, R10).
        rd="$(_realpath_field "$dir")"
        printf '%s/%s' "$rd" "${head#"$dir"/}$tail"
      else
        printf '%s' "$pat"
      fi ;;
    *) _realpath_field "$pat" ;;   # glob 없는 정확 경로 패턴
  esac
}

# settings.allow 패턴과 input 비교 → MATCH 면 exit 0 + stdout 에 패턴.
# $1=entry_role $2=tool $3=input_json
matrix_lookup() {
  local entry_role="$1" tool="$2" input="$3"
  local settings="${PROJECT_ROOT}/.agent-harness/.boot-settings/${entry_role}.json"
  [ -f "$settings" ] || return 1
  local allows
  allows="$(jq -r '.permissions.allow // [] | .[]' "$settings" 2>/dev/null)"
  # spec §5.1: add_to_allow 의 mv rename 과 동시 read 시 fd 가 구버전 잡아 빈 결과 가능 →
  # 재시도 1회(E8 결정성 보강). 재시도도 비면 NO_MATCH (lead-auto-allow/pending 으로 흘러 재처리).
  if [ -z "$allows" ]; then
    sleep 0.05
    allows="$(jq -r '.permissions.allow // [] | .[]' "$settings" 2>/dev/null)"
  fi
  [ -n "$allows" ] || return 1
  local field key
  case "$tool" in
    Bash) key="command" ;;
    Edit|Write) key="file_path" ;;
    *) key="" ;;
  esac
  if [ -n "$key" ]; then
    field="$(printf '%s' "$input" | jq -r --arg k "$key" '.[$k] // ""')"
  else
    field=""
  fi
  # Edit/Write file_path 실물경로 정규화 (2026-06-01 라이브 e2e 결함).
  # 결함: 도구가 상대경로(.agent-harness/review/x.md)로 호출하면 settings allow 의
  #   절대패턴과 매칭 실패 → gray 봉쇄. 같은 권한인데 호출자 경로 표기(상대 vs 절대)에 따라
  #   게이트 결과가 갈리는 비결정성 → N=2 합의 무작위 봉쇄.
  # 추가 함정(심링크): settings allow 패턴은 awa-up 의 --project 값(예 macOS /var/...,
  #   심링크)으로 생성되는데, 런타임 PROJECT_ROOT 은 lib.sh 가 git toplevel 로 재계산해
  #   실물경로(/private/var/...)가 된다. → 한쪽만 정규화하면 /private/var vs /var 로 어긋남.
  # 해법: field 와 매칭 대상 패턴의 경로를 *둘 다* 실물경로(pwd -P)로 통일(공통산출 특례와
  #   동일 원리 — _fp·_hp 양쪽 해소). field 는 부모 dir 정규화(신규 Write 미존재 대응),
  #   패턴은 glob 앞 고정 prefix 만 정규화(_norm_path_field). 상대/절대·심링크 무관 결정적.
  case "$tool" in
    Edit|Write) field="$(_realpath_field "$field")" ;;
  esac
  local pat ptool pinner prefix
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    case "$pat" in
      *'('*)
        ptool="${pat%%(*}"
        pinner="${pat#*(}"; pinner="${pinner%)}"
        [ "$ptool" = "$tool" ] || continue
        # Edit|Write 패턴 경로를 field 와 같은 실물경로 정규형으로 통일(심링크 어긋남 차단).
        # 매칭에만 사용 — stdout 출력은 원본 $pat 유지(gate.log 가독성·기존 동작 보존).
        case "$tool" in Edit|Write) pinner="$(_realpath_pattern "$pinner")" ;; esac
        case "$pinner" in
          *':*')
            prefix="${pinner%:\*}"
            prefix_match "$prefix" "$field" && { printf '%s' "$pat"; return 0; }
            ;;
          *' *')
            # space-glob 형식 (4차 P0 컨벤션): prefix 뒤 공백+*
            prefix="${pinner% \*}"
            prefix_match "$prefix" "$field" && { printf '%s' "$pat"; return 0; }
            ;;
          *'*'*)
            # 결함 B: Edit/Write 의 file_path 스코프 glob (예: Write(/proj/**), Edit(/proj/*)).
            # ':*'·' *'(Bash prefix glob)에 안 걸린 나머지 inner glob 을 경로 의미론으로 매칭.
            # scope_match(lib.sh)에 위임: **→.* / *→[^/]* / .→\. + ^...$ 앵커 (DRY).
            # ★ Edit|Write 한정: command 엔 '/' 가 흔해 Bash 의 중간 glob(예: Bash(git * main))을
            #   경로 의미론(scope_match)으로 처리하면 오작동 → file_path 도구만 위임 (안전).
            #   Bash 패턴은 거의 ':*'/' *' 형식이라 이 케이스 도달 전 위에서 잡힘.
            case "$tool" in
              Edit|Write)
                scope_match "$field" "$pinner" && { printf '%s' "$pat"; return 0; }
                ;;
            esac
            ;;
          *)
            [ "$field" = "$pinner" ] && { printf '%s' "$pat"; return 0; }
            ;;
        esac
        ;;
      *)
        [ "$pat" = "$tool" ] && { printf '%s' "$pat"; return 0; }
        ;;
    esac
  done <<EOF
$allows
EOF
  return 1
}

# lead-auto-allow.yaml 카테고리 순서대로 패턴 매칭 → MATCH 면 exit 0 + "category:pattern".
# $1=tool $2=input_json
lead_auto_allow_lookup() {
  local tool="$1" input="$2"
  local yaml="${PROJECT_ROOT}/config/lead-auto-allow.yaml"
  # P2 수정(2026-05-30) — 기본 카탈로그 + 프로젝트 학습 파일을 함께 매칭 대상으로.
  #   learned 쓰기가 .agent-harness/learned-allow.yaml 로 분리됐으므로(lib.sh confirm_allow_yaml)
  #   읽기도 둘 다 평탄화해야 학습 패턴이 게이트에 즉시 반영된다.
  local learned_yaml="${PROJECT_ROOT}/.agent-harness/learned-allow.yaml"
  [ -f "$yaml" ] || return 1
  local field key
  case "$tool" in
    Bash) key="command" ;;
    Edit|Write) key="file_path" ;;
    *) key="" ;;
  esac
  if [ -n "$key" ]; then
    field="$(printf '%s' "$input" | jq -r --arg k "$key" '.[$k] // ""')"
  else
    field=""
  fi
  # awk 파서: "category:" 줄 + "  - "pattern"" 줄을 "category<TAB>pattern" 으로 평탄화.
  # 단순 형식만 지원 (§5.9): category: + 들여쓰기 2칸 + - "패턴". 주석(#) 줄 무시.
  # 두 파일 전달 — awk 가 각 파일 시작 시 cat 초기화(FNR==1)해 카테고리 누수 방지.
  local flat yaml_args=("$yaml")
  [ -f "$learned_yaml" ] && yaml_args+=("$learned_yaml")
  flat="$(awk '
    FNR==1 { cat="" }
    /^[[:space:]]*#/ { next }
    /^[a-zA-Z][a-zA-Z0-9_-]*:[[:space:]]*$/ { cat=$1; sub(/:$/,"",cat); next }
    /^[[:space:]]+-[[:space:]]/ {
      line=$0
      sub(/^[[:space:]]+-[[:space:]]*/,"",line)
      gsub(/^"|"$/,"",line)
      if (cat != "") print cat "\t" line
    }
  ' "${yaml_args[@]}")"
  local catname pat ptool pinner prefix
  while IFS="$(printf '\t')" read -r catname pat; do
    [ -n "$pat" ] || continue
    case "$pat" in
      *'('*)
        ptool="${pat%%(*}"
        pinner="${pat#*(}"; pinner="${pinner%)}"
        [ "$ptool" = "$tool" ] || continue
        case "$pinner" in
          *':*')
            prefix="${pinner%:\*}"
            prefix_match "$prefix" "$field" && { printf '%s:%s' "$catname" "$pat"; return 0; }
            ;;
          *)
            [ "$field" = "$pinner" ] && { printf '%s:%s' "$catname" "$pat"; return 0; }
            ;;
        esac
        ;;
      *)
        [ "$pat" = "$tool" ] && { printf '%s:%s' "$catname" "$pat"; return 0; }
        ;;
    esac
  done <<EOF
$flat
EOF
  return 1
}
