#!/bin/bash
# This script is only run on an ephemeral GitHub-hosted macOS runner.
set -euo pipefail
umask 077
: "${RUNNER_TEMP:?CI only}"
: "${APPLE_CERTIFICATE_P12_BASE64:?Missing Apple signing certificate secret}"
: "${APPLE_CERTIFICATE_PASSWORD:?Missing certificate password secret}"
: "${SPARKLE_PRIVATE_KEY:?Missing Sparkle update signing secret}"
keychain="$RUNNER_TEMP/quickshot-signing.keychain-db"
p12="$RUNNER_TEMP/quickshot-signing.p12"
password=$(openssl rand -base64 32)
trap 'rm -f "$p12"' EXIT
printf '%s' "$APPLE_CERTIFICATE_P12_BASE64" | base64 --decode > "$p12"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$p12" -P "$APPLE_CERTIFICATE_PASSWORD" -t cert -f pkcs12 -k "$keychain" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
security find-identity -v -p codesigning "$keychain"
