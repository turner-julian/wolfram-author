#!/usr/bin/env python3
"""Code-generation eval harness for the mathematica-author skill.

The skill's product is a runnable, documented Wolfram script. The honest way to
grade such a product is NOT an LLM judge but the same machine checks the skill
already trusts: run the script in a real kernel and confirm its computed values
satisfy convention-independent assertions (curvature invariants, scalar
identities), all decided by Wolfram alone. No second engine is consulted -- if
the kernel can't decide it, the assertion fails rather than reaching for SymPy.

An eval *case* is a JSON file (see cases/*.json) pairing a natural-language
`prompt` with a reference `script` (the generated artifact under test) and a list
of machine-checkable `assertions`. Three assertion kinds:

  * "wl"     -- evaluate `expr` in the script's kernel context; pass iff the
                result equals `expect` (default "True"). For boolean invariants,
                e.g. EquivalentQ[riem, maximally-symmetric-form].
  * "scalar" -- evaluate `wl` in the script's context to get a scalar literal,
                then confirm `CT`EquivalentQ[literal, expect]` is True in a
                clean kernel. Wolfram-only (EquivalentQ does PossibleZeroQ ->
                FullSimplify -> numeric spot-check). verify_bridge.py is still on
                disk for opt-in cross-engine work, but the grader never calls it.
  * "head"   -- evaluate `wl`; pass iff Head[result] == `expect`. Used to assert
                an honesty signal, e.g. an integral with no closed form comes
                back with head "Integrate" (non-closure correctly surfaced),
                rather than a bogus answer.

Every case also gets an automatic "script runs clean" check (status == ok: no WL
messages, not $Failed) unless it sets "skip_clean_check": true.

Assertions are evaluated by prepending `Get["<script>"];` to the kernel payload,
so they read the globals the script assigns (ricciScalar, kretschmann, ...). The
script is re-run per assertion -- fine for a small suite, and it keeps each check
independent.

Usage:
  run_codegen_eval.py run <case.json>     # grade one case
  run_codegen_eval.py selftest            # grade every case in cases/
Exit code 0 iff all assertions pass, else 1 (matches the other skill scripts).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Reuse the existing harnesses rather than re-implementing kernel/bridge logic.
EVALS_DIR = Path(__file__).resolve().parent
SCRIPTS_DIR = EVALS_DIR.parent / "scripts"
CASES_DIR = EVALS_DIR / "cases"
sys.path.insert(0, str(SCRIPTS_DIR))

import wolfram  # noqa: E402


def _resolve_script(case_path: Path, script_field: str) -> Path:
    """Script paths are relative to the case file's directory."""
    p = (case_path.parent / script_field).resolve()
    return p


def _wl_get_prefix(script: Path) -> str:
    # Forward slashes survive on every platform inside a WL string literal.
    return f'Get["{script.as_posix()}"];'


def _eval_in_script(script: Path, expr: str, loads: list[str], timeout: float) -> dict:
    """Run `Get[script]; (expr)` and return the wolfram.run result dict."""
    payload = f"{_wl_get_prefix(script)} ({expr})"
    return wolfram.run(payload, loads=loads, timeout=timeout)


def _check_assertion(script: Path, a: dict, loads: list[str], timeout: float) -> dict:
    """Evaluate one assertion; return {passed, detail}."""
    kind = a.get("type")
    desc = a.get("desc", kind)

    if kind == "wl":
        expect = a.get("expect", "True")
        r = _eval_in_script(script, a["expr"], loads, timeout)
        passed = r["status"] == "ok" and r["result"] == expect
        return {"desc": desc, "passed": passed,
                "detail": f"status={r['status']} result={r['result']} want={expect}"}

    if kind == "head":
        expect = a["expect"]
        r = _eval_in_script(script, a["wl"], loads, timeout)
        passed = r["status"] == "ok" and r["head"] == expect
        return {"desc": desc, "passed": passed,
                "detail": f"status={r['status']} head={r['head']} want={expect}"}

    if kind == "scalar":
        expect = a["expect"]
        # First extract the script's computed scalar as an InputForm literal,
        # in the script's own context (so it sees ricciScalar, kretschmann, ...).
        r = _eval_in_script(script, a["wl"], loads, timeout)
        if r["status"] != "ok" or r["result"] is None:
            return {"desc": desc, "passed": False,
                    "detail": f"could not extract scalar: status={r['status']} "
                              f"head={r['head']} result={r['result']}"}
        literal = r["result"]
        # Then decide equality with EquivalentQ in a clean mauthor-only kernel.
        # Wolfram alone; no SymPy. EquivalentQ returns True / False / $Failed --
        # only an explicit True passes (undecided fails honestly).
        chk = wolfram.run(f"CT`EquivalentQ[({literal}),({expect})]",
                          loads=["ct"], timeout=timeout)
        passed = chk["status"] == "ok" and chk["result"] == "True"
        return {"desc": desc, "passed": passed,
                "detail": f"value={literal} expect={expect} "
                          f"EquivalentQ={chk['result']} (status={chk['status']})"}

    return {"desc": desc, "passed": False, "detail": f"unknown assertion type {kind!r}"}


def grade_case(case_path: Path) -> dict:
    """Grade one case file; return {id, passed, results:[...]}."""
    case = json.loads(case_path.read_text(encoding="utf-8"))
    cid = case.get("id", case_path.stem)
    script = _resolve_script(case_path, case["script"])
    loads = case.get("loads", [])
    timeout = float(case.get("timeout", 150))

    results: list[dict] = []

    if not script.exists():
        results.append({"desc": f"script exists ({script.name})", "passed": False,
                        "detail": f"missing: {script}"})
        return {"id": cid, "passed": False, "results": results}

    # Automatic clean-run check (skippable for honest non-closure cases that
    # still evaluate without WL messages -- those stay status ok anyway).
    if not case.get("skip_clean_check", False):
        r = wolfram.run(_wl_get_prefix(script), loads=loads, timeout=timeout)
        results.append({"desc": "script runs clean", "passed": r["status"] == "ok",
                        "detail": f"status={r['status']} msgs={r['messages']}"})

    for a in case.get("assertions", []):
        results.append(_check_assertion(script, a, loads, timeout))

    passed = all(r["passed"] for r in results)
    return {"id": cid, "passed": passed, "results": results}


def _print_case(report: dict) -> None:
    print(f"=== {report['id']} ===")
    for r in report["results"]:
        flag = "PASS" if r["passed"] else "FAIL"
        print(f"  [{flag}] {r['desc']}: {r['detail']}")
    print(f"  -> {'PASS' if report['passed'] else 'FAIL'} ({report['id']})")


def _cmd_run(args: argparse.Namespace) -> int:
    report = grade_case(Path(args.case).resolve())
    _print_case(report)
    return 0 if report["passed"] else 1


def _cmd_selftest(args: argparse.Namespace) -> int:
    case_files = sorted(CASES_DIR.glob("*.json"))
    if not case_files:
        print(f"[FAIL] no cases found in {CASES_DIR}")
        return 1
    ok = True
    for cf in case_files:
        report = grade_case(cf)
        _print_case(report)
        ok = ok and report["passed"]
    print(f"\n{'PASS' if ok else 'FAIL'}: {len(case_files)} case(s)")
    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="mathematica-author code-gen eval harness.")
    sub = parser.add_subparsers(dest="command", required=True)

    p_run = sub.add_parser("run", help="grade one case file")
    p_run.add_argument("case", help="path to a case JSON")
    p_run.set_defaults(func=_cmd_run)

    p_self = sub.add_parser("selftest", help="grade every case in cases/")
    p_self.set_defaults(func=_cmd_selftest)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
