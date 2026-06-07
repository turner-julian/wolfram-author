#!/usr/bin/env python3
"""Benchmark-and-equivalence harness -- the gate for promoting code into lib/.

The library's whole justification is that every primitive is (a) the fastest of
several candidates and (b) verified to agree with the others. This harness
enforces both. Given a setup and >= 2 candidate WL expressions computing the
same thing, it:

  * times each candidate with RepeatedTiming (median of many runs -- single
    Timing is too noisy to rank fast ops), via the wolfram.py harness;
  * checks every candidate is EquivalentQ to the reference (candidate 0), using
    the library's correctness primitive;
  * reports the winner (fastest among equivalent candidates) and a `promotable`
    verdict: True only if there are >= 2 candidates, all evaluate cleanly, and
    all are equivalent.

A candidate that disagrees, fails to evaluate, or leaves equivalence undecided
blocks promotion -- the honest outcome when we cannot certify correctness.

Usage:
    python3 bench.py selftest
    python3 bench.py run spec.json   # {"setup","loads","candidates":[{"id","expr"}]}
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import wolfram  # noqa: E402


def _parse_seconds(result: str | None) -> float | None:
    if result is None:
        return None
    try:
        return float(result.replace("*^", "e"))  # WL scientific 1.23*^-6 -> float
    except ValueError:
        return None


def _parse_verdicts(result: str | None) -> list:
    """Parse a WL list like {True, False, $Failed} into Python values."""
    if not result:
        return []
    inner = result.strip().lstrip("{").rstrip("}").strip()
    if not inner:
        return []
    out = []
    for tok in inner.split(","):
        tok = tok.strip()
        out.append(True if tok == "True" else False if tok == "False" else "undecided")
    return out


def benchmark(
    setup: str,
    candidates: list[dict],
    loads: list[str] | None = None,
    timeout: float = 120.0,
) -> dict:
    loads = list(loads or [])
    # EquivalentQ + canonical rep must be available; "gr" already loads mauthor.
    if not ({"core", "gr"} & set(loads)):
        loads = loads + ["core"]
    prefix = (setup + ";\n") if setup.strip() else ""

    rows = []
    for cand in candidates:
        cid, expr = cand["id"], cand["expr"]
        res = wolfram.run(prefix + f"({expr})", loads=loads, timeout=timeout)
        tim = wolfram.run(
            prefix + f"First @ RepeatedTiming[({expr})]", loads=loads, timeout=timeout
        )
        rows.append(
            {
                "id": cid,
                "status": res["status"],
                "head": res["head"],
                "result": res["result"],
                "messages": res["messages"],
                "seconds": _parse_seconds(tim["result"]) if tim["status"] == "ok" else None,
            }
        )

    notes = []
    # equivalence: paste each result's InputForm back and compare to reference.
    ref = rows[0]
    pairs = []
    all_equivalent = True
    if ref["result"] is None:
        all_equivalent = False
        notes.append("reference candidate did not produce a result")
    elif len(rows) >= 2:
        checks = ",".join(
            f"EquivalentQ[({ref['result']}),({r['result']})]"
            if r["result"] is not None
            else "$Failed"
            for r in rows[1:]
        )
        eq = wolfram.run(f"{{{checks}}}", loads=["core"], timeout=timeout)
        verdicts = _parse_verdicts(eq["result"])
        for r, v in zip(rows[1:], verdicts):
            pairs.append({"id": r["id"], "verdict": v})
            if v is not True:
                all_equivalent = False

    clean = [r for r in rows if r["status"] == "ok" and r["seconds"] is not None]
    eligible = clean if all_equivalent else []
    winner = min(eligible, key=lambda r: r["seconds"]) if eligible else None

    promotable = (
        len(candidates) >= 2
        and all_equivalent
        and all(r["status"] == "ok" for r in rows)
        and winner is not None
    )
    if len(candidates) < 2:
        notes.append("governance requires >= 2 candidates to promote")
    if not all_equivalent:
        notes.append("candidates not all equivalent -- not promotable")

    return {
        "candidates": rows,
        "equivalence": {
            "reference": ref["id"],
            "pairs": pairs,
            "all_equivalent": all_equivalent,
        },
        "winner": winner["id"] if winner else None,
        "winner_seconds": winner["seconds"] if winner else None,
        "promotable": promotable,
        "notes": notes,
    }


def _cmd_run(args: argparse.Namespace) -> int:
    spec = json.loads(Path(args.spec).read_text(encoding="utf-8"))
    result = benchmark(
        spec.get("setup", ""),
        spec["candidates"],
        loads=spec.get("loads", []),
        timeout=spec.get("timeout", 120.0),
    )
    print(json.dumps(result, indent=2))
    return 0 if result["promotable"] else 1


def _cmd_selftest(args: argparse.Namespace) -> int:
    ok = True

    good = benchmark(
        "n = 100",
        [
            {"id": "loop", "expr": "Sum[i, {i, 1, n}]"},
            {"id": "closed-form", "expr": "n (n + 1)/2"},
        ],
    )
    g_ok = good["promotable"] and good["winner"] is not None and good["equivalence"]["all_equivalent"]
    ok = ok and g_ok
    print(f"[{'PASS' if g_ok else 'FAIL'}] equivalent candidates -> promotable")
    print(f"   winner={good['winner']} ({good['winner_seconds']}s) "
          f"all_equivalent={good['equivalence']['all_equivalent']} promotable={good['promotable']}")

    bad = benchmark(
        "n = 100",
        [
            {"id": "correct", "expr": "Sum[i, {i, 1, n}]"},
            {"id": "wrong", "expr": "n (n + 1)/2 + 1"},
        ],
    )
    b_ok = (not bad["promotable"]) and (not bad["equivalence"]["all_equivalent"])
    ok = ok and b_ok
    print(f"[{'PASS' if b_ok else 'FAIL'}] disagreeing candidate -> blocked")
    print(f"   pairs={bad['equivalence']['pairs']} promotable={bad['promotable']}")

    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark + equivalence gate for lib/.")
    sub = parser.add_subparsers(dest="command", required=True)

    p_run = sub.add_parser("run", help="run a benchmark spec (JSON file)")
    p_run.add_argument("spec")
    p_run.set_defaults(func=_cmd_run)

    p_self = sub.add_parser("selftest", help="run a built-in battery")
    p_self.set_defaults(func=_cmd_selftest)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
