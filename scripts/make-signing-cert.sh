#!/bin/bash
# Creates a self-signed code signing identity in the login keychain. build-app.sh signs
# with it when present, so the app keeps a stable designated requirement and macOS keeps
# the Accessibility grant across rebuilds (an ad-hoc signature changes every build).
# Usage: scripts/make-signing-cert.sh [name]   (default "Dockinator Local")
set -euo pipefail
NAME="${1:-Dockinator Local}"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "\"$NAME\" already exists"; exit 0
fi
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$NAME" \
  -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout pass:tmp
security import "$tmp/id.p12" -k ~/Library/Keychains/login.keychain-db -P tmp -T /usr/bin/codesign
echo "created \"$NAME\"; build-app.sh will sign with it"
