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

Consume it from another repo in this org:

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    branches: [main]

jobs:
  release:
    uses: manubalasree-homelab/sre-tf-homelab/.github/workflows/semantic-version.yml@main
```
