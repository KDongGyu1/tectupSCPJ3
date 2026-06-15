#!/usr/bin/env bash
set -euo pipefail

export AWS_PAGER=""

MODE="${1:-}"

aws_cf() {
  if [[ -n "${AWS_PROFILE:-}" ]]; then
    aws --profile "$AWS_PROFILE" cloudfront "$@"
    return
  fi

  unset AWS_PROFILE
  aws cloudfront "$@"
}

require_env() {
  local name="$1"

  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: ${name}" >&2
    exit 1
  fi
}

find_trust_store_id() {
  local trust_store_id

  trust_store_id="$(
    aws_cf list-trust-stores --no-paginate --output json \
      | jq -r --arg name "$TRUST_STORE_NAME" \
          '(.TrustStoreList
            | if type == "object" then (.Items // []) else (. // []) end)
          | map(select(.Name == $name))
          | .[0].Id // empty'
  )"

  if [[ "$trust_store_id" == "None" || "$trust_store_id" == "null" ]]; then
    trust_store_id=""
  fi

  printf '%s' "$trust_store_id"
}

trust_store_source_arg() {
  local source_arg

  source_arg="CaCertificatesBundleS3Location={Bucket=${CA_BUNDLE_BUCKET},Key=${CA_BUNDLE_KEY},Region=${CA_BUNDLE_REGION}"

  if [[ -n "${CA_BUNDLE_VERSION:-}" && "${CA_BUNDLE_VERSION:-}" != "null" ]]; then
    source_arg="${source_arg},Version=${CA_BUNDLE_VERSION}"
  fi

  source_arg="${source_arg}}"
  printf '%s' "$source_arg"
}

wait_trust_store_active() {
  local trust_store_id="$1"
  local status
  local reason

  for _ in {1..60}; do
    status="$(
      aws_cf get-trust-store \
        --identifier "$trust_store_id" \
        --query "TrustStore.Status" \
        --output text
    )"

    case "$status" in
      active)
        return 0
        ;;
      failed)
        reason="$(
          aws_cf get-trust-store \
            --identifier "$trust_store_id" \
            --query "TrustStore.Reason" \
            --output text
        )"
        echo "CloudFront trust store failed: ${reason}" >&2
        return 1
        ;;
    esac

    sleep 5
  done

  echo "CloudFront trust store did not become active in time: ${trust_store_id}" >&2
  return 1
}

upsert_trust_store() {
  local trust_store_id
  local source_arg
  local etag

  source_arg="$(trust_store_source_arg)"
  trust_store_id="$(find_trust_store_id)"

  if [[ -z "$trust_store_id" ]]; then
    echo "Creating CloudFront trust store: ${TRUST_STORE_NAME}" >&2
    trust_store_id="$(
      aws_cf create-trust-store \
        --name "$TRUST_STORE_NAME" \
        --ca-certificates-bundle-source "$source_arg" \
        --query "TrustStore.Id" \
        --output text
      )"
  else
    echo "Updating CloudFront trust store: ${TRUST_STORE_NAME} (${trust_store_id})" >&2
    etag="$(
      aws_cf get-trust-store \
        --identifier "$trust_store_id" \
        --query "ETag" \
        --output text
    )"

    aws_cf update-trust-store \
      --id "$trust_store_id" \
      --ca-certificates-bundle-source "$source_arg" \
      --if-match "$etag" \
      --output json >/dev/null
  fi

  wait_trust_store_active "$trust_store_id"
  printf '%s' "$trust_store_id"
}

apply_viewer_mtls() {
  local trust_store_id
  local tmpdir
  local distribution_config
  local updated_config
  local etag

  trust_store_id="$(upsert_trust_store)"
  tmpdir="$(mktemp -d)"
  distribution_config="${tmpdir}/distribution-config.json"
  updated_config="${tmpdir}/updated-distribution-config.json"

  aws_cf get-distribution-config \
    --id "$DISTRIBUTION_ID" \
    >"$distribution_config"

  etag="$(jq -r '.ETag' "$distribution_config")"

  if jq -e \
    --arg mode "$VIEWER_MTLS_MODE" \
    --arg trust_store_id "$trust_store_id" \
    --argjson advertise_ca_names "$ADVERTISE_CA_NAMES" \
    --argjson ignore_certificate_expiry "$IGNORE_CERTIFICATE_EXPIRY" \
    '.DistributionConfig.ViewerMtlsConfig? as $config
      | $config != null
      and $config.Mode == $mode
      and $config.TrustStoreConfig.TrustStoreId == $trust_store_id
      and (($config.TrustStoreConfig.AdvertiseTrustStoreCaNames // false) == $advertise_ca_names)
      and (($config.TrustStoreConfig.IgnoreCertificateExpiry // false) == $ignore_certificate_expiry)' \
    "$distribution_config" >/dev/null; then
    echo "CloudFront viewer mTLS is already configured on distribution: ${DISTRIBUTION_ID}"
    rm -rf "$tmpdir"
    return 0
  fi

  jq \
    --arg mode "$VIEWER_MTLS_MODE" \
    --arg trust_store_id "$trust_store_id" \
    --argjson advertise_ca_names "$ADVERTISE_CA_NAMES" \
    --argjson ignore_certificate_expiry "$IGNORE_CERTIFICATE_EXPIRY" \
    '.DistributionConfig
      | .ViewerMtlsConfig = {
          Mode: $mode,
          TrustStoreConfig: {
            TrustStoreId: $trust_store_id,
            AdvertiseTrustStoreCaNames: $advertise_ca_names,
            IgnoreCertificateExpiry: $ignore_certificate_expiry
          }
        }' \
    "$distribution_config" >"$updated_config"

  echo "Applying CloudFront viewer mTLS to distribution: ${DISTRIBUTION_ID}"
  aws_cf update-distribution \
    --id "$DISTRIBUTION_ID" \
    --if-match "$etag" \
    --distribution-config "file://${updated_config}" \
    --output json >/dev/null

  aws_cf wait distribution-deployed --id "$DISTRIBUTION_ID"
  rm -rf "$tmpdir"
}

remove_viewer_mtls() {
  local tmpdir
  local distribution_config
  local updated_config
  local etag

  tmpdir="$(mktemp -d)"
  distribution_config="${tmpdir}/distribution-config.json"
  updated_config="${tmpdir}/updated-distribution-config.json"

  if ! aws_cf get-distribution-config --id "$DISTRIBUTION_ID" >"$distribution_config"; then
    echo "CloudFront distribution not found or not readable; skipping viewer mTLS removal: ${DISTRIBUTION_ID}" >&2
    rm -rf "$tmpdir"
    return 0
  fi

  if jq -e '.DistributionConfig.ViewerMtlsConfig? == null' "$distribution_config" >/dev/null; then
    echo "CloudFront viewer mTLS is already absent: ${DISTRIBUTION_ID}"
    rm -rf "$tmpdir"
    return 0
  fi

  etag="$(jq -r '.ETag' "$distribution_config")"
  jq '.DistributionConfig | del(.ViewerMtlsConfig)' "$distribution_config" >"$updated_config"

  echo "Removing CloudFront viewer mTLS from distribution: ${DISTRIBUTION_ID}"
  aws_cf update-distribution \
    --id "$DISTRIBUTION_ID" \
    --if-match "$etag" \
    --distribution-config "file://${updated_config}" \
    --output json >/dev/null

  aws_cf wait distribution-deployed --id "$DISTRIBUTION_ID"
  rm -rf "$tmpdir"
}

delete_trust_store() {
  local trust_store_id
  local etag

  trust_store_id="$(find_trust_store_id)"

  if [[ -z "$trust_store_id" ]]; then
    echo "CloudFront trust store is already absent: ${TRUST_STORE_NAME}"
    return 0
  fi

  etag="$(
    aws_cf get-trust-store \
      --identifier "$trust_store_id" \
      --query "ETag" \
      --output text
  )"

  echo "Deleting CloudFront trust store: ${TRUST_STORE_NAME} (${trust_store_id})"
  aws_cf delete-trust-store \
    --id "$trust_store_id" \
    --if-match "$etag"
}

show_status() {
  aws_cf get-distribution-config \
    --id "$DISTRIBUTION_ID" \
    --query "DistributionConfig.ViewerMtlsConfig"
}

case "$MODE" in
  apply)
    require_env DISTRIBUTION_ID
    require_env TRUST_STORE_NAME
    require_env CA_BUNDLE_BUCKET
    require_env CA_BUNDLE_KEY
    require_env CA_BUNDLE_REGION
    require_env VIEWER_MTLS_MODE
    require_env ADVERTISE_CA_NAMES
    require_env IGNORE_CERTIFICATE_EXPIRY

    apply_viewer_mtls
    ;;
  destroy)
    require_env DISTRIBUTION_ID
    require_env TRUST_STORE_NAME

    remove_viewer_mtls
    delete_trust_store
    ;;
  status)
    require_env DISTRIBUTION_ID

    show_status
    ;;
  *)
    echo "Usage: $0 {apply|destroy|status}" >&2
    exit 2
    ;;
esac
