#!/usr/bin/env python3
"""flux - lightweight schema validator for Panorama XML config.

The "validate before apply" gate of the flux pipeline: checks an XML fragment
(<entry>...</entry>) against schema/panorama-schema.json BEFORE it would be pushed
via the PAN-OS XML API. Python stdlib only -> runs anywhere (e.g. the GitLab
runner), no pip dependencies.

What it checks (mirrors PAN-OS behaviour observed via constraint probing and
the validate-full comparison):
  - target XPath -> a known resource type?
  - entry has a non-empty name attribute
  - only allowed child elements (mirrors PAN-OS "unexpected here")
  - required fields -- the XML-API "set" lets these through, "commit" does not
  - choice groups: zero -> error (mirrors "missing one of ..."),
    more than one -> warning (PAN-OS silently keeps one, so we flag, not fail)
  - enum values (e.g. action)
  - value formats (ip-netmask, ip-range, fqdn, port)
  - member lists contain non-empty <member>

The schema is bound to a PAN-OS version (schema["panosVersion"]). Pass
--panos-version to enforce that the target matches the schema.

Exit code: 0 = PASS (errors == 0; warnings allowed), 1 = FAIL, 2 = usage/load error.
"""
import argparse
import ipaddress
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

PRED_RE = re.compile(r"\[@[^\]]*\]")
FQDN_RE = re.compile(
    r"^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?"
    r"(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$"
)


def as_list(x):
    if x is None:
        return []
    return x if isinstance(x, list) else [x]


def strip_pred(xp):
    """Remove [@name='...'] predicates -> canonical path for container matching."""
    return PRED_RE.sub("", xp)


# ---- format checkers ----
def test_ip(v):
    addr, sep, prefix = v.partition("/")
    try:
        ip = ipaddress.ip_address(addr)
    except ValueError:
        return False
    if sep:  # a '/' was present
        if not prefix.isdigit():
            return False
        p = int(prefix)
        if p < 0 or p > (128 if ip.version == 6 else 32):
            return False
    return True


def test_format(fmt, v):
    v = v or ""
    if fmt == "ip-netmask":
        return test_ip(v)
    if fmt == "ip-range":
        parts = v.split("-")
        return len(parts) == 2 and test_ip(parts[0]) and test_ip(parts[1])
    if fmt == "fqdn":
        return bool(FQDN_RE.match(v))
    if fmt == "port-spec":
        for tok in v.split(","):
            bounds = tok.split("-")
            if len(bounds) > 2:
                return False
            for b in bounds:
                if not b.isdigit():
                    return False
                if not (1 <= int(b) <= 65535):
                    return False
        return True
    return True  # unknown format -> do not block


class Validator:
    def __init__(self):
        self.findings = []

    def add(self, level, path, msg):
        self.findings.append({"level": level, "path": path, "message": msg})

    def test_node(self, node, sch, path):
        children = list(node)
        present = [c.tag for c in children]

        if "allowedChildren" in sch:
            allowed = as_list(sch.get("allowedChildren"))
            for c in children:
                if c.tag not in allowed:
                    self.add("error", f"{path}/{c.tag}",
                             f"element '{c.tag}' is not allowed here (unexpected)")

        for r in as_list(sch.get("required")):
            if r not in present:
                self.add("error", f"{path}/{r}", f"required field '{r}' is missing")

        # choice groups: 0 -> error (commit-time "missing one of"),
        # >1 -> warning (PAN-OS silently keeps one)
        for group in as_list(sch.get("oneOf")):
            group = as_list(group)
            hit = [g for g in group if g in present]
            if len(hit) == 0:
                self.add("error", path,
                         f"requires one of {{ {', '.join(group)} }}, none present")
            elif len(hit) > 1:
                self.add("warning", path,
                         f"more than one of {{ {', '.join(group)} }} present "
                         f"({', '.join(hit)}); PAN-OS keeps only one")

        enums = sch.get("enums") or {}
        formats = sch.get("formats") or {}
        memberlists = as_list(sch.get("memberlists"))
        nested = sch.get("nested") or {}

        for c in children:
            cp = f"{path}/{c.tag}"
            text = (c.text or "").strip()
            if c.tag in enums:
                allowedv = as_list(enums[c.tag])
                if text not in allowedv:
                    self.add("error", cp, f"value '{text}' not allowed; "
                                          f"valid: {{ {', '.join(allowedv)} }}")
            if c.tag in formats:
                if not test_format(formats[c.tag], text):
                    self.add("error", cp, f"value '{text}' violates format '{formats[c.tag]}'")
            if c.tag in memberlists:
                members = [m for m in list(c) if m.tag == "member"]
                if not members:
                    self.add("error", cp, f"member list '{c.tag}' contains no <member>")
                elif any((m.text or "").strip() == "" for m in members):
                    self.add("error", cp, f"empty <member> in '{c.tag}'")
            if c.tag in nested:
                self.test_node(c, nested[c.tag], cp)


def resolve_resource(resources, xpath, forced=None):
    if forced:
        return forced
    container = re.sub(r"/entry$", "", strip_pred(xpath))
    for rn, rd in resources.items():
        if container in as_list(rd.get("containers")):
            return rn
    return None


def main():
    ap = argparse.ArgumentParser(
        description="flux Panorama XML config schema validator (validate before apply)")
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--xml", help="path to the XML fragment file (<entry>...)")
    src.add_argument("--xml-string", dest="xml_string", help="XML fragment as a string")
    ap.add_argument("--xpath", required=True, help="target XPath the fragment would be set at")
    ap.add_argument("--resource", help="force the resource type (otherwise derived from XPath)")
    ap.add_argument("--schema", help="path to panorama-schema.json")
    ap.add_argument("--panos-version", dest="panos_version",
                    help="target PAN-OS version; must match the schema's panosVersion")
    ap.add_argument("--json", action="store_true", help="emit a JSON report")
    a = ap.parse_args()

    schema_path = (Path(a.schema) if a.schema
                   else Path(__file__).resolve().parent.parent / "schema" / "panorama-schema.json")
    try:
        with open(schema_path, encoding="utf-8-sig") as f:
            schema = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"cannot load schema ({schema_path}): {e}", file=sys.stderr)
        sys.exit(2)
    resources = schema["resources"]
    schema_version = schema.get("panosVersion", "unknown")

    v = Validator()

    # version binding
    if a.panos_version and a.panos_version != schema_version:
        v.add("error", "(schema)",
              f"schema is for PAN-OS {schema_version}, but target is {a.panos_version}")

    res_name = resolve_resource(resources, a.xpath, a.resource)

    root = None
    try:
        root = ET.parse(a.xml).getroot() if a.xml else ET.fromstring(a.xml_string)
    except (ET.ParseError, OSError) as e:
        v.add("error", a.xpath, f"XML not parseable: {e}")

    if root is not None:
        if not res_name:
            container = re.sub(r"/entry$", "", strip_pred(a.xpath))
            v.add("error", a.xpath, f"unknown/unsupported target XPath (container "
                                    f"'{container}'). Known: {', '.join(resources)}")
        else:
            if root.tag != "entry":
                v.add("error", a.xpath, f"root element is '{root.tag}', expected 'entry'")
            if not (root.get("name") or "").strip():
                v.add("error", a.xpath, "entry without a (non-empty) name attribute")
            v.test_node(root, resources[res_name], f"entry[{root.get('name')}]")

    errors = [f for f in v.findings if f["level"] == "error"]
    warnings = [f for f in v.findings if f["level"] == "warning"]
    passed = not errors

    if a.json:
        print(json.dumps({"pass": passed, "resource": res_name,
                          "panosVersion": schema_version, "xpath": a.xpath,
                          "findings": v.findings}, indent=2, ensure_ascii=False))
    else:
        print(f"resource: {res_name or '<unknown>'} (PAN-OS {schema_version})")
        for f in warnings:
            print(f"  [warning] {f['path']}: {f['message']}")
        if passed:
            suffix = f" ({len(warnings)} warning(s))" if warnings else ""
            print(f"PASS - no schema violations.{suffix}")
        else:
            print(f"FAIL - {len(errors)} violation(s):")
            for f in errors:
                print(f"  [error] {f['path']}: {f['message']}")
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
