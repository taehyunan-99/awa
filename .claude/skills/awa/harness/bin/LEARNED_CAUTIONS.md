# bin — LEARNED CAUTIONS

<!--
이 파일은 작업 중 발견된 실수/주의사항을 누적하는 자리다.
- `learn` 스킬(`/learn` 또는 Codex의 `$learn`)이 이 파일에만 항목을 추가한다.
- 같은 폴더의 본문 가이드(AGENTS.md / CLAUDE.md)는 절대 수정하지 않는다.
- update 스킬도 이 파일은 자동 덮어쓰지 않는다 — 사용자 결정으로 만들어진 자산이므로 보존.
- 변경이 필요한 경우 반드시 사용자에게 확인을 받고 진행한다.
-->

- (2026-06-10) bash 3.2(macOS)에서 `$VAR` 바로 뒤에 한글(멀티바이트 문자)이 오면 변수명 파싱이 깨진다. `$EXPECTED_VOTERS종` 처럼 쓰면 bash가 멀티바이트 첫 바이트를 변수명에 포함시켜 미정의 변수를 참조하고, set -u 환경에서 즉사한다(`EXPECTED_VOTERS␀: unbound variable` 무한 출력 → watcher 사망 → dispatch 대행 정지). 재현: `/bin/bash -c 'set -u; X=3; echo "$X종"'` → `X␀: unbound variable`. 규칙: bash 스크립트에서 변수 바로 뒤에 한글/멀티바이트가 붙는 경우 반드시 `${VAR}` 중괄호로 감싼다. 영문/공백/구두점이 뒤따르면 문제없지만, 한글 메시지를 다루는 이 프로젝트 특성상 항상 `${VAR}`를 기본으로 하는 게 안전하다. (B4 테스트에서 V1으로 실증, 커밋 48ced91에서 수정)
