#!/bin/bash
# Exports the self-signed certificate, so that another Mac can sign builds the
# same way.
#
# Why: the notification permission is tied to the certificate's identity. A Mac
# that signs with a freshly generated certificate looks like a different app to
# macOS, and every notification permission is granted again. Moving this file
# over avoids that.
#
# Usage:
#   ./scripts/export-signing.sh               writes ./PriceBar-Self-Signed.p12
#   ./scripts/export-signing.sh /path/to.p12  writes somewhere else
#
# Import on the other Mac (the password is the one typed here):
#   security import PriceBar-Self-Signed.p12 \
#       -k ~/Library/Keychains/login.keychain-db -P <password> -T /usr/bin/codesign
#
# The file holds a private key: keep it out of the repository and out of shared
# folders. The password is the only thing protecting it.

set -euo pipefail

CERT_NAME="PriceBar Self-Signed"
MATERIALS="$HOME/Library/Application Support/PriceBar/signing"
OUT="${1:-$(pwd)/PriceBar-Self-Signed.p12}"

if ! security find-identity -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "No \"$CERT_NAME\" in the keychain; run ./scripts/setup-signing.sh first." >&2
    exit 1
fi
if [[ ! -f "$MATERIALS/key.pem" || ! -f "$MATERIALS/cert.pem" ]]; then
    echo "Missing $MATERIALS; re-create the certificate with ./scripts/setup-signing.sh." >&2
    echo "(\`security export\` cannot help here: it selects by keychain, not by name," >&2
    echo "and would write every identity in it.)" >&2
    exit 1
fi
if [[ -e "$OUT" ]]; then
    echo "$OUT already exists; move it away first." >&2
    exit 1
fi

read -r -s -p "Password for the exported file: " PASS
echo
read -r -s -p "Again: " PASS2
echo
if [[ "$PASS" != "$PASS2" ]]; then
    echo "Passwords do not match." >&2
    exit 1
fi
if [[ -z "$PASS" ]]; then
    echo "An empty password would leave the private key unprotected." >&2
    exit 1
fi

echo "==> Exporting to $OUT"
# The same older PKCS#12 encryption the import side reads.
openssl pkcs12 -export -out "$OUT" \
    -inkey "$MATERIALS/key.pem" -in "$MATERIALS/cert.pem" \
    -name "$CERT_NAME" -passout "pass:$PASS" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 2>/dev/null

if [[ ! -s "$OUT" ]]; then
    echo "Export produced no file." >&2
    exit 1
fi

chmod 600 "$OUT"
echo "==> Done ($(du -h "$OUT" | cut -f1))"
echo
echo "Keep this file private: it contains the signing key."
echo "On the other Mac, import it with the command at the top of this script."
