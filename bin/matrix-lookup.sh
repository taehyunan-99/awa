#!/usr/bin/env bash
# matrix_lookup + lead_auto_allow_lookup. source 시 부수효과 없음 (함수 정의만).
# bash 3.2 호환.

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
  local pat ptool pinner prefix
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    case "$pat" in
      *'('*)
        ptool="${pat%%(*}"
        pinner="${pat#*(}"; pinner="${pinner%)}"
        [ "$ptool" = "$tool" ] || continue
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
