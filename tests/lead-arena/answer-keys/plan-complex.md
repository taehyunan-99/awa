# 정답: plan-complex
- task 수: 3 (코어·테스트·문서)
- 배정: dev ← 코어(src/strutil.py), tester ← 테스트(tests/), dev/researcher ← 문서
- 의존: 테스트 입력=코어 산출, 문서 입력=테스트 결과 (입력경로 명시 필수)
- allowed_paths: 각 task 에 명시 (코어=src/, 테스트=tests/, 문서=README.md)
- 품질 게이트: 테스트 통과 후 문서 (순서 존중)
