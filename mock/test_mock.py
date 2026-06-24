#!/usr/bin/env python3
"""flux - end-to-end tests for the mock Panorama XML-API server.

Starts the mock in-process on an ephemeral port and drives it over HTTP, asserting
realistic XML responses and the set-time vs commit-time behaviour. Stdlib only.

    python mock/test_mock.py
"""
import sys
import threading
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import panorama_mock as mock  # noqa: E402

SH = "/config/shared"
RESULTS = []


def call(port, **params):
    data = urllib.parse.urlencode(params).encode()
    req = urllib.request.Request(f"http://127.0.0.1:{port}/api/", data=data)
    with urllib.request.urlopen(req) as r:
        return r.read().decode()


def check(name, cond, detail=""):
    RESULTS.append((name, bool(cond)))
    mark = "OK  " if cond else "XX  "
    print(f"{mark} {name}" + (f"  -- {detail}" if not cond else ""))


def status(xml_text):
    return ET.fromstring(xml_text).get("status")


def main():
    server, state = mock.make_server("127.0.0.1", 0)
    port = server.server_address[1]
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()
    try:
        # 1. no key -> 403
        r = call(port, type="config", action="get", xpath=SH + "/address")
        check("missing key rejected", status(r) == "error" and 'code="403"' in r)

        # 2. keygen
        r = call(port, type="keygen", user="admin", password="x")
        key = ET.fromstring(r).find(".//key").text
        check("keygen returns a key", key == mock.API_KEY)

        # 3. set with an unknown child -> set-time error (code 12)
        r = call(port, type="config", action="set", key=key,
                 xpath=SH + "/address/entry[@name='bad']", element="<bogus>x</bogus>")
        check("unknown child rejected at set", status(r) == "error" and 'code="12"' in r, r)

        # 4. valid address set -> success
        r = call(port, type="config", action="set", key=key,
                 xpath=SH + "/address/entry[@name='web']",
                 element="<ip-netmask>10.0.0.1/32</ip-netmask>")
        check("valid address set succeeds", status(r) == "success")

        # 5. get returns the stored entry
        r = call(port, type="config", action="get", key=key,
                 xpath=SH + "/address/entry[@name='web']")
        e = ET.fromstring(r).find(".//entry")
        check("get returns the entry", e is not None and e.get("name") == "web"
              and e.findtext("ip-netmask") == "10.0.0.1/32")

        # 6. service without a port: accepted at set, rejected by validate full
        r = call(port, type="config", action="set", key=key,
                 xpath=SH + "/service/entry[@name='svc']",
                 element="<protocol><tcp></tcp></protocol>")
        check("incomplete service accepted at set", status(r) == "success", r)

        r = call(port, type="op", key=key, cmd="<validate><full></full></validate>")
        jid = ET.fromstring(r).find(".//job").text
        r = call(port, type="op", key=key, cmd=f"<show><jobs><id>{jid}</id></jobs></show>")
        job = ET.fromstring(r).find(".//job")
        lines = " | ".join(l.text for l in job.find("details"))
        check("validate full fails on missing port",
              job.findtext("result") == "FAIL" and "svc" in lines and "port" in lines, lines)

        # 7. fix the service -> validate full OK
        r = call(port, type="config", action="set", key=key,
                 xpath=SH + "/service/entry[@name='svc']",
                 element="<protocol><tcp><port>8080</port></tcp></protocol>")
        r = call(port, type="op", key=key, cmd="<validate><full></full></validate>")
        jid = ET.fromstring(r).find(".//job").text
        r = call(port, type="op", key=key, cmd=f"<show><jobs><id>{jid}</id></jobs></show>")
        check("validate full passes once fixed",
              ET.fromstring(r).find(".//job").findtext("result") == "OK")

        # 8. commit -> running updated; show reads running
        r = call(port, type="op", key=key, cmd="<commit></commit>")
        jid = ET.fromstring(r).find(".//job").text
        r = call(port, type="op", key=key, cmd=f"<show><jobs><id>{jid}</id></jobs></show>")
        check("commit succeeds", ET.fromstring(r).find(".//job").findtext("result") == "OK")
        r = call(port, type="config", action="show", key=key,
                 xpath=SH + "/service/entry[@name='svc']")
        check("show reads committed running config",
              ET.fromstring(r).find(".//entry") is not None)

        # 9. delete -> gone from candidate
        r = call(port, type="config", action="delete", key=key,
                 xpath=SH + "/address/entry[@name='web']")
        check("delete succeeds", status(r) == "success")
        r = call(port, type="config", action="get", key=key,
                 xpath=SH + "/address/entry[@name='web']")
        check("deleted entry is gone", ET.fromstring(r).find(".//entry") is None)

        # 10. system info reports Panorama + version
        r = call(port, type="op", key=key, cmd="<show><system><info></info></system></show>")
        sysm = ET.fromstring(r).find(".//system")
        check("system info reports Panorama",
              sysm.findtext("model") == "Panorama" and sysm.findtext("sw-version") == state.version)
    finally:
        server.shutdown()

    ok = sum(1 for _, p in RESULTS if p)
    print(f"\nResult: {ok}/{len(RESULTS)} checks passed")
    sys.exit(0 if ok == len(RESULTS) else 1)


if __name__ == "__main__":
    main()
