#!/bin/bash
# Creates a self-signed code-signing identity in the login keychain (once).
# Signing with a fixed certificate keeps macOS privacy permissions (Accessibility, Input Monitoring)
# across rebuilds; ad-hoc signatures change on every build, so macOS treats each build as a new app.
# Remove it later with: security delete-identity -c "LongoKit Local Signing"
set -euo pipefail

NAME="LongoKit Local Signing"
if security find-identity -p codesigning | grep -q "$NAME"; then
    echo "Identity \"$NAME\" already exists"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -passout pass:longokit
security import "$WORK/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P longokit -T /usr/bin/codesign >/dev/null

echo "Created identity \"$NAME\""
