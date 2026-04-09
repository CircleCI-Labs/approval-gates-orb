package org

import future.keywords

# Enforces that deployment workflows include approval gates and that deployment
# jobs run the approver validation script as their first command step.
#
# This policy prevents developers from removing the approval validation from
# their pipeline configs, closing the loop on the runtime check.

# ===================== USER CONFIGURATION =====================
# Edit the values below. Do not modify anything below this block.

# Set to true to enforce across all projects in the org.
# When false, only projects listed in target_project_ids are checked.
enforce_org_wide := false

# Add one or more CircleCI project UUIDs (Project Settings > Overview).
# Ignored when enforce_org_wide is true.
target_project_ids := {
    "00000000-0000-0000-0000-000000000000",
}

# Job name substrings that identify deployment jobs.
deploy_job_patterns := ["deploy", "release", "promote", "publish"]

# ================ END USER CONFIGURATION =====================

policy_name contains "approval_gate_enforcement"

is_target_project if { enforce_org_wide }
is_target_project if {
    not enforce_org_wide
    input._compiled_.meta.project_id in target_project_ids
}

is_deploy_job(job_name) if {
    some pattern in deploy_job_patterns
    contains(lower(job_name), pattern)
}

has_approval_job(workflow) if {
    some job_name, job_config in workflow.jobs[_]
    is_object(job_config)
    job_config.type == "approval"
}

has_approval_job(workflow) if {
    some job_entry in workflow.jobs
    is_string(job_entry)
    false
}

has_deploy_job(workflow) if {
    some job_entry in workflow.jobs
    is_object(job_entry)
    some job_name, _ in job_entry
    is_deploy_job(job_name)
}

has_required_contexts(job_config) if {
    contexts := job_config.context
    some ctx in contexts
    ctx == "deployment-approvers"
}

has_api_context(job_config) if {
    contexts := job_config.context
    some ctx in contexts
    ctx == "circleci-api"
}

first_step_is_validation(job_config) if {
    steps := job_config.steps
    count(steps) > 0
    first_step := steps[0]
    is_object(first_step)
    some key, val in first_step
    key == "run"
    is_object(val)
    contains(val.command, "validate_approver")
}

first_step_is_validation(job_config) if {
    steps := job_config.steps
    count(steps) > 0
    first_step := steps[0]
    is_object(first_step)
    some key, val in first_step
    key == "run"
    is_string(val)
    contains(val, "validate_approver")
}

# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------

enable_hard contains "require_approval_before_deploy"

require_approval_before_deploy := reason if {
    is_target_project
    some wf_name, wf_config in input.workflows
    has_deploy_job(wf_config)
    not has_approval_job(wf_config)
    reason := sprintf(
        "Workflow '%s' contains deployment jobs but no approval gate. Add a job with type: approval before any deploy jobs.",
        [wf_name]
    )
}

enable_hard contains "deploy_jobs_require_approver_context"

deploy_jobs_require_approver_context := reason if {
    is_target_project
    some job_name, job_config in input.jobs
    is_deploy_job(job_name)
    not has_required_contexts(job_config)
    reason := sprintf(
        "Deploy job '%s' must include the 'deployment-approvers' context to enforce approval validation.",
        [job_name]
    )
}

enable_hard contains "deploy_jobs_require_api_context"

deploy_jobs_require_api_context := reason if {
    is_target_project
    some job_name, job_config in input.jobs
    is_deploy_job(job_name)
    not has_api_context(job_config)
    reason := sprintf(
        "Deploy job '%s' must include the 'circleci-api' context to enable approval validation.",
        [job_name]
    )
}

enable_hard contains "deploy_jobs_validate_approver"

deploy_jobs_validate_approver := reason if {
    is_target_project
    some job_name, job_config in input.jobs
    is_deploy_job(job_name)
    not first_step_is_validation(job_config)
    reason := sprintf(
        "Deploy job '%s' must run validate_approver.sh as its first step to enforce approval gating.",
        [job_name]
    )
}
