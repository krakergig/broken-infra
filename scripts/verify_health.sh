#!/usr/bin/env bash
# verify_health.sh
# Post-deploy smoke test: polls an endpoint until it returns an acceptable HTTP
# status, or fails after a timeout. Called by the Jenkins pipeline against the
# application ALB after a deploy.
#
# Usage: ./verify_health.sh <url> [expected_status] [max_attempts] [sleep_seconds]
#   url            Full URL to probe (e.g. https://app-alb.eu-central-1.elb.amazonaws.com/health)
#   expected_status Comma-separated acceptable HTTP codes (default: 200)
#   max_attempts    Number of polling attempts before giving up (default: 10)
#   sleep_seconds   Delay between attempts (default: 6)

set -euo pipefail

URL="${1:-}"
EXPECTED_STATUS="${2:-200}"
MAX_ATTEMPTS="${3:-10}"
SLEEP_SECONDS="${4:-6}"

if [[ -z "${URL}" ]]; then
  echo "ERROR: target URL is required" >&2
  echo "Usage: $0 <url> [expected_status] [max_attempts] [sleep_seconds]" >&2
  exit 2
fi

# Returns the HTTP status code for a single request. -k because the challenge uses a
# self-signed ALB certificate.
http_status() {
  curl -k -s -o /dev/null -w '%{http_code}' --max-time 5 "$1"
}

# True if $1 is one of the comma-separated codes in $EXPECTED_STATUS.
status_ok() {
  local code="$1"
  IFS=',' read -ra allowed <<< "${EXPECTED_STATUS}"
  for a in "${allowed[@]}"; do
    [[ "${code}" == "${a}" ]] && return 0
  done
  return 1
}

echo "Verifying health of ${URL} (expecting ${EXPECTED_STATUS})..."

attempt=1
while (( attempt <= MAX_ATTEMPTS )); do
  # FLAW (script): the endpoint is probed THREE times per attempt when a single
  # request is sufficient to determine health. These redundant calls add no
  # reliability (we only evaluate the last result) yet triple the request volume,
  # which — because the pipeline logs every command's output to S3 (see Jenkinsfile)
  # — also inflates log volume and cost. Core behaviour is unaffected: health is
  # still correctly detected. Fix: probe once per attempt and evaluate that result.
  status="$(http_status "${URL}")"   # probe 1
  status="$(http_status "${URL}")"   # probe 2 (redundant)
  status="$(http_status "${URL}")"   # probe 3 (redundant)

  if status_ok "${status}"; then
    echo "OK: ${URL} returned ${status} on attempt ${attempt}."
    exit 0
  fi

  echo "Attempt ${attempt}/${MAX_ATTEMPTS}: got HTTP ${status}, retrying in ${SLEEP_SECONDS}s..."
  (( attempt++ ))
  sleep "${SLEEP_SECONDS}"
done

echo "ERROR: ${URL} did not become healthy after ${MAX_ATTEMPTS} attempts." >&2
exit 1
