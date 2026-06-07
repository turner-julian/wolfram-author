#!/usr/bin/env python3
"""Admission gate + trust DAG for the wolfram-core capability library.

The gate is the load-bearing artifact of the open-ended engine (docs/gate.md),
not the capability list. It is what keeps a demand-driven library trustworthy.
This module enforces the gate as a *policy layer* over the registry shape-check
in registry.py.

A primitive is admitted (status `verified`) iff ALL THREE hold (docs/gate.md):
  1. needed     -- recorded in `first_demanded_by` (a real content/check miss);
  2. verified   -- `verification.method` is closed-form / independent-method /
                   second-library / benchmark-equivalence, with evidence + a
                   reference recorded;
  3. documented -- `conventions` records the sign/index/units under which (2) holds.

Plus the trust DAG (docs/gate.md):
  * every `depends_on` resolves to a registered primitive, and the graph is acyclic;
  * a `verified` primitive may not rest on a non-verified dependency ("trusted
    only as far as its dependencies are");
  * a `high_stakes` primitive (one a content claim rests on directly) needs at
    least one NON-CHAINED check -- evidence that does not route through its own
    dependency chain. Operationally: method must be `second-library` or
    `closed-form` (an external authority), not an internal cross-computation that
    could share a latent error with the chain it is built from.

The gate is STATIC and always runnable (no kernel needed): it checks that the
evidence is recorded and well-formed and that the DAG is sound. The evidence
itself (closed-form / second-library agreement) is *established* at authoring
time -- via bench.py (EquivalentQ across candidates) or verify_bridge.py -- and
recorded in the entry. `admit --run` will optionally re-run a candidate's bench
spec through bench.py when a live kernel is present.

Boundary: wolfram-core returns raw facts; it never assigns tiers. The gate
reports admit/pass/fail, not `proved`/`spot-checked`. (The tier vocabulary
belonged to verify-math, removed 2026-06-07.)

Usage:
    gate.py audit [--json]              # audit the whole shipped registry
    gate.py admit <candidate.json> [--run] [--json]   # would this entry be admitted?
    gate.py selftest
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
import registry  # noqa: E402  (sibling module in scripts/)

# A high-stakes primitive's non-chained check must compare against an external
# authority, not an internal cross-computation that may share a dependency.
NON_CHAINED_METHODS = ("second-library", "closed-form")


def gate_entry(entry: dict, reg: dict) -> dict:
    """Evaluate ONE entry against the three-part gate (needed/verified/documented).
    Returns the three booleans, an admit verdict, and human reasons. DAG-level
    checks (depends_on resolution, cycles, high-stakes) are in trust_dag()."""
    name = entry.get("name", "<unnamed>")
    reasons: list[str] = []

    needed = bool(entry.get("first_demanded_by"))
    if not needed:
        reasons.append("not needed: empty first_demanded_by")

    conv = entry.get("conventions")
    documented = isinstance(conv, dict) and len(conv) > 0
    if not documented:
        reasons.append("not documented: conventions missing/empty")

    ver = entry.get("verification") or {}
    method = ver.get("method")
    has_evidence = (
        method in registry.VALID_METHODS
        and bool(ver.get("evidence"))
        and bool(ver.get("reference"))
    )
    if not has_evidence:
        reasons.append(
            f"no recorded verification (method={method!r}, "
            f"evidence={'set' if ver.get('evidence') else 'missing'}, "
            f"reference={'set' if ver.get('reference') else 'missing'})"
        )

    status = entry.get("status")
    gate_pass = needed and documented and has_evidence
    # `verified` is a claim the gate must back; provisional/deprecated are honest
    # non-admission, not failures.
    if status == "verified":
        admit = gate_pass
        if not gate_pass:
            reasons.append("labeled 'verified' but does NOT meet the gate (mislabeled)")
    else:
        admit = False
        if status == "provisional":
            reasons.append("provisional: in lib/ and callable, but not gate-admitted "
                           + ("(gate conditions met; needs an independent check or "
                              "status bump)" if gate_pass else "(see above)"))
        elif status == "deprecated":
            reasons.append("deprecated: superseded, not admitted")

    return {
        "name": name,
        "status": status,
        "admit": admit,
        "needed": needed,
        "documented": documented,
        "verified_evidence": has_evidence,
        "gate_pass": gate_pass,
        "reasons": reasons,
    }


def trust_dag(reg: dict) -> dict:
    """Check the dependency graph: resolution, acyclicity, verified-rests-only-on
    -verified, and the high-stakes non-chained-check rule."""
    caps = reg["capabilities"]
    by_name = {c["name"]: c for c in caps}
    errors: list[str] = []
    warnings: list[str] = []

    # 1. resolution
    for c in caps:
        for d in c.get("depends_on", []) or []:
            if d not in by_name:
                errors.append(f"{c['name']}: depends_on '{d}' is not registered")

    # 2. acyclicity (DFS) + topological order
    WHITE, GREY, BLACK = 0, 1, 2
    color = {n: WHITE for n in by_name}
    order: list[str] = []
    cyclic = [False]

    def visit(n: str, stack: list[str]) -> None:
        color[n] = GREY
        for d in by_name[n].get("depends_on", []) or []:
            if d not in by_name:
                continue
            if color[d] == GREY:
                cyclic[0] = True
                errors.append(f"cycle: {' -> '.join(stack + [n, d])}")
            elif color[d] == WHITE:
                visit(d, stack + [n])
        color[n] = BLACK
        order.append(n)

    for n in by_name:
        if color[n] == WHITE:
            visit(n, [])

    # 3. a verified primitive may not rest on a non-verified dependency
    for c in caps:
        if c.get("status") == "verified":
            for d in c.get("depends_on", []) or []:
                dep = by_name.get(d)
                if dep is not None and dep.get("status") != "verified":
                    errors.append(
                        f"{c['name']} is verified but depends on '{d}' "
                        f"(status {dep.get('status')}) -- trust cannot exceed its deps"
                    )

    # 4. high-stakes -> at least one non-chained check
    for c in caps:
        if c.get("high_stakes") and c.get("status") == "verified":
            method = (c.get("verification") or {}).get("method")
            if method not in NON_CHAINED_METHODS:
                errors.append(
                    f"{c['name']} is high_stakes but its only check is '{method}', "
                    f"which may route through its own dependency chain; needs a "
                    f"non-chained check ({' or '.join(NON_CHAINED_METHODS)})"
                )

    return {
        "ok": not errors,
        "errors": errors,
        "warnings": warnings,
        "order": order,
        "acyclic": not cyclic[0],
    }


def audit(reg: dict | None = None) -> dict:
    """Full audit of the shipped registry: shape + per-entry gate + trust DAG.
    `ok` is True iff the registry is self-consistent -- every `verified` entry
    genuinely meets the gate, the DAG is sound, and high-stakes entries have a
    non-chained check. Provisional/deprecated entries are reported, not failures."""
    reg = reg if reg is not None else registry.load_registry()
    shape = registry.validate(reg)
    entries = [gate_entry(c, reg) for c in reg["capabilities"]]
    dag = trust_dag(reg)

    mislabeled = [e["name"] for e in entries
                  if e["status"] == "verified" and not e["admit"]]
    verified = [e["name"] for e in entries if e["status"] == "verified"]
    provisional = [e["name"] for e in entries if e["status"] == "provisional"]
    deprecated = [e["name"] for e in entries if e["status"] == "deprecated"]

    ok = shape["ok"] and dag["ok"] and not mislabeled
    return {
        "ok": ok,
        "shape_ok": shape["ok"],
        "shape_errors": shape["errors"],
        "dag": dag,
        "entries": entries,
        "summary": {
            "total": len(entries),
            "verified": verified,
            "provisional": provisional,
            "deprecated": deprecated,
            "mislabeled_verified": mislabeled,
        },
    }


def _maybe_run_bench(candidate: dict) -> dict | None:
    """If the candidate carries a runnable `bench` spec and a kernel is present,
    re-confirm equivalence live via bench.py. Returns None when skipped."""
    spec = candidate.get("bench")
    if not isinstance(spec, dict) or len(spec.get("candidates", [])) < 2:
        return {"ran": False, "detail": "no runnable 2+-candidate bench spec on the candidate"}
    try:
        import bench  # vendored sibling
    except Exception as exc:  # pragma: no cover - defensive
        return {"ran": False, "detail": f"bench.py unavailable: {exc}"}
    result = bench.benchmark(
        spec.get("setup", ""), spec["candidates"],
        loads=spec.get("loads", []), timeout=spec.get("timeout", 120.0),
    )
    return {
        "ran": True,
        "all_equivalent": result["equivalence"]["all_equivalent"],
        "promotable": result["promotable"],
        "notes": result["notes"],
    }


def admit(candidate: dict, reg: dict | None = None, run: bool = False) -> dict:
    """Evaluate a CANDIDATE entry as if for admission: shape, the three-part gate,
    and its depends_on resolution + high-stakes rule against the current registry.
    Optionally (`run`) re-confirm recorded evidence live via bench.py."""
    reg = reg if reg is not None else registry.load_registry()

    shape = registry.validate({"capabilities": [candidate]})
    g = gate_entry(candidate, reg)

    by_name = {c["name"] for c in reg["capabilities"]}
    dep_problems = [d for d in candidate.get("depends_on", []) or [] if d not in by_name]

    hs_problem = None
    if candidate.get("high_stakes"):
        method = (candidate.get("verification") or {}).get("method")
        if method not in NON_CHAINED_METHODS:
            hs_problem = (f"high_stakes candidate's check '{method}' is potentially "
                          f"chained; needs {' or '.join(NON_CHAINED_METHODS)}")

    bench_result = _maybe_run_bench(candidate) if run else None
    bench_blocks = bool(bench_result and bench_result.get("ran")
                        and not bench_result.get("all_equivalent"))

    would_admit = (
        shape["ok"] and g["gate_pass"] and not dep_problems
        and hs_problem is None and not bench_blocks
        and candidate.get("status") == "verified"
    )
    reasons = list(g["reasons"])
    if not shape["ok"]:
        reasons += [f"shape: {e}" for e in shape["errors"]]
    if dep_problems:
        reasons.append(f"unresolved depends_on: {dep_problems}")
    if hs_problem:
        reasons.append(hs_problem)
    if bench_blocks:
        reasons.append("live bench: candidates NOT all equivalent")

    return {
        "name": candidate.get("name", "<unnamed>"),
        "would_admit": would_admit,
        "gate": g,
        "depends_on_resolves": not dep_problems,
        "high_stakes_problem": hs_problem,
        "bench": bench_result,
        "reasons": reasons,
    }


# --- CLI ---------------------------------------------------------------------

def _cmd_audit(args: argparse.Namespace) -> int:
    rep = audit()
    if args.json:
        print(json.dumps(rep, indent=2))
        return 0 if rep["ok"] else 1
    s = rep["summary"]
    print(f"shape: {'OK' if rep['shape_ok'] else 'FAIL'}  "
          f"dag: {'OK' if rep['dag']['ok'] else 'FAIL'}  "
          f"(acyclic={rep['dag']['acyclic']})")
    print(f"verified: {len(s['verified'])}  provisional: {len(s['provisional'])}  "
          f"deprecated: {len(s['deprecated'])}  total: {s['total']}")
    if s["provisional"]:
        print(f"  provisional (callable, not gate-admitted): {', '.join(s['provisional'])}")
    for e in rep["entries"]:
        if e["status"] == "verified" and not e["admit"]:
            print(f"  MISLABELED verified: {e['name']} -- {'; '.join(e['reasons'])}")
    for err in rep["dag"]["errors"]:
        print(f"  DAG: {err}")
    print(f"\n{'PASS' if rep['ok'] else 'FAIL'}: registry is "
          f"{'self-consistent' if rep['ok'] else 'NOT self-consistent'}")
    return 0 if rep["ok"] else 1


def _cmd_admit(args: argparse.Namespace) -> int:
    candidate = json.loads(Path(args.candidate).read_text(encoding="utf-8"))
    res = admit(candidate, run=args.run)
    if args.json:
        print(json.dumps(res, indent=2))
    else:
        print(f"{'ADMIT' if res['would_admit'] else 'REJECT'}: {res['name']}")
        for r in res["reasons"]:
            print(f"  - {r}")
        if res["bench"]:
            print(f"  bench: {res['bench']}")
    return 0 if res["would_admit"] else 1


def _cmd_selftest(args: argparse.Namespace) -> int:
    ok = True

    def report(label: str, passed: bool, extra: str = "") -> None:
        nonlocal ok
        ok = ok and passed
        print(f"[{'PASS' if passed else 'FAIL'}] {label}{(' -- ' + extra) if extra else ''}")

    # 1. the shipped registry audits clean (static; no kernel)
    rep = audit()
    report("shipped registry audits self-consistent", rep["ok"],
           "" if rep["ok"] else f"dag={rep['dag']['errors']} mislabeled={rep['summary']['mislabeled_verified']}")

    # 2. the DAG is acyclic and resolves
    report("trust DAG acyclic + resolves", rep["dag"]["ok"] and rep["dag"]["acyclic"])

    # 3. a well-formed candidate is ADMITTED
    good = {
        "name": "RicciScalarCandidate", "file": "lib/gr.wl", "context": "GR`",
        "signature": "F[g_?FieldQ]", "depends_on": ["Ricci"],
        "representation": "metric -> scalar",
        "conventions": {"ricci_scalar": "R = g^sn R_sn"},
        "verification": {"method": "closed-form", "evidence": "AdS4 R=-12/L^2",
                         "reference": "eval schwarzschild-kretschmann"},
        "first_demanded_by": "spec-loom: some section", "high_stakes": True,
        "status": "verified",
    }
    a_good = admit(good)
    report("well-formed high-stakes candidate -> ADMIT", a_good["would_admit"],
           "" if a_good["would_admit"] else "; ".join(a_good["reasons"]))

    # 4. an unverified (no evidence) candidate is REJECTED
    bad = dict(good, name="NoEvidence",
               verification={"method": "closed-form", "evidence": "", "reference": ""})
    a_bad = admit(bad)
    report("candidate with no recorded evidence -> REJECT", not a_bad["would_admit"])

    # 5. a high-stakes candidate whose only check is chained is REJECTED
    chained = dict(good, name="ChainedHighStakes",
                   verification={"method": "independent-method",
                                 "evidence": "Trc[Riemann]", "reference": "Tensor`Trc"})
    a_ch = admit(chained)
    report("high-stakes w/ only a chained check -> REJECT",
           not a_ch["would_admit"] and a_ch["high_stakes_problem"] is not None)

    # 6. an unresolved dependency is REJECTED
    dangling = dict(good, name="Dangling", depends_on=["NoSuchPrimitive"])
    a_dg = admit(dangling)
    report("candidate with a dangling depends_on -> REJECT",
           not a_dg["would_admit"] and not a_dg["depends_on_resolves"])

    # 7. a synthetic cyclic registry is caught
    cyc = {"capabilities": [
        dict(name="A", file="lib/core.wl", signature="A[]", representation="r",
             conventions={"a": "b"}, depends_on=["B"],
             verification={"method": "closed-form", "evidence": "e", "reference": "r"},
             first_demanded_by="s", status="verified"),
        dict(name="B", file="lib/core.wl", signature="B[]", representation="r",
             conventions={"a": "b"}, depends_on=["A"],
             verification={"method": "closed-form", "evidence": "e", "reference": "r"},
             first_demanded_by="s", status="verified"),
    ]}
    d_cyc = trust_dag(cyc)
    report("cyclic dependency graph -> caught", not d_cyc["ok"] and not d_cyc["acyclic"])

    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="wolfram-core admission gate + trust DAG.")
    sub = parser.add_subparsers(dest="command", required=True)

    p_audit = sub.add_parser("audit", help="audit the shipped registry against the gate")
    p_audit.add_argument("--json", action="store_true")
    p_audit.set_defaults(func=_cmd_audit)

    p_admit = sub.add_parser("admit", help="would a candidate entry (JSON file) be admitted?")
    p_admit.add_argument("candidate", help="path to a candidate entry JSON file")
    p_admit.add_argument("--run", action="store_true",
                         help="also re-confirm a bench spec live via bench.py (needs a kernel)")
    p_admit.add_argument("--json", action="store_true")
    p_admit.set_defaults(func=_cmd_admit)

    p_self = sub.add_parser("selftest", help="run a built-in battery")
    p_self.set_defaults(func=_cmd_selftest)

    args = parser.parse_args()
    try:
        return args.func(args)
    except registry.RegistryError as exc:
        print(f"registry error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
