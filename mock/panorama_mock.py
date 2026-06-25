#!/usr/bin/env python3
"""flux - mock Panorama XML-API server (Python stdlib only).

A lightweight stand-in for a Panorama management plane that speaks the PAN-OS
XML-API. It keeps an in-memory candidate (and running) config, validates `set`
requests against the flux schema exactly as the real device does at set time,
defers required/choice checks to commit / `validate full`, returns realistic XML
responses, and writes an audit log of every request.

Reuses tools/validate_config.py so the mock and the validate-before-apply gate
share one schema and one validation implementation.

The API key may be passed as &key= or via the X-PAN-KEY header (the panos Terraform
provider uses the header).

Supported requests (https://host/api/?...):
  type=keygen&user=&password=                       -> API key
  type=config&action=set&xpath=&element=&key=       -> merge into candidate (set-time validated)
  type=config&action=edit&xpath=&element=&key=      -> replace the node at xpath in candidate
  type=config&action=multi-config&element=&key=     -> a <multi-configure-request> batch of
                                                       set/edit/delete ops (the panos provider
                                                       uses this for policy-rule resources)
  type=config&action=get|show&xpath=&key=           -> read candidate (get) / running (show)
  type=config&action=delete&xpath=&key=             -> delete node from candidate
  type=op&cmd=<show><system><info>...&key=          -> system info
  type=op&cmd=<validate><full>...&key=              -> full (commit-time) validation, returns a job
  type=op&cmd=<commit>...  (or type=commit)         -> validate, then candidate -> running
  type=op&cmd=<show><jobs><id>N...&key=             -> job status/result

Run:  python mock/panorama_mock.py --port 8080 [--seed candidate.xml] [--version 12.1.2]
"""
import argparse
import re
import sys
import time
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import validate_config as vc  # noqa: E402

API_KEY = "flux-mock-key-0000000000000000000000000000"
SEG_RE = re.compile(r"^([^\[]+)(?:\[@([^=]+)='([^']*)'\])?$")


# ---------------- XPath navigation over ElementTree ----------------
def split_xpath(xpath):
    """Split an XPath on '/', but NOT on '/' inside a predicate, so names that
    contain a slash (e.g. an interface entry[@name='ethernet1/1']) stay intact."""
    segs, cur, depth = [], [], 0
    for ch in xpath.strip("/"):
        if ch == "[":
            depth += 1
            cur.append(ch)
        elif ch == "]":
            depth -= 1
            cur.append(ch)
        elif ch == "/" and depth == 0:
            if cur:
                segs.append("".join(cur))
                cur = []
        else:
            cur.append(ch)
    if cur:
        segs.append("".join(cur))
    return [s for s in segs if s]


def parse_seg(seg):
    m = SEG_RE.match(seg)
    if not m:
        raise ValueError(f"unparseable xpath segment: {seg!r}")
    return m.group(1), m.group(2), m.group(3)  # tag, attr, value


def find_child(parent, tag, attr, val):
    for ch in parent:
        if ch.tag == tag and (attr is None or ch.get(attr) == val):
            return ch
    return None


def navigate(root, xpath, create=False):
    """Return the element at xpath. With create=True, missing nodes are created.
    The first segment must match the root tag (config)."""
    segs = split_xpath(xpath)
    if not segs:
        return root
    first_tag, _, _ = parse_seg(segs[0])
    if first_tag != root.tag:
        return None
    cur = root
    for seg in segs[1:]:
        tag, attr, val = parse_seg(seg)
        nxt = find_child(cur, tag, attr, val)
        if nxt is None:
            if not create:
                return None
            nxt = ET.SubElement(cur, tag)
            if attr is not None:
                nxt.set(attr, val)
        cur = nxt
    return cur


def merge_into(target, fragment_xml):
    """Merge the children of `fragment_xml` (inner XML body) into target,
    replacing an existing child with the same tag (and same name attr)."""
    if not fragment_xml or not fragment_xml.strip():
        return
    wrapper = ET.fromstring(f"<_>{fragment_xml}</_>")
    for child in list(wrapper):
        name = child.get("name")
        existing = find_child(target, child.tag, "name" if name is not None else None, name)
        if existing is not None:
            target.remove(existing)
        target.append(child)


# ---------------- response builders ----------------
def _xml(s):
    return s.encode("utf-8")


def resp_success(result_inner="", code=None, msg=None):
    c = f' code="{code}"' if code else ""
    body = ""
    if msg is not None:
        body += f"<msg>{msg}</msg>"
    if result_inner:
        body += f"<result>{result_inner}</result>"
    return _xml(f'<response status="success"{c}>{body}</response>')


def resp_error(lines, code="12"):
    inner = "".join(f"<line>{ln}</line>" for ln in lines)
    return _xml(f'<response status="error" code="{code}"><msg>{inner}</msg></response>')


# ---------------- mock state ----------------
class MockState:
    def __init__(self, schema, version, seed_path=None, log_file=None):
        self.schema = schema
        self.version = version
        self.candidate = ET.Element("config")
        self.running = ET.Element("config")
        self.jobs = {}
        self.next_job = 1
        self.log_file = log_file
        if seed_path:
            self.candidate = ET.parse(seed_path).getroot()

    def log(self, **fields):
        ts = time.strftime("%Y-%m-%dT%H:%M:%S")
        line = "audit " + ts + " " + " ".join(f"{k}={v!r}" for k, v in fields.items())
        print(line, file=sys.stderr)
        if self.log_file:
            with open(self.log_file, "a", encoding="utf-8") as f:
                f.write(line + "\n")

    # ----- validation helpers -----
    def validate_set(self, xpath, entry):
        """set-time validation: only phase 'set' errors block the set."""
        _, findings = vc.validate_entry(self.schema, xpath, entry)
        return [f for f in findings if f["level"] == "error" and f["phase"] == "set"]

    def validate_full(self, root):
        """commit-time validation across all supported entries -> list of message lines."""
        lines = []
        for res_name, rd in self.schema["resources"].items():
            for pattern in vc.as_list(rd.get("containers")):
                for container in self._find_containers(root, split_xpath(pattern)):
                    for entry in [c for c in container if c.tag == "entry"]:
                        _, fs = vc.validate_entry(self.schema, "", entry, resource=res_name)
                        for f in fs:
                            if f["level"] == "error":
                                lines.append(f"{res_name} -> {entry.get('name')} -> {f['message']}")
        return lines

    @staticmethod
    def _find_containers(root, segs):
        """Walk a predicate-stripped container path; 'entry' matches any entry."""
        if not segs or segs[0] != root.tag:
            return []
        current = [root]
        for seg in segs[1:]:
            current = [c for node in current for c in node if c.tag == seg]
        return current


# ---------------- request handling ----------------
def handle(state, params):
    typ = (params.get("type") or [""])[0]
    if typ == "keygen":
        user = (params.get("user") or [""])[0]
        if not user:
            return resp_error(["keygen requires user/password"], code="400")
        return resp_success(result_inner=f"<key>{API_KEY}</key>")

    # everything else needs a valid key
    if (params.get("key") or [""])[0] != API_KEY:
        return resp_error(["Invalid Credential"], code="403")

    if typ == "config":
        return handle_config(state, params)
    if typ in ("op", "commit"):
        return handle_op(state, params)
    return resp_error([f"unsupported type '{typ}'"], code="400")


def apply_change(state, action, xpath, element):
    """Apply a single set/edit/delete to the candidate config.
    Returns (ok, error_lines). Set-time schema violations block the change.

    PAN-OS semantics:
      set    - merge `element` (inner XML) into the node at xpath (created if absent).
      edit   - replace the node at xpath with `element` (the full node, e.g. <entry>).
      delete - remove the node at xpath.
    """
    segs = split_xpath(xpath)
    last_tag, last_attr, last_val = parse_seg(segs[-1])
    parent_path = "/".join([""] + segs[:-1]) or "/config"

    if action == "delete":
        parent = navigate(state.candidate, parent_path, create=False)
        node = navigate(state.candidate, xpath, create=False)
        if parent is None or node is None:
            return False, ["No such node"]
        parent.remove(node)
        return True, []

    if action == "edit":
        wrapper = ET.fromstring(f"<_>{element}</_>") if element.strip() else ET.Element("_")
        kids = list(wrapper)
        node_el = kids[0] if kids else ET.Element(last_tag)
        if not kids and last_attr:
            node_el.set(last_attr, last_val)
        if node_el.tag == "entry":
            errs = state.validate_set(xpath, node_el)
            if errs:
                return False, [f"{m['path']} -> {m['message']}" for m in errs]
        parent = navigate(state.candidate, parent_path, create=True)
        existing = find_child(parent, last_tag, last_attr, last_val)
        if existing is not None:
            parent.remove(existing)
        parent.append(node_el)
        return True, []

    # action == "set": merge into (created) node, validating the merged entry.
    target_preview = navigate(state.candidate, xpath, create=False)
    if target_preview is not None:
        preview = ET.fromstring(ET.tostring(target_preview, encoding="unicode"))
    else:
        preview = ET.Element(last_tag)
        if last_attr:
            preview.set(last_attr, last_val)
    merge_into(preview, element)
    if preview.tag == "entry":
        errs = state.validate_set(xpath, preview)
        if errs:
            return False, [f"{m['path']} -> {m['message']}" for m in errs]
    target = navigate(state.candidate, xpath, create=True)
    merge_into(target, element)
    return True, []


def handle_multi_config(state, element):
    """type=config&action=multi-config: a <multi-configure-request> batch of
    set/edit/delete ops, each with an xpath (the panos provider uses this for
    policy-rule resources). Applied in order; the aggregated per-op response
    mirrors the real device."""
    try:
        req = ET.fromstring(element) if element.strip() else None
    except ET.ParseError as e:
        return resp_error([f"multi-config parse error: {e}"], code="400")

    parts, ok_all = [], True
    for i, op in enumerate(list(req) if req is not None else [], start=1):
        opid = op.get("id", str(i))
        xp = op.get("xpath", "")
        if not xp:
            parts.append(f'<response status="error" code="12" id="{opid}"><msg><line>xpath is required</line></msg></response>')
            ok_all = False
            continue
        body = "".join(ET.tostring(c, encoding="unicode") for c in list(op))
        ok, errs = apply_change(state, op.tag, xp, body)
        if ok:
            parts.append(f'<response status="success" code="20" id="{opid}"/>')
        else:
            inner = "".join(f"<line>{e}</line>" for e in errs)
            parts.append(f'<response status="error" code="12" id="{opid}"><msg>{inner}</msg></response>')
            ok_all = False

    status, code = ("success", "20") if ok_all else ("error", "12")
    return _xml(f'<response status="{status}" code="{code}">{"".join(parts)}</response>')


def handle_config(state, params):
    action = (params.get("action") or [""])[0]
    xpath = (params.get("xpath") or [""])[0]
    element = (params.get("element") or [""])[0]

    if action == "multi-config":
        return handle_multi_config(state, element)

    if not xpath:
        return resp_error(["xpath is required"], code="400")

    if action in ("set", "edit"):
        ok, errs = apply_change(state, action, xpath, element)
        if not ok:
            return resp_error(errs, code="12")
        return resp_success(code="20", msg="command succeeded")

    if action in ("get", "show"):
        root = state.candidate if action == "get" else state.running
        node = navigate(root, xpath, create=False)
        # Real Panorama ALWAYS returns a <result> element: code 19 with count
        # attributes when the node exists, code 7 with an empty <result/> when it
        # does not. The panos SDK relies on <result> being present (an empty
        # <response/> trips its XML decoder), so mirror the device exactly.
        if node is None:
            return _xml('<response status="success" code="7"><result/></response>')
        inner = ET.tostring(node, encoding="unicode")
        entries = node.findall("entry")
        n = len(entries) if entries else 1
        return _xml(f'<response status="success" code="19">'
                    f'<result total-count="{n}" count="{n}">{inner}</result></response>')

    if action == "delete":
        ok, errs = apply_change(state, "delete", xpath, "")
        if not ok:
            return resp_error(errs, code="7")
        return resp_success(code="20", msg="command succeeded")

    return resp_error([f"unsupported action '{action}'"], code="400")


def handle_op(state, params):
    cmd = (params.get("cmd") or [""])[0]

    if "<system>" in cmd and "<info>" in cmd:
        sysinfo = (f"<system><hostname>flux-mock</hostname><model>Panorama</model>"
                   f"<serial>unknown</serial><sw-version>{state.version}</sw-version>"
                   f"<system-mode>management-only</system-mode><family>pc</family></system>")
        return resp_success(result_inner=sysinfo)

    if "<jobs>" in cmd and "<id>" in cmd:
        m = re.search(r"<id>(\d+)</id>", cmd)
        jid = m.group(1) if m else ""
        job = state.jobs.get(jid)
        if not job:
            return resp_error([f"job {jid} not found"], code="7")
        details = "".join(f"<line>{ln}</line>" for ln in job["lines"])
        inner = (f"<job><id>{jid}</id><type>{job['type']}</type><status>FIN</status>"
                 f"<result>{job['result']}</result><details>{details}</details></job>")
        return resp_success(result_inner=inner)

    if "<validate>" in cmd:
        lines = state.validate_full(state.candidate)
        result = "FAIL" if lines else "OK"
        out = ["Validation Error:"] + lines if lines else ["Configuration is valid"]
        jid = str(state.next_job)
        state.next_job += 1
        state.jobs[jid] = {"type": "Validate", "result": result, "lines": out}
        return resp_success(code="19",
                            result_inner=f"<msg><line>Validate job enqueued with jobid {jid}</line></msg><job>{jid}</job>")

    if "<commit>" in cmd:
        lines = state.validate_full(state.candidate)
        jid = str(state.next_job)
        state.next_job += 1
        if lines:
            state.jobs[jid] = {"type": "Commit", "result": "FAIL",
                               "lines": ["Commit failed - validation errors:"] + lines}
        else:
            state.running = ET.fromstring(ET.tostring(state.candidate, encoding="unicode"))
            state.jobs[jid] = {"type": "Commit", "result": "OK", "lines": ["Configuration committed successfully"]}
        return resp_success(code="19",
                            result_inner=f"<msg><line>Commit job enqueued with jobid {jid}</line></msg><job>{jid}</job>")

    return resp_error([f"unsupported op cmd: {cmd[:60]}"], code="400")


def make_handler(state):
    class Handler(BaseHTTPRequestHandler):
        def _params(self):
            params = parse_qs(urlparse(self.path).query, keep_blank_values=True)
            if self.command == "POST":
                length = int(self.headers.get("Content-Length", 0) or 0)
                body = self.rfile.read(length).decode("utf-8") if length else ""
                for k, v in parse_qs(body, keep_blank_values=True).items():
                    params.setdefault(k, v)
            # Real Panorama also accepts the API key via the X-PAN-KEY header; the
            # panos Terraform provider sends it there by default.
            if "key" not in params:
                hdr = self.headers.get("X-PAN-KEY")
                if hdr:
                    params["key"] = [hdr]
            return params

        def _serve(self):
            if urlparse(self.path).path.rstrip("/") not in ("/api", ""):
                self.send_response(404)
                self.end_headers()
                return
            params = self._params()
            try:
                body = handle(state, params)
                ok = b'status="error"' not in body
            except Exception as e:  # never crash the mock; report as an error response
                body = resp_error([f"internal mock error: {e}"], code="500")
                ok = False
            state.log(method=self.command, type=(params.get("type") or [""])[0],
                      action=(params.get("action") or [""])[0],
                      xpath=(params.get("xpath") or [""])[0], ok=ok)
            self.send_response(200)
            self.send_header("Content-Type", "application/xml; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        do_GET = _serve
        do_POST = _serve

        def log_message(self, *args, **kwargs):
            pass  # silence the default stderr access log

    return Handler


def make_server(host, port, schema_path=None, version="12.1.2", seed=None, log_file=None):
    schema = vc.load_schema(schema_path)
    state = MockState(schema, version, seed_path=seed, log_file=log_file)
    server = ThreadingHTTPServer((host, port), make_handler(state))
    return server, state


def main():
    ap = argparse.ArgumentParser(description="flux mock Panorama XML-API server")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--schema", help="path to panorama-schema.json")
    ap.add_argument("--version", default=None, help="reported PAN-OS sw-version (default: schema panosVersion)")
    ap.add_argument("--seed", help="XML file to preload as the candidate config")
    ap.add_argument("--log-file", dest="log_file", help="append the audit log to this file")
    a = ap.parse_args()
    schema = vc.load_schema(a.schema)
    version = a.version or schema.get("panosVersion", "0.0.0")
    state = MockState(schema, version, seed_path=a.seed, log_file=a.log_file)
    server = ThreadingHTTPServer((a.host, a.port), make_handler(state))
    print(f"flux mock Panorama (PAN-OS {version}) on http://{a.host}:{a.port}/api/  (Ctrl+C to stop)",
          file=sys.stderr)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == "__main__":
    main()
