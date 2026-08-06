#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

release_base="${QUALITY_BASE_REF:-$(git describe --tags --abbrev=0 2>/dev/null || printf 'HEAD')}"
expected_cert_sha256="ceb40402d706589acee5da5df5a010c3dd5c2e9329cd3218961dfce56a6d38ac"

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

status_before="$(git status --porcelain=v1 --untracked-files=all)"
if [[ "$build_mode" == "release" || "$build_mode" == "all" ]] &&
  [[ -n "$status_before" ]]; then
  echo "release verification requires a clean committed working tree" >&2
  printf '%s\n' "$status_before" >&2
  exit 1
fi

tree_fingerprint() {
  {
    git diff --binary HEAD --
    while IFS= read -r -d '' untracked; do
      printf 'untracked %s\n' "$untracked"
      shasum -a 256 "$untracked"
    done < <(git ls-files --others --exclude-standard -z | sort -z)
  } | shasum -a 256 | awk '{print $1}'
}

tree_before="$(tree_fingerprint)"

step() {
  printf '\n[quality] %s\n' "$1"
}

step "PRD/TRD structural verification"
python3 scripts/verify_prd_trd.py

step "Flutter dependency resolution"
flutter pub get

step "Dart static analysis"
flutter analyze --no-pub

step "Full Flutter test suite"
flutter test --no-pub --concurrency=1

case "$build_mode" in
  debug|all)
    step "Android debug APK"
    flutter build apk --debug
    ;;
esac

case "$build_mode" in
  release|all)
    if [[ -z "${SANBO_RELEASE_STORE_PASSWORD:-}" ]] &&
      command -v security >/dev/null 2>&1; then
      signing_password="$(security find-generic-password \
        -a "${USER}" -s sanbo-release-keystore -w 2>/dev/null || true)"
      if [[ -n "$signing_password" ]]; then
        export SANBO_RELEASE_STORE_PASSWORD="$signing_password"
        export SANBO_RELEASE_KEY_PASSWORD="$signing_password"
      fi
    fi
    step "Android release split APKs"
    # Do not use --no-pub here: Flutter's build preparation refreshes the
    # platform registrant and excludes dev-only integration_test plugins from
    # the release Java compilation.
    flutter build apk --release --split-per-abi
    if ! command -v apkanalyzer >/dev/null 2>&1; then
      echo "required release tool unavailable: apkanalyzer" >&2
      exit 1
    fi
    android_sdk="$(flutter config --list | sed -n 's/^  android-sdk: //p')"
    apksigner_bin="$(command -v apksigner 2>/dev/null || true)"
    if [[ -z "$apksigner_bin" && -n "$android_sdk" ]]; then
      apksigner_bin="$(find "$android_sdk/build-tools" -type f -name apksigner 2>/dev/null | sort | tail -1)"
    fi
    if [[ -z "$apksigner_bin" || ! -x "$apksigner_bin" ]]; then
      echo "required release tool unavailable: apksigner" >&2
      exit 1
    fi

    step "Android release manifest"
    apk="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
    permissions="$(apkanalyzer manifest permissions "$apk")"
    for required in \
      android.permission.ACCESS_FINE_LOCATION \
      android.permission.FOREGROUND_SERVICE_LOCATION \
      android.permission.POST_NOTIFICATIONS \
      android.permission.WAKE_LOCK; do
      if ! grep -qx "$required" <<<"$permissions"; then
        echo "missing release manifest permission: $required" >&2
        exit 1
      fi
    done
    manifest="$(apkanalyzer manifest print "$apk")"
    grep -q 'com.baseflow.geolocator.GeolocatorLocationService' <<<"$manifest"
    grep -q 'foregroundServiceType="0x8"' <<<"$manifest"

    step "Android release signing certificate"
    for signed_apk in build/app/outputs/flutter-apk/app-*-release.apk; do
      certs="$("$apksigner_bin" verify --print-certs "$signed_apk")"
      if ! grep -Fqx \
        "Signer #1 certificate SHA-256 digest: $expected_cert_sha256" \
        <<<"$certs"; then
        echo "release certificate mismatch: $signed_apk" >&2
        exit 1
      fi
    done
    ;;
esac

step "Patch whitespace check"
git diff --check "$release_base" --
git diff HEAD --check

status_after="$(git status --porcelain=v1 --untracked-files=all)"
tree_after="$(tree_fingerprint)"
if [[ "$status_after" != "$status_before" || "$tree_after" != "$tree_before" ]]; then
  echo "quality commands changed the working tree; generated-file audit failed" >&2
  diff <(printf '%s\n' "$status_before") <(printf '%s\n' "$status_after") || true
  exit 1
fi

printf '\n[quality] PASS\n'
