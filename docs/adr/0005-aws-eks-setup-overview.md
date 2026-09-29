---
status: accepted
---

# How the AWS EKS setup fits together

This is the map over ADR-0002, 0003 and 0004: what exists in this repo, what
lives elsewhere, and what is still to build. It records the shape, not new
decisions; each decision's reasoning lives in its own ADR.

## The layers

```
homelab-tf-account-vars   tfvars, cascade global > account > region > env > service
sre-tf-aws-eks (planned)  root config: backend, provider, calls the wrapper
        |
sre-tf-homelab (this repo)
  aws/sre-tf-eks              thin wrapper module (ADR-0003)
  terraform-aws-eks           Mirror of upstream v21.26.0 (ADR-0004)
  terraform-aws-eks-pod-identity  Mirror of upstream v2.9.0 (ADR-0004)
  per-account-aws/jobs/       plan / apply / destroy composite actions (ADR-0002)
  mirrors.conf + mirror-sync.yml  weekly upstream sync PRs (ADR-0004)
  aws-module-ci.yml           fmt, tflint, validate on PRs (paths: aws/, mirrors)
        |
sre-gitops-bootstrap      installs everything in-cluster via ArgoCD (Hub)
```

- **Module vs root config.** The wrapper is a reusable module with no backend
  or provider. Root configs live in other repos, source it as
  `git::...//aws/sre-tf-eks?ref=refs/tags/<tag>`, and read their tfvars from
  `homelab-tf-account-vars`. "Account" means the cloud-provider account, so the
  existing var-file cascade is reused unchanged.
- **Wrapper contents.** The EKS control plane, Spot managed node groups
  (node group `kubernetes_version` and `ami_release_version` are settable for
  upgrade practice), access entries only, a public API endpoint restricted to
  `public_access_cidrs`, and EKS-native addons only (`vpc-cni`, `coredns`,
  `kube-proxy`, `eks-pod-identity-agent`, `aws-ebs-csi-driver` via Pod
  Identity). `kubernetes_version` is required and is chosen at latest minus 2.
  The VPC is a separate repo's concern; the wrapper takes `vpc_id` and
  `subnet_ids`.
- **Cluster name** is a finished input matching `<provider>-<env>-<region>-<nn>`
  (for example `aws-lab-us-east-1-01`), validated by the module.

## How it runs

- **Auth.** GitHub OIDC assumes an IAM role. `AWS_ROLE_ARN` and `AWS_REGION`
  are GitHub variables passed to the AWS composite actions as inputs.
- **One-time bootstrap by hand per AWS account:** the OIDC provider, the CI
  role, the S3 state bucket and the DynamoDB lock table. Terraform cannot
  create the role it runs as. Humans get cluster admin through
  `admin_principal_arns` (an IAM user you create), not through CI.
- **State** is S3 with DynamoDB locking, one Terraform workspace per account.
- **Lifecycle** is ephemeral. Apply and destroy are manual, and destroy sits
  behind a required-reviewer GitHub Environment. An AWS Budgets alert is the
  cost backstop; there is no scheduled auto-destroy.
- **In-cluster software** is not Terraform's job. The cluster is a Hub with
  its own ArgoCD, rendering the same `sre-helm` charts through app-of-apps.
  Each recreate means re-applying the Root by hand.

## Done and not done

Done and checked locally: the wrapper module (`init`, `validate`, `fmt`,
`tflint`), both Mirrors, consuming the wrapper by git URL with `../../` paths
resolving, and the three AWS actions (YAML parses).

Not built, not run: any `plan` or `apply`; the `mirror-sync` and
`aws-module-ci` workflows on GitHub; the root-config repo `sre-tf-aws-eks`;
AWS entries in `homelab-tf-account-vars`; the VPC repo; the bootstrap wizard
for the role, bucket and table; the `aws` Provider values layer and S3 change
in `sre-gitops-bootstrap` (its ROADMAP item 8); a `per-account-aws-deploy.yml`
bundling plan and apply.

## Known caveats

- `terraform-aws-eks` sources `terraform-aws-modules/kms/aws` (`4.0.0`) from
  the registry, so the registry is still a dependency (ADR-0004).
- PRs opened by `mirror-sync` use the default token and so do not trigger CI
  until it is swapped for a PAT or GitHub App token.
- The module version consumers pin is this repo's repo-wide tag, not a
  per-module one.
- N-2 may fall into EKS extended support, which costs several times more per
  control-plane hour; check the EKS version calendar before choosing.
