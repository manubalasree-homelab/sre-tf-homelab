---
status: accepted
---

# Upstream Terraform modules are mirrored into this repo as root-level folders

`aws/sre-tf-eks` sources `terraform-aws-eks` and `terraform-aws-eks-pod-identity`
by relative path from unmodified copies (Mirrors) at the repo root, named like
their upstream repos, instead of from the Terraform Registry. Each Mirror is
added and updated with `git subtree ... --squash` at an exact upstream tag,
and `mirrors.conf` records its directory, upstream URL, pinned major version
and current tag. A scheduled workflow (`mirror-sync.yml`) opens a PR when a
newer tag exists within the pinned major. The point is a ready place to patch
later without forking; nothing is patched today. Separate repos per upstream
module would be cleaner, but for a homelab one repo is less to manage.

## Considered Options

- **Keep the registry source** (ADR-0003's original choice): simplest, but no
  place to patch, and the `version` range moves silently within a major.
- **A fork per upstream module**: keeps upstream history and can send patches
  back, at the cost of one repo per module.
- **Mirrors in this repo** (chosen).

## Consequences

- Supersedes ADR-0003's clause that the community module is pinned by a
  literal registry `version`. The rest of ADR-0003 stands.
- Mirrors are convention-only unmodified: no CI compares them with upstream.
  If one is ever patched, keep the patch as its own commit on top of the
  subtree so `subtree pull` still merges.
- Mirrors are excluded from formatting and lint; the wrapper's `terraform
  validate` is what proves they resolve.
- This does **not** remove the registry dependency: `terraform-aws-eks`
  itself sources `terraform-aws-modules/kms/aws` (pinned `4.0.0`) from the
  registry. Mirroring kms would need a one-line patch to the eks Mirror, which
  we declined so the Mirror stays unmodified.
- The repo now holds third-party code (roughly 2 MB for eks, mostly examples
  and tests) alongside tooling. Module versions are the repo's semver tag plus
  whatever tag each Mirror sits at.
