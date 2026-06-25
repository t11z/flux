# Panorama XPath map (PAN-OS 12.1, XML-API)

Editable configuration paths that flux supports. The huge `<readonly>` branch (predefined
threats/app-ids/services, ~23 MB) is **not** an editable schema and is excluded. Device root
everywhere: `/config/devices/entry[@name='localhost.localdomain']`.

## Top level of the config
```
/config
├── mgt-config          # admins, password complexity (out of scope)
├── devices/entry[@name='localhost.localdomain']
│   ├── device-group/entry[@name='<DG>']         # objects, security + NAT rules
│   ├── template/entry[@name='<TPL>']            # carries a full firewall config subtree
│   ├── template-stack/entry[@name='<STACK>']
│   └── ... (deviceconfig, log-collector-group, ...)
├── readonly            # EXCLUDED (predefined content)
├── panorama            # Panorama settings
└── shared              # device-wide objects
```

## Supported resources -> XPath
| Resource         | Container XPath (entry = `.../entry[@name='…']`) |
|------------------|---------------------------------------------------|
| address (shared) | `/config/shared/address` |
| address (DG)     | `…/device-group/entry[@name='<DG>']/address` |
| service          | `/config/shared/service`  ·  `…/device-group/entry[@name='<DG>']/service` |
| address-group    | `/config/shared/address-group`  ·  `…/device-group/entry[@name='<DG>']/address-group` |
| security-rule    | `…/device-group/entry[@name='<DG>']/pre-rulebase/security/rules`  ·  `…/post-rulebase/security/rules` |
| nat-rule         | `…/device-group/entry[@name='<DG>']/pre-rulebase/nat/rules`  ·  `…/post-rulebase/nat/rules` |
| device-group     | `…/device-group` |
| template         | `…/template` |
| template-stack   | `…/template-stack` |

### Template-interior network config
A template carries a full firewall config subtree; its network objects live under the template's
**own** config root: `…/template/entry[@name='<TPL>']/config/devices/entry[@name='localhost.localdomain']`
(abbreviated `<TCFG>`).

| Resource           | Container XPath |
|--------------------|-----------------|
| ethernet-interface | `<TCFG>/network/interface/ethernet` |
| zone               | `<TCFG>/vsys/entry[@name='vsys1']/zone` |
| virtual-router     | `<TCFG>/network/virtual-router` |

**Ordering / import rule:** a zone (and a virtual router) can only reference an interface that
exists, and a zone additionally needs the interface **imported into its vsys**
(`<TCFG>/vsys/entry[@name='vsys1']/import/network/interface`). PAN-OS checks these references **at
set time**, so the seed order is interface → vsys-import → zone. These cross-object reference
checks are outside flux's single-entry validator scope (as with security/NAT member references).

## Element structure (from real fixtures)
Real, canonical XML forms live under `schema/fixtures/*.xml` (bookkeeping attributes
`admin/dirtyId/time/uuid/loc` are stripped). Examples:

**Address** (`schema/fixtures/shared_address.xml`)
```xml
<entry name="flux-web-srv">
  <ip-netmask>10.10.10.10/32</ip-netmask>
  <description>...</description>
</entry>
```
Exactly **one** type child: `ip-netmask | ip-range | ip-wildcard | fqdn`.

**Service** (`schema/fixtures/shared_service.xml`)
```xml
<entry name="flux-tcp-8080">
  <protocol><tcp><port>8080</port></tcp></protocol>
</entry>
```

**Security rule** (`schema/fixtures/dg_security_rule.xml`) - member lists + `action` enum.

**Template-stack** requires a `<settings>` element (may be empty) - enforced at commit.

## XML-API mechanics
- Auth: `type=keygen&user=…&password=…` -> `key`; then `&key=…`.
- Read: `type=config&action=get` (candidate) / `action=show` (running).
- Write: `action=set` (merge) / `edit` (replace) / `delete`. Body = `element` (inner XML).
- `set` enforces enums/format/unknown elements, **not** required fields / choice cardinality
  (those are commit-time; flux checks them ahead). Details: `schema/constraints/probe-results.md`.

## Source of truth
The normalized, machine-readable schema: `schema/panorama-schema.json` (built by
`tools/build-schema.ps1`, checked by `tools/validate_config.py`). The schema is bound to the
PAN-OS version it was derived from (`panosVersion`); versioned copies are archived under
`schema/versions/`.
