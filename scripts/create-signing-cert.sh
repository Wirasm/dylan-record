#!/usr/bin/env bash
set -euo pipefail

# Creates a stable self-signed code-signing identity in your login keychain.
#
# Why: DylanRecord needs Microphone, Screen & System Audio Recording, and
# Accessibility permissions. macOS ties those grants to the app's code-signing
# identity. Ad-hoc signing (codesign -s -) changes the signature every build,
# so the grants reset on every reinstall. Signing with a fixed certificate
# gives the app a stable Designated Requirement, so the permissions stick.
#
# Run this once per machine, then use scripts/install.sh as usual. The private
# key stays in your login keychain and is never committed. Recreating the cert
# (e.g. on a new machine) produces a new identity, so you grant the permissions
# one more time there — after that, rebuilds keep them.

IDENTITY="Dylan Record Local Signing"
LK="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -q "$IDENTITY"; then
  echo "Signing identity '$IDENTITY' already exists. Nothing to do."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
pw="dylanrecord"

cat > "$tmp/cert.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = Dylan Record Local Signing
[v3]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

echo "==> Generating self-signed code-signing certificate (10 years)"
openssl req -x509 -newkey rsa:2048 -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
  -days 3650 -nodes -config "$tmp/cert.cnf" >/dev/null 2>&1

# macOS's Security framework only reads PKCS#12 files written with the legacy
# SHA1/3DES algorithms, and rejects an empty MAC password — hence -legacy + pw.
echo "==> Packaging into PKCS#12"
openssl pkcs12 -export -legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
  -out "$tmp/id.p12" -passout "pass:$pw" -name "$IDENTITY" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1

echo "==> Importing into login keychain (authorizing codesign to use the key)"
security import "$tmp/id.p12" -k "$LK" -P "$pw" -T /usr/bin/codesign -T /usr/bin/security

echo "==> Done. Identity now available:"
security find-identity -p codesigning | grep "$IDENTITY" || true
echo
echo "Next: run scripts/install.sh, then grant the app's permissions once."
