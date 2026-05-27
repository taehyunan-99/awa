# 15차 라이브 체크리스트 — /agpn 통합 진입점 + Symphony + Bookmarks

자동 테스트 (tests/test-bookmarks.sh + test-symphony.sh + test-down-menu.sh + test-main-flow.sh + test-rename-guard-15th.sh) 가 ALL PASS 인 상태에서, 실제 claude 로 라이브 가동해 사용자 눈으로 확인.

## 준비
```bash
mkdir -p /tmp/agpn15-a /tmp/agpn15-b
( cd /tmp/agpn15-a && git init -q )
( cd /tmp/agpn15-b && git init -q )
```

## 1. 단일 발진 (no plan, current cwd)
- [ ] `! cd /tmp/agpn15-a` 후 `/agpn` 호출
- [ ] Step 1: plan 없음 답
- [ ] Step 2: live 0 → Single 자동
- [ ] Step 3: Current (cwd) 선택
- [ ] Step 4: preset=default 선택
- [ ] 발진 명령 출력 확인
- [ ] `!` 로 실행 → `agenphony-agpn15-a` 세션 발진
- [ ] `tmux attach -t agenphony-agpn15-a` 로 attach, LEAD/PM/workers/review 확인

## 2. bookmarks 자동 등록
- [ ] `! bash bin/agenphony-bookmarks.sh list` → `/tmp/agpn15-a` 항목 보임
- [ ] preset=default, last_used 타임스탬프 정상

## 3. 두번째 프로젝트 + Multi-view
- [ ] `! cd /tmp/agpn15-b` 후 `/agpn` 호출
- [ ] Step 0 Resume? → no
- [ ] Step 2: live_others=1 (agenphony-agpn15-a) → Multi-view 옵션 표시
- [ ] Multi-view 선택
- [ ] 발진 명령 출력
- [ ] `!` 로 실행 → agenphony-agpn15-b 발진
- [ ] claude code 가 자동으로 `symphony compose ...` 호출 (메시지 확인)
- [ ] `tmux attach -t _SYMPHONY` → 두 프로젝트 team window 보임
- [ ] window 1: `[ agpn15-a ] LEAD/PM` 라벨
- [ ] window 2: `[ agpn15-b ] LEAD/PM` 라벨

## 4. Symphony 액션
- [ ] `/agpn symphony detach agenphony-agpn15-a-team`
- [ ] _SYMPHONY 에서 a 제거, agenphony-agpn15-a 에 team 복원 확인
- [ ] _SYMPHONY 에 1개만 남음 → auto detach + kill 메시지
- [ ] `tmux ls` 로 _SYMPHONY 없음 확인

## 5. Resume + Bookmarks alias
- [ ] `! bash bin/agenphony-bookmarks.sh set-alias` → /tmp/agpn15-a 에 alias "a" 부여
- [ ] `/agpn` Step 3 Custom path → "a" 입력 → /tmp/agpn15-a 해석 확인

## 6. down 메뉴
- [ ] `/agpn down` 호출
- [ ] N=2 → 목록 + 선택 프롬프트
- [ ] "all" 입력 → 두 세션 모두 종료
- [ ] tmux ls 에 agenphony-* 없음

## 7. 잔존 마이그레이션
- [ ] `/agpn plan` → deprecated 안내 + exit
- [ ] `/agpn stage` → deprecated 안내
- [ ] `/agpn list` → deprecated 안내

## 결과
- 라이브 일시:
- 사용자 확인:
- 발견 결함:

## 정리
- [ ] `! bash bin/agenphony-down-menu.sh` (남은 세션 정리)
- [ ] `rm -rf /tmp/agpn15-a /tmp/agpn15-b`
