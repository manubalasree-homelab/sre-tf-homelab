# Scaling demo: per-account / per-environment / per-region

A working demonstration of scaling the Terraform plan/apply reusable
workflows across multiple accounts, environments, and regions — one real,
runnable pipeline per dimension, rather than just a description.

## How this maps to `per-account/jobs/terraform_apply.yml`

The original model for this (a GitLab-style layout) has real,
independently schedulable job files nested arbitrarily deep, e.g.
`per-account/jobs/terraform_apply.yml`. GitHub Actions doesn't allow a
*callable* workflow to live anywhere but flat under `.github/workflows/`,
so that exact shape isn't possible for the schedulable part — but composite
actions have no such restriction, so the actual per-scope logic does live
at those nested paths: [`../per-account/jobs/`](../per-account/jobs/),
[`../per-region/jobs/`](../per-region/jobs/),
[`../per-environment/jobs/`](../per-environment/jobs/). A thin flat
`workflow_call` wrapper per scope+action
(`per-account-plan.yml`/`per-account-apply.yml`, etc., in
`.github/workflows/`) exists only to get a real, independently
schedulable and gateable job — see
[ADR-0001](../docs/adr/0001-per-scope-terraform-plan-apply.md) for the full
reasoning, including what this trades away (three copies of similar bash
logic, one per scope) for what it buys (each scope's logic — workspace
selection, approval-gate semantics — reflects what that scope actually
needs, not a lowest-common-denominator generic path).

- Each scaling dimension gets its own **caller** demo workflow:
  [`demo-per-account.yml`](../.github/workflows/demo-per-account.yml),
  [`demo-per-environment.yml`](../.github/workflows/demo-per-environment.yml),
  [`demo-per-region.yml`](../.github/workflows/demo-per-region.yml). Each
  runs a `strategy.matrix` over its scope's values, calling that scope's
  dedicated plan/apply wrapper pair once per value.
- Per-scope **approval gates**: `per-environment-apply.yml`'s `environment`
  input doubles as the GitHub Environment gate name directly (for this
  scope, the deployment environment *is* the natural gate). `demo-per-
  environment.yml` passes `prod`, which maps to a real `prod` GitHub
  Environment configured in this repo with a required reviewer — `dev`/
  `staging` apply straight through, `prod` pauses for approval.
  `per-account-apply.yml`/`per-region-apply.yml` instead take an optional,
  separate `github_environment` input, since account/region values have no
  inherent approval-gate meaning of their own.
- Per-scope **state isolation** comes from `per-account-plan.yml`/
  `per-account-apply.yml`'s `account` input: it selects (creating if
  needed) a Terraform workspace of that name before planning/applying.
  `demo-per-account.yml` passes its matrix value here, so `acct-a` and
  `acct-b` each get their own workspace. Per-region and per-environment
  don't do this — only account maps to a workspace in this design.
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
real root config exist (unlike the per-scope plan/apply actions used for
real infrastructure, which do need those).

## Running a demo

Each is `workflow_dispatch`-triggered (not on push) so it doesn't run
automatically:

```
gh workflow run "Demo: per-account deploy" -R manubalasree-homelab/sre-tf-homelab
gh workflow run "Demo: per-environment deploy" -R manubalasree-homelab/sre-tf-homelab
gh workflow run "Demo: per-region deploy" -R manubalasree-homelab/sre-tf-homelab
```
