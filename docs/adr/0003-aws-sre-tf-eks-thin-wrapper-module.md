---
status: superseded by ADR-0006
---

# `aws/sre-tf-eks` is a thin wrapper module; root configs live in other repos

`aws/sre-tf-eks` is a reusable Terraform module (no backend, no provider
config) wrapping `terraform-aws-modules/eks/aws` and exposing only what we
vary. Root configs (e.g. `sre-tf-aws-eks`) live in separate repos, source it
via `git::...//aws/sre-tf-eks?ref=refs/tags/<tag>`, and read tfvars from
`homelab-tf-account-vars`. This repo stays tooling plus reusable modules;
it never holds a root config.

## Consequences

- The community module's `version` must be a literal — Terraform does not
  allow a variable there. Bumping it means a new wrapper release, and root
  configs pick it up by moving their `?ref=`. What *is* a variable: the
  worker node group's `kubernetes_version` and `ami_release_version`, so
  nodes can lag the control plane for upgrade practice.
- `kubernetes_version` is required with no default, and is chosen at latest
  EKS minus two. Check that this is still in EKS standard support;
  extended support costs several times more per control-plane hour.
- The module takes `vpc_id`/`subnet_ids` as plain inputs (the VPC is a
  separate repo) and a finished, validated `cluster_name`.
- Cluster access is EKS access entries only (`admin_principal_arns`); no
  `aws-auth`, no creator-admin. The public API endpoint requires an explicit
  `public_access_cidrs`.
- Versioning uses this repo's repo-wide semver tag, so unrelated tooling
  changes also bump the module version.
- CI here is path-filtered to `aws/**` and runs `terraform fmt`, `validate`
  and lint only; real plans happen in the root-config repo.
