#!/bin/bash
# Explicit one-time credential upload; run only after approving this destination.
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
repo=Wirenut33/quick-shot
p12=${1:?Usage: configure_ci_signing.sh /absolute/path/to/QuickShot-signing.p12}
[[ -f "$p12" ]] || { echo 'P12 file not found' >&2; exit 1; }
tools=.build/SourcePackages/artifacts/sparkle/Sparkle/bin
[[ -x "$tools/generate_keys" ]] || { echo 'Resolve the Sparkle package first.' >&2; exit 1; }
read -r -s -p 'P12 export password: ' cert_password
printf '\n'
[[ -n "$cert_password" ]] || { echo 'A password-protected P12 is required.' >&2; exit 1; }
# Verify the password before writing any remote secrets.
openssl pkcs12 -in "$p12" -passin fd:3 -noout 3<<< "$cert_password"
key_dir=$(mktemp -d)
trap 'rm -rf "$key_dir"; unset cert_password' EXIT
"$tools/generate_keys" --account quickshot-updates -x "$key_dir/sparkle.key"
base64 < "$p12" | gh secret set APPLE_CERTIFICATE_P12_BASE64 --repo "$repo"
printf '%s' "$cert_password" | gh secret set APPLE_CERTIFICATE_PASSWORD --repo "$repo"
gh secret set SPARKLE_PRIVATE_KEY --repo "$repo" < "$key_dir/sparkle.key"
echo "Configured signing secrets for $repo. No private keys were added to the repository."
