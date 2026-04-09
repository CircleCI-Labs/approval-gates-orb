#!/usr/bin/env bash
set -euo pipefail

# Detect platform and ensure dependencies are available.
detect_os() {
  case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
    linux*)  PLATFORM="linux" ;;
    darwin*) PLATFORM="linux" ;;
    msys*|cygwin*|mingw*) PLATFORM="windows" ;;
    *)
      echo "ERROR: Unsupported platform: $(uname -s)"
      exit 1
      ;;
  esac
}

ensure_deps() {
  if ! command -v curl &>/dev/null; then
    echo "ERROR: curl is required but not found."
    exit 1
  fi
  if ! command -v jq &>/dev/null; then
    if [[ "$PLATFORM" == "windows" ]]; then
      echo "jq not found, installing via Chocolatey..."
      choco install jq -y --no-progress >/dev/null 2>&1
      eval "$(grep -v 'export PATH' /c/ProgramData/chocolatey/bin/refreshenv.cmd 2>/dev/null || true)"
      export PATH="/c/ProgramData/chocolatey/bin:$PATH"
    else
      echo "ERROR: jq is required but not found."
      exit 1
    fi
  fi
}

detect_os
ensure_deps

# Resolve env var names from orb parameters (indirect expansion).
# Falls back to direct env var names for standalone use outside the orb.
if [[ -n "${ORB_VAL_API_TOKEN_VAR:-}" ]]; then
  CIRCLECI_API_TOKEN="${!ORB_VAL_API_TOKEN_VAR:-}"
fi

if [[ -n "${ORB_VAL_APPROVERS_VAR:-}" ]]; then
  AUTHORIZED_APPROVERS="${!ORB_VAL_APPROVERS_VAR:-}"
fi

if [[ -n "${ORB_VAL_APPROVAL_JOB_NAME:-}" ]]; then
  APPROVAL_JOB_NAME="${ORB_VAL_APPROVAL_JOB_NAME}"
fi

API_BASE="https://circleci.com/api/v2"

if [[ -z "${CIRCLECI_API_TOKEN:-}" ]]; then
  echo "ERROR: CIRCLECI_API_TOKEN is not set. Add the circleci-api context to this job."
  exit 1
fi

if [[ -z "${AUTHORIZED_APPROVERS:-}" ]]; then
  echo "ERROR: AUTHORIZED_APPROVERS is not set. Add the deployment-approvers context to this job."
  exit 1
fi

if [[ -z "${CIRCLE_WORKFLOW_ID:-}" ]]; then
  echo "ERROR: CIRCLE_WORKFLOW_ID is not set. This script must run inside a CircleCI job."
  exit 1
fi

echo "Checking approval authorization for workflow ${CIRCLE_WORKFLOW_ID}..."

WORKFLOW_JOBS=$(curl -s -w "\n%{http_code}" \
  -H "Circle-Token: ${CIRCLECI_API_TOKEN}" \
  "${API_BASE}/workflow/${CIRCLE_WORKFLOW_ID}/job")
HTTP_CODE=$(echo "${WORKFLOW_JOBS}" | tail -1)
WORKFLOW_JOBS=$(echo "${WORKFLOW_JOBS}" | sed '$d')
if [[ "${HTTP_CODE}" -ne 200 ]]; then
  echo "ERROR: Failed to fetch workflow jobs (HTTP ${HTTP_CODE})"
  echo "Response: ${WORKFLOW_JOBS}"
  exit 1
fi

APPROVAL_JOB_NAME="${APPROVAL_JOB_NAME:-}"

if [[ -n "${APPROVAL_JOB_NAME}" ]]; then
  APPROVED_BY=$(echo "${WORKFLOW_JOBS}" | jq -r \
    --arg name "${APPROVAL_JOB_NAME}" \
    '.items[] | select(.type == "approval" and .name == $name and .status == "success") | .approved_by' \
    | head -1)
else
  APPROVED_BY=$(echo "${WORKFLOW_JOBS}" | jq -r \
    '.items[] | select(.type == "approval" and .status == "success") | .approved_by' \
    | head -1)
fi

if [[ -z "${APPROVED_BY}" ]]; then
  echo "ERROR: Could not determine who approved this workflow."
  echo "API response did not include approved_by field."
  exit 1
fi

USER_INFO=$(curl -s -w "\n%{http_code}" \
  -H "Circle-Token: ${CIRCLECI_API_TOKEN}" \
  "${API_BASE}/user/${APPROVED_BY}")
HTTP_CODE=$(echo "${USER_INFO}" | tail -1)
USER_INFO=$(echo "${USER_INFO}" | sed '$d')
if [[ "${HTTP_CODE}" -ne 200 ]]; then
  echo "ERROR: Failed to fetch user info for ${APPROVED_BY} (HTTP ${HTTP_CODE})"
  echo "Response: ${USER_INFO}"
  exit 1
fi

APPROVER_LOGIN=$(echo "${USER_INFO}" | jq -r '.login // empty')
APPROVER_NAME=$(echo "${USER_INFO}" | jq -r '.name // "Unknown"')

if [[ -z "${APPROVER_LOGIN}" ]]; then
  echo "ERROR: Could not resolve approver identity for user ID ${APPROVED_BY}."
  exit 1
fi

echo "Approval was granted by: ${APPROVER_NAME} (${APPROVER_LOGIN})"

IFS=',' read -ra ALLOWED <<< "${AUTHORIZED_APPROVERS}"
AUTHORIZED=false

for allowed_user in "${ALLOWED[@]}"; do
  trimmed=$(echo "${allowed_user}" | xargs)
  if [[ "${APPROVER_LOGIN}" == "${trimmed}" ]]; then
    AUTHORIZED=true
    break
  fi
done

if [[ "${AUTHORIZED}" == "true" ]]; then
  echo "AUTHORIZED: ${APPROVER_LOGIN} is in the approved deployers list."
  echo "Proceeding with deployment..."
else
  echo ""
  echo "============================================================"
  echo "  DEPLOYMENT BLOCKED"
  echo "============================================================"
  echo ""
  echo "  ${APPROVER_NAME} (${APPROVER_LOGIN}) is NOT authorized"
  echo "  to approve production deployments."
  echo ""
  echo "  Authorized approvers: ${AUTHORIZED_APPROVERS}"
  echo ""
  echo "  Contact your DevSecOps team lead to request approval."
  echo ""
  echo "============================================================"
  exit 1
fi
