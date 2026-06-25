#!/usr/bin/env python3
"""flux - regression harness for validate_config.py.

Runs the validator over valid fixtures (expected PASS) and invalid fixtures
(expected FAIL), and compares the exit code with the expectation. The
two-address-types case is expected to PASS *with a warning* (PAN-OS accepts it
and silently keeps one type). Stdlib only; pytest not required.

    python tools/test_validator.py
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FX = ROOT / "schema" / "fixtures"
VAL = ROOT / "tools" / "validate_config.py"

DEV = "/config/devices/entry[@name='localhost.localdomain']"
DG = f"{DEV}/device-group/entry[@name='flux-dg']"
SH = "/config/shared"
TCFG = f"{DEV}/template/entry[@name='flux-tpl']/config/devices/entry[@name='localhost.localdomain']"

# (fixture relative to schema/fixtures, target xpath, expectation)
CASES = [
    # --- valid -> PASS ---
    ("shared_address.xml",       f"{SH}/address/entry[@name='flux-web-srv']",                       "PASS"),
    ("dg_address.xml",           f"{DG}/address/entry[@name='flux-db-srv']",                        "PASS"),
    ("shared_service.xml",       f"{SH}/service/entry[@name='flux-tcp-8080']",                      "PASS"),
    ("shared_address_group.xml", f"{SH}/address-group/entry[@name='flux-web-grp']",                 "PASS"),
    ("dg_security_rule.xml",     f"{DG}/pre-rulebase/security/rules/entry[@name='flux-allow-web']", "PASS"),
    ("device_group.xml",         f"{DEV}/device-group/entry[@name='flux-dg']",                      "PASS"),
    ("template.xml",             f"{DEV}/template/entry[@name='flux-tpl']",                         "PASS"),
    ("template_stack.xml",       f"{DEV}/template-stack/entry[@name='flux-stack']",                 "PASS"),
    # --- template-interior + NAT valid -> PASS ---
    ("template_interface.xml",      f"{TCFG}/network/interface/ethernet/entry[@name='ethernet1/1']", "PASS"),
    ("template_zone.xml",           f"{TCFG}/vsys/entry[@name='vsys1']/zone/entry[@name='flux-trust']", "PASS"),
    ("template_virtual_router.xml", f"{TCFG}/network/virtual-router/entry[@name='flux-vr']",          "PASS"),
    ("dg_nat_rule.xml",             f"{DG}/pre-rulebase/nat/rules/entry[@name='flux-nat-hide']",      "PASS"),
    # --- warning -> PASS (PAN-OS accepts, keeps one type) ---
    ("invalid/address_two_types.xml", f"{SH}/address/entry[@name='bad-addr']", "PASS"),
    # --- invalid -> FAIL ---
    ("invalid/rule_bad_action_missing_to.xml", f"{DG}/pre-rulebase/security/rules/entry[@name='bad-rule']", "FAIL"),
    ("invalid/address_bad_ip.xml",        f"{SH}/address/entry[@name='bad-ip']",    "FAIL"),
    ("invalid/address_unknown_child.xml", f"{SH}/address/entry[@name='bad-child']", "FAIL"),
    ("invalid/address_no_type.xml",       f"{SH}/address/entry[@name='no-type']",   "FAIL"),
    ("invalid/service_no_port.xml",       f"{SH}/service/entry[@name='bad-svc']",   "FAIL"),
    ("invalid/nat_bad_type.xml",          f"{DG}/pre-rulebase/nat/rules/entry[@name='bad-nat']",        "FAIL"),
    ("invalid/nat_missing_fields.xml",    f"{DG}/pre-rulebase/nat/rules/entry[@name='nat-incomplete']", "FAIL"),
    ("invalid/interface_unknown_child.xml", f"{TCFG}/network/interface/ethernet/entry[@name='ethernet1/1']", "FAIL"),
    ("invalid/zone_unknown_child.xml",      f"{TCFG}/vsys/entry[@name='vsys1']/zone/entry[@name='bad-zone']", "FAIL"),
]


def run_case(fixture, xpath):
    p = subprocess.run(
        [sys.executable, str(VAL), "--xml", str(FX / fixture), "--xpath", xpath],
        capture_output=True, text=True)
    return ("PASS" if p.returncode == 0 else "FAIL"), p.stdout.strip()


def main():
    ok = bad = 0
    for fixture, xpath, expect in CASES:
        got, out = run_case(fixture, xpath)
        good = got == expect
        ok, bad = (ok + 1, bad) if good else (ok, bad + 1)
        mark = "OK  " if good else "XX  "
        print(f"{mark} {fixture:<42} expect={expect} got={got}")
        if not good:
            for line in out.splitlines():
                print(f"      {line}")
    print(f"\nResult: {ok} ok, {bad} failed, {len(CASES)} total")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
