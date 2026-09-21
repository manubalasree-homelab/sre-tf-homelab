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
  is scope-agnostic. It takes a `working_directory` plus optional
  `account`/`region`/`environment`/`service` values; it has no idea
  whether a given call represents an account, an environment, or a region.
- Each scaling dimension gets its own **caller** workflow instead of its
  own job file: [`demo-per-account.yml`](../.github/workflows/demo-per-account.yml),
  [`demo-per-environment.yml`](../.github/workflows/demo-per-environment.yml),
  [`demo-per-region.yml`](../.github/workflows/demo-per-region.yml). Each
  runs a `strategy.matrix` over its scope's values, calling the same two
  reusable workflows once per value.
- Per-scope **approval gates** (the actual reason the original model kept
  them as separate files) come from `terraform-apply.yml`'s
  `github_environment` input, mapped to a real [GitHub Environment](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment).
  `demo-per-environment.yml` maps its `prod` matrix value to a `prod`
  GitHub Environment configured in this repo with a required reviewer —
  `dev`/`staging` apply straight through, `prod` pauses for approval. This
  is the same mechanism a real per-account or per-region gate would use.
- Per-scope **state isolation** comes from `terraform-plan.yml`/
  `terraform-apply.yml`'s `account` input: when set, it selects (creating
  if needed) a Terraform workspace of that name before planning/applying.
  `demo-per-account.yml` passes its matrix value here, so `acct-a` and
  `acct-b` each get their own workspace.
- Per-scope **variables** come from the cascading var-file convention
  (`var_files_root` + `account`/`region`/`environment`/`service`; see
  [`scaling-demo/vars/`](scaling-demo/vars/) and the catalog README for
  the exact resolution order). `demo-per-account.yml` exercises this too:
  `vars/global.tfvars` applies to both accounts, `vars/acct-a/account.tfvars`
  only exists for `acct-a` — `acct-b`'s plan logs a "not found" warning for
  its missing account file and falls back to the global default, which is
  the intended behavior, not an error.

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
