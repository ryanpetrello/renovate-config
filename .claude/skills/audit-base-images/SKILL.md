---
name: audit-base-images
description: Audit GitHub repos for AIPCC base image Renovate compliance. Checks if repos using AIPCC base images extend the shared //base-images preset from opendatahub-io/renovate-config.
tools: [Bash, Read]
user-invocable: true
---

# AIPCC Base Image Renovate Compliance Audit

Check whether GitHub repositories consuming AIPCC base images are using the
shared `//base-images` Renovate preset from `opendatahub-io/renovate-config`.

## When to use

- User asks to audit a repo or org for base image Renovate compliance
- User asks which repos are not using Renovate for AIPCC base images
- User asks to check if a repo's base image pins are managed by Renovate

## Prerequisites

- `gh` (GitHub CLI) must be authenticated
- `jq` must be installed

## How it works

The audit checks three things for a given repo:

1. **Does the repo reference AIPCC base images in buildable files?**
   Searches for `quay.io/aipcc/base-images/*` and
   `registry.redhat.io/rhai{,-early-access}/base-image-*` in Dockerfiles,
   Containerfiles, and build-args configs. Documentation files are excluded.

2. **Does the repo have a Renovate config that extends the shared preset?**
   Looks for `renovate.json`, `renovate.json5`, `.renovaterc`, or
   `.github/renovate.json{,5}` and checks whether it contains
   `opendatahub-io/renovate-config//base-images` in its extends chain.

3. **Which specific files have pinned base image references?**
   Reports each file and line number with a clickable GitHub URL.

A repo is **compliant** if it either has no AIPCC base image references in
buildable files, or it extends the `//base-images` preset.

## Instructions

### Single repo audit

Run the audit script against the target repo:

```bash
bash .claude/skills/audit-base-images/audit.sh <owner/repo>
```

Report the result to the user. If the repo fails, show the pinned files and
explain that the repo should add `//base-images` to its Renovate config per:
https://github.com/opendatahub-io/renovate-config/blob/main/README.md

### Org-wide audit

To discover non-compliant repos across an entire GitHub organization:

```bash
bash .claude/skills/audit-base-images/audit.sh --org <ORG>
```

Replace `<ORG>` with the target organization (e.g., `opendatahub-io`).

The `--org` mode performs only 2 GitHub code search API calls (one per
query pattern) to discover all files across the org, then audits each
repo using the pre-fetched paths. Per-repo audits skip the search API
entirely and only use the contents API for file fetching and Renovate
config checks.

Present the results grouped by status: non-compliant repos first with their
pinned files, then compliant repos, then skipped repos (docs-only references).

### JSON output

For machine-readable output, pass `--json` as the second argument:

```bash
bash .claude/skills/audit-base-images/audit.sh <owner/repo> --json
```
