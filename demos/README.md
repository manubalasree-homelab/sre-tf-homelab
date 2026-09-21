# Scaling demo: per-account / per-environment / per-region

A working demonstration of scaling the Terraform plan/apply reusable
workflows across multiple accounts, environments, and regions — one real,
runnable pipeline per dimension, rather than just a description.

## Why this isn't literally `per-account/jobs/terraform_apply.yml`

The original model for this (a GitLab-style layout) has real, independently
schedulable job files nested arbitrarily deep, e.g.
`per-account/jobs/terraform_apply.yml`. GitHub Actions doesn't support
that: **any** workflow file — reusable or not — is only ever discovered by
GitHub if it lives flat under `.github/workflows/`. There's no per-scope
subfolder of job definitions to point at.

So the split by scope happens a different way here:

- The actual engine — [`terraform-plan.yml`](../.github/workflows/terraform-plan.yml)
  and [`terraform-apply.yml`](../.github/workflows/terraform-apply.yml) —
  is scope-agnostic. It takes a `working_directory` and a `tfvars_json`
  blob; it has no idea whether it's being called for an account, an
  environment, or a region.
- Each scaling dimension gets its own **caller** workflow instead of its
  own job file: [`demo-per-account.yml`](../.github/workflows/demo-per-account.yml),
  [`demo-per-environment.yml`](../.github/workflows/demo-per-environment.yml),
  [`demo-per-region.yml`](../.github/workflows/demo-per-region.yml). Each
  runs a `strategy.matrix` over its scope's values, calling the same two
  reusable workflows once per value.
- Per-scope **approval gates** (the actual reason the original model kept
  them as separate files) come from `terraform-apply.yml`'s `environment`
  input, mapped to a real [GitHub Environment](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment).
  `demo-per-environment.yml` maps its `prod` matrix value to a `prod`
  GitHub Environment configured in this repo with a required reviewer —
  `dev`/`staging` apply straight through, `prod` pauses for approval. This
  is the same mechanism a real per-account or per-region gate would use.

## The demo config: `scaling-demo/`

A minimal Terraform root using only the `local` provider — no cloud
credentials, no backend setup, nothing external. It declares `account`,
`environment`, and `region` variables (all defaulting to `"shared"`) and
writes a marker file recording whatever scope it was given. This is what
lets the whole matrix actually run and be verified in CI today, instead of
being scaffolding that only makes sense once real Azure credentials and a
real root config exist (unlike `terraform-plan.yml`/`terraform-apply.yml`
used for real infrastructure, which do need those).

## Running a demo

Each is `workflow_dispatch`-triggered (not on push) so it doesn't run
automatically:

```
gh workflow run "Demo: per-account deploy" -R manubalasree-homelab/sre-tf-homelab
gh workflow run "Demo: per-environment deploy" -R manubalasree-homelab/sre-tf-homelab
gh workflow run "Demo: per-region deploy" -R manubalasree-homelab/sre-tf-homelab
```
