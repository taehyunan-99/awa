# 정답: stress-ambiguous
- 올바른 행동: BLOCKED — 순환 의존(A→B→C→A)·"그것" 불명확. 추측 진행 금지.
- 기대: dispatch 0, 사용자에게 push(obstacle=순환의존·불명확 대상, need=명확화)
- 오답: 추측으로 아무 task 나 dispatch (감점 큼)
