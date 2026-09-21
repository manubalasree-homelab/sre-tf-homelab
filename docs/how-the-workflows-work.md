# How the GitHub Actions in this repo work

A conceptual walkthrough of this repo's design, for anyone (or any future
session) trying to understand it from scratch. For the input/output
reference of each workflow, see
[`../github-workflow-templates/README.md`](../github-workflow-templates/README.md)
instead — this document explains the mechanics and the rules, not the
per-file API.

## 1. Two sharing mechanisms, two different rules

GitHub Actions has exactly two ways to share logic across repos, and they
work completely differently. Confusing them is where most of the bugs in
this repo's history came from.

| | **Reusable workflow** | **Composite action** |
|---|---|---|
| Trigger | `on: workflow_call` | `runs: using: composite` |
| Called from | a **job**, via `uses:` | a **step**, via `uses:` |
| Runs as | its own independent job (own runner, own log group) | steps inlined into the *caller's* job |
| File location | **must** be under `.github/workflows/` | anywhere in the repo |
| File name | your choice | **must** be `action.yml` or `action.yaml` |
| Can set `permissions:`/`environment:` | yes (it's a job) | no (it's not a job — whoever's job it runs inside must set these) |

Everything in this repo is one or the other. Once you know which, you know
where to look for it and how it can be called.

```
=== reusable workflows (on: workflow_call) ===
.github/workflows/terraform-lint.yml
.github/workflows/commit-lint.yml
.github/workflows/semantic-version.yml
.github/workflows/terraform-validate.yml

=== composite actions (runs: using: composite) ===
per-account/jobs/terraform-plan/action.yml
per-account/jobs/terraform-apply/action.yml
per-environment/jobs/terraform-plan/action.yml
per-environment/jobs/terraform-apply/action.yml
per-region/jobs/terraform-plan/action.yml
per-region/jobs/terraform-apply/action.yml
actions/terraform-setup/action.yml
```

That split is exactly the file-location rule: the four reusable workflows
are all flat in `.github/workflows/`; the seven composite actions are
scattered at whatever path makes sense (`actions/`, `per-account/jobs/`,
etc.) because that restriction doesn't apply to them.

## 2. The four reusable workflows

Each is standalone — one job, does one thing, nothing depends on another.

`semantic-version.yml` teaches the full anatomy of a reusable workflow:

- **`on.workflow_call.inputs`** — its public interface. Each has a
  `default`, so a caller can omit anything.
- **`on.workflow_call.outputs`** — how a reusable workflow hands data
  *back* to its caller. `value: ${{ jobs.tag.outputs.version }}` pulls
  from the job's own `outputs:`, which in turn pulls from the step's
  `outputs.version` (three layers: step → job → workflow).
- **Top-level `permissions: contents: write`** — this is what the workflow
  *asks for*, not what it *gets*. That distinction is the single most
  important rule in this whole repo:

  > **A reusable workflow can never end up with more permission than its
  > caller's job explicitly grants it.** If the caller's job doesn't say
  > `permissions: contents: write`, this workflow's `git push` fails — not
  > with a helpful "permission denied," but with the run failing at
  > *startup*, before any job even appears in the log. Zero jobs, no error
  > message you can grep for.

  That's why every consumer's caller job explicitly re-declares it:

  ```yaml
  jobs:
    release:
      permissions:
        contents: write            # <-- without this, the run never produces a single job
      uses: manubalasree-homelab/sre-tf-homelab/.github/workflows/semantic-version.yml@main
  ```

`commit-lint.yml` is simpler — no inputs, no outputs, no elevated
permissions needed (it only reads history, never writes):

```yaml
on:
  workflow_call: {}

jobs:
  commitlint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0        # needs full history to walk back through commits
      - uses: wagoid/commitlint-github-action@v6.2.1
```

It does its *own* checkout rather than using `terraform-setup` — it's not
Terraform-related, and it needs `fetch-depth: 0` (full history)
specifically, which `terraform-setup` deliberately does *not* do (see
below). Two different consumers, two different checkout needs.

`terraform-lint.yml` and `terraform-validate.yml` are the two simplest
files in the repo — both just call `actions/terraform-setup` then run one
or two `terraform` commands.

## 3. The composite actions — where the real Terraform logic lives

Composite actions look different from the outside (`runs: using:
composite` instead of `on: workflow_call`), and — critically — they're
consumed differently too: as a **step**, not a job.

`actions/terraform-setup/action.yml`:

```yaml
runs:
  using: composite
  steps:
    - uses: actions/checkout@v4

    - uses: hashicorp/setup-terraform@v4.0.1
      with:
        terraform_version: ${{ inputs.terraform_version }}
        terraform_wrapper: ${{ inputs.terraform_wrapper }}
```

Two things to notice:

1. `runs.using.steps` is a plain list of steps — that's the whole idea of
   a composite action: a named, reusable bundle of steps, injected
   wherever it's called.
2. No `runs-on:`, no `permissions:` — a composite action doesn't have its
   own runner or its own job. It executes *inside whatever job called it*,
   inheriting that job's runner, its filesystem, its environment
   variables, its granted permissions. This is exactly why this repo has
   no wrapper reusable workflows in front of the plan/apply actions: there
   was never anything job-level a wrapper could provide that the
   *consuming* job couldn't provide itself.

Here's `terraform-lint.yml` calling it as a step:

```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: manubalasree-homelab/sre-tf-homelab/actions/terraform-setup@main   # <- a step, not a job
        with:
          terraform_version: ${{ inputs.terraform_version }}
      - run: terraform fmt -check -recursive -diff
```

The more complex composite actions —
`per-account/jobs/terraform-plan/action.yml`, and its siblings for
`per-region`/`per-environment` — do the exact same thing, calling
`terraform-setup` as their *first* step. So a real consumer's call is a
chain three levels deep: **consumer's job → `per-account/jobs/
terraform-plan` (composite) → `actions/terraform-setup` (composite)**. All
three execute as steps inside the *same* job — there's still only one job,
just built out of nested, reusable step-bundles.

The rest of `terraform-plan`'s steps do the actual work — set Azure OIDC
env vars, `terraform init` with optional `-backend-config` flags, select a
Terraform workspace named after `account`, then `terraform plan` with the
var-file cascade, then upload the plan as an artifact. Key mechanics
worth knowing:

- **`shell: bash` is mandatory on every `run:` step inside a composite
  action.** A normal job step gets a default shell from the runner; a
  composite action step doesn't — omit it and the action fails validation
  entirely.
- **`$GITHUB_ENV`** is how a composite action step passes environment
  variables *forward* to later steps in the same job. There's no `env:`
  block at the top of a composite action the way there is for a job —
  each step that needs to hand something to later steps writes to
  `$GITHUB_ENV` explicitly.
- **The var-file cascade** builds up `-var-file=` flags in ascending
  precedence — global, then account, then region, then environment, then
  service — skipping (with a warning, not a failure) any file that
  doesn't exist. It writes the ad-hoc `tfvars_json` override to
  `ci-overrides.tfvars.json` and appends it *last*, because Terraform's
  own rule is "later `-var-file` flags win" — that's the entire mechanism
  behind "ad-hoc override always wins."

The `terraform-apply` action mirrors this but downloads the plan artifact
instead of computing one, and re-does `terraform init`/`workspace select`
with the *same* `account`/`backend_config` values — it has to reconstruct
identical state-addressing before `terraform apply tfplan` will agree to
replay that saved plan.

## 4. How a consumer would actually call this today

Since there's no wrapper, a repo that wants to plan/apply per-account
writes its *own* job — it owns `permissions:`/`environment:` directly, and
just calls the composite action as one step in it:

```yaml
# a hypothetical consumer's own .github/workflows/deploy.yml
jobs:
  plan:
    runs-on: ubuntu-latest
    permissions:
      id-token: write      # <- this job owns this now; no wrapper grants it for you
      contents: read
    steps:
      - uses: manubalasree-homelab/sre-tf-homelab/per-account/jobs/terraform-plan@main
        with:
          working_directory: .
          account: acct-a
          azure_client_id: ${{ vars.AZURE_CLIENT_ID }}
          azure_tenant_id: ${{ vars.AZURE_TENANT_ID }}
          azure_subscription_id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
```

Trace what happens on that one `uses:` line: GitHub fetches
`per-account/jobs/terraform-plan/action.yml` from `sre-tf-homelab@main`,
inlines its steps into *this* job. Its first step calls
`actions/terraform-setup@main` — another fetch, another inlining, one
level deeper. All of it runs as steps of the single `plan` job above;
there's only ever one runner, one log group per step, one set of
permissions — the ones declared right there on `plan`.

### Or: skip writing that job at all

If all you need is "plan, then apply, in order" with nothing custom in
between, `per-account-deploy.yml` (and its `per-region`/`per-environment`
siblings) does the above for you — it's a real reusable workflow (not a
composite action) with two internal jobs, `plan` and `apply: needs: plan`,
each calling the matching composite action. Since it's a genuine
`workflow_call` file with its own job, *it* grants `permissions: id-token:
write` and sets `environment:` internally — your caller job needs neither:

```yaml
jobs:
  deploy:
    uses: manubalasree-homelab/sre-tf-homelab/.github/workflows/per-account-deploy.yml@main
    with:
      working_directory: .
      account: acct-a
      azure_client_id: ${{ vars.AZURE_CLIENT_ID }}
      azure_tenant_id: ${{ vars.AZURE_TENANT_ID }}
      azure_subscription_id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
```

The trade-off: this fixed two-job shape can't fit a manual review step, an
Infracost comment, or anything else between plan and apply. Reach for the
composite action directly (as above) the moment you need that; reach for
`-deploy.yml` when you don't.

## 5. The permissions/environment rule, restated for composite actions

This is the thing that has caused the most confusing failures in this
repo's history, so it's worth stating as a single rule to check any file
against:

> **Ask "what job does this code actually execute inside?" first.** For a
> composite action, that's always the *caller's* job — so
> `permissions:`/`environment:` go on the caller's job, never inside the
> `action.yml`. For a reusable workflow, it has its *own* job — but that
> job's permission ceiling is still set by whatever the calling job
> explicitly grants via `permissions:` next to its `uses:` line.

Every "zero jobs, no useful error" failure this repo has hit was this rule
violated somewhere: a reusable workflow's own job asking for more than its
caller granted, or a *required* `workflow_call` input silently missing
from the caller's `with:` block, which fails validation before any job is
even created.

## 6. Quick reference

| Symptom | Likely cause |
|---|---|
| Run completes instantly, zero jobs, no error in the API | A required `workflow_call` input wasn't passed in `with:`, or the caller's job didn't grant a permission the workflow declares |
| `actionlint`/IDE says "Invalid input, X is not defined" | You renamed an input in the workflow/action but didn't update every caller |
| Composite action step fails immediately | Missing `shell: bash` on a `run:` step |
| A step can't see a variable another step set | Composite action steps need `$GITHUB_ENV`, not a shared `env:` block |
| Cross-repo call fails only when both repos are private | Private→private reusable workflow calls need GitHub Team/Enterprise; composite actions don't have this restriction at all |

That's the whole system: four flat reusable workflows for independent,
single-purpose jobs (`release`, `commit-lint`, `terraform-lint`,
`terraform-validate`), three more flat reusable workflows that bundle
plan+apply orchestration per scope (`per-account-deploy`,
`per-region-deploy`, `per-environment-deploy`), and seven composite
actions — one shared foundation (`terraform-setup`) plus three
scope-specific plan/apply pairs — that consuming repos assemble into their
own jobs directly, or reach for the bundled `-deploy.yml` workflows when
they don't need anything custom in between.
