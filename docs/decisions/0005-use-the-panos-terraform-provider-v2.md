---
title: "Use the panos Terraform Provider v2 (XML-API) as the Apply Path"
description: "Drive Panorama from Terraform with the official PaloAltoNetworks/panos v2 provider over the XML-API (set + multi-config)."
type: adr
category: architecture
tags: [terraform, panos, xml-api, provider, gitops]
status: accepted
created: 2026-06-25
updated: 2026-06-25
author: "Thomas Sprock"
project: flux
related: [0001-target-the-panorama-xml-api.md, 0004-mock-server-python-stdlib.md]
---

# ADR-0005: Use the panos Terraform Provider v2 (XML-API) as the Apply Path

## Status

Accepted

Supersedes none.

## Context

### Background and Problem Statement

Phase 3 needs Terraform to actually push Panorama configuration as the GitOps "apply"
step. The official provider was rewritten: v1 was a hand-written provider on a legacy
SDK; **v2** is built on the Terraform plugin framework and auto-generated (with the
`pango` SDK) from `pan-os-codegen`. The two are not source-compatible — v2 replaces the
`panos_panorama_*` resource names with a uniform `location { … }` block and adds
`multi-config` batching.

flux already commits to the **XML-API only** (ADR-0001). The provider choice must keep
that single coherent interface for schema, mock, and apply.

### Current Limitations

1. v1 resource names and idioms differ from v2; examples online are mixed.
2. The provider's wire protocol (auth header, `set` vs `multi-config`, response shapes)
   had to be known precisely so the mock (ADR-0004) can stand in for a real Panorama.

## Decision Drivers

### Primary Decision Drivers

1. **XML-API alignment** (ADR-0001): v2 speaks the XML-API, not the REST API.
2. **Official and current**: v2 is the supported, actively generated provider; it covers
   PAN-OS 10.1+ (the lab is 12.1.2).
3. **Coverage**: v2 ships the resources the use cases need — objects, security/NAT rule
   lists, and template-interior network config (interfaces, zones, virtual routers).

### Secondary Decision Drivers

1. **Mock fidelity**: a well-defined wire protocol lets the stdlib mock reproduce it.

## Considered Options

### Option 1: panos provider v2 (`PaloAltoNetworks/panos` ~> 2.0)

**Description**: Use the v2 provider with `location`-scoped resources; pin `~> 2.0`.

**Technical Characteristics**:
- Auth via the `X-PAN-KEY` header; reads via `action=get`; writes via `action=set` and,
  for policy-rule resources, `action=multi-config` (`<multi-configure-request>` batches).
- `location { panorama | device_group | template … }` selects the XPath container.

**Advantages**:
- Official, current, XML-API; broad resource coverage; verified end-to-end here.

**Disadvantages**:
- Newer wire features (multi-config) the mock must implement.

**Risk Assessment**:
- **Technical Risk**: Low. `terraform apply` of all three use cases verified against the
  mock (12 resources, idempotent, commit OK) and `terraform plan` against the live box.
- **Schedule Risk**: Low.
- **Ecosystem Risk**: Low. Tracks PAN-OS via codegen.

### Option 2: panos provider v1

**Description**: Stay on the legacy `panos_panorama_*` provider.

**Disadvantages**:
- Superseded; diverging from the maintained generation path.

**Disqualifying Factor**: Not the current provider; weaker forward coverage.

### Option 3: raw XML-API via `local-exec` / a custom provider

**Description**: Script the XML-API directly from Terraform.

**Disqualifying Factor**: Reinvents state/diffing the panos provider already gives us.

## Decision

Use the **panos provider v2** over the **XML-API** as flux's apply path, pinned `~> 2.0`,
with `location`-scoped resources. This reaffirms ADR-0001 and keeps one interface across
schema, mock, and apply.

## Consequences

### Positive

1. **One interface**: schema, mock, and apply all speak the XML-API.
2. **Verified path**: the three use cases apply cleanly and idempotently.

### Negative

1. The mock had to learn `X-PAN-KEY` header auth, `action=multi-config`, faithful
   `<result>` responses, and slash-bearing entry names (interfaces). Captured in
   `mock/panorama_mock.py` and `mock/test_mock.py`.

### Neutral

1. A `panos_template_stack` needs `default_vsys` so the provider emits the `<settings>`
   element PAN-OS requires at commit.

## Decision Outcome

`terraform apply` of all three use cases (publish-app, template-network, NAT-interplay)
runs end-to-end against the mock — created, idempotent on re-plan, validate-full and
commit OK — and `terraform plan` resolves against the live Panorama.

Mitigations:
- Provider pinned `~> 2.0`; the mock's protocol coverage is regression-tested.

## Related Decisions

- [ADR-0001: Target the Panorama XML-API](0001-target-the-panorama-xml-api.md)
- [ADR-0004: Mock Panorama Server in Python stdlib](0004-mock-server-python-stdlib.md)

## Links

- [smADR](https://smadr.dev/) - decision record format.
- [PaloAltoNetworks/panos provider](https://registry.terraform.io/providers/PaloAltoNetworks/panos/latest)

## More Information

- **Date:** 2026-06-25
- **Source:** Provider v2.0.12 verified against the lab Panorama (12.1.2) and the mock.
- **Related ADRs:** ADR-0001, ADR-0004.

## Audit

### 2026-06-25

**Status:** Compliant

**Findings:**

| Finding | Files | Lines | Assessment |
|---------|-------|-------|------------|
| Provider pinned to v2 (XML-API) | terraform/versions.tf, terraform/modules/*/versions.tf | - | compliant |
| Apply path verified end-to-end | terraform/, mock/panorama_mock.py | - | compliant |
| Mock reproduces the v2 wire protocol | mock/panorama_mock.py, mock/test_mock.py | - | compliant |

**Summary:** flux applies via the panos v2 provider over the XML-API, consistent with ADR-0001; the mock faithfully reproduces the provider's protocol.

**Action Required:** None.
