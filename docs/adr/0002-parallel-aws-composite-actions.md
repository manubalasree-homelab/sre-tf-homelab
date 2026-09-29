---
status: accepted
---

# AWS gets its own composite actions, not branches inside the Azure ones

The per-scope plan/apply composite actions hard-code Azure OIDC (`ARM_*`
env vars). EKS needs a different mechanism — assuming an IAM role via
GitHub OIDC (`aws-actions/configure-aws-credentials`) — so we add parallel
AWS actions (e.g. `per-account-aws/jobs/terraform-plan`, `-apply`, and a
`-destroy`) instead of adding `aws_*` inputs and `if:` branches to the
existing ones. Role ARN and region arrive as GitHub variables
(`AWS_ROLE_ARN`, `AWS_REGION`), passed in as inputs.

## Considered Options

- **Branch inside the Azure actions** (`aws_role_arn` input, conditional
  steps): rejected — this is the "different mechanism, not a different
  value" case ADR-0001 named as the reason to duplicate per scope.
- **Parallel AWS actions** (chosen).

## Consequences

- Same drift risk ADR-0001 accepted: a fix to the var-file cascade or
  backend-config logic now touches the Azure and AWS copies.
- Only the AWS set has a destroy action. Clusters are ephemeral, so destroy
  is a manual `workflow_dispatch` behind a required-reviewer GitHub
  Environment; there is no scheduled auto-destroy.
- The GitHub OIDC provider, the CI IAM role, the S3 state bucket and the
  DynamoDB lock table are created by hand once per AWS account, outside
  Terraform, since Terraform cannot create the role it needs to run.
