# Integrations

**Analysis Date:** 2026-04-07

## Scope

Integrations must be described per repo group. The workspace does not expose one unified integration surface.

## Direct Cross-Repo Relationships

### Stamp Inventory And Provisioning

`stamps-catalog-csha/` -> `parloa-infra-pre-stamp-csha/`
- stamp definitions sync into pre-stamp provisioning inputs
- schemas, manifests, and sync automation all live in the catalog repo rather than in pre-stamp

`stamps-catalog-csha/` -> `parloa-k8s-csha/`
- stamp events feed the stamp automation subsystem inside `parloa-k8s-csha/`
- integration caveat: this edge explains one subsystem inside `parloa-k8s-csha/`, not the repo’s full purpose

`parloa-infra-pre-stamp-csha/` -> `parloa-k8s-csha/`
- pre-stamp bring-up workflows create or update Argo material in the k8s repo during stamp onboarding
- integration caveat: this edge is strongest during stamp bring-up, not as a full description of the k8s repo

### DU Packaging And Release Distribution

`crossplane-xrd-csha/` -> `stamps-release-channels-csha/`
- release workflows publish channel content
- integration caveat: this is a concrete producer -> channel relationship, not merely topical overlap

`stamps-release-channels-csha/` -> `parloa-k8s-csha/`
- connector or consumption path for release-channel artifacts into cluster GitOps flows
- integration caveat: repo docs and observed channel usage suggest the channel repo is part of delivery plumbing as well as content storage

### Shared Dependencies

`parloa-terraform-modules-csha/` -> Terraform/OpenTofu repos
- shared module registry for multiple IaC repos
- strongest concrete consumer visible in this workspace is `parloa-infra-csha/`

`parloa-infra-global-csha/` -> `parloa-infra-it-csha/`
- IT repo references global backend configuration for permission and backend behavior

`claudes-kitchen-csha/` <-> `open-kitchen-csha/`
- relationship is manual ecosystem porting and overlap in plugin families, not runtime coupling

## External Platforms By Repo Group

### `parloa-k8s-csha/`

Primary external platforms:

- Kubernetes
- Argo CD
- Helm chart sources
- GitHub
- Azure as cluster/cloud context
- Slack notifications referenced in Argo conventions

Important nuance:

- stamp automation is one integration path
- the repo also independently manages general cluster infrastructure and app delivery concerns across many environment folders
- cluster GitOps is the core integration surface; stamp automation is a specialized ingestion path into that surface

### Stamp Inventory And Provisioning Repos

Relevant repos:

- `stamps-catalog-csha/`
- `parloa-infra-pre-stamp-csha/`

Primary external platforms:

- GitHub Actions
- Azure
- AKS
- Python-based validation and generation tooling

### DU And Release Repos

Relevant repos:

- `crossplane-xrd-csha/`
- `stamps-release-channels-csha/`

Primary external platforms:

- Crossplane
- Helm
- Kubernetes
- GitHub Actions

### Broad Infrastructure Repositories

Relevant repos:

- `parloa-infra-csha/`
- `parloa-infra-global-csha/`
- `parloa-infra-it-csha/`
- `parloa-terraform-modules-csha/`

Primary external platforms vary by subproject:

- Azure
- GCP
- Cloudflare
- Datadog
- Rootly
- JFrog
- Okta
- other provider or SaaS integrations depending on the directory

Important nuance:

- `parloa-infra-csha/` and `parloa-infra-global-csha/` should be treated as repo families whose integrations are often directory-specific
- `parloa-infra-global-csha/README.md` under-describes this breadth, so its integrations are easiest to undercount

### Metadata And AI Tooling

`engineering-catalog-csha/`
- HiBob
- GitHub
- Datadog
- Rootly

`claudes-kitchen-csha/`
- Claude Code marketplace
- MCP backends such as Jira, Notion, Miro, GitHub, Datadog, Rootly, Slack, Gong, Google Workspace, Salesforce

`open-kitchen-csha/`
- Cursor marketplace
- Claude Code marketplace
- MCP and packaging for multiple AI coding tools

Important nuance:

- the kitchen repos relate strongly to each other as ecosystems, but they do not show the same kind of runtime dependency edges seen in the infra/delivery repos

## Integration Strength Classification

### Strong And Operational

- `stamps-catalog-csha` <-> `parloa-infra-pre-stamp-csha`
- `stamps-catalog-csha` <-> stamp automation inside `parloa-k8s-csha`
- `parloa-infra-pre-stamp-csha` <-> `parloa-k8s-csha`
- `crossplane-xrd-csha` <-> `stamps-release-channels-csha`
- `stamps-release-channels-csha` <-> `parloa-k8s-csha`
- `parloa-terraform-modules-csha` -> `parloa-infra-csha` and other Terraform consumers
- `parloa-infra-global-csha` -> `parloa-infra-it-csha` via backend and permission plumbing

### Related But Broader Than One Workflow

- `parloa-k8s-csha` with the rest of the platform
- `parloa-infra-csha`
- `parloa-infra-global-csha`
- `parloa-infra-it-csha`
- `parloa-terraform-modules-csha`

### Adjacent Tooling

- `engineering-catalog-csha`
- `claudes-kitchen-csha`
- `open-kitchen-csha`

## Common Mistakes

- over-reading `parloa-k8s-csha` through the stamp automation flow
- letting one integration edge stand in for a repo’s whole purpose
- assuming `parloa-infra-global-csha`’s README captures all of its real integration edges
- flattening `stamps-release-channels-csha` into pure content and missing its workflow-backed distribution role
- reading `claudes-kitchen-csha` and `open-kitchen-csha` as runtime/platform integrations rather than developer-tool integrations
- projecting one repo group’s integrations onto the whole workspace

---

*Integration analysis deepened on 2026-04-07*
