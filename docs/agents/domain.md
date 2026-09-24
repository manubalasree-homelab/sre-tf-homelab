# Domain Docs

How the engineering skills should consume domain documentation when exploring this repo.

Layout: **single-context, shared across repos**. One glossary covers every repo in the `manubalasree-homelab` workspace; each repo keeps its own decisions in `docs/adr/`.

## Before exploring, read these

- **Shared glossary**: `CONTEXT.md` in `sre-tf-azure-vnet`. From this repo that is `../sre-tf-azure-vnet/CONTEXT.md` (sibling checkout), or <https://github.com/manubalasree-homelab/sre-tf-azure-vnet/blob/main/CONTEXT.md> if it is not checked out. It covers the whole platform. Don't create a per-repo `CONTEXT.md`; new terms go into the shared one (ADR-0002 in `sre-tf-azure-vnet`).
- **`docs/adr/`** in this repo: decisions scoped to this repo. Read ADRs that touch the area you're about to work in.
- When work crosses repo boundaries, also check the sibling repos' `docs/adr/` (e.g. `../sre-tf-azure-aks/docs/adr/`).

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill creates them lazily when terms or decisions actually get resolved.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because…_
