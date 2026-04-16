# Testing

**Analysis Date:** 2026-04-07

## Testing Posture

Testing and validation are repo-specific across this workspace. There is no single shared testing model.

## Validation Patterns By Repo Group

### Stamp Inventory And Provisioning

`stamps-catalog-csha/`
- schema validation
- manifest reference validation
- Python validation scripts
- GitHub Actions
- testing focus is data correctness and sync safety, not application behavior

`parloa-infra-pre-stamp-csha/`
- generation checks
- Terramate formatting/generation
- plan/apply sequencing by layer
- tests and runbooks for operational validation
- docs and implementation differ in places, so validation should include actual generator inputs, not only README expectations

### Kubernetes GitOps And Cluster Operations

`parloa-k8s-csha/`

Observed or documented validation patterns:

- GitOps review through PRs
- Argo CD reconciliation behavior
- `kubectl apply --dry-run=client`
- Kustomize build verification
- Argo CD diff review

Stamp-specific validation inside the repo:

- `receive-stamp-from-catalog` manual testing
- `sync-stamp-manifests` and Copier-generated output checks

Important correction:

- stamp workflow testing is only one part of `parloa-k8s-csha`
- it should not be treated as the repo’s main validation story
- `parloa-k8s-csha` also needs validation of the broader GitOps tree, not only stamp-generated content

### DU Packaging And Release Distribution

`crossplane-xrd-csha/`
- install and verify runbooks
- provider and CRD health checks
- DU examples and inspection guidance
- testing is heavily integration/operational rather than unit-test centric

`stamps-release-channels-csha/`
- workflow correctness
- downstream consumption validation
- channel-content review rules
- docs and layout drift mean validation should check real workflow outputs, not only README-described paths

### Broad Infrastructure Repositories

`parloa-infra-csha/`
- Terraform plan workflows
- `terraform validate`
- `terraform fmt`
- `tflint`

`parloa-infra-global-csha/`
- workflow-centric Terraform validation per top-level project

`parloa-infra-it-csha/`
- PR-comment Terraform plans
- automated apply after merge
- local validation and plan/apply where permitted

`parloa-terraform-modules-csha/`
- module-level validation expected
- validation should be thought of module-by-module rather than repo-wide

### Metadata And AI Tooling

`engineering-catalog-csha/`
- generation and consistency checks
- manual edits should be tested against generation outputs because many outputs are derived artifacts

`claudes-kitchen-csha/`, `open-kitchen-csha/`
- package or plugin validation
- setup and marketplace-related checks
- validation should account for manifest/prose drift in plugin counts and packaging metadata

## Testing Interpretation

Different repos rely on different confidence signals:

- schema checks
- Terraform plans
- generation correctness
- GitOps reconciliation
- install-time health checks
- package validation

That is why testing claims should be scoped by repo, not generalized across the workspace.

## Deep-Pass Testing Cautions

- if a repo is a multi-project estate, one subtree’s validation pattern does not prove a repo-wide norm
- if a repo is a package ecosystem, marketplace manifests can matter as much as README prose
- if a repo contains a specialized subsystem, its tests do not define the entire repo’s testing posture

---

*Testing analysis deepened on 2026-04-07*
