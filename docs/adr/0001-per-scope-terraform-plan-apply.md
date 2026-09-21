---
status: accepted
---

# Duplicate Terraform plan/apply per scaling scope, not one generic parameterized workflow

We first built one generic `terraform-plan.yml`/`terraform-apply.yml`,
parameterized by `working_directory` plus optional `account`/`region`/
`environment`/`service` values, with callers supplying a `strategy.matrix`
per scope. That was less code and kept every scope's logic identical by
construction. We replaced it with three dedicated pairs of composite
actions — `per-account/jobs/`, `per-region/jobs/`, `per-environment/jobs/`
— each holding that scope's actual logic, called directly as a step in
whichever job the consuming repo defines. We initially put a thin flat
`workflow_call` wrapper workflow in front of each (to grant
`permissions:`/`environment:`, which only a job can set), then removed all
six: since a composite action's steps run inside whichever job calls it,
the consuming repo's own job can grant those directly, and the wrapper
added nothing but repeated input pass-through.

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
  Terraform workspace, per-region and per-environment don't. For
  approval gates, per-environment's calling job sets its own
  `environment:` to the deployment-environment value directly (they're
  naturally the same thing for that scope); per-account/per-region's
  calling job sets `environment:` to whatever it wants independently,
  since account/region values have no inherent approval-gate meaning. The
  cost is real: three near-identical copies of the var-file-cascade and
  backend-config bash logic, which can drift if one is fixed and the
  others aren't.

## Consequences

- GitHub Actions has no equivalent of nested per-scope job files (the
  original model for this used files like `per-account/jobs/
  terraform_apply.yml`): *any* `workflow_call` reusable workflow must live
  flat under `.github/workflows/`. Composite actions have no such
  restriction, so the actual logic lives at nested paths matching that
  original shape (`per-account/jobs/terraform-plan/action.yml`, etc.) —
  called directly as a step in the consuming repo's own job, which grants
  whatever `permissions:`/`environment:` that job needs itself. There is
  no wrapper reusable workflow in front of these at all; a composite
  action's steps run inside whichever job calls it, so nothing job-level
  needs to be proxied.
- Fixing a bug shared across all three (e.g. a Terraform version handling
  issue, or the var-file resolution logic) now means editing three
  composite actions, not one workflow. There is no automated check that
  they stay in sync; drift is a real risk we're deliberately accepting for
  the ability to diverge.
- A fourth scaling scope would mean a fourth composite-action pair,
  following the same shape as the three here — not a change to shared
  code.
