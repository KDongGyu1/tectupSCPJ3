#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

AWS_REGION="${AWS_REGION:-ap-northeast-2}"
AWS_PROFILE="${AWS_PROFILE:-}"
NAME_PREFIX="${NAME_PREFIX:-finpay-dev}"
APP_ARTIFACT_KEY="${APP_ARTIFACT_KEY:-tmp/server.py}"
MIN_HEALTHY_PERCENTAGE="${MIN_HEALTHY_PERCENTAGE:-0}"
INSTANCE_WARMUP="${INSTANCE_WARMUP:-60}"
WAIT_FOR_REFRESH="${WAIT_FOR_REFRESH:-true}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-15}"
MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-900}"

AWS_ARGS=(--region "$AWS_REGION")
if [[ -n "$AWS_PROFILE" ]]; then
  AWS_ARGS+=(--profile "$AWS_PROFILE")
fi

if [[ ! -f app/server.py ]]; then
  echo "app/server.py not found. Run this script from the repository root." >&2
  exit 1
fi

echo "Validating app/server.py..."
python3 -m py_compile app/server.py

ACCOUNT_ID="$(aws sts get-caller-identity "${AWS_ARGS[@]}" --query Account --output text)"
APP_ARTIFACT_BUCKET="${APP_ARTIFACT_BUCKET:-${NAME_PREFIX}-tfstate-${ACCOUNT_ID}}"

echo "Uploading app/server.py to s3://${APP_ARTIFACT_BUCKET}/${APP_ARTIFACT_KEY}..."
aws s3 cp app/server.py "s3://${APP_ARTIFACT_BUCKET}/${APP_ARTIFACT_KEY}" "${AWS_ARGS[@]}"

ASG_NAMES=(
  "${NAME_PREFIX}-payment-asg"
  "${NAME_PREFIX}-auth-asg"
  "${NAME_PREFIX}-ops-asg"
)

echo "Starting Auto Scaling instance refresh..."
for asg_name in "${ASG_NAMES[@]}"; do
  refresh_id="$(
    aws autoscaling start-instance-refresh \
      "${AWS_ARGS[@]}" \
      --auto-scaling-group-name "$asg_name" \
      --preferences "{\"MinHealthyPercentage\":${MIN_HEALTHY_PERCENTAGE},\"InstanceWarmup\":${INSTANCE_WARMUP}}" \
      --query InstanceRefreshId \
      --output text
  )"
  echo "- ${asg_name}: ${refresh_id}"
done

echo
if [[ "$WAIT_FOR_REFRESH" != "true" ]]; then
  echo "Check refresh status with:"
  for asg_name in "${ASG_NAMES[@]}"; do
    cat <<EOF
aws autoscaling describe-instance-refreshes \\
  --region ${AWS_REGION} \\
  --auto-scaling-group-name ${asg_name} \\
  --max-records 1 \\
  --query 'InstanceRefreshes[0].{Status:Status,Percent:PercentageComplete,Reason:StatusReason}'

EOF
  done
  exit 0
fi

echo "Waiting for instance refresh to finish..."
deadline=$((SECONDS + MAX_WAIT_SECONDS))
while true; do
  all_done=true
  for index in "${!ASG_NAMES[@]}"; do
    asg_name="${ASG_NAMES[$index]}"
    status="$(
      aws autoscaling describe-instance-refreshes \
        "${AWS_ARGS[@]}" \
        --auto-scaling-group-name "$asg_name" \
        --max-records 1 \
        --query 'InstanceRefreshes[0].Status' \
        --output text
    )"
    percent="$(
      aws autoscaling describe-instance-refreshes \
        "${AWS_ARGS[@]}" \
        --auto-scaling-group-name "$asg_name" \
        --max-records 1 \
        --query 'InstanceRefreshes[0].PercentageComplete' \
        --output text
    )"
    echo "- ${asg_name}: ${status} (${percent}%)"

    case "$status" in
      Successful)
        ;;
      Failed|Cancelled|RollbackFailed)
        echo "Instance refresh failed for ${asg_name}. Check Auto Scaling events before retrying." >&2
        exit 1
        ;;
      *)
        all_done=false
        ;;
    esac
  done

  if [[ "$all_done" == "true" ]]; then
    echo "App deployment finished."
    exit 0
  fi

  if (( SECONDS >= deadline )); then
    echo "Timed out waiting for instance refresh after ${MAX_WAIT_SECONDS} seconds." >&2
    exit 1
  fi

  sleep "$POLL_INTERVAL_SECONDS"
done
