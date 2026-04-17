# Architecture

**Analysis Date:** 2026-04-07

## Executive Summary

This workspace is a **portfolio of repositories**, not a single architecture.

The main lesson from the deeper pass is that almost every repo has an easy **misread**:

- `parloa-k8s-csha/` can be over-read through its stamp automation subsystem
- `parloa-infra-global-csha/` can be under-read through its DNS-focused root README
- `stamps-release-channels-csha/` can be flattened into static content instead of workflow-backed distribution
- `parloa-terraform-modules-csha/` can be mistaken for an environment repo instead of a module registry
- `engineering-catalog-csha/` can be read as docs instead of a generated/synced system
- `claudes-kitchen-csha/` and `open-kitchen-csha/` can be treated as generic tooling folders instead of plugin ecosystems

The best model is:

1. stamp inventory and provisioning
2. Kubernetes GitOps and cluster operations
3. DU packaging and release distribution
4. broad infrastructure estates
5. metadata and AI tooling ecosystems

## Portfolio Categories

### Stamp Inventory And Provisioning

`stamps-catalog-csha/`
- Primary purpose: central stamp inventory plus full per-stamp manifests, validation, and downstream sync.
- Scope caveat: the repo includes both inventory and infra-shaped stamp definitions, not only lightweight catalog metadata.
- Architecture shape: one product with subsystems for schema validation, sync, docs, and OpenSpec.

`parloa-infra-pre-stamp-csha/`
- Primary purpose: layered OpenTofu/Terramate provisioning for Azure and AKS pre-stamp infrastructure.
- Scope caveat: the generator-driven and layered lifecycle model is as important as the module tree.
- Architecture shape: one platform with explicit layers, code generation, runbooks, and GitOps handoff.

### Kubernetes GitOps And Cluster Operations

`parloa-k8s-csha/`
- Primary purpose: the broad Kubernetes GitOps monorepo for cluster infrastructure, application delivery, Argo CD applications, charts, cron jobs, and monitoring.
- Scope caveat: stamp automation is one subsystem inside the repo, not the lens that best explains the whole tree.
- Architecture shape: one repo with multiple operational subsystems:
  - `argocd-apps/` for many environments and clusters
  - `infra-components/` for shared cluster add-ons
  - `parloa-components/` for application deployment units
  - `shared-components/`, `helm/`, `cron-jobs/`, `monitoring/`
  - `copier-templates/` and `openspec/specs/stamp-automation/` for a specific stamp onboarding subsystem
- Key interpretation: stamp automation is important, but it is only one lane inside a larger GitOps repo.

### DU Packaging And Release Distribution

`crossplane-xrd-csha/`
- Primary purpose: package and install the Crossplane-based DU platform through four staged charts plus KCL compositions and DU examples.
- Scope caveat: install sequencing, provider wiring, and composition logic are core parts of the repo shape.
- Architecture shape: one platform repo with install, provider, provider-config, and platform-composition layers.

`stamps-release-channels-csha/`
- Primary purpose: GitHub-backed release-channel distribution for shared Kubernetes/DU artifacts.
- Scope caveat: reusable workflows and delivery plumbing are part of the repo’s real function.
- Architecture shape: one delivery repo with channel content, reusable workflows, and adjacent tag-handling behavior.

### Broad Infrastructure Estates

`parloa-infra-csha/`
- Primary purpose: main product/runtime Terraform monorepo for many services and shared platform concerns.
- Scope caveat: top-level directories often behave more like parallel Terraform projects than one bounded system.
- Architecture shape: many mostly independent top-level Terraform projects under shared conventions.

`parloa-infra-global-csha/`
- Primary purpose: org-wide/shared Terraform estate for DNS, policies, backends, GCP layers, observability, registry, and vendor/security integrations.
- Scope caveat: the root README is much narrower than the actual repo contents.
- Architecture shape: many global projects under one repo family.

`parloa-infra-it-csha/`
- Primary purpose: IT-owned Terraform for Okta, SCIM bridge, and related integrations.
- Scope caveat: it is a smaller family of Terraform projects rather than one single-purpose app repo.
- Architecture shape: smaller multi-project Terraform monorepo.

`parloa-terraform-modules-csha/`
- Primary purpose: private Terraform module registry consumed by other Terraform repos.
- Scope caveat: it is best understood as a multi-package registry/release repo.
- Architecture shape: multi-package module monorepo with release automation.

### Metadata And AI Tooling Ecosystems

`engineering-catalog-csha/`
- Primary purpose: source-of-truth ownership/team/resource catalog that generates artifacts for downstream tools.
- Scope caveat: generated outputs and sync workflows are central to how the repo works.
- Architecture shape: one catalog system with ingest, validation, generation, and sync stages.

`claudes-kitchen-csha/`
- Primary purpose: Claude-focused plugin marketplace and gateway/tooling ecosystem.
- Scope caveat: the repo is a plugin ecosystem/package set, not a runtime service tree.
- Architecture shape: many installable plugin packages under one marketplace repo.

`open-kitchen-csha/`
- Primary purpose: tool-agnostic plugin ecosystem with packaging for Cursor, Claude Code, and other agent tools.
- Scope caveat: it overlaps strongly with `claudes-kitchen-csha`, but the relationship is manual porting rather than shared runtime coupling.
- Architecture shape: ecosystem/package set with multiple plugin families and generation scripts.

## Relationship Strength

### Strong And Operational

- `stamps-catalog-csha/` -> `parloa-infra-pre-stamp-csha/`
- `stamps-catalog-csha/` -> stamp automation inside `parloa-k8s-csha/`
- `parloa-infra-pre-stamp-csha/` -> `parloa-k8s-csha/`
- `crossplane-xrd-csha/` <-> `stamps-release-channels-csha/`
- `stamps-release-channels-csha/` -> `parloa-k8s-csha/`
- `parloa-terraform-modules-csha/` -> Terraform consumers such as `parloa-infra-csha/`
- `parloa-infra-global-csha/` -> `parloa-infra-it-csha/` via backend and permission conventions

### Related But Not One System

- `parloa-infra-csha/`
- `parloa-infra-global-csha/`
- `parloa-infra-it-csha/`
- `parloa-terraform-modules-csha/`

### Adjacent And Independent

- `engineering-catalog-csha/`
- `claudes-kitchen-csha/`
- `open-kitchen-csha/`

## Important Drift And Uncertainty

- `parloa-k8s-csha`: OpenSpec still partly reflects older manifest-source assumptions while README/workflows show live catalog integration.
- `parloa-infra-pre-stamp-csha`: docs still mention `stamps.yaml` in places while implementation uses `stamps/*.yaml`.
- `parloa-infra-global-csha`: root README is much narrower than the actual repo.
- `stamps-release-channels-csha`: README layout descriptions and actual workflow/layout behavior do not fully match.
- `claudes-kitchen-csha` and `open-kitchen-csha`: plugin/tool counts differ between prose docs and marketplace manifests.

## Common Mapping Mistakes

- treating the workspace as one system
- treating `parloa-k8s-csha/` as primarily a stamp repo
- treating `parloa-infra-global-csha/` as only DNS
- treating `stamps-release-channels-csha/` as static storage instead of delivery infrastructure
- treating `parloa-terraform-modules-csha/` as a stack repo
- placing AI tooling repos inside the runtime architecture

---

*Architecture analysis deepened on 2026-04-07*
