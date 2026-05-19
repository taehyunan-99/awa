#!/usr/bin/env bash
# 기능 개발 팀: 구현/테스트/문서 워커 + 관점별 리뷰어. 모델 차등.
SESSION="agents"
LAYOUT="tiled"
WORKERS=("dev:dev:sonnet" "test:tester:haiku" "arch:researcher:sonnet")
REVIEWERS=("spec-rev:reviewer-spec:sonnet" "quality-rev:reviewer-quality:haiku" "arch-rev:reviewer-arch:opus")
ORCHESTRATOR_MODEL="opus"
