#!/usr/bin/env bash
# 테스트 공통 — 하니스 디렉토리 단일 출처.
# 테스트는 이 파일을 source 하고 $HARNESS_BIN 등으로 참조 → 하니스 이동 시 이 파일만 수정.
# (이동 전: bin 등이 repo 루트. 이동 후: .claude/skills/awa/harness 로 이 한 줄만 변경.)
_HP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="$(cd "$_HP_DIR/../.claude/skills/awa/harness" && pwd)"
HARNESS_BIN="$HARNESS/bin"
HARNESS_PROFILES="$HARNESS/profiles"
HARNESS_PROMPTS="$HARNESS/prompts"
HARNESS_TEMPLATES="$HARNESS/templates"
HARNESS_CONFIG="$HARNESS/config"
export HARNESS HARNESS_BIN HARNESS_PROFILES HARNESS_PROMPTS HARNESS_TEMPLATES HARNESS_CONFIG
