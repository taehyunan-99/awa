#!/usr/bin/env bash
# danger_check <tool> <input_json> → MATCH 면 exit 0 + stdout 카테고리, SAFE 면 exit 1.
# source 시 부수효과 없음. bash 3.2 + BSD ERE. \b/\s/\w 금지.
# BSD bash 3.2: ERE 를 변수에 담아 [[ "$x" =~ $re ]] 로 평가 (quoting 안 함 — quote 시 literal).

danger_check() {
  local tool="$1" input="$2"
  local cmd="" path="" re
  case "$tool" in
    Bash) cmd="$(printf '%s' "$input" | jq -r '.command // ""')" ;;
    Edit|Write) path="$(printf '%s' "$input" | jq -r '.file_path // ""')" ;;
  esac

  if [ -n "$cmd" ]; then
    re='(^|[^a-zA-Z0-9_/])rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*([[:space:]]|$)|--recursive([[:space:]]|$))'
    [[ "$cmd" =~ $re ]] && { echo rm-recursive; return 0; }
    re='(^|[^a-zA-Z0-9_])sudo([[:space:]]|$)'
    [[ "$cmd" =~ $re ]] && { echo sudo; return 0; }
    re='(^|[^a-zA-Z0-9_])dd[[:space:]].*of='
    [[ "$cmd" =~ $re ]] && { echo dd-write; return 0; }
    re='(^|[^a-zA-Z0-9_])chmod[[:space:]]+([0-7]?[0-7][0-7][2367]([[:space:]]|$)|.*(o|a)[+=][^,]*w)'
    [[ "$cmd" =~ $re ]] && { echo chmod-world; return 0; }
    re='(^|[^a-zA-Z0-9_])git[[:space:]]+push([[:space:]].*)?[[:space:]](-f([[:space:]]|$)|--force)'
    [[ "$cmd" =~ $re ]] && { echo git-force; return 0; }
    re='(^|[^a-zA-Z0-9_])git[[:space:]]+reset[[:space:]].*--hard'
    [[ "$cmd" =~ $re ]] && { echo git-reset-hard; return 0; }
    re='(^|[^a-zA-Z0-9_])git[[:space:]]+clean[[:space:]].*-[fdx]+'
    [[ "$cmd" =~ $re ]] && { echo git-clean-force; return 0; }
    re='>[[:space:]]*/dev/(sda|nvme|hd|disk)'
    [[ "$cmd" =~ $re ]] && { echo dev-write; return 0; }
    re='(^|[^a-zA-Z0-9_])curl([[:space:]].*)?\|[[:space:]]*(sh|bash|zsh)'
    [[ "$cmd" =~ $re ]] && { echo curl-pipe-sh; return 0; }
    re='(^|[^a-zA-Z0-9_])wget([[:space:]].*)?\|[[:space:]]*(sh|bash|zsh)'
    [[ "$cmd" =~ $re ]] && { echo wget-pipe-sh; return 0; }
    re='(^|[^a-zA-Z0-9_])eval([[:space:]].*)?\$\('
    [[ "$cmd" =~ $re ]] && { echo eval-stdin; return 0; }
    re=':[[:space:]]*\([[:space:]]*\)[[:space:]]*\{.*:\|:.*\}'
    [[ "$cmd" =~ $re ]] && { echo fork-bomb; return 0; }
    re='(^|[^a-zA-Z0-9_])rm[[:space:]].*[/~](home|Users)'
    [[ "$cmd" =~ $re ]] && { echo home-rm; return 0; }
    # ★ 재발 방지 가드(B): 하네스 본체 경로를 rm 대상으로 삼는 명령 거부.
    #   2026-05-30 소실 근본원인 — 일회용 스크립트의 `rm -rf "$PROJECT_ROOT"` 가
    #   lib.sh 의 PROJECT_ROOT 재계산으로 HARNESS_ROOT(=awa 본체)를 가리켜 통째 삭제.
    #   HARNESS_ROOT 가 set 돼 있을 때만 평가(source 시 lib.sh 가 export). literal 경로·
    #   $HARNESS_ROOT/$PROJECT_ROOT 변수형 모두 차단.
    if [ -n "${HARNESS_ROOT:-}" ]; then
      case "$cmd" in
        *rm\ *"$HARNESS_ROOT"*|*rm\ *'$HARNESS_ROOT'*|*rm\ *'$PROJECT_ROOT'*|*rm\ *'${PROJECT_ROOT}'*|*rm\ *'${HARNESS_ROOT}'*)
          echo harness-root-rm; return 0 ;;
      esac
    fi
    re='>[[:space:]]*(~|/(home|Users|root))(/[^[:space:]]+)?/\.ssh/'
    [[ "$cmd" =~ $re ]] && { echo dotssh-write; return 0; }
    re='(^|[^a-zA-Z0-9_])(bash|sh|zsh)[[:space:]]+-c([[:space:]]|$)'
    [[ "$cmd" =~ $re ]] && { echo bash-c-wrapper; return 0; }

    # ★ 7차 후속(보안 회귀 차단): Bash 명령이 민감 경로에 쓰기를 시도하면 danger.
    #   danger 의 경로규칙(아래 system-config/ssh-key/cred)은 Edit/Write file_path 에만 걸려
    #   Bash 리다이렉트·touch/chmod 인자는 무방비였음 → echo/touch/chmod +x auto-allow 가
    #   /etc/sudoers·~/.ssh·.env 를 통과시키는 권한상승·시크릿 누수 구멍(실측 확인).
    #   여기서 *쓰기 동작의 대상*으로 등장할 때만 잡아 따옴표 텍스트·커밋 메시지 오탐 회피.
    #   회피 한계(변수치환 $P·따옴표분할 /et"c"/)는 셸 AST 미재구현 → 워커 deny + claude 권한모델이 다층 방어.
    # SENS_PATH: 절대 시스템 경로 + 홈 dotdir(.ssh/.aws/.gnupg) + 홈 dotfile(.bashrc 등).
    local SENS_PATH='(/etc/|/System/|/private/etc/|/usr/(bin|lib|sbin)/|(~|/(home|Users|root)/[^[:space:]]*)/\.(ssh|aws|gnupg)/|(~|/(home|Users|root)/[^[:space:]]*)/\.(bash(rc|_profile|_login|_logout)|zshrc|zprofile|profile|netrc|pgpass))'
    # 가드1: 리다이렉트(> >> >|) 직후 (선택적 따옴표) 민감 경로.
    #   >| 는 noclobber 강제 덮어쓰기 표준 형식 — 한 글자 추가로 가드 우회되던 구멍(실측) → \|? 로 흡수.
    re=">>?\|?[[:space:]]*['\"]?${SENS_PATH}"
    [[ "$cmd" =~ $re ]] && { echo sensitive-write; return 0; }
    # 가드2: 리다이렉트 직후 .env/.credentials 파일 (경로 세그먼트 끝).
    re=">>?\|?[[:space:]]*['\"]?([^[:space:]'\"]*/)?(\.env|\.credentials)(['\"[:space:]]|$|;|&|\|)"
    [[ "$cmd" =~ $re ]] && { echo sensitive-write; return 0; }
    # 가드3: 파일 변형 명령(touch/chmod/cp/mv/ln/tee/install) 인자에 민감 경로.
    re="(^|[^a-zA-Z0-9_])(touch|chmod|cp|mv|ln|tee|install)([[:space:]]+[^[:space:];&|]*)*[[:space:]]+['\"]?[^[:space:]'\"]*${SENS_PATH}"
    [[ "$cmd" =~ $re ]] && { echo sensitive-write; return 0; }
    # 가드4: 파일 변형 명령 인자에 .env/.credentials.
    re="(^|[^a-zA-Z0-9_])(touch|chmod|cp|mv|ln|tee|install)([[:space:]]+[^[:space:];&|]*)*[[:space:]]+['\"]?([^[:space:]'\"]*/)?(\.env|\.credentials)(['\"[:space:]]|$|;|&|\|)"
    [[ "$cmd" =~ $re ]] && { echo sensitive-write; return 0; }
  fi

  if [ -n "$path" ]; then
    re='^(/etc/|/System/|/usr/(bin|lib|sbin)/)'
    [[ "$path" =~ $re ]] && { echo system-config-edit; return 0; }
    re='\.ssh/(authorized_keys|id_(ed25519|rsa|ecdsa))'
    [[ "$path" =~ $re ]] && { echo ssh-key-edit; return 0; }
    re='(\.env|\.credentials|/\.aws/credentials|/aws/credentials)$'
    [[ "$path" =~ $re ]] && { echo cred-file-edit; return 0; }
  fi

  return 1
}

# Task 7 NEW — CLI mode: --check-allow-yaml <yaml_path>
# allow ∩ deny 충돌 검증 (C5 PASS 조건). exit 0=PASS, 1=충돌 발견.
# 기존 danger_check 함수는 그대로 — source 시 부수효과 없음 유지.
if [ "${1:-}" = "--check-allow-yaml" ]; then
  yaml="${2:-}"
  if [ ! -f "$yaml" ]; then
    echo "[ABORT] yaml 미존재: $yaml" >&2
    exit 1
  fi

  # yaml 안의 모든 패턴 추출 (단순 awk — `  - "..."` 라인).
  patterns="$(awk '/^  - "/ { gsub(/^  - "|"$/, ""); print }' "$yaml")"

  # C-2 정정 — 다중 fake input. 패턴 'Bash(git push:*)' 가 '--force' 등 위험 토큰을
  # 만나면 danger 매치되는데, 단일 'arg1 arg2' probe 로는 검출 못 함. 다중 probe 로 보강.
  DANGER_PROBES="arg1 arg2
--force
-rf /
-f /
--hard HEAD
of=/dev/sda
| sh"

  conflicts=0
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    # 패턴이 Bash(<command>:*) / Edit(<path>) / Write(<path>) 형식이면 danger_check 시도.
    case "$pat" in
      'Bash('*)
        cmd_prefix="${pat#Bash(}"
        cmd_prefix="${cmd_prefix%:\*)}"
        cmd_prefix="${cmd_prefix%\)}"
        matched=0
        while IFS= read -r probe; do
          [ -n "$probe" ] || continue
          # fake input json — danger_check 가 .command 만 읽음.
          input_json="$(printf '{"command":"%s"}' "$cmd_prefix $probe")"
          if cat="$(danger_check "Bash" "$input_json")"; then
            echo "[CONFLICT] allow 패턴 '$pat' (probe='$probe') → danger '$cat'" >&2
            conflicts=$((conflicts + 1))
            matched=1
            break  # 패턴당 1회만 보고 — 다중 probe FAIL 폭주 방지
          fi
        done <<PROBES
$DANGER_PROBES
PROBES
        ;;
      'Edit('*|'Write('*)
        # I-7 정정 — Edit/Write 패턴도 danger_check path 분기로 검사.
        tool="${pat%%(*}"
        path_arg="${pat#*(}"; path_arg="${path_arg%)}"
        # glob 제거 — /etc/sudoers/* → /etc/sudoers
        path_arg="${path_arg%/\*}"
        path_arg="${path_arg%\*}"
        input_json="$(printf '{"file_path":"%s"}' "$path_arg")"
        if cat="$(danger_check "$tool" "$input_json")"; then
          echo "[CONFLICT] allow 패턴 '$pat' → danger '$cat'" >&2
          conflicts=$((conflicts + 1))
        fi
        ;;
    esac
  done <<EOF
$patterns
EOF

  [ "$conflicts" -eq 0 ] && exit 0 || exit 1
fi
