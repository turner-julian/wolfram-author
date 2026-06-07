#!/usr/bin/env python3
"""Thin capability-registry check for wolfram-core.

The registry (`../registry.json`) is the open-ended record of what wolfram-core
can verify (ADR-0007). This module is the *data layer* over it: load, shape-check
against docs/registry-schema.md, look a primitive up, and answer the one question
the consumers ask at call time --

    is capability <name> available, or is this `no-capability`?

`check(name)` NEVER raises for an absent primitive: a miss is reported as a raw
`no-capability` fact, not a crash (docs/gate.md: "a primitive absent from the
registry is unchecked:no-capability at call time, never a crash"). That graceful
miss is what makes the demand-driven library safe to grow.

Boundary (ADR-0004 / docs/PLAN.md): wolfram-core returns RAW capability facts and
verdicts; it does NOT assign verify-math tiers. The raw status here is
`no-capability`; verify-math is what maps that to the `unchecked:no-capability`
tier. We never emit a tier string.

The *admission* policy (needed / verified / documented + trust DAG) lives in
gate.py, which builds on the shape validation here.

Usage:
    registry.py check <name> [--json]      # available? exit 0 ok, 1 no-capability
    registry.py list [--status STATUS] [--json]
    registry.py validate [--json]          # shape vs the schema; exit 0/1
    registry.py selftest
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_DIR = SCRIPT_DIR.parent
REGISTRY_PATH = REPO_DIR / "registry.json"

# Schema (docs/registry-schema.md). `context` and `depends_on` may be null/empty.
REQUIRED_FIELDS = (
    "name", "file", "signature", "representation",
    "conventions", "verification", "first_demanded_by", "status",
)
VERIFICATION_FIELDS = ("method", "evidence", "reference")
VALID_STATUS = ("verified", "provisional", "deprecated")
VALID_METHODS = (
    "closed-form", "independent-method", "second-library", "benchmark-equivalence",
)
# Which statuses mean "the capability is present and callable". A deprecated or
# absent primitive is `no-capability`; a provisional one is available but flagged.
AVAILABLE_STATUS = ("verified", "provisional")


class RegistryError(Exception):
    """The registry file itself is missing or malformed -- a setup error worth
    failing loudly on (distinct from a primitive simply being absent)."""


def load_registry(path: Path | None = None) -> dict:
    """Load and minimally type-check registry.json. Raises RegistryError on a
    missing file or malformed top-level shape -- NOT on an absent primitive."""
    p = path or REGISTRY_PATH
    if not p.exists():
        raise RegistryError(f"registry not found at {p}")
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise RegistryError(f"registry is not valid JSON: {exc}") from exc
    if not isinstance(data, dict) or not isinstance(data.get("capabilities"), list):
        raise RegistryError("registry must be an object with a 'capabilities' array")
    return data


def capabilities(registry: dict | None = None) -> list[dict]:
    reg = registry if registry is not None else load_registry()
    return reg["capabilities"]


def lookup(name: str, registry: dict | None = None) -> dict | None:
    """Return the capability entry for `name`, or None if it is not registered."""
    for cap in capabilities(registry):
        if cap.get("name") == name:
            return cap
    return None


def check(name: str, registry: dict | None = None) -> dict:
    """The thin capability check. Returns a RAW capability fact (never a tier):

        {"status": "ok" | "no-capability",
         "name": <name>,
         "available": bool,
         "registry_status": "verified"|"provisional"|"deprecated"|None,
         "entry": <entry>|None,
         "detail": <str>}

    `ok` -> the primitive is registered and callable (verified or provisional).
    `no-capability` -> absent, or registered-but-deprecated. verify-math maps this
    to the `unchecked:no-capability` tier; wolfram-core does not assign tiers."""
    entry = lookup(name, registry)
    if entry is None:
        return {
            "status": "no-capability",
            "name": name,
            "available": False,
            "registry_status": None,
            "entry": None,
            "detail": (
                f"no registered capability '{name}'. Raw status no-capability "
                "(verify-math renders this as the unchecked:no-capability tier; "
                "author + gate + register the primitive to close the miss)."
            ),
        }
    rstatus = entry.get("status")
    if rstatus in AVAILABLE_STATUS:
        return {
            "status": "ok",
            "name": name,
            "available": True,
            "registry_status": rstatus,
            "entry": entry,
            "detail": (
                f"capability '{name}' is registered ({rstatus})"
                + ("" if rstatus == "verified"
                   else "; provisional -- callable but lacking an independent check")
                + "."
            ),
        }
    # deprecated (or any non-available status) -> treat as no-capability
    return {
        "status": "no-capability",
        "name": name,
        "available": False,
        "registry_status": rstatus,
        "entry": entry,
        "detail": f"capability '{name}' is {rstatus}; not available. Raw status no-capability.",
    }


def validate(registry: dict | None = None) -> dict:
    """Shape-validate every entry against docs/registry-schema.md. Returns
    {"ok": bool, "checked": N, "errors": [...]}. This is well-formedness only;
    admission policy (the gate) is gate.py."""
    reg = registry if registry is not None else load_registry()
    caps = reg["capabilities"]
    errors: list[str] = []
    seen: set[str] = set()

    for i, cap in enumerate(caps):
        if not isinstance(cap, dict):
            errors.append(f"[{i}] entry is not an object")
            continue
        name = cap.get("name", f"<entry {i}>")

        for field in REQUIRED_FIELDS:
            val = cap.get(field)
            if val is None or val == "" or val == {} or val == []:
                errors.append(f"{name}: missing/empty required field '{field}'")

        if name in seen:
            errors.append(f"{name}: duplicate name")
        seen.add(name)

        if cap.get("status") not in VALID_STATUS:
            errors.append(f"{name}: status '{cap.get('status')}' not in {VALID_STATUS}")

        conv = cap.get("conventions")
        if conv is not None and not isinstance(conv, dict):
            errors.append(f"{name}: 'conventions' must be an object")

        dep = cap.get("depends_on", [])
        if dep is not None and not isinstance(dep, list):
            errors.append(f"{name}: 'depends_on' must be a list")

        ver = cap.get("verification")
        if isinstance(ver, dict):
            for f in VERIFICATION_FIELDS:
                if not ver.get(f):
                    errors.append(f"{name}: verification.{f} missing/empty")
            method = ver.get("method")
            if method is not None and method not in VALID_METHODS:
                errors.append(f"{name}: verification.method '{method}' not in {VALID_METHODS}")
        elif ver is not None:
            errors.append(f"{name}: 'verification' must be an object")

    return {"ok": not errors, "checked": len(caps), "errors": errors}


# --- CLI ---------------------------------------------------------------------

def _cmd_check(args: argparse.Namespace) -> int:
    res = check(args.name)
    if args.json:
        print(json.dumps(res, indent=2))
    else:
        print(f"{res['status']}: {res['detail']}")
    return 0 if res["available"] else 1


def _cmd_list(args: argparse.Namespace) -> int:
    caps = capabilities()
    rows = [c for c in caps if not args.status or c.get("status") == args.status]
    if args.json:
        print(json.dumps(
            [{"name": c["name"], "status": c.get("status"),
              "file": c.get("file"), "depends_on": c.get("depends_on", [])}
             for c in rows], indent=2))
    else:
        for c in rows:
            hs = " [high-stakes]" if c.get("high_stakes") else ""
            print(f"  {c.get('status','?'):11s} {c['name']}{hs}")
        print(f"\n{len(rows)} capabilit{'y' if len(rows)==1 else 'ies'}"
              + (f" with status={args.status}" if args.status else ""))
    return 0


def _cmd_validate(args: argparse.Namespace) -> int:
    res = validate()
    if args.json:
        print(json.dumps(res, indent=2))
    else:
        if res["ok"]:
            print(f"OK: {res['checked']} entries conform to docs/registry-schema.md")
        else:
            print(f"FAIL: {len(res['errors'])} shape error(s) across {res['checked']} entries:")
            for e in res["errors"]:
                print(f"  - {e}")
    return 0 if res["ok"] else 1


def _cmd_selftest(args: argparse.Namespace) -> int:
    ok = True

    def report(label: str, passed: bool, extra: str = "") -> None:
        nonlocal ok
        ok = ok and passed
        print(f"[{'PASS' if passed else 'FAIL'}] {label}{(' -- ' + extra) if extra else ''}")

    # 1. the shipped registry is well-formed
    v = validate()
    report("shipped registry validates", v["ok"],
           "" if v["ok"] else "; ".join(v["errors"][:3]))

    # 2. a known primitive resolves as available/ok
    known = check("Riemann")
    report("known primitive -> ok/available",
           known["status"] == "ok" and known["available"] is True,
           f"status={known['status']}")

    # 3. an ABSENT primitive is a graceful no-capability, not a crash
    absent = check("DefinitelyNotARealPrimitive")
    report("absent primitive -> no-capability (no crash)",
           absent["status"] == "no-capability" and absent["available"] is False,
           f"status={absent['status']}")

    # 4. a provisional primitive is available but flagged
    prov = check("Geodesic")
    report("provisional primitive -> available, flagged",
           prov["available"] is True and prov["registry_status"] == "provisional")

    # 5. a synthetic deprecated entry -> no-capability
    synth = {"capabilities": [dict(name="X", file="lib/core.wl", signature="X[]",
             representation="r", conventions={"a": "b"},
             verification={"method": "closed-form", "evidence": "e", "reference": "r"},
             first_demanded_by="seed", status="deprecated")]}
    dep = check("X", registry=synth)
    report("deprecated primitive -> no-capability",
           dep["status"] == "no-capability" and dep["available"] is False)

    # 6. shape validation actually catches a malformed entry
    bad = {"capabilities": [{"name": "Bad", "status": "bogus"}]}
    bv = validate(bad)
    report("validate() catches a malformed entry", not bv["ok"] and len(bv["errors"]) > 0)

    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="wolfram-core capability registry check.")
    sub = parser.add_subparsers(dest="command", required=True)

    p_check = sub.add_parser("check", help="is a capability available? (ok | no-capability)")
    p_check.add_argument("name")
    p_check.add_argument("--json", action="store_true")
    p_check.set_defaults(func=_cmd_check)

    p_list = sub.add_parser("list", help="list registered capabilities")
    p_list.add_argument("--status", choices=VALID_STATUS, help="filter by status")
    p_list.add_argument("--json", action="store_true")
    p_list.set_defaults(func=_cmd_list)

    p_val = sub.add_parser("validate", help="shape-check registry.json against the schema")
    p_val.add_argument("--json", action="store_true")
    p_val.set_defaults(func=_cmd_validate)

    p_self = sub.add_parser("selftest", help="run a built-in battery")
    p_self.set_defaults(func=_cmd_selftest)

    args = parser.parse_args()
    try:
        return args.func(args)
    except RegistryError as exc:
        print(json.dumps({"status": "error", "detail": str(exc)})
              if getattr(args, "json", False) else f"registry error: {exc}",
              file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
