#!/usr/bin/env bash
set -euo pipefail

CERT_DIR="${CERT_DIR:-certs/mtls}"
CLIENT_CERT_PASSWORD="${CLIENT_CERT_PASSWORD:-finpay-dev}"

CA_KEY="${CERT_DIR}/client-ca.key"
CA_CERT="${CERT_DIR}/client-ca.crt"
CA_BUNDLE="${CERT_DIR}/client-ca-bundle.pem"
CLIENT_KEY="${CERT_DIR}/client.key"
CLIENT_CSR="${CERT_DIR}/client.csr"
CLIENT_CERT="${CERT_DIR}/client.crt"
CLIENT_P12="${CERT_DIR}/client.p12"
CLIENT_SERIAL="${CERT_DIR}/client-ca.srl"

mkdir -p "$CERT_DIR"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

client_ext="${tmpdir}/client-ext.cnf"

cat >"$client_ext" <<'EOF'
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

echo "Generating local CloudFront viewer mTLS CA and client certificate in ${CERT_DIR}"

openssl genrsa -out "$CA_KEY" 4096
openssl req \
  -x509 \
  -new \
  -nodes \
  -key "$CA_KEY" \
  -sha256 \
  -days 3650 \
  -subj "/CN=FinPay Dev Viewer mTLS Client CA" \
  -out "$CA_CERT"

cp "$CA_CERT" "$CA_BUNDLE"

openssl genrsa -out "$CLIENT_KEY" 2048
openssl req \
  -new \
  -key "$CLIENT_KEY" \
  -subj "/CN=finpay-dev-client" \
  -out "$CLIENT_CSR"

openssl x509 \
  -req \
  -in "$CLIENT_CSR" \
  -CA "$CA_CERT" \
  -CAkey "$CA_KEY" \
  -CAcreateserial \
  -out "$CLIENT_CERT" \
  -days 825 \
  -sha256 \
  -extfile "$client_ext"

openssl pkcs12 \
  -export \
  -out "$CLIENT_P12" \
  -inkey "$CLIENT_KEY" \
  -in "$CLIENT_CERT" \
  -certfile "$CA_CERT" \
  -name "finpay-dev-client" \
  -passout "pass:${CLIENT_CERT_PASSWORD}"

rm -f "$CLIENT_CSR" "$CLIENT_SERIAL"
chmod 600 "$CA_KEY" "$CLIENT_KEY" "$CLIENT_P12"
chmod 644 "$CA_CERT" "$CA_BUNDLE" "$CLIENT_CERT"

cat <<EOF
Generated:
  CA bundle for CloudFront: ${CA_BUNDLE}
  Client certificate:       ${CLIENT_CERT}
  Client private key:       ${CLIENT_KEY}
  Browser import bundle:    ${CLIENT_P12}

Browser P12 password:
  ${CLIENT_CERT_PASSWORD}

After terraform apply, verify with:
  curl -v --cert ${CLIENT_CERT} --key ${CLIENT_KEY} https://app.finpay-sec.p-e.kr/health
EOF
