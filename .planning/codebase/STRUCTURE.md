# Codebase Structure

**Analysis Date:** 2026-04-07

## Workspace Shape

The workspace root is a holder for many sibling Git repositories plus local planning files. The siblings should be treated as separate codebases first.

```text
cursor-self-hosted-agent/
├── .cursor/
├── .planning/
├── AGENTS.md
├── README.md
├── crossplane-xrd-csha/
├── engineering-catalog-csha/
├── claudes-kitchen-csha/
├── open-kitchen-csha/
├── parloa-infra-csha/
├── parloa-infra-global-csha/
├── parloa-infra-it-csha/
├── parloa-infra-pre-stamp-csha/
├── parloa-k8s-csha/
├── parloa-terraform-modules-csha/
├── stamps-catalog-csha/
└── stamps-release-channels-csha/
```

## Key Structural Categories

### Stamp Inventory And Provisioning

`stamps-catalog-csha/`
- `stamp-catalog.yaml`
- `stamps/`
- `schemas/`
- `.github/workflows/`
- `docs/`
- `tests/`
- `openspec/`

`parloa-infra-pre-stamp-csha/`
- `config.yaml`
- `stacks/`
- `modules/`
- `scripts/`
- `tests/`
- `docs/`
- `openspec/`

Interpretation:
- these repos are stamp-centric and lifecycle-oriented
- `stamps-catalog-csha/` is one focused system with validation and sync subsystems
- `parloa-infra-pre-stamp-csha/` is one platform with layered lifecycle structure rather than many unrelated projects

### Kubernetes GitOps And Cluster Operations

`parloa-k8s-csha/`

Observed top-level structure:

- `argocd-apps/`
- `infra-components/`
- `parloa-components/`
- `shared-components/`
- `helm/`
- `cron-jobs/`
- `monitoring/`
- `copier-templates/`
- `openspec/`

Observed `argocd-apps/` shape:

- many environment and cluster folders such as `prod-eu`, `prod-us`, `stg-eu`, `stg-us`, `comm-prod-weu`, `control-plane-stg-weu`, `devex-sandbox-gwc`, `test-env`
- one `stamps/` subtree

Interpretation:

- `parloa-k8s-csha/` is a broad operational monorepo for Kubernetes GitOps state
- `stamps/` is a subtree, not the repo’s whole purpose
- the presence of `parloa-components/`, `infra-components/`, `shared-components/`, and `helm/` shows the repo spans platform components and application deployment concerns across many clusters
- current tree shape suggests the legacy/general environment layout is still larger than the newer stamp-automation subtree

Stamp automation placement:

- `copier-templates/stamp-argocd-apps/`
- workflows such as `receive-stamp-from-catalog.yaml` and `sync-stamp-manifests.yml`
- `openspec/specs/stamp-automation/`

Important structural note:

- the stamp automation spec explicitly keeps generated output under `argocd-apps/stamps/{stamp-name}/`
- it explicitly says not to modify existing environment folders like `argocd-apps/prod-eu/` or `argocd-apps/stg-eu/`

That means the structure itself distinguishes:

- legacy or general cluster environment folders
- a newer stamp-automation path

### DU Packaging And Release Distribution

`crossplane-xrd-csha/`
- `charts/`
- `scripts/`
- `du-*.yaml`

`stamps-release-channels-csha/`
- `k8s/`
- release-channel directories
- GitHub workflows

Interpretation:
- `crossplane-xrd-csha/` is one product with several install and composition layers
- `stamps-release-channels-csha/` is a delivery/content repo with reusable workflow plumbing, not just a static directory of channel files

### Broad Infrastructure Repositories

`parloa-infra-csha/`
- many top-level service and platform directories
- shared `modules/`
- `scripts/`
- template and example roots

`parloa-infra-global-csha/`
- many top-level global projects such as `domain`, `azure-policy`, `datadog`, `jfrog`, `rootly`, `terraform-backends`, `wiz`, and several `gcp-*` directories

`parloa-infra-it-csha/`
- `okta/`
- `okta-bootstrap/`
- `okta-org-groups/`
- `okta-policies/`
- `scim-bridge/`
- `jpd-sf-integration/`

Interpretation:
- these are multi-project containers, not single bounded systems
- `parloa-infra-csha/` is a large family of mostly independent product/platform stacks
- `parloa-infra-global-csha/` is a large family of global/shared org stacks
- `parloa-infra-it-csha/` is a smaller family of IT-focused stacks

### Shared Modules, Metadata, And Tooling

`parloa-terraform-modules-csha/`
- many `terraform-*-module/` packages
- release and validation automation

`engineering-catalog-csha/`
- `teams/`
- `overrides/`
- `hibob/`
- generation outputs and scripts
- schemas and CI automation

`claudes-kitchen-csha/`, `open-kitchen-csha/`
- plugin ecosystems under `plugins/`
- marketplace metadata
- gateway/tooling docs and scripts

Interpretation:
- `parloa-terraform-modules-csha/` is a registry/package monorepo rather than a deployable service
- `engineering-catalog-csha/` is one catalog system with generated outputs, not a loose documentation folder
- `claudes-kitchen-csha/` and `open-kitchen-csha/` are ecosystem/package-set repos, not single applications

## Repo-Specific Structural Caveats

`stamps-catalog-csha/`
- Summary caveat: `stamp-catalog.yaml` is only one entry point; manifests, schemas, validation, and sync structure are equally important.

`parloa-infra-pre-stamp-csha/`
- Summary caveat: the layered `stacks/` tree and generator-driven workflow explain the repo better than the module tree alone.

`parloa-k8s-csha/`
- Summary caveat: the `argocd-apps/stamps/` subtree is only one part of a much broader GitOps repo.

`crossplane-xrd-csha/`
- Summary caveat: the four-chart install structure and KCL composition tree are more representative than the root `du-*.yaml` examples.

`stamps-release-channels-csha/`
- Summary caveat: reusable workflows are part of the repo’s actual structure, not just supporting detail.

`parloa-infra-csha/`
- Summary caveat: top-level directories are often closer to separate Terraform projects than to one bounded codebase.

`parloa-infra-global-csha/`
- Summary caveat: the root README understates the repo breadth; the filesystem gives the truer scope.

`parloa-infra-it-csha/`
- Summary caveat: Okta is central, but not the whole repo.

`parloa-terraform-modules-csha/`
- Summary caveat: it behaves like a multi-package registry, not one Terraform project.

`engineering-catalog-csha/`
- Summary caveat: generation and sync machinery are central to the repo identity.

`claudes-kitchen-csha/`, `open-kitchen-csha/`
- Summary caveat: these are plugin ecosystems with packaging, manifests, and gateway tooling, not simple utility repos.

## Practical Reading Rules

- start with repo boundaries
- inspect top-level directories before inferring project boundaries
- do not infer that `parloa-k8s-csha/` is stamp-specific just because it has stamp automation
- distinguish general cluster operations from the stamp onboarding subsystem inside the repo
- read workflows, templates, and specs in addition to README files when a repo appears broader than its top-level prose suggests

---

*Structure analysis deepened on 2026-04-07*
