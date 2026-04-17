# Codebase Concerns

**Analysis Date:** 2026-04-07

## Highest-Level Risk

The main risk in this workspace is still **misclassification**.

If a reader maps the workspace incorrectly, they will:

- overstate coupling
- search in the wrong repo
- misunderstand rollout boundaries
- confuse adjacent tooling with runtime systems

## Specific Concern: `parloa-k8s-csha` Is Easy To Misread

Why it gets misread:

- the root README contains a dedicated "Stamps Catalog Integration" section
- the repo has stamp automation workflows and Copier templates
- `argocd-apps/` contains a `stamps/` subtree

Why that is incomplete:

- the repo README also says it contains manifest files for all components running in Kubernetes clusters plus Argo CD application files
- top-level directories show much broader scope: `infra-components/`, `parloa-components/`, `shared-components/`, `helm/`, `cron-jobs/`, `monitoring/`
- `argocd-apps/` contains many non-stamp environment folders
- the stamp automation spec isolates generated content under `argocd-apps/stamps/` and explicitly avoids modifying legacy environment folders

Better framing:

- `parloa-k8s-csha/` is a broad GitOps repo with a stamp automation subsystem
- documentation that makes the whole repo "about stamps" is misleading

## Repo Breadth Concerns

Highest-risk examples:

- `parloa-k8s-csha/`
- `parloa-infra-csha/`
- `parloa-infra-global-csha/`
- `parloa-infra-it-csha/`
- `claudes-kitchen-csha/`
- `open-kitchen-csha/`

Reason:

- all of these repos contain more than one obvious operational area
- shallow summaries can easily overfit one visible subsystem

## Repo-Specific Scope Risks

`stamps-catalog-csha/`
- Scope risk: reducing it to a lightweight inventory and missing its full manifest and sync behavior.

`parloa-infra-pre-stamp-csha/`
- Scope risk: reducing it to a Terraform repo and missing its layered Terramate/generator model.

`parloa-k8s-csha/`
- Scope risk: over-reading the stamp automation subsystem and under-reading the broader GitOps monorepo.

`crossplane-xrd-csha/`
- Scope risk: reducing it to XRD/schema output and missing install sequencing, providers, KCL compositions, and DU examples.

`stamps-release-channels-csha/`
- Scope risk: flattening it into static content storage and missing reusable workflows and delivery plumbing.

`parloa-infra-csha/`
- Scope risk: treating it as one coherent platform architecture instead of a family of mostly independent service/platform stacks.

`parloa-infra-global-csha/`
- Scope risk: reading from the DNS-oriented root README and hiding the broader global/shared infrastructure tree.

`parloa-infra-it-csha/`
- Scope risk: reducing it to Okta and overlooking other IT integrations and patterns.

`parloa-terraform-modules-csha/`
- Scope risk: treating it like an environment repo instead of a module registry/package monorepo.

`engineering-catalog-csha/`
- Scope risk: reading it as documentation instead of an actively generated and synced control/data system.

`claudes-kitchen-csha/`, `open-kitchen-csha/`
- Scope risk: treating them as generic tooling repos instead of multi-plugin ecosystems with packaging and gateway infrastructure.

## README Scope Drift

Examples:

- `parloa-infra-global-csha/README.md` under-describes repo breadth
- `parloa-k8s-csha/README.md` is accurate but easy to over-read through the stamp integration section unless the directory layout is checked too
- `stamps-release-channels-csha/README.md` does not fully match observed layout/workflow reality
- `claudes-kitchen-csha` and `open-kitchen-csha` prose counts can drift from marketplace manifests

## Cross-Repo Workflow Concerns

Real cross-repo workflows do exist, especially around:

- `stamps-catalog-csha/`
- `parloa-infra-pre-stamp-csha/`
- stamp automation inside `parloa-k8s-csha/`
- `crossplane-xrd-csha/`
- `stamps-release-channels-csha/`

But concern:

- those workflows should not redefine unrelated repos
- a real integration path does not imply one unified architecture

## Analysis Guardrails

Future mapping should:

- classify repo purpose before following integration edges
- inspect top-level directories in large repos
- treat specialized subsystems as subsystems, not as full-repo identities
- keep claims conservative when repo docs and repo breadth differ
- prefer repo docs plus observed filesystem/workflow evidence over either one alone

---

*Concern analysis deepened on 2026-04-07*
