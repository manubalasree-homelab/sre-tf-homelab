---
status: accepted
---

# Modules are independent repos; the deployable root config lives in this repo as `tf-eks`

Supersedes ADR-0003 and ADR-0004. Each Terraform module is its own public
repo with a 1:1 relation to its upstream: `terraform-aws-eks` and
`terraform-aws-eks-pod-identity` are org forks (unpatched, tags carried over),
and `sre-tf-eks` is the thin wrapper around them (own semver tags via the
shared `semantic-version.yml`, own CI calling the shared lint/validate
workflows). The deployable root config, `tf-eks/`, lives in this repo, sources
`sre-tf-eks` by tag, and is deployed by `tf-eks-deploy.yml` using the
`per-account-aws` actions. The relative-path mirrors, `mirrors.conf` and
`mirror-sync.yml` are gone; an upstream bump is a fork sync plus a new ref in
the consumer.

## Considered Options

- **Mirrors as folders in this repo** (ADR-0004): removed. Keeping upstream
  code inside a tooling repo cost more than it saved once separate repos were
  acceptable.
- **A separate root-config repo** (ADR-0003's `sre-tf-aws-eks`): dropped in
  favour of keeping the deployer next to the actions it calls, at the cost of
  the risks below.

## Consequences

- This repo is **public** on a Free org. Workflow logs, including plan output,
  are public. Tfvars therefore stay in the private `homelab-tf-account-vars`,
  cloned in the workflow with a token (`ACCOUNT_VARS_TOKEN`), and plan output
  must not be treated as private.
- The OIDC trust policy matches environment subs only:
  `repo:manubalasree-homelab/sre-tf-homelab:environment:aws-plan`, `aws-apply`
  and `aws-destroy`. A `pull_request` or branch sub is never trusted. Each
  Environment defines its own `AWS_ROLE_ARN`; plan's role is read-only.
- A bad commit here can now affect both the shared tooling and live
  infrastructure. Apply and destroy are manual `workflow_dispatch`, behind
  required-reviewer Environments.
- `terraform-aws-eks` still sources `terraform-aws-modules/kms/aws` (`4.0.0`)
  from the registry; the forks do not remove that dependency.
- The wrapper was split out of this repo with `git subtree split`, so its
  history is kept. The upstream forks keep their full history.
- Everything else from ADR-0003 carries over unchanged: the module interface
  (required `kubernetes_version` at latest minus 2, validated `cluster_name`,
  access entries only, `public_access_cidrs` required, settable node group
  version and AMI release), the VPC as a separate concern, ephemeral clusters,
  and S3 + DynamoDB state.
