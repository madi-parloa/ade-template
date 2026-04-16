# Technology Stack

**Analysis Date:** 2026-04-07

## Reading The Stack Correctly

There is no single workspace-wide runtime stack. Different repo groups use different stacks.

Most important correction:

- `parloa-k8s-csha/` should be read as a broad Kubernetes GitOps repo
- not as a stamp-focused repo

## Repo Group Stack Profiles

### Stamp Inventory And Provisioning

Repositories:

- `stamps-catalog-csha/`
- `parloa-infra-pre-stamp-csha/`

Main technologies:

- YAML manifests
- JSON Schema
- Python validation and generation scripts
- OpenTofu / Terraform
- Terramate
- GitHub Actions
- Azure CLI and cloud provisioning tools

Important nuance:

- `stamps-catalog-csha/` is a manifest/schema/automation stack, not just "YAML"
- `parloa-infra-pre-stamp-csha/` is a Terramate-generation platform, not just raw Terraform

### Kubernetes GitOps And Cluster Operations

Repository:

- `parloa-k8s-csha/`

Main technologies:

- Kubernetes manifests
- Argo CD
- Helm
- Kustomize
- YAML
- Copier templates
- GitHub Actions
- `kubectl`

Notes:

- stamp automation uses the same repo and toolchain
- it is an add-on workflow inside this broader GitOps stack
- `parloa-k8s-csha/` also has a large hand-curated GitOps surface for environments, components, and charts that is not generated from stamp inputs

### DU Packaging And Release Distribution

Repositories:

- `crossplane-xrd-csha/`
- `stamps-release-channels-csha/`

Main technologies:

- Helm
- Crossplane
- KCL
- Kubernetes APIs
- YAML release artifacts
- GitHub Actions

Important nuance:

- `crossplane-xrd-csha/` has a richer platform-install stack than an XRD-only label suggests
- `stamps-release-channels-csha/` is partly workflow infrastructure, not only artifact storage

### Broad Infrastructure Repositories

Repositories:

- `parloa-infra-csha/`
- `parloa-infra-global-csha/`
- `parloa-infra-it-csha/`
- `parloa-terraform-modules-csha/`

Main technologies:

- Terraform
- Azure
- GCP in parts of `parloa-infra-csha/` and `parloa-infra-global-csha/`
- Cloudflare in parts of `parloa-infra-csha/`
- GitHub Actions
- TFLint and Terraform validation

Important nuance:

- `parloa-infra-csha/` and `parloa-infra-global-csha/` are not single stacks; different top-level directories may use different providers and tooling mixes
- `parloa-terraform-modules-csha/` should be thought of as a module packaging/release stack

### Metadata And AI Tooling

Repositories:

- `engineering-catalog-csha/`
- `claudes-kitchen-csha/`
- `open-kitchen-csha/`

Main technologies:

- TypeScript / Node.js
- YAML
- Markdown skill definitions
- marketplace/plugin manifests
- Rust for MCP gateway components
- shell and Python setup or validation scripts

Important nuance:

- `engineering-catalog-csha/` is a generation/sync stack, not only a YAML data repo
- `claudes-kitchen-csha/` and `open-kitchen-csha/` are packaging ecosystems, not just markdown skill repositories

## Cloud And Platform Targets

Azure is strongest in:

- `parloa-infra-pre-stamp-csha/`
- `parloa-infra-csha/`
- `parloa-infra-global-csha/`
- `parloa-infra-it-csha/`
- `parloa-terraform-modules-csha/`
- `crossplane-xrd-csha/`

Kubernetes is strongest in:

- `parloa-k8s-csha/`
- `crossplane-xrd-csha/`
- `stamps-release-channels-csha/`
- stamp-related inputs from `stamps-catalog-csha/`

AI-tool platform packaging is strongest in:

- `claudes-kitchen-csha/`
- `open-kitchen-csha/`

## Repo-Level Notes

`stamps-catalog-csha/`
- YAML, JSON Schema, Python, GitHub Actions

`parloa-infra-pre-stamp-csha/`
- OpenTofu, Terramate, Python, Azure

`parloa-k8s-csha/`
- Kubernetes YAML, Argo CD, Helm, Kustomize, Copier
- plus a wide environment/component layout that makes it a GitOps operations repo rather than a narrow generator repo

`crossplane-xrd-csha/`
- Helm, Crossplane, KCL, shell

`stamps-release-channels-csha/`
- YAML content and GitHub Actions

`parloa-infra-csha/`
- Terraform, Azure, GCP, Cloudflare

`parloa-infra-global-csha/`
- Terraform, Azure, GCP, shared org infra

`parloa-infra-it-csha/`
- Terraform, Azure, Okta-focused IT stacks

`parloa-terraform-modules-csha/`
- Terraform module packaging
- git-tagged multi-module release model

`engineering-catalog-csha/`
- TypeScript, YAML, generation workflows
- downstream artifact generation and sync

`claudes-kitchen-csha/`, `open-kitchen-csha/`
- plugin ecosystems, marketplace packaging, gateway tooling
- multi-manifest packaging with some doc/count drift between prose and marketplace files

## Stack Summary

Accurate short version:

- stamp inventory/provisioning repos
- one broad Kubernetes GitOps repo
- DU packaging and release distribution repos
- several Terraform estates
- one module registry
- metadata and AI-tooling repos

---

*Stack analysis deepened on 2026-04-07*
