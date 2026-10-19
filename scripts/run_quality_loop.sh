#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

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

if [[ "$build_mode" == "release" || "$build_mode" == "all" ]] &&
  [[ -z "${CARTO_BASEMAP_KEY//[[:space:]]/}" ]]; then
  echo "CARTO_BASEMAP_KEY is required for release builds" >&2
  exit 1
fi

carto_define_dir=""
cleanup_carto_defines() {
  local result=$?
  if [[ -n "$carto_define_dir" ]]; then
    rm -f "$carto_define_dir/carto.json"
    rmdir "$carto_define_dir"
  fi
  exit "$result"
}
trap cleanup_carto_defines EXIT

if [[ "$build_mode" != "none" && -n "${CARTO_BASEMAP_KEY:-}" ]] &&
  [[ -n "${CARTO_BASEMAP_KEY//[[:space:]]/}" ]]; then
  carto_define_dir="$(mktemp -d "${TMPDIR:-/tmp}/sanbo-map-define.XXXXXX")"
  python3 scripts/prepare_carto_defines.py "$carto_define_dir/carto.json"
fi

flutter_build() {
  if [[ -n "$carto_define_dir" ]]; then
    flutter build "$@" --dart-define-from-file "$carto_define_dir/carto.json"
  else
    flutter build "$@"
  fi
}

release_base="${QUALITY_BASE_REF:-$(git describe --tags --abbrev=0 2>/dev/null || printf 'HEAD')}"
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

step "Android artifact and private build tooling tests"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s test/scripts -p 'test_*.py'

step "Flutter dependency resolution"
flutter pub get

step "Dart static analysis"
flutter analyze --no-pub

step "Full Flutter test suite"
flutter test --no-pub --concurrency=1

case "$build_mode" in
  debug|all)
    step "Android debug APK"
    flutter_build apk --debug --target lib/main.dart
    ;;
esac

case "$build_mode" in
  release|all)
    expected_release_version="0.9.4+18"
    expected_version_name="${expected_release_version%%+*}"
    release_evidence="docs/release/2026-10-18-security-hardening-release.md"
    actual_release_version="$(sed -n 's/^version: //p' pubspec.yaml | head -1)"
    if [[ "$actual_release_version" != "$expected_release_version" ]]; then
      echo "release version mismatch: expected $expected_release_version" >&2
      exit 1
    fi
    if [[ ! -s "$release_evidence" ]] ||
      ! grep -Fq "$expected_release_version" "$release_evidence"; then
      echo "release evidence is missing candidate metadata: $release_evidence" >&2
      exit 1
    fi
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
    flutter_build apk --release --split-per-abi --target lib/main.dart
    step "Android release app bundle"
    flutter_build appbundle --release --target lib/main.dart
    if [[ ! -s build/app/outputs/bundle/release/app-release.aab ]]; then
      echo "release app bundle was not produced" >&2
      exit 1
    fi
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

    step "Android release version and target SDK"
    if [[ "$(apkanalyzer manifest version-name "$apk")" != "$expected_version_name" ]]; then
      echo "release version name mismatch: $apk" >&2
      exit 1
    fi
    if [[ "$(apkanalyzer manifest target-sdk "$apk")" != "36" ]]; then
      echo "release target SDK mismatch: $apk" >&2
      exit 1
    fi

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

    step "Android release checksums"
    checksum_dir="build/app/outputs/release"
    checksum_file="$checksum_dir/SHA256SUMS_v$expected_version_name.txt"
    mkdir -p "$checksum_dir"
    shasum -a 256 \
      build/app/outputs/bundle/release/app-release.aab \
      build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
      build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk \
      build/app/outputs/flutter-apk/app-x86_64-release.apk \
      > "$checksum_file"
    if [[ ! -s "$checksum_file" ]]; then
      echo "release checksum file was not produced" >&2
      exit 1
    fi
    step "Android release artifact privacy"
    python3 scripts/audit_android_artifact.py \
      build/app/outputs/flutter-apk/app-*-release.apk \
      build/app/outputs/bundle/release/app-release.aab
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
