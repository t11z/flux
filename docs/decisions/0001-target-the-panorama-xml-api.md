---
title: "Target the Panorama XML-API, Not the REST API"
description: "flux derives its schema and pushes config exclusively via the PAN-OS XML-API."
type: adr
category: integration
tags: [panorama, xml-api, terraform, pango]
status: accepted
created: 2026-06-24
updated: 2026-06-24
author: "Thomas Sprock"
project: flux
technologies: [pan-os, terraform-provider-panos, pango]
---

# ADR-0001: Target the Panorama XML-API, Not the REST API

## Status

Accepted

## Context

### Background and Problem Statement

PAN-OS/Panorama exposes two distinct configuration interfaces: the XPath-based **XML-API**
(`type=config`/`action=...`) and the resource-based **REST API** (`/restapi/v12.1/...`). flux
must pick one as the source of truth for schema derivation and as the interface its generated
configuration is validated against and (eventually) pushed through.

### Current Limitations

1. The two interfaces are not interchangeable: they use different addressing (XPath vs resource
   URIs), different request/response shapes, and different on-device documentation.
2. The schema and the "validate before apply" gate must match whatever interface the delivery
   pipeline actually uses, or validation is meaningless.

## Decision Drivers

### Primary Decision Drivers

1. **Match the delivery tooling**: the `panos` Terraform provider (pango SDK) speaks the XML-API.
   The validator must model the same interface the pipeline pushes through.
2. **Single source of truth**: one interface keeps the schema, fixtures, and validator coherent.

### Secondary Decision Drivers

1. **Discoverability**: the XML-API config tree maps directly to XPaths usable for both reads
   and writes, which is convenient for schema extraction.

## Considered Options

### Option 1: XML-API only

**Description**: Derive the schema and validate/push exclusively via the XPath-based XML-API.

**Technical Characteristics**:
- XPath addressing; `set`/`edit`/`get`/`delete` plus `op`/`validate full`.
- Matches the pango SDK used by terraform-provider-panos.

**Advantages**:
- Aligns the validator with the actual delivery path (Terraform/pango).
- One coherent model for schema, fixtures, and validation.

**Disadvantages**:
- No machine-readable OpenAPI spec; the schema must be derived (see ADR-0002).

**Risk Assessment**:
- **Technical Risk**: Low. The XML-API is stable and well documented.
- **Schedule Risk**: Low. Discovery tooling already works against the live box.
- **Ecosystem Risk**: Low. The XML-API is the long-standing primary interface.

### Option 2: REST API (OpenAPI) as the schema source

**Description**: Use the on-device REST API and its OpenAPI/Swagger spec as the schema source.

**Technical Characteristics**:
- Resource-based; ships a machine-readable spec.

**Advantages**:
- A complete, machine-readable schema for the supported resources.

**Disadvantages**:
- Models a *different* interface than the Terraform/pango delivery path.
- The on-device Swagger UI is gated behind an interactive GUI session, not the API key.

**Risk Assessment**:
- **Technical Risk**: Medium. Validating against the wrong interface gives false confidence.
- **Schedule Risk**: Low.
- **Ecosystem Risk**: Medium. Couples flux to a second interface it does not push through.

**Disqualifying Factor**: It does not match the interface the delivery pipeline uses.

## Decision

flux targets the **XML-API only**. The REST API / OpenAPI spec is explicitly not a source.

The implementation will use:
- **`tools/pan-api.ps1`** for XML-API access (keygen, config get/show/set/edit/delete, op).

## Consequences

### Positive

1. **Coherence**: schema, fixtures, and validator all describe the same interface the pipeline uses.
2. **Correctness**: validation reflects what Terraform/pango will actually push.

### Negative

1. **No off-the-shelf schema**: the schema must be derived from the live box (ADR-0002).

### Neutral

1. The REST API remains available for ad-hoc reads but is out of scope for flux.

## Decision Outcome

flux models the XML-API end to end. The lack of a machine-readable spec is addressed by ADR-0002.

Mitigations:
- Derive a normalized schema from live probing + fixtures and bind it to a PAN-OS version.

## Related Decisions

- [ADR-0002: Derive the Schema From Live Probing and Fixtures](0002-derive-schema-from-live-probing.md) - how the schema is built given no OpenAPI source.

## Links

- [PAN-OS XML API](https://docs.paloaltonetworks.com/pan-os/11-1/pan-os-panorama-api) - interface reference.

## More Information

- **Date:** 2026-06-24
- **Source:** Live discovery against Panorama 12.1.2.
- **Related ADRs:** ADR-0002.

## Audit

### 2026-06-24

**Status:** Compliant

**Findings:**

| Finding | Files | Lines | Assessment |
|---------|-------|-------|------------|
| Wrapper is XML-API only; no REST functions | tools/pan-api.ps1 | - | compliant |
| Schema declares `api: xml`, no REST source | schema/panorama-schema.json | - | compliant |

**Summary:** flux uses the XML-API exclusively; no REST code paths exist.

**Action Required:** None.
