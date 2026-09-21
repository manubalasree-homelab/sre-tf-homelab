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
