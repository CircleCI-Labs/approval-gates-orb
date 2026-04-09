$ErrorActionPreference = "Stop"

# Resolve env var names from orb parameters (indirect lookup).
# Falls back to direct env var names for standalone use outside the orb.
$ApiTokenVarName = if ($env:ORB_VAL_API_TOKEN_VAR) { $env:ORB_VAL_API_TOKEN_VAR } else { "CIRCLECI_API_TOKEN" }
$ApproversVarName = if ($env:ORB_VAL_APPROVERS_VAR) { $env:ORB_VAL_APPROVERS_VAR } else { "AUTHORIZED_APPROVERS" }

$ApiToken = [Environment]::GetEnvironmentVariable($ApiTokenVarName)
$AuthorizedApprovers = [Environment]::GetEnvironmentVariable($ApproversVarName)
$WorkflowId = $env:CIRCLE_WORKFLOW_ID
$ApprovalJobName = $env:ORB_VAL_APPROVAL_JOB_NAME

$ApiBase = "https://circleci.com/api/v2"

if (-not $ApiToken) {
    Write-Host "ERROR: $ApiTokenVarName is not set. Add the circleci-api context to this job."
    exit 1
}

if (-not $AuthorizedApprovers) {
    Write-Host "ERROR: $ApproversVarName is not set. Add the deployment-approvers context to this job."
    exit 1
}

if (-not $WorkflowId) {
    Write-Host "ERROR: CIRCLE_WORKFLOW_ID is not set. This script must run inside a CircleCI job."
    exit 1
}

Write-Host "Checking approval authorization for workflow $WorkflowId..."

$Headers = @{ "Circle-Token" = $ApiToken }

try {
    $WorkflowJobs = Invoke-RestMethod -Uri "$ApiBase/workflow/$WorkflowId/job" -Headers $Headers -Method Get
} catch {
    Write-Host "ERROR: Failed to fetch workflow jobs."
    Write-Host "Response: $($_.Exception.Message)"
    exit 1
}

$ApprovalJobs = $WorkflowJobs.items | Where-Object { $_.type -eq "approval" -and $_.status -eq "success" }

if ($ApprovalJobName) {
    $ApprovalJob = $ApprovalJobs | Where-Object { $_.name -eq $ApprovalJobName } | Select-Object -First 1
} else {
    $ApprovalJob = $ApprovalJobs | Select-Object -First 1
}

$ApprovedBy = $ApprovalJob.approved_by

if (-not $ApprovedBy) {
    Write-Host "ERROR: Could not determine who approved this workflow."
    Write-Host "API response did not include approved_by field."
    exit 1
}

try {
    $UserInfo = Invoke-RestMethod -Uri "$ApiBase/user/$ApprovedBy" -Headers $Headers -Method Get
} catch {
    Write-Host "ERROR: Failed to fetch user info for $ApprovedBy."
    Write-Host "Response: $($_.Exception.Message)"
    exit 1
}

$ApproverLogin = $UserInfo.login
$ApproverName = if ($UserInfo.name) { $UserInfo.name } else { "Unknown" }

if (-not $ApproverLogin) {
    Write-Host "ERROR: Could not resolve approver identity for user ID $ApprovedBy."
    exit 1
}

Write-Host "Approval was granted by: $ApproverName ($ApproverLogin)"

$AllowedUsers = $AuthorizedApprovers -split "," | ForEach-Object { $_.Trim() }
$Authorized = $AllowedUsers -contains $ApproverLogin

if ($Authorized) {
    Write-Host "AUTHORIZED: $ApproverLogin is in the approved deployers list."
    Write-Host "Proceeding with deployment..."
} else {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host "  DEPLOYMENT BLOCKED"
    Write-Host "============================================================"
    Write-Host ""
    Write-Host "  $ApproverName ($ApproverLogin) is NOT authorized"
    Write-Host "  to approve production deployments."
    Write-Host ""
    Write-Host "  Authorized approvers: $AuthorizedApprovers"
    Write-Host ""
    Write-Host "  Contact your DevSecOps team lead to request approval."
    Write-Host ""
    Write-Host "============================================================"
    exit 1
}
