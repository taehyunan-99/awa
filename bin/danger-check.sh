#!/usr/bin/env bash
# danger_check <tool> <input_json> → MATCH 면 exit 0 + stdout 카테고리, SAFE 면 exit 1.
# source 시 부수효과 없음. bash 3.2 + BSD ERE. \b/\s/\w 금지.
# BSD bash 3.2: ERE 를 변수에 담아 [[ "$x" =~ $re ]] 로 평가 (quoting 안 함 — quote 시 literal).

danger_check() {
  local tool="$1" input="$2"
  local cmd="" path="" re
  case "$tool" in
    Bash) cmd="$(printf '%s' "$input" | jq -r '.command // ""')" ;;
    Edit|Write|MultiEdit) path="$(printf '%s' "$input" | jq -r '.file_path // ""')" ;;
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
    re='>[[:space:]]*(~|/(home|Users|root))(/[^[:space:]]+)?/\.ssh/'
    [[ "$cmd" =~ $re ]] && { echo dotssh-write; return 0; }
    re='(^|[^a-zA-Z0-9_])(bash|sh|zsh)[[:space:]]+-c([[:space:]]|$)'
    [[ "$cmd" =~ $re ]] && { echo bash-c-wrapper; return 0; }
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
