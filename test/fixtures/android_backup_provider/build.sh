#!/usr/bin/env bash
set -euo pipefail
fixture_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$fixture_dir/../../.." && pwd)"
sdk_dir="${1:?Pass the Android SDK directory}"
out_dir="$repo_dir/build/backup-provider-fixture"
tools_dir="$sdk_dir/build-tools/36.0.0"
android_jar="$sdk_dir/platforms/android-34/android.jar"
mkdir -p "$out_dir/classes" "$out_dir/dex"
javac --release 8 -classpath "$android_jar" -d "$out_dir/classes" "$fixture_dir/"*.java
"$tools_dir/d8" --min-api 26 --output "$out_dir/dex" "$out_dir/classes/com/sanbo/qa/documents/"*.class
"$tools_dir/aapt2" link -I "$android_jar" --manifest "$fixture_dir/AndroidManifest.xml" -o "$out_dir/unsigned.apk"
zip -j -q "$out_dir/unsigned.apk" "$out_dir/dex/classes.dex"
# Disposable test identity, unrelated to Sanbo's application signing key.
if [[ ! -f "$out_dir/qa.keystore" ]]; then
  keytool -genkeypair -keystore "$out_dir/qa.keystore" -storepass android -keypass android \
    -alias qa -dname CN=SanboQA -keyalg RSA -validity 30 -noprompt
fi
signing_key="$out_dir/qa.keystore"
signing_alias=qa
if [[ "${2:-}" == "--lifecycle" ]]; then
  signing_key="${SANBO_QA_DEBUG_KEYSTORE:-$HOME/.android/debug.keystore}"
  signing_alias=androiddebugkey
  [[ -f "$signing_key" ]] || { echo "The target app's default debug keystore is required" >&2; exit 1; }
fi
"$tools_dir/apksigner" sign --ks "$signing_key" --ks-key-alias "$signing_alias" \
  --ks-pass pass:android --key-pass pass:android --out "$out_dir/provider.apk" "$out_dir/unsigned.apk"
printf 'Built %s\n' "$out_dir/provider.apk"
