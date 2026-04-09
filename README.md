# Approval Gates Orb

[![CircleCI Build Status](https://circleci.com/gh/CircleCI-Labs/approval-gates-orb.svg?style=shield "CircleCI Build Status")](https://circleci.com/gh/CircleCI-Labs/approval-gates-orb) [![CircleCI Orb Version](https://badges.circleci.com/orbs/cci-labs/approval-gates.svg)](https://circleci.com/developer/orbs/orb/cci-labs/approval-gates) [![GitHub License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://raw.githubusercontent.com/CircleCI-Labs/approval-gates-orb/main/LICENSE) [![CircleCI Community](https://img.shields.io/badge/community-CircleCI%20Discuss-343434.svg)](https://discuss.circleci.com/c/ecosystem/orbs)

A CircleCI orb for enforcing approval gating on production deployments by validating that the user who approved a workflow is on an authorized approvers list before allowing deployment to proceed.

### Disclaimer

CircleCI Labs, including this repo, is a collection of solutions developed by members of CircleCI's Field Engineering teams through our engagement with various customer needs.

 ✅ Created by engineers @ CircleCI
 ✅ Used by real CircleCI customers
 ❌ not officially supported by CircleCI support

## Overview

This orb provides commands and jobs to:

- Validate that the user who clicked "Approve" on a workflow is in an authorized approvers list
- Block unauthorized deployments immediately with a clear error message
- Support Linux, macOS, and Windows executors with automatic platform detection
- Work with any VCS provider

CircleCI's `type: approval` workflow step does not natively restrict who can approve -- anyone with write access to the project can click "Approve." This orb adds a runtime authorization check after approval, comparing the approver's identity against a context-managed allowlist.

## Prerequisites

- A CircleCI [Scale plan](https://circleci.com/pricing/) or above
- A CircleCI context named `circleci-api` with the following environment variable:
  - `CIRCLECI_API_TOKEN`: A CircleCI personal API token with read access
- A CircleCI context named `deployment-approvers` with the following environment variable:
  - `AUTHORIZED_APPROVERS`: Comma-separated list of authorized CircleCI login usernames (e.g. `Zendaya,Muhammad,Ryan Coogler`)
- `curl` and `jq` available in the executor. The orb's built-in executors and all standard CircleCI images (`cimg/*`, machine, macOS) include both. On Windows, jq is installed automatically if missing. If you use a custom or minimal Docker image, ensure both tools are installed.

## Commands

### validate_approver

Validates that the user who approved the upstream approval job is in the authorized approvers list. Run this as the first step of any deployment job that follows an approval gate.

**Parameters:**

- `api-token` (env_var_name): Name of the env var containing the CircleCI API token (default: `CIRCLECI_API_TOKEN`)
- `authorized-approvers` (env_var_name): Name of the env var containing the comma-separated authorized logins (default: `AUTHORIZED_APPROVERS`)
- `approval-job-name` (string): Name of the specific approval job to check. If empty, the first successful approval-type job in the workflow is used (default: `""`)

The platform is detected automatically at runtime. No configuration needed for Linux, macOS, or Windows executors.

Note on env_var_name parameters:

- These parameters expect the NAME of an environment variable, not the value. The orb resolves the actual values at runtime via indirect expansion.

## Jobs

### validate_approver

A standalone job that wraps the `validate_approver` command. Use this as a separate workflow step between the approval gate and your deployment job.

**Parameters:**

- All parameters from the `validate_approver` command above, plus:
- `executor` (executor): Executor to run the validation on (default: `default`)

## Executors

### default

Linux Docker executor (`cimg/base`) with curl and jq pre-installed.

**Parameters:**

- `tag` (string): cimg/base image tag (default: `current`)

### windows

Windows machine executor (`windows-server-2022-gui`). The orb automatically detects the platform and installs any missing dependencies (such as jq).

**Parameters:**

- `tag` (string): Windows machine image tag (default: `current`)

## Example Usage

```yaml
version: 2.1

orbs:
  approval-gates: your-namespace/approval-gates@1.0.0

jobs:
  deploy-to-prod:
    docker:
      - image: cimg/base:current
    steps:
      - approval-gates/validate_approver
      - run:
          name: Deploy to production
          command: |
            # Your deployment commands here
            echo "Deploying to production..."

workflows:
  build-approve-deploy:
    jobs:
      - build
      - approve-deploy:
          type: approval
          requires:
            - build
      - deploy-to-prod:
          context:
            - deployment-approvers
            - circleci-api
          requires:
            - approve-deploy
```

## Supplementary: Config Policy

The orb validates approvers at runtime, but a developer could remove the validation step from their config and bypass the check entirely. The `config-policy/` directory contains an OPA/Rego policy that closes this gap by enforcing approval gate usage at the config compilation level -- before the pipeline ever runs.

Config policies are a Scale plan feature. See the [CircleCI docs](https://circleci.com/docs/config-policy-management/) for details on pushing policies to your org.

### Configuration

Open `config-policy/approval_gate_policy.rego` and edit the configuration block at the top of the file:

```rego
enforce_org_wide := false

target_project_ids := {
    "00000000-0000-0000-0000-000000000000",
}

deploy_job_patterns := ["deploy", "release", "promote", "publish"]
```

- `enforce_org_wide`: Set to `true` to enforce across all projects in the org. When `false`, only projects listed in `target_project_ids` are checked.
- `target_project_ids`: One or more CircleCI project UUIDs. Find yours under Project Settings > Overview in the CircleCI UI. Ignored when `enforce_org_wide` is `true`.
- `deploy_job_patterns`: Substrings used to identify deployment jobs by name. Any job whose name contains one of these patterns (case-insensitive) is treated as a deploy job.

### What the Policy Enforces

For every deploy job in a target project, the policy requires:

1. The workflow contains at least one `type: approval` job
2. The deploy job includes the `deployment-approvers` context
3. The deploy job includes the `circleci-api` context
4. The deploy job runs `validate_approver` as its first step

### Pushing the Policy

After editing the configuration, push the policy to your org using the CircleCI CLI:

```bash
circleci policy push config-policy/ --owner-id <your-org-id>
```

If your org already has other config policies, fetch them first and push the combined bundle to avoid overwriting existing policies. See the [policy management docs](https://circleci.com/docs/config-policy-management/) for the full workflow.

## Resources

### How to Contribute

We welcome [issues](https://github.com/CircleCI-Labs/approval-gates-orb/issues) to and [pull requests](https://github.com/CircleCI-Labs/approval-gates-orb/pulls) against this repository!

### How to Publish An Update

1. Merge pull requests with desired changes to the main branch.
2. Find the current version of the orb.
   - You can run `circleci orb info your-namespace/approval-gates | grep "Latest"` to see the current version.
3. Create a [new Release](https://github.com/CircleCI-Labs/approval-gates-orb/releases/new) on GitHub.
   - Click "Choose a tag" and create a new [semantically versioned](http://semver.org/) tag. (ex: v1.0.0)
4. Click "Publish Release".
   - This will push a new tag and trigger your publishing pipeline on CircleCI.
