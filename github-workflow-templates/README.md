# GitHub workflow templates

Catalog of the reusable GitHub Actions workflows this repo provides for the
`sre-tf-*` homelab repos. GitHub requires a *callable* reusable workflow
(`on: workflow_call`) to physically live under `.github/workflows/` in its
source repo — it can't be called from an arbitrary path — so the runnable
YAML for each template below lives there, not in this directory. This file
is the index; treat it as the entry point when looking for what's available.

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

## Terraform: lint, validate, plan, apply

Four workflows for a Terraform CI/CD pipeline, modeled on a common
lint → validate → plan → apply pipeline shape. Where that model usually
has separate plan/apply copies per account, environment, and region, here
there's just one `terraform-plan.yml` / `terraform-apply.yml`, parameterized
by `working_directory` — the calling repo runs a matrix over its own
accounts/environments/regions instead of this repo maintaining N near-
identical copies. Per-scope approval gates (the actual reason those used to
need separate files) are expressed via `terraform-apply.yml`'s `environment`
input, mapped to a [GitHub Environment](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
with its own required reviewers.

All four share
[`../actions/terraform-setup`](../actions/terraform-setup/action.yml), a
composite action (checkout + install Terraform CLI) — composite actions,
unlike reusable workflows, aren't restricted to `.github/workflows/`, so it
lives here as the shared step sequence.

**`terraform-lint.yml`** and **`terraform-validate.yml`** need no cloud
credentials — `terraform fmt`, `terraform validate`, and `terraform test`
(run automatically if `*.tftest.hcl` files exist) are all static/local
checks. Consume both from a module repo like `sre-tf-azure-vnet`:

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

**`terraform-plan.yml`** and **`terraform-apply.yml`** authenticate to
Azure via OIDC (`ARM_USE_OIDC=true` + the ambient GitHub Actions ID token —
no client secret, but the caller must grant `permissions: id-token: write`
and pass `azure_client_id`/`azure_tenant_id`/`azure_subscription_id`, all
optional — leave them out for a root config that doesn't use the `azurerm`
provider). They only make sense for a Terraform *root* config with a real
backend — not a reusable module repo like `vnet`/`aks`, which have no state
of their own. Nothing in this org uses them for real yet (there's no
root-config repo, and no Azure federated credential set up for CI); see
[`../demos/`](../demos/README.md) for a working proof of the pattern using
a credential-free root config.

Beyond the basics (`working_directory`, `terraform_version`,
`plan_artifact_name`), both support scoping a multi-account/environment/
region setup:

- **`account`**: if set, selects (creating if needed) a Terraform
  workspace of this name before planning/applying — pass the *same* value
  to both calls for a given scope, so apply runs against the same
  workspace the plan was made in.
- **`backend_config`**: newline-separated `key=value` pairs, each passed
  as `terraform init -backend-config=...` — lets one backend definition
  serve multiple scopes (e.g. a different state `key` per
  account/environment/region). Must also match between the plan and apply
  calls for the same scope.
- **`var_files_root`** (plan only) + **`region`**/**`environment`**/
  **`service`**: a cascading var-file convention, each applied only if the
  file exists (a missing one just logs a warning, not a failure):
  `<root>/global.tfvars` → `<root>/<account>/account.tfvars` →
  `<root>/<account>/<region>/region.tfvars` →
  `<root>/<account>/<region>/<environment>/env.tfvars` →
  `<root>/<account>/<region>/<environment>/<service>.tfvars`. Later files
  override earlier ones.
- **`tfvars_json`** (plan only): an ad-hoc JSON override, applied *after*
  the cascade — highest precedence, wins over everything above. The saved
  plan file carries all of this into apply, so apply doesn't need any of
  it repeated except `account`/`backend_config`.

```yaml
# .github/workflows/deploy.yml (example — not yet used by any repo)
name: Deploy

on:
  push:
    branches: [main]

jobs:
  plan:
    strategy:
      matrix:
        environment: [dev, staging, prod]
    uses: manubalasree-homelab/sre-tf-homelab/.github/workflows/terraform-plan.yml@main
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
    strategy:
      matrix:
        environment: [dev, staging, prod]
    uses: manubalasree-homelab/sre-tf-homelab/.github/workflows/terraform-apply.yml@main
    with:
      working_directory: environments/${{ matrix.environment }}
      plan_artifact_name: tfplan-${{ matrix.environment }}
      # github_environment (not "environment" -- that's terraform-plan's
      # deployment-scope input, a different thing) is the GitHub
      # Environment name for the approval gate.
      github_environment: ${{ matrix.environment }}
      azure_client_id: ${{ vars.AZURE_CLIENT_ID }}
      azure_tenant_id: ${{ vars.AZURE_TENANT_ID }}
      azure_subscription_id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
```

For a working, runnable proof of the account/environment/region matrix
pattern above — including the `environment`-gate mechanism, using a
credential-free `local`-provider root config so it actually runs today —
see [`../demos/`](../demos/README.md).
