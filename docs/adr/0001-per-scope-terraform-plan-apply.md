---
status: accepted
---

# Duplicate Terraform plan/apply per scaling scope, not one generic parameterized workflow

We first built one generic `terraform-plan.yml`/`terraform-apply.yml`,
parameterized by `working_directory` plus optional `account`/`region`/
`environment`/`service` values, with callers supplying a `strategy.matrix`
per scope. That was less code and kept every scope's logic identical by
construction. We replaced it with three dedicated pairs — `per-account-*`,
`per-region-*`, `per-environment-*` — each a thin flat `workflow_call`
wrapper around a composite action holding that scope's actual logic
(`per-account/jobs/`, `per-region/jobs/`, `per-environment/jobs/`).

## Considered Options

- **One generic, parameterized plan/apply** (what we had): rejected —
  every scope was forced through identical mechanics. Per-account's
  Terraform-workspace selection, for instance, had to be a no-op for
  callers that left `account` empty, rather than each scope's file simply
  doing what's appropriate for it. If one scope ever needs genuinely
  different behavior (not just a different value, but a different
  mechanism — e.g. one account needing a different auth flow, or one
  region needing an extra compliance step), that logic would have to be
  conditional branching inside the shared workflow, entangling unrelated
  scopes together.
- **Per-scope duplication** (chosen): each scope's composite action only
  contains what that scope actually needs — per-account selects a
  Terraform workspace, per-region and per-environment don't; per-
  environment's apply collapses the deployment-environment value and the
  GitHub Environment approval-gate name into one input, since for that
  scope they're naturally the same thing, where per-account/per-region
  keep a separate optional `github_environment` input since their scope
  value has no inherent approval-gate meaning. The cost is real: three
  near-identical copies of the var-file-cascade and backend-config bash
  logic, which can drift if one is fixed and the others aren't.

## Consequences

- GitHub Actions has no equivalent of nested per-scope job files (the
  original model for this used files like `per-account/jobs/
  terraform_apply.yml`): *any* workflow file, reusable or not, must live
  flat under `.github/workflows/`. Composite actions have no such
  restriction, so the actual step logic lives at nested paths
  (`per-account/jobs/terraform-plan/action.yml`, etc.), matching that
  original shape, while a thin flat wrapper workflow exists purely to get
  a real, independently schedulable and gateable job. That wrapper is
  mostly pass-through ceremony (every input repeated), not meaningful
  logic — worth knowing so it isn't mistaken for the "real" implementation
  when debugging.
- Fixing a bug shared across all three (e.g. a Terraform version handling
  issue, or the var-file resolution logic) now means editing three
  composite actions, not one workflow. There is no automated check that
  they stay in sync; drift is a real risk we're deliberately accepting for
  the ability to diverge.
- A fourth scaling scope would mean a fourth composite-action pair plus a
  fourth flat wrapper pair, following the same shape as the three here —
  not a change to shared code.
