#!/bin/bash
# Creates a self-signed code-signing identity for Ghostshot.
#
# Why: an ad-hoc signature (`codesign --sign -`) has a designated requirement of
# nothing but the cdhash, so every rebuild is a different app as far as TCC is
# concerned and the Accessibility / Screen Recording grants stop matching. Signing
# with a real certificate makes the requirement "this bundle id, signed by this
# leaf", which survives rebuilds. One-time setup; asks for your login password.
set -euo pipefail
cd "$(dirname "$0")"

NAME="Ghostshot Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "identity already present: $NAME"
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/ext.cnf" <<'EOF'
[req]
distinguished_name = dn
prompt = no
[dn]
CN = Ghostshot Local Signing
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -config "$WORK/ext.cnf" -extensions v3 2>/dev/null

# The Security framework cannot import a PKCS#12 with an empty password, and
# OpenSSL 3 defaults to a cipher it also cannot read, hence -legacy.
P12PASS=ghostshot
openssl pkcs12 -export -legacy -out "$WORK/id.p12" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -passout "pass:$P12PASS" 2>/dev/null

# -A lets codesign use the key without a per-call prompt.
security import "$WORK/id.p12" -k "$KEYCHAIN" -P "$P12PASS" -A -T /usr/bin/codesign

# codesign refuses a certificate that is not trusted for code signing.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

security find-identity -v -p codesigning | grep "$NAME"
echo
echo "done. now run ./build.sh, then grant Accessibility and Screen Recording once."
