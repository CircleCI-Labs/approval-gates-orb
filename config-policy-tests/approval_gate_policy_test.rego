package org

import future.keywords

meta_target := {"_compiled_": {"meta": {"project_id": "00000000-0000-0000-0000-000000000000"}}}
meta_other := {"_compiled_": {"meta": {"project_id": "11111111-1111-1111-1111-111111111111"}}}
meta_second_target := {"_compiled_": {"meta": {"project_id": "22222222-2222-2222-2222-222222222222"}}}

# ---------------------------------------------------------------------------
# Project-scoped tests
# ---------------------------------------------------------------------------

# Test: workflow with deploy job and no approval should fail
test_require_approval_before_deploy if {
    result := require_approval_before_deploy with input as object.union(meta_target, {
        "workflows": {
            "build-and-deploy": {
                "jobs": [
                    {"build": {}},
                    {"deploy-to-prod": {"requires": ["build"]}}
                ]
            }
        },
        "jobs": {
            "build": {"steps": [{"run": "echo hello"}]},
            "deploy-to-prod": {"steps": [{"run": "echo deploying"}]}
        }
    })
    result != ""
}

# Test: workflow with approval gate should pass
test_approval_present_passes if {
    not require_approval_before_deploy with input as object.union(meta_target, {
        "workflows": {
            "build-and-deploy": {
                "jobs": [
                    {"build": {}},
                    {"hold-for-approval": {"type": "approval", "requires": ["build"]}},
                    {"deploy-to-prod": {"requires": ["hold-for-approval"]}}
                ]
            }
        },
        "jobs": {
            "build": {"steps": [{"run": "echo hello"}]},
            "deploy-to-prod": {
                "context": ["deployment-approvers", "circleci-api"],
                "steps": [
                    {"run": {"command": "bash ./scripts/validate_approver.sh"}},
                    {"run": "echo deploying"}
                ]
            }
        }
    })
}

# Test: deploy job without deployment-approvers context should fail
test_deploy_missing_approver_context if {
    result := deploy_jobs_require_approver_context with input as object.union(meta_target, {
        "jobs": {
            "deploy-to-staging": {
                "context": ["circleci-api"],
                "steps": [
                    {"run": {"command": "bash ./scripts/validate_approver.sh"}},
                    {"run": "echo deploying"}
                ]
            }
        }
    })
    result != ""
}

# Test: deploy job without circleci-api context should fail
test_deploy_missing_api_context if {
    result := deploy_jobs_require_api_context with input as object.union(meta_target, {
        "jobs": {
            "deploy-to-prod": {
                "context": ["deployment-approvers"],
                "steps": [
                    {"run": {"command": "bash ./scripts/validate_approver.sh"}},
                    {"run": "echo deploying"}
                ]
            }
        }
    })
    result != ""
}

# Test: deploy job without validation script as first step should fail
test_deploy_missing_validation_step if {
    result := deploy_jobs_validate_approver with input as object.union(meta_target, {
        "jobs": {
            "deploy-to-prod": {
                "context": ["deployment-approvers", "circleci-api"],
                "steps": [
                    {"run": "echo deploying"}
                ]
            }
        }
    })
    result != ""
}

# Test: deploy job with validation script as first step should pass
test_deploy_with_validation_passes if {
    not deploy_jobs_validate_approver with input as object.union(meta_target, {
        "jobs": {
            "deploy-to-prod": {
                "context": ["deployment-approvers", "circleci-api"],
                "steps": [
                    {"run": {"command": "bash ./scripts/validate_approver.sh"}},
                    {"run": "echo deploying"}
                ]
            }
        }
    })
}

# Test: non-deploy job should not be affected
test_non_deploy_job_ignored if {
    not deploy_jobs_require_approver_context with input as object.union(meta_target, {
        "jobs": {
            "build": {
                "steps": [{"run": "echo building"}]
            },
            "test": {
                "steps": [{"run": "echo testing"}]
            }
        }
    })
}

# Test: policy should NOT fire for a different project
test_different_project_ignored if {
    not require_approval_before_deploy with input as object.union(meta_other, {
        "workflows": {
            "build-and-deploy": {
                "jobs": [
                    {"build": {}},
                    {"deploy-to-prod": {"requires": ["build"]}}
                ]
            }
        },
        "jobs": {
            "build": {"steps": [{"run": "echo hello"}]},
            "deploy-to-prod": {"steps": [{"run": "echo deploying"}]}
        }
    })
}

# ---------------------------------------------------------------------------
# Multi-project tests
# ---------------------------------------------------------------------------

# Test: second project in target_project_ids should also trigger rules
test_multi_project_second_id_fires if {
    result := require_approval_before_deploy with input as object.union(meta_second_target, {
        "workflows": {
            "ship-it": {
                "jobs": [
                    {"build": {}},
                    {"deploy-to-prod": {"requires": ["build"]}}
                ]
            }
        },
        "jobs": {
            "build": {"steps": [{"run": "echo hello"}]},
            "deploy-to-prod": {"steps": [{"run": "echo deploying"}]}
        }
    })
        with target_project_ids as {"00000000-0000-0000-0000-000000000000", "22222222-2222-2222-2222-222222222222"}
    result != ""
}

# ---------------------------------------------------------------------------
# Org-wide tests
# ---------------------------------------------------------------------------

# Test: with enforce_org_wide, rules fire for any project
test_org_wide_fires_for_any_project if {
    result := require_approval_before_deploy with input as object.union(meta_other, {
        "workflows": {
            "build-and-deploy": {
                "jobs": [
                    {"build": {}},
                    {"deploy-to-prod": {"requires": ["build"]}}
                ]
            }
        },
        "jobs": {
            "build": {"steps": [{"run": "echo hello"}]},
            "deploy-to-prod": {"steps": [{"run": "echo deploying"}]}
        }
    })
        with enforce_org_wide as true
    result != ""
}
