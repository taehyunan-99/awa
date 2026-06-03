#!/usr/bin/env bash
# config/lead-auto-allow.yaml 의 카테고리 매칭 (실제 yaml + matrix-lookup).
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
export HARNESS_PROJECT="$ROOT"   # config/lead-auto-allow.yaml 이 ROOT/config 에 있음
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh"
# shellcheck disable=SC1091
source "$ROOT/bin/matrix-lookup.sh"

[ -f "$ROOT/config/lead-auto-allow.yaml" ]; assert_success "$?" "yaml 존재"

echo "[Y1] read-only 매칭"
out="$(lead_auto_allow_lookup Bash '{"command":"ls /tmp"}')"
assert_eq "read-only:Bash(ls:*)" "$out" "Y1 ls → read-only"

echo "[Y2] safe-test 매칭"
out="$(lead_auto_allow_lookup Bash '{"command":"pytest tests/"}')"
assert_eq "safe-test:Bash(pytest:*)" "$out" "Y2 pytest → safe-test"

echo "[Y3] git-readonly 매칭"
out="$(lead_auto_allow_lookup Bash '{"command":"git status"}')"
assert_eq "git-readonly:Bash(git status:*)" "$out" "Y3 git status"

echo "[Y4] 위험 명령 미포함 (rm -rf 는 매칭 안 됨 — danger-check 영역)"
lead_auto_allow_lookup Bash '{"command":"rm -rf /tmp"}' >/dev/null
assert_fail "$?" "Y4 rm -rf 미매칭"

echo "[Y5] dev-deps lock-file 기반만 (npm install <pkg> 미매칭)"
lead_auto_allow_lookup Bash '{"command":"npm install evil-pkg"}' >/dev/null
assert_fail "$?" "Y5 npm install <pkg> 미매칭 (공급망 보수 정책)"
out="$(lead_auto_allow_lookup Bash '{"command":"npm ci"}')"
assert_eq "dev-deps:Bash(npm ci:*)" "$out" "Y5 npm ci 매칭"

echo "[Y6] safe-fs: chmod +x 매칭"
out="$(lead_auto_allow_lookup Bash '{"command":"chmod +x todo.sh"}')"
assert_eq "safe-fs:Bash(chmod +x:*)" "$out" "Y6 chmod +x → safe-fs"

echo "[Y7] safe-fs: mkdir / touch 매칭"
out="$(lead_auto_allow_lookup Bash '{"command":"mkdir tests"}')"
assert_eq "safe-fs:Bash(mkdir:*)" "$out" "Y7 mkdir → safe-fs"
out="$(lead_auto_allow_lookup Bash '{"command":"touch a.txt"}')"
assert_eq "safe-fs:Bash(touch:*)" "$out" "Y7 touch → safe-fs"

echo "[Y9] git-write: 로컬 git 쓰기 매칭 (add/commit 만 — checkout/switch 는 회색)"
out="$(lead_auto_allow_lookup Bash '{"command":"git add todo.sh"}')"
assert_eq "git-write:Bash(git add:*)" "$out" "Y9 git add → git-write"
out="$(lead_auto_allow_lookup Bash '{"command":"git commit -m x"}')"
assert_eq "git-write:Bash(git commit:*)" "$out" "Y9 git commit → git-write"

echo "[Y10] read-only 보강: diff / which / echo 매칭"
out="$(lead_auto_allow_lookup Bash '{"command":"diff -u a b"}')"
assert_eq "read-only:Bash(diff:*)" "$out" "Y10 diff → read-only"
out="$(lead_auto_allow_lookup Bash '{"command":"which jq"}')"
assert_eq "read-only:Bash(which:*)" "$out" "Y10 which → read-only"
out="$(lead_auto_allow_lookup Bash '{"command":"echo hi"}')"
assert_eq "read-only:Bash(echo:*)" "$out" "Y10 echo → read-only"

echo "[Y12] harness-infra: 워커 완료신호 인프라 명령 박제 (P2 수정 2026-05-30)"
# tmux wait-for(완료 신호) + printf(events.log done 라인) 은 prompts/_common.md 가
# 워커에게 시키는 하니스 내부 통신 → 첫 사이클부터 게이트 미발생해야 함.
out="$(lead_auto_allow_lookup Bash '{"command":"tmux wait-for -S done-awa-x-dev-T1"}')"
assert_eq "harness-infra:Bash(tmux wait-for:*)" "$out" "Y12 tmux wait-for → harness-infra"
out="$(lead_auto_allow_lookup Bash '{"command":"printf x >> .agent-harness/events.log"}')"
assert_eq "harness-infra:Bash(printf:*)" "$out" "Y12 printf → harness-infra"

echo "[Y11] 의도적 회색 유지 (데이터손실 인지 — 사람 1회 승인)"
# ★ 정책 전환 (2026-06-01, self-verify): `bash ./X`·`./X` 는 *더이상 회색이 아니라 self-verify auto*.
#   근거 = AWA 정체성(무인 자동 운영 — lead.md ⓐ 이벤트 반응형·격리 --project). 그 환경엔 '사람 1회
#   승인' 주체가 없어 engineer 자가검증이 영영 봉쇄(결함 #1 실측). deny-bounded 한계선은 exec-sensitive
#   (danger)가 지킴 — 시스템·민감 경로 실행은 여전히 무조건 차단. 안전=danger / 편의=auto 책임 분리.
#   단 git checkout/switch 는 데이터손실 위험이라 self-verify 와 무관하게 *여전히 회색*(아래 유지).
lead_auto_allow_lookup Bash '{"command":"git checkout -- todo.sh"}' >/dev/null
assert_fail "$?" "Y11 git checkout 은 회색 (데이터손실 인지)"
lead_auto_allow_lookup Bash '{"command":"git switch main"}' >/dev/null
assert_fail "$?" "Y11 git switch 는 회색"

echo "[Y11b] self-verify: 프로젝트 내부 스크립트 실행 → auto (결함 #1 봉쇄 해소)"
# 무인 환경 봉쇄 해소 — engineer 자가검증(`bash ./x.sh`·`. ./x.sh`)이 auto-allow.
out="$(lead_auto_allow_lookup Bash '{"command":"bash ./test.sh"}')"
assert_eq "self-verify:Bash(bash :*)" "$out" "Y11b bash ./X → self-verify"
out="$(lead_auto_allow_lookup Bash '{"command":". ./src/range.sh && range_sum 1 5"}')"
assert_eq "self-verify:Bash(. :*)" "$out" "Y11b . ./X → self-verify"
out="$(lead_auto_allow_lookup Bash '{"command":"source ./tests/t.sh"}')"
assert_eq "self-verify:Bash(source :*)" "$out" "Y11b source ./X → self-verify"
# ★ self-verify 는 lead_auto_allow_lookup 단독으론 시스템경로도 매칭(auto)하지만, classify 종단에선
#   danger(exec-sensitive)가 *먼저* 평가돼 차단됨. 여기선 auto 단 격리 검증이라 danger 미적용 —
#   `bash /etc/passwd` 가 self-verify 로 잡히는 건 정상(종단 안전은 classify 평가순서가 보장, test-self-verify-gate S4 검증).
out="$(lead_auto_allow_lookup Bash '{"command":"bash /etc/passwd"}')"
assert_eq "self-verify:Bash(bash :*)" "$out" "Y11b bash /절대 → auto단 self-verify (종단은 danger 우선)"

echo "[Y12] read-only 확대 — 부작용 0 출력 도구 (게이트 폭주 완화 2026-06-03)"
# 워커/리뷰어가 흔히 쓰는 순수 출력 도구. 부작용·명령실행 없음 → 게이트 노이즈 제거.
for c in "nl -ba app.js" "cut -d, -f1 data.csv" "sort names.txt" "uniq -c log" \
         "comm a b" "column -t tbl" "tr a b" "basename /x/y" "dirname /x/y" \
         "realpath ./x" "jq . pkg.json" "cmp a b" "cksum f" "od -c bin"; do
  out="$(lead_auto_allow_lookup Bash "{\"command\":\"$c\"}")"
  case "$out" in read-only:*) : ;; *) assert_eq "read-only:*" "$out" "Y12 '$c' → read-only" ;; esac
done
# 대표 1건 명시 어서션(케이스 무력화 방지 — 실제 매칭 문자열 검증)
out="$(lead_auto_allow_lookup Bash '{"command":"nl -ba app.js"}')"
assert_eq "read-only:Bash(nl:*)" "$out" "Y12 nl → read-only:Bash(nl:*)"

echo "[Y13] 임의코드/공급망 도구는 gray 유지 (deny-bounded 보존)"
# node=임의코드, npm install <pkg>=공급망, python script=임의코드. danger 불가시 위험이라
# permission-gated(LEAD 1회 학습)로 메움 — auto 카탈로그 진입 금지.
for c in "node index.js" "node ./server/app.js" "python app.py" "npx vite"; do
  lead_auto_allow_lookup Bash "{\"command\":\"$c\"}" >/dev/null
  assert_fail "$?" "Y13 '$c' 미매칭 (gray 유지 — 임의코드)"
done

test_summary
