---
status: accepted
---

# How the AWS EKS setup fits together

This is the map over ADR-0002 and ADR-0006: what exists, where it lives, and
what is still to build. It records shape, not new decisions, and it goes
stale as items get built; update it then.

## The layers

```
terraform-aws-eks (fork, public)             1:1 with upstream, tag v21.26.0
terraform-aws-eks-pod-identity (fork, public) 1:1 with upstream, tag v2.9.0
        |  sourced by git URL + tag
sre-tf-eks (repo, public)                    thin wrapper, own semver (v0.1.0)
        |  sourced by git URL + tag
sre-tf-homelab/tf-eks (this repo)            root config: S3 backend, aws provider
        |  deployed by
sre-tf-homelab/.github/workflows/tf-eks-deploy.yml + per-account-aws/jobs/
        |  GitHub OIDC -> IAM role, per Environment
AWS account                                   EKS cluster
homelab-tf-account-vars (private)             tfvars, cloned in the workflow
sre-gitops-bootstrap                          installs in-cluster software via ArgoCD (Hub)
```

- **Wrapper contents.** EKS control plane, Spot managed node groups (node
  group `kubernetes_version` and `ami_release_version` are settable), access
  entries only, a public API endpoint limited to `public_access_cidrs`, and
  EKS-native addons only. `kubernetes_version` is required (latest minus 2).
  The wrapper takes `vpc_id` and `subnet_ids`; the VPC is a separate concern.
- **Cluster name** is a finished input matching `<provider>-<env>-<region>-<nn>`
  (for example `aws-lab-us-east-1-01`), validated by the module.

## How it runs

- **Auth.** Each job runs in an Environment (`aws-plan`, `aws-apply`,
  `aws-destroy`), each with its own `AWS_ROLE_ARN`. Repo variables:
  `AWS_REGION`, `TF_STATE_BUCKET`, `TF_LOCK_TABLE`. Secret:
  `ACCOUNT_VARS_TOKEN`, for cloning the private var-files repo.
- **One-time bootstrap by hand per AWS account:** the OIDC provider, the IAM
  roles, the S3 state bucket and the DynamoDB lock table.
- **State** is S3 with DynamoDB locking, one Terraform workspace per account.
- **Lifecycle** is ephemeral and manual. `tf-eks-deploy.yml` is
  `workflow_dispatch` only, with plan, apply and destroy behind Environments;
  apply and destroy need a reviewer. There is no scheduled destroy.
- **In-cluster software** is ArgoCD's job. The cluster is a Hub rendering the
  same `sre-helm` charts; each recreate means re-applying the Root by hand.

## Done and not done

Built and validated locally or in CI: the wrapper (`sre-tf-eks` CI green,
`v0.1.0` tagged), the root config (`terraform validate` against the tagged
wrapper), the two forks.

Not built or not run: any `plan` or `apply`; `tf-eks-deploy.yml` on GitHub;
the AWS bootstrap (OIDC provider, roles, bucket, table); the GitHub
Environments, variables and secret; an AWS directory in
`homelab-tf-account-vars`; the VPC; the `aws` Provider values layer in
`sre-gitops-bootstrap`.

## Known caveats

- `terraform-aws-eks` still pulls `terraform-aws-modules/kms/aws` from the
  registry.
- This repo is public, so plan output is public (ADR-0006).
- Latest minus 2 may fall into EKS extended support, which costs several
  times more per control-plane hour; check the EKS version calendar.
