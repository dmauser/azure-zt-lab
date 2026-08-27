# Azure Deployment Plan

## Status

Validated

## Mode

Modernize an existing Azure networking lab.

## Scope

- Preserve the two teaching scenarios:
  - Scenario 1: static routing over a ZeroTier overlay.
  - Scenario 2: dynamic BGP routing through Azure Route Server and FRR.
- Harden the Bicep modules, VM authentication, network exposure, and explicit
  outbound connectivity.
- Make deployment, ZeroTier authorization, route application, verification,
  and cleanup deterministic and repeatable.
- Add local and pull-request quality gates.
- Refresh the lab documentation and diagrams so they match the implementation.

## Architecture

- Azure hub-and-spoke virtual networks with Linux NVAs.
- Private workload VMs; SSH-key authentication only.
- Public IP addresses limited to the NVAs for controlled administration and
  explicit masqueraded egress.
- Scenario 1 uses Azure UDRs plus persistent guest routes between the Azure and
  on-premises prefixes.
- Scenario 2 uses Azure Route Server and filtered FRR BGP advertisements.
- Existing ZeroTier network membership is authorized through Legacy Central
  API v1 when a token is supplied, with a documented manual fallback.

## Implementation steps

- [x] Correct static and dynamic routing behavior.
- [x] Replace password access with SSH keys and reduce public exposure.
- [x] Harden Bicep types, constraints, APIs, and diagnostics.
- [x] Finish deployment state, input validation, and cleanup automation.
- [x] Add repository validation and GitHub Actions.
- [x] Refresh documentation and diagrams.
- [x] Validate both scenarios locally.
- [x] Validate and deploy each scenario to Azure.
- [x] Run a read-only Azure posture review.
- [x] Remove test resources.

## Deployment context

The active Azure subscription and target location must be confirmed immediately
before live deployment. Live testing creates billable resources, including
Azure Route Server in Scenario 2.

## Validation hand-off

When preparation is complete, update this status to `Ready for Validation` and
run the `azure-validate` workflow before any deployment.

## All validation checks pass

- [x] Bicep compilation for both scenario entry points.
- [x] Resource-group template validation with representative parameters.
- [x] What-if preview for both scenarios.
- [x] Azure CLI authentication and selected subscription verification.
- [x] Bicep linting and repository quality workflow.
- [x] Assigned Azure Policy review.
- [x] Regional compute and network quota review.
- [x] Static RBAC role-assignment review.

## Role Assignment Verification

- Status: Verified
- Identities checked: No managed identities are declared by either scenario.
- Roles confirmed: No role assignments are required for VM, network, or Route
  Server provisioning in these templates.
- Issues: None.

## Section 7: Validation Proof

- Validated at: `2026-03-24T15:13:36Z`.
- Azure context: authenticated to `DMAUSER-FDPO`; Central US selected at the
  user's direction.
- `bash scripts/validate.sh`: passed Bash syntax, ShellCheck, Bicep lint/build,
  Markdown-link, Mermaid-render, and whitespace checks. Local cloud-init schema
  validation was unavailable; both cloud-config files remain covered by the CI
  job that installs `cloud-init`.
- `az bicep build` and `az bicep lint`: passed for both scenario entry points
  and all reusable modules.
- `az deployment group validate`: passed for Scenario 1 and Scenario 2 with the
  actual SSH key, source CIDR, VM SKU, region, and base64 cloud-init inputs.
- `az deployment group what-if --result-format ResourceIdOnly`: passed;
  Scenario 1 reported 28 creates and Scenario 2 reported 33 creates, with no
  modifications or deletions.
- `az quota list` / `az quota usage list`: Central US has 97 of 100 regional
  vCPUs available and 100 DSv2-family vCPUs available; the largest scenario
  requires six.
- `az network list-usages`: 10 Standard IPv4 public addresses are available;
  Scenario 2 requires three.
- `az vm list-skus`: `Standard_DS1_v2` is available in Central US without
  restrictions.
- `az provider show`: Compute and Network providers are registered, and Azure
  Route Server is available in Central US.
- `az policy assignment list`: reviewed; assignments scoped to unrelated
  resource groups do not affect these tests, and subscription-level Defender
  assignments do not deny the planned resources.

## Live validation proof

- Validated on `2026-08-27` in the user-selected `DMAUSER-FDPO` subscription
  and Central US.
- Scenario 1: verified the private ZeroTier overlay, persistent guest routes,
  effective UDRs, explicit NVA egress, and bidirectional ICMP/HTTP among the
  on-premises, hub, and spoke workloads.
- Scenario 2: verified both Route Server sessions plus the overlay BGP session,
  filtered advertisements, learned `192.168.100.0/24` routes on all Azure
  workload NICs, and bidirectional ICMP/HTTP among all workloads.
- Live testing identified and corrected Route Server output timing, FRR
  next-hop resolution, on-premises aggregate routing, forwarded Internet NSG
  access, guest-agent-safe ZeroTier installation, and deployment ordering.
- Azure Quick Review completed for both scenarios with no critical findings.
  Availability zones, VM scale sets, premium disks, backup, monitoring, and
  disaster recovery remain intentional production-grade exceptions for this
  short-lived, low-cost training lab. IP forwarding is enabled only on the two
  NVAs in each scenario.
