# 14차 UX 라이브 체크리스트 — window layout + border 라벨

자동 테스트(tests/test-window-layout.sh) 가 ALL PASS 인 상태에서, 실 claude 로 라이브 가동해 사용자 눈으로 확인. 사용자가 `!` 로 실행 (claude 토큰 규약).

## 준비

```bash
mkdir -p /tmp/agpn-uxlive && cd /tmp/agpn-uxlive && git init -q
bash /Users/taehyunan/Desktop/Repo/Practice/agenphony/bin/awa-up.sh \
  /Users/taehyunan/Desktop/Repo/Practice/agenphony/profiles/default.sh
# attach 후 확인.
tmux attach -t awa-agpn-uxlive
```

## 확인 항목

### window 0 (team) — Ctrl-b 0
- [ ] 좌측 pane border 상단 라벨: `[ agpn-uxlive ] LEAD`
- [ ] 우측 pane border 상단 라벨: `[ agpn-uxlive ] PM`
- [ ] 두 pane 모두 claude REPL 정상 기동
- [ ] LEAD 가 왼쪽·PM 이 오른쪽 (가로 분할 even-horizontal)

### window 1 (workers) — Ctrl-b 1
- [ ] 상→하 순으로 pane: `[ agpn-uxlive ] dev`, `[ agpn-uxlive ] test`, `[ agpn-uxlive ] watcher`
- [ ] watcher 가 가장 아래
- [ ] dev/test 는 claude REPL, watcher 는 셸

### window 2 (review) — Ctrl-b 2
- [ ] `[ agpn-uxlive ] quality-rev` 단일 pane (또는 profile 의 REVIEWERS 개수만큼)
- [ ] claude REPL 기동

### 회귀 — 신호경로 정상 (윈도우 분리됐어도 pane_id 기반이라 면역)
- [ ] LEAD pane (window 0) 에서 "@pm: dev 에게 hello.py 만들고 'hi' 출력하도록 시켜" 같은 dispatch 트리거
- [ ] dev pane (window 1) 으로 TASK 정상 도달
- [ ] watcher (window 1 최하단) 가 events.log 갱신
- [ ] /agpn (Step 0 resume) 또는 /agpn bookmarks list 가 워커명만 출력 (watcher·LEAD·PM·reviewer 안 섞임)

### 정리
- [ ] `bash /Users/taehyunan/Desktop/Repo/Practice/agenphony/bin/awa-down.sh agpn-uxlive` 로 세션 종료
- [ ] tmux ls 에 awa-agpn-uxlive 없음

## 결과 기록
- 라이브 일시:
- 사용자 확인 결과:
- 발견 결함:
