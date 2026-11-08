#!/bin/bash
# Creates a self-signed code signing certificate, so that every build has the
# same code identity.
#
# Why this matters: an ad-hoc signature (`codesign --sign -`) has no
# certificate, so macOS identifies the app by the hash of that one build
# (`cdhash`). Rebuild, and the hash changes, so macOS treats the new build as a
# different app and drops its notification permission. A certificate gives the
# app a stable designated requirement instead:
#
#   identifier "dev.pricebar.app" and certificate root = H"..."
#
# That requirement survives rebuilds, so the permission granted once keeps
# working. No Apple Developer Program membership is needed: the certificate
# never leaves this Mac, and nothing is notarised.
#
# Run once per Mac: ./scripts/setup-signing.sh
# Move it to another Mac: ./scripts/export-signing.sh
# Remove it: security delete-identity -c "PriceBar Self-Signed"

set -euo pipefail

CERT_NAME="PriceBar Self-Signed"
VALID_DAYS=3650
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# The certificate and its key, kept so that export-signing.sh can rebuild a
# .p12 without asking the keychain for every identity in it.
MATERIALS="$HOME/Library/Application Support/PriceBar/signing"

if security find-identity -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "==> Already present: $CERT_NAME"
    if [[ -f "$MATERIALS/key.pem" && -f "$MATERIALS/cert.pem" ]]; then
        echo "    Materials: $MATERIALS"
    else
        echo "    Materials are missing; ./scripts/export-signing.sh will not work."
        echo "    To start over: security delete-identity -c \"$CERT_NAME\""
        echo "    then run this script again."
    fi
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

cat > openssl.cnf <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $CERT_NAME
O = PriceBar
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

echo "==> Generating certificate ($VALID_DAYS days)"
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout key.pem -out cert.pem -days "$VALID_DAYS" -config openssl.cnf 2>/dev/null

# The Security framework only reads the older PKCS#12 encryption, which current
# OpenSSL no longer writes by default.
openssl pkcs12 -export -out id.p12 \
    -inkey key.pem -in cert.pem -name "$CERT_NAME" \
    -passout pass:pricebar \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 2>/dev/null

echo "==> Importing into the login keychain"
# -T lets codesign use the private key without asking for permission each time.
security import id.p12 -k "$KEYCHAIN" -P pricebar -T /usr/bin/codesign >/dev/null

echo "==> Keeping the certificate and key for export"
mkdir -p "$MATERIALS"
chmod 700 "$MATERIALS"
cp key.pem cert.pem "$MATERIALS/"
chmod 600 "$MATERIALS/key.pem" "$MATERIALS/cert.pem"

echo "==> Done"
security find-identity -p codesigning | grep "$CERT_NAME" || true
echo
echo "build.sh now signs with it automatically."
echo "It stays untrusted as a root certificate, which is expected: the app is"
echo "still not notarised, so a download still opens with a right-click."
