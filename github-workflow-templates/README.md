# GitHub workflow templates

Catalog of the reusable GitHub Actions workflows this repo provides for the
`sre-tf-*` homelab repos. GitHub requires a *callable* reusable workflow
(`on: workflow_call`) to physically live under `.github/workflows/` in its
source repo — it can't be called from an arbitrary path — so the runnable
YAML for each template below lives there, not in this directory. This file
is the index; treat it as the entry point when looking for what's available.
For how it all actually works mechanically (reusable workflows vs.
composite actions, the permissions rule, common failure modes), see
[`../docs/how-the-workflows-work.md`](../docs/how-the-workflows-work.md).

## semantic-version

[`../.github/workflows/semantic-version.yml`](../.github/workflows/semantic-version.yml)

Computes the next semver tag from commit messages since the last tag (using
[`paulhatch/semantic-version`](https://github.com/paulhatch/semantic-version):
`!:`/`BREAKING CHANGE:` → major, `feat:` → minor, anything else → patch) and
pushes that tag if the version changed.

Consume it from another repo in this org. The calling job must explicitly
grant `contents: write` — this workflow pushes a tag, and a reusable
workflow can't be granted more permission than its caller job has. Most
repos default their workflow token to read-only, so omitting this fails
the run at startup with no job ever created:

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    branches: [main]

jobs:
  release:
    permissions:
      contents: write
    uses: manubalasree-homelab/sre-tf-homelab/.github/workflows/semantic-version.yml@main
```

## commit-lint

[`../.github/workflows/commit-lint.yml`](../.github/workflows/commit-lint.yml)

Enforces Conventional Commits on the commits in a push or pull request,
using [`wagoid/commitlint-github-action`](https://github.com/wagoid/commitlint-github-action).
No config file is shipped here — the action falls back to
`@commitlint/config-conventional` automatically when it doesn't find one in
the caller's repo, and that ruleset's types (`feat`, `fix`, `chore`, etc.)
and `!`/`BREAKING CHANGE:` footer are exactly what `semantic-version`'s
default patterns look for. Keeping commits conventional is what makes that
workflow's major/minor/patch classification reliable instead of defaulting
everything to a patch bump.

No extra permissions needed — it only reads commit history:

```yaml
# .github/workflows/commit-lint.yml
name: Commit lint

on:
  pull_request:

jobs:
  lint:
    uses: manubalasree-homelab/sre-tf-homelab/.github/workflows/commit-lint.yml@main
```

## Terraform: lint, validate

Two workflows, needing no cloud credentials — `terraform fmt`, `terraform
validate`, and `terraform test` (run automatically if `*.tftest.hcl` files
exist) are all static/local checks. Consume both from a module repo like
`sre-tf-azure-vnet`:

```yaml
# .github/workflows/validate.yml
name: Validate

on:
  push:
    branches: [main]
  pull_request:

jobs:
  lint:
    uses: manubalasree-homelab/sre-tf-homelab/.github/workflows/terraform-lint.yml@main
  validate:
    uses: manubalasree-homelab/sre-tf-homelab/.github/workflows/terraform-validate.yml@main
```

Both share
[`../actions/terraform-setup`](../actions/terraform-setup/action.yml), a
composite action (checkout + install Terraform CLI) — composite actions,
unlike reusable workflows, aren't restricted to `.github/workflows/`, so it
lives here as the shared step sequence.

## Terraform: plan/apply, per scaling scope

Deliberately duplicated **per scope** rather than one generic
`terraform-plan.yml`/`terraform-apply.yml` — see
[ADR-0001](../docs/adr/0001-per-scope-terraform-plan-apply.md) for why. Three
scopes, each with its own plan+apply pair:

| Scope | Plan action | Apply action | Distinctive behavior |
|---|---|---|---|
| Account (Azure subscription) | [`per-account/jobs/terraform-plan`](../per-account/jobs/terraform-plan/action.yml) | [`per-account/jobs/terraform-apply`](../per-account/jobs/terraform-apply/action.yml) | Selects/creates a Terraform workspace named after `account` |
| Region | [`per-region/jobs/terraform-plan`](../per-region/jobs/terraform-plan/action.yml) | [`per-region/jobs/terraform-apply`](../per-region/jobs/terraform-apply/action.yml) | No workspace switching — regions share the account's workspace |
| Environment (dev/staging/prod) | [`per-environment/jobs/terraform-plan`](../per-environment/jobs/terraform-plan/action.yml) | [`per-environment/jobs/terraform-apply`](../per-environment/jobs/terraform-apply/action.yml) | The calling job's own `environment:` is set to the deployment environment directly — no separate gate input |

Each pair lives as a composite action, called directly as a step in the
*consuming* repo's own job — [`../per-account/jobs/`](../per-account/jobs/),
[`../per-region/jobs/`](../per-region/jobs/),
[`../per-environment/jobs/`](../per-environment/jobs/). Composite actions
can live at any path, so these mirror the original per-scope folder shape
this was modeled on directly, with no wrapper reusable workflow in
between. There's no `workflow_call` file for these at all: since a
composite action's steps run *inside* whichever job calls it, that job is
just an ordinary job in the consuming repo's own workflow, and it sets its
own `permissions:`/`environment:` directly — there's nothing a wrapper
workflow would add.

All three plan actions authenticate to Azure via OIDC (`ARM_USE_OIDC=true`
+ the ambient GitHub Actions ID token — no client secret, but the calling
job must grant `permissions: id-token: write` itself) and pass
`azure_client_id`/`azure_tenant_id`/`azure_subscription_id`, all optional
— leave them out for a root config that doesn't use the `azurerm`
provider. They only make sense for a Terraform *root* config with a real
backend — not a reusable module repo like `vnet`/`aks`. Nothing in this org
uses them for real yet — there's no root-config repo, and no Azure
federated credential set up for CI.

Shared, generic inputs across all three plan actions:

- **`backend_config`**: newline-separated `key=value` pairs, each passed
  as `terraform init -backend-config=...`. Must also match between the
  plan and apply calls for the same scope.
- **`var_files_root`** (plan only) + **`account`**/**`region`**/
  **`environment`**/**`service`**: a cascading var-file convention, each
  applied only if the file exists (a missing one just logs a warning, not
  a failure): `<root>/global.tfvars` → `<root>/<account>/account.tfvars` →
  `<root>/<account>/<region>/region.tfvars` →
  `<root>/<account>/<region>/<environment>/env.tfvars` →
  `<root>/<account>/<region>/<environment>/<service>.tfvars`. Later files
  override earlier ones. See
  [`homelab-tf-account-vars`](https://github.com/manubalasree-homelab/homelab-tf-account-vars)
  for the real instance of this convention.
- **`tfvars_json`** (plan only): an ad-hoc JSON override, applied *after*
  the cascade — highest precedence, wins over everything above. The saved
  plan file carries all of this into apply, so apply doesn't need any of
  it repeated except the scope-selecting input (`account` for per-account)
  and `backend_config`.

```yaml
# .github/workflows/deploy.yml (example -- not yet used by any repo)
name: Deploy

on:
  push:
    branches: [main]

jobs:
  plan:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    strategy:
      matrix:
        environment: [dev, staging, prod]
    steps:
      - uses: manubalasree-homelab/sre-tf-homelab/per-environment/jobs/terraform-plan@main
        with:
          working_directory: environments/${{ matrix.environment }}
          plan_artifact_name: tfplan-${{ matrix.environment }}
          var_files_root: tf-vars
          environment: ${{ matrix.environment }}
          azure_client_id: ${{ vars.AZURE_CLIENT_ID }}
          azure_tenant_id: ${{ vars.AZURE_TENANT_ID }}
          azure_subscription_id: ${{ vars.AZURE_SUBSCRIPTION_ID }}

  apply:
    needs: plan
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    # The job's own environment: gate -- for per-environment, the deployment
    # environment IS the gate name directly. Configure a GitHub Environment
    # per value (with required reviewers where wanted) to make this a real gate.
    environment: ${{ matrix.environment }}
    strategy:
      matrix:
        environment: [dev, staging, prod]
    steps:
      - uses: manubalasree-homelab/sre-tf-homelab/per-environment/jobs/terraform-apply@main
        with:
          working_directory: environments/${{ matrix.environment }}
          plan_artifact_name: tfplan-${{ matrix.environment }}
          azure_client_id: ${{ vars.AZURE_CLIENT_ID }}
          azure_tenant_id: ${{ vars.AZURE_TENANT_ID }}
          azure_subscription_id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
```

## Terraform: deploy (plan + apply combined), per scaling scope

For the common case — just plan, then apply, in order, nothing custom in
between — writing out both jobs with `needs:` every time is pure
repetition. `per-account-deploy.yml`, `per-region-deploy.yml`, and
`per-environment-deploy.yml` bundle that orchestration into one reusable
workflow per scope, each internally calling the matching pair of composite
actions above. Unlike the composite actions, these *are* real
`workflow_call` reusable workflows (flat under `.github/workflows/`, as
required) — worth being one, since sequencing `plan` → `apply` via
`needs:` is real orchestration value, not just pass-through ceremony the
way the now-removed generic wrappers were.

This sits **alongside** the composite actions, not in place of them: reach
for `per-account/jobs/terraform-plan|apply` directly when you need
something between plan and apply (a manual review step, an Infracost
comment, a Slack notification) that a fixed two-job workflow can't express;
reach for `per-account-deploy.yml` when you don't.

A nice side effect of bundling: since plan and apply now live in the same
workflow run, there's no `plan_artifact_name` to keep in sync between two
separate calls — it's fixed internally.

```yaml
# .github/workflows/deploy.yml (example -- not yet used by any repo)
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    strategy:
      matrix:
        environment: [dev, staging, prod]
    uses: manubalasree-homelab/sre-tf-homelab/.github/workflows/per-environment-deploy.yml@main
    with:
      working_directory: environments/${{ matrix.environment }}
      var_files_root: tf-vars
      environment: ${{ matrix.environment }}
      azure_client_id: ${{ vars.AZURE_CLIENT_ID }}
      azure_tenant_id: ${{ vars.AZURE_TENANT_ID }}
      azure_subscription_id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
```

Note this caller job needs no `permissions:` of its own — unlike the
composite-action example above, `per-environment-deploy.yml` is a reusable
workflow with its own job, so it grants `id-token: write` on its own
`plan`/`apply` jobs internally. The caller only needs
`permissions: id-token: write` if calling a plan/apply *composite action*
directly, not when calling one of these `-deploy.yml` workflows.
