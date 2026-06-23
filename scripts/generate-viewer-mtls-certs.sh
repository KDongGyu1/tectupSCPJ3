#!/usr/bin/env bash
set -euo pipefail

CERT_DIR="${CERT_DIR:-certs/mtls}"
CLIENT_CERT_PASSWORD="${CLIENT_CERT_PASSWORD:-finpay-dev}"

ROOT_KEY="${CERT_DIR}/finpay-root-ca.key"
ROOT_CERT="${CERT_DIR}/finpay-root-ca.crt"
INTERMEDIATE_KEY="${CERT_DIR}/finpay-intermediate-ca.key"
INTERMEDIATE_CSR="${CERT_DIR}/finpay-intermediate-ca.csr"
INTERMEDIATE_CERT="${CERT_DIR}/finpay-intermediate-ca.crt"
CA_BUNDLE="${CERT_DIR}/finpay-ca-bundle.pem"

CLIENT_KEY="${CERT_DIR}/finpay-client-01.key"
CLIENT_CSR="${CERT_DIR}/finpay-client-01.csr"
CLIENT_CERT="${CERT_DIR}/finpay-client-01.crt"
CLIENT_P12="${CERT_DIR}/finpay-client-01.p12"
CLIENT_BROWSER_P12="${CERT_DIR}/finpay-client-01-browser.p12"

COMPAT_CA_BUNDLE="${CERT_DIR}/client-ca-bundle.pem"
COMPAT_CLIENT_KEY="${CERT_DIR}/client.key"
COMPAT_CLIENT_CERT="${CERT_DIR}/client.crt"
COMPAT_CLIENT_P12="${CERT_DIR}/client.p12"
COMPAT_BROWSER_P12="${CERT_DIR}/client-browser.p12"

UNTRUSTED_KEY="${CERT_DIR}/untrusted-client-01.key"
UNTRUSTED_CERT="${CERT_DIR}/untrusted-client-01.crt"
UNTRUSTED_P12="${CERT_DIR}/untrusted-client-01.p12"

mkdir -p "$CERT_DIR"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

intermediate_ext="${tmpdir}/intermediate-ca-ext.cnf"
client_ext="${tmpdir}/client-ext.cnf"

cat >"$intermediate_ext" <<'EOF'
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

cat >"$client_ext" <<'EOF'
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

echo "Generating FinPay CloudFront viewer mTLS PKI in ${CERT_DIR}"

openssl genrsa -out "$ROOT_KEY" 4096
openssl req \
  -x509 \
  -new \
  -nodes \
  -key "$ROOT_KEY" \
  -sha256 \
  -days 3650 \
  -subj "/C=KR/ST=Seoul/O=FinPay/OU=PKI/CN=FinPay Root CA" \
  -out "$ROOT_CERT" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:1" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash"

openssl genrsa -out "$INTERMEDIATE_KEY" 4096
openssl req \
  -new \
  -key "$INTERMEDIATE_KEY" \
  -subj "/C=KR/ST=Seoul/O=FinPay/OU=PKI/CN=FinPay Client Intermediate CA" \
  -out "$INTERMEDIATE_CSR"

openssl x509 \
  -req \
  -in "$INTERMEDIATE_CSR" \
  -CA "$ROOT_CERT" \
  -CAkey "$ROOT_KEY" \
  -CAcreateserial \
  -out "$INTERMEDIATE_CERT" \
  -days 1825 \
  -sha256 \
  -extfile "$intermediate_ext"

openssl genrsa -out "$CLIENT_KEY" 2048
openssl req \
  -new \
  -key "$CLIENT_KEY" \
  -subj "/C=KR/ST=Seoul/O=FinPay/OU=Viewer-mTLS/CN=finpay-client-01" \
  -out "$CLIENT_CSR"

openssl x509 \
  -req \
  -in "$CLIENT_CSR" \
  -CA "$INTERMEDIATE_CERT" \
  -CAkey "$INTERMEDIATE_KEY" \
  -CAcreateserial \
  -out "$CLIENT_CERT" \
  -days 825 \
  -sha256 \
  -extfile "$client_ext"

cat "$INTERMEDIATE_CERT" "$ROOT_CERT" >"$CA_BUNDLE"
cp "$CA_BUNDLE" "$COMPAT_CA_BUNDLE"
cp "$CLIENT_KEY" "$COMPAT_CLIENT_KEY"
cp "$CLIENT_CERT" "$COMPAT_CLIENT_CERT"

openssl pkcs12 \
  -export \
  -out "$CLIENT_P12" \
  -inkey "$CLIENT_KEY" \
  -in "$CLIENT_CERT" \
  -certfile "$CA_BUNDLE" \
  -name "finpay-client-01" \
  -passout "pass:${CLIENT_CERT_PASSWORD}"

openssl pkcs12 \
  -export \
  -legacy \
  -out "$CLIENT_BROWSER_P12" \
  -inkey "$CLIENT_KEY" \
  -in "$CLIENT_CERT" \
  -certfile "$CA_BUNDLE" \
  -name "finpay-client-01" \
  -passout "pass:${CLIENT_CERT_PASSWORD}"

cp "$CLIENT_P12" "$COMPAT_CLIENT_P12"
cp "$CLIENT_BROWSER_P12" "$COMPAT_BROWSER_P12"

openssl req \
  -x509 \
  -newkey rsa:2048 \
  -nodes \
  -keyout "$UNTRUSTED_KEY" \
  -sha256 \
  -days 825 \
  -subj "/C=KR/ST=Seoul/O=FinPay/OU=Viewer-mTLS/CN=untrusted-client-01" \
  -out "$UNTRUSTED_CERT"

openssl pkcs12 \
  -export \
  -out "$UNTRUSTED_P12" \
  -inkey "$UNTRUSTED_KEY" \
  -in "$UNTRUSTED_CERT" \
  -name "untrusted-client-01" \
  -passout "pass:${CLIENT_CERT_PASSWORD}"

rm -f "$INTERMEDIATE_CSR" "$CLIENT_CSR" "${CERT_DIR}"/*.srl
chmod 600 "$ROOT_KEY" "$INTERMEDIATE_KEY" "$CLIENT_KEY" "$COMPAT_CLIENT_KEY" "$UNTRUSTED_KEY"
chmod 600 "$CLIENT_P12" "$CLIENT_BROWSER_P12" "$COMPAT_CLIENT_P12" "$COMPAT_BROWSER_P12" "$UNTRUSTED_P12"
chmod 644 "$ROOT_CERT" "$INTERMEDIATE_CERT" "$CA_BUNDLE" "$COMPAT_CA_BUNDLE" "$CLIENT_CERT" "$COMPAT_CLIENT_CERT" "$UNTRUSTED_CERT"

openssl verify -CAfile "$CA_BUNDLE" "$CLIENT_CERT" >/dev/null

cat <<EOF
Generated:
  CA bundle for CloudFront: ${CA_BUNDLE}
  Client certificate:       ${CLIENT_CERT}
  Client private key:       ${CLIENT_KEY}
  Browser import bundle:    ${CLIENT_P12}
  macOS browser bundle:     ${CLIENT_BROWSER_P12}
  Compatibility cert:       ${COMPAT_CLIENT_CERT}
  Compatibility key:        ${COMPAT_CLIENT_KEY}
  Compatibility P12:        ${COMPAT_CLIENT_P12}
  Compatibility macOS P12:  ${COMPAT_BROWSER_P12}
  Untrusted test cert:      ${UNTRUSTED_CERT}

Browser P12 password:
  ${CLIENT_CERT_PASSWORD}

After terraform apply, verify with:
  curl -v --cert ${COMPAT_CLIENT_CERT} --key ${COMPAT_CLIENT_KEY} https://app.finpay.p-e.kr/health
EOF
