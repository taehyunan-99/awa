#!/usr/bin/env bash
# AWA attach splash — display-popup 안에서 실행되는 모달 첫 화면.
# 인자 없음. 팀 구성은 팀 요약 파일($AWA_SPLASH_TEAM_FILE)에서 읽는다.
# 닫힘: 끝의 read -t N -n1 (키 입력 OR N초 자동) → 반환 시 display-popup -E 가 닫음.
# tmux -k(any-key dismiss)에 의존하지 않는다 — -k 는 N초 타임아웃을 못 해주기 때문.
#
# 레이아웃은 /usr/bin/python3(시스템 stdlib, 의존성 없음)로 렌더한다 — bash 3.2 는
# 한글/블록문자의 터미널 표시폭(컬럼)을 신뢰성 있게 계산하지 못한다(wc -L/awk/${#}/read -n1
# 모두 바이트 기준이라 깨짐). python3 unicodedata.east_asian_width 만 정확하다.
set -u

# 팀 요약 파일 경로: env override(테스트) > 기본 런타임 경로.
TEAM_FILE="${AWA_SPLASH_TEAM_FILE:-$HOME/.cache/awa/team-summary.txt}"
TIMEOUT="${AWA_SPLASH_TIMEOUT:-5}"

# 256색 — 청록(브랜드)/회색(보조)/베이지(역할). NO_COLOR 존중 + tty 아니면 무색.
if [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then
  C_BRAND=$'\033[38;5;44m'; C_DIM=$'\033[38;5;245m'; C_ACC=$'\033[38;5;180m'; C_RST=$'\033[0m'
else
  C_BRAND=""; C_DIM=""; C_ACC=""; C_RST=""
fi

# 역할(bare) → 한국어 요약 매핑 (단일 출처). awa-up 은 raw role 만 파일에 쓴다.
# 매핑은 prompts/roles 실측: orch=팀 감독 / desk=사용자 창구 / dev·researcher=개발 /
# tester=품질 검증 / reviewer-*·review-manager=드리프트 추적 / security=안전 한계선.
splash_role_summary() {
  case "$1" in
    orch|lead)                  printf '팀 감독' ;;     # lead = 구 역할명 하위호환
    desk|pm)                    printf '사용자 창구' ;;  # pm = 구 역할명 하위호환
    reviewer-*|review-manager)  printf '드리프트 추적' ;;
    security)                   printf '안전 한계선' ;;
    dev|researcher)             printf '개발' ;;
    tester)                     printf '품질 검증' ;;
    *)                          printf '작업' ;;
  esac
}

# 커서 숨김 — popup 이 100% 덮어도 터미널 하드웨어 커서가 뒤 claude pane 위치에
# 비쳐 보인다(popup 은 tmux 가상 레이어). tty 일 때만 숨기고, 종료 시 반드시 복원.
if [ -t 1 ]; then
  printf '\033[?25l'                       # 커서 숨김
  trap 'printf "\033[?25h"' EXIT INT TERM   # 종료·인터럽트 시 복원
fi

# 터미널 크기 (popup 내부). 실패 시 기본값.
COLS="$( (tput cols) 2>/dev/null || echo 80 )"; [ "$COLS" -gt 0 ] 2>/dev/null || COLS=80
LINES_N="$( (tput lines) 2>/dev/null || echo 24 )"; [ "$LINES_N" -gt 0 ] 2>/dev/null || LINES_N=24

# 팀 표를 탭 구분 plain 행(이름\t요약\t모델)으로 모은다 — python 에 넘겨 폭 계산·정렬.
TEAM_ROWS=""
if [ -f "$TEAM_FILE" ]; then
  while IFS=$'\t' read -r _name _role _model || [ -n "$_name" ]; do
    [ -n "$_name" ] || continue
    _sum="$(splash_role_summary "$_role")"
    TEAM_ROWS="${TEAM_ROWS}${_name}	${_sum}	${_model:-}
"
  done < "$TEAM_FILE"
fi

# 레이아웃 렌더: 로고/태그라인/안내는 각 줄 중앙정렬, 팀 표는 표시폭 기준 열정렬 후
# 블록 전체를 중앙정렬. 전체 블록은 화면 세로 중앙(약간 위)에 배치.
# ANSI 이스케이프는 폭 계산에서 제외(중앙정렬 어긋남 방지).
# 팀 데이터는 env(AWA_TEAM_DATA)로 전달 — `python3 - <<HEREDOC` 는 stdin 을 스크립트
# 소스로 쓰므로 파이프 stdin 이 무시된다. env 가 따옴표/특수문자에도 안전.
AWA_TEAM_DATA="$TEAM_ROWS" /usr/bin/python3 - "$COLS" "$LINES_N" "$TIMEOUT" "$C_BRAND" "$C_DIM" "$C_ACC" "$C_RST" <<'PYEOF'
import sys, os, re, unicodedata as u

cols   = int(sys.argv[1])
rows_n = int(sys.argv[2])
timeout = sys.argv[3]
CB, CD, CA, CR = sys.argv[4], sys.argv[5], sys.argv[6], sys.argv[7]

ansi = re.compile(r'\033\[[0-9;]*m')
def width(s):
    # ANSI 제거 후 표시폭 — 한글/전각(W,F)=2칸, 그 외=1칸. 블록문자는 ambiguous(=1칸).
    s = ansi.sub('', s)
    return sum(2 if u.east_asian_width(c) in ("W", "F") else 1 for c in s)

def center(text):
    pad = max((cols - width(text)) // 2, 0)
    return " " * pad + text

def pad_to(text, target):  # 표시폭이 target 이 되도록 오른쪽 공백
    return text + " " * max(target - width(text), 0)

def truncate(text, limit):  # 표시폭이 limit 을 넘으면 … 로 자른다(표시폭 기준).
    if width(text) <= limit:
        return text
    ell = "…"
    budget = max(limit - width(ell), 0)
    acc, wsum = "", 0
    for c in text:
        cw = 2 if u.east_asian_width(c) in ("W", "F") else 1
        if wsum + cw > budget:
            break
        acc += c; wsum += cw
    return acc + ell

# 확정 로고 (봉우리 +1칸). half-block 은 ghostty 등에서 ambiguous=1칸으로 폭 일치.
LOGO = [
    "█▀▀█   █   █   █▀▀█",
    "█▄▄█   █ ▄ █   █▄▄█",
    "█  █   ▀▄▀▄▀   █  █",
]

rows = [r.split("\t") for r in os.environ.get("AWA_TEAM_DATA", "").splitlines() if r.strip()]

out = []
for line in LOGO:
    out.append(center(CB + line + CR))
out += ["", "", ""]                       # 로고-내용 여백 확대
# 태그라인 — "Watching" 만 브랜드색. 폭 계산은 plain 기준(center 가 ANSI 제외).
out.append(center(CD + "Agents " + CR + CB + "Watching" + CR + CD + " Agents" + CR))
out += ["", ""]
# 팀 표 — 표시폭 기준 열 정렬 후 블록 중앙정렬.
# 긴 값 대비: 표 블록 폭 상한 = 화면 폭의 70%(최소 40칸). 이름/요약 열에 개별 상한을
# 두고 초과분은 … 로 자른다(모델은 짧아 자르지 않음). 열은 내용에 맞춰 늘되 상한 안에서.
if rows:
    sep = 2                               # 열 사이 공백 폭
    block_cap = max(cols * 7 // 10, 40)   # 표 블록 폭 상한
    m_w = max((width(r[2]) for r in rows), default=0)  # 모델 열(자르지 않음)
    # 이름+요약에 쓸 수 있는 폭 = 상한 - 모델 - 간격 2개.
    avail = max(block_cap - m_w - sep * 2, 10)
    # 이름:요약 = 4:6 배분(이름이 보통 짧음). 각자 최소 6칸 보장.
    n_cap = max(avail * 4 // 10, 6)
    s_cap = max(avail - n_cap, 6)
    names = [truncate(r[0], n_cap) for r in rows]
    sums  = [truncate(r[1], s_cap) for r in rows]
    models = [r[2] for r in rows]
    c0 = max(width(x) for x in names)     # 이름 열(자른 뒤 실제 최대)
    c1 = max(width(x) for x in sums)      # 요약 열
    plain_rows = [pad_to(names[i], c0) + " " * sep + pad_to(sums[i], c1) + " " * sep + models[i]
                  for i in range(len(rows))]
    block_w = max(width(p) for p in plain_rows)
    # 구분선: "팀 구성" 을 블록 폭 중앙에 두고 양쪽을 ─ 로 채운다.
    label = " 팀 구성 "
    fill = max(block_w - width(label), 0)
    left = fill // 2
    div = "─" * left + label + "─" * (fill - left)
    bpad = " " * max((cols - block_w) // 2, 0)
    out.append(bpad + CD + div + CR)
    out.append("")                        # 구분선-표 사이 공백 한 줄
    for i in range(len(rows)):
        line = (CB + pad_to(names[i], c0) + CR + " " * sep
                + CA + pad_to(sums[i], c1) + CR + " " * sep + CD + models[i] + CR)
        out.append(bpad + line)
    out += ["", ""]
out.append(center(CA + "[아무 키] 또는 " + timeout + "초 뒤 시작" + CR))

# 세로 배치: 콘텐츠를 화면 세로 중앙보다 약간 위(40% 지점)에 둔다 — 위쪽 여백을 동적 계산.
top = max((rows_n - len(out)) * 2 // 5, 1)
sys.stdout.write("\n" * top + "\n".join(out) + "\n")
PYEOF

# 닫힘 대기: 키 입력 OR N초. read 실패(비정상 timeout 값 등)는 흡수 → 안전 반환.
read -t "$TIMEOUT" -n1 -r _ 2>/dev/null || true
