#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

build_mode="none"
case "${1:-}" in
  "") ;;
  --debug-apk) build_mode="debug" ;;
  --release-apk) build_mode="release" ;;
  --all-apk) build_mode="all" ;;
  *)
    echo "usage: $0 [--debug-apk|--release-apk|--all-apk]" >&2
    exit 2
    ;;
esac

step() {
  printf '\n[quality] %s\n' "$1"
}

step "PRD/TRD structural verification"
python3 scripts/verify_prd_trd.py

step "Dart static analysis"
flutter analyze

step "Full Flutter test suite"
flutter test --concurrency=1

case "$build_mode" in
  debug|all)
    step "Android debug APK"
    flutter build apk --debug
    ;;
esac

case "$build_mode" in
  release|all)
    step "Android release split APKs"
    flutter build apk --release --split-per-abi
    ;;
esac

step "Patch whitespace check"
git diff --check

if git diff --name-only | grep -qE '^(ios/Podfile|ios/Flutter/(Debug|Release)\.xcconfig)$'; then
  printf '[quality] note: Flutter regenerated iOS support files; clean those generated files before commit.\n'
fi

printf '\n[quality] PASS\n'
