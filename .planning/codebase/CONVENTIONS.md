# Conventions

**Analysis Date:** 2026-04-07

## Workspace-Level Conventions

- each `*-csha/` directory is its own Git repository
- run Git commands inside the relevant repo
- do not infer shared architecture from workspace colocation alone
- prefer repo-local docs over workspace-level assumptions

## Documentation Conventions

When documenting this workspace:

- classify repo type before describing cross-repo flows
- identify multi-project repos explicitly
- distinguish "directly coupled" from "adjacent"
- distinguish a repo’s primary purpose from optional subsystems inside it

Important example:

- `parloa-k8s-csha/` contains stamp automation, but its primary role is broader Kubernetes GitOps and cluster operations
- the same rule applies elsewhere: one visible subsystem must not define an entire repo

## Repo-Specific Conventions

### `parloa-infra-pre-stamp-csha/`

- generated `*.tm.hcl` files should not be edited directly
- regenerate with:
  - `uv run scripts/generate-terramate-stacks.py`
  - `terramate generate`
  - `terramate fmt`

### `parloa-k8s-csha/`

Observed conventions:

- Argo CD is the preferred deployment path
- repo layout separates infrastructure components, app components, shared components, charts, monitoring, and generated app material
- sync-wave annotations and GitOps ordering matter

Stamp-related convention:

- stamp automation exists under dedicated workflows, copier templates, and `argocd-apps/stamps/`
- the stamp automation spec explicitly isolates generated content from legacy environment folders

Interpretation:

- treat stamp-related changes as one subset of `parloa-k8s-csha/`, not the default lens for the repo
- document stamp onboarding as one subsystem inside the broader GitOps repo

### `stamps-catalog-csha/`

- manifests, schemas, validation, and sync automation should be treated as co-equal parts of the repo
- repo summaries should give inventory, manifest, validation, and sync equal weight

### `crossplane-xrd-csha/`

- staged installation across multiple Helm charts
- DU manifests are the main abstraction
- provider configuration and platform composition are intentionally separated

### `stamps-release-channels-csha/`

- channel content should stay cluster-agnostic
- reusable workflows publish producer content into channels
- observed layout and README may drift, so workflow behavior should be checked directly when documenting paths

### `parloa-infra-csha/`

- many top-level Terraform projects under shared CI and review patterns
- environment naming and plan behavior vary by environment
- repo-level summaries should acknowledge that top-level projects are often more independent than a single README suggests

### `parloa-infra-global-csha/`

- top-level directories are a better guide than the root README for understanding repo scope
- documentation should call out that DNS is only one part of the repo

### `parloa-infra-it-csha/`

- new projects are cloned from `example-app`
- PR automation is part of the normal workflow

### `engineering-catalog-csha/`

- manual source files are distinct from generated outputs
- generated files should not be hand-edited
- repo summaries should include the generation/sync pipeline, not just the editable YAML

### `claudes-kitchen-csha/`, `open-kitchen-csha/`

- plugin ecosystems with marketplace packaging
- docs and packaging differ by target AI tool
- prose plugin counts may drift from marketplace manifests, so manifests are the stronger source when counts matter

## Mapping Guardrails

- inspect top-level directories before inferring repo scope
- use structure to validate README claims
- if a repo contains one specialized subsystem, do not let that subsystem define the repo’s entire identity
- for ecosystem/package repos, check marketplace manifests as well as README prose
- for broad infra repos, assume directory-level heterogeneity unless docs prove uniformity

---

*Convention analysis deepened on 2026-04-07*
