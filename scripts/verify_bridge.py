#!/usr/bin/env python3
"""Cross-engine quality gate: confirm a Wolfram scalar result with SymPy.

The wolfram-author skill computes in Wolfram. This bridge asks the
verify-math skill's SymPy verifier for an INDEPENDENT second opinion on a scalar
equality (result == expected). Two independent CAS engines agreeing is much
stronger evidence than one -- it catches a Wolfram-specific quirk, a convention
slip, or a bug a single engine would miss.

Honesty design. The fragile step is translating Wolfram InputForm to SymPy
syntax, and a silent mistranslation here would poison the very check it provides.
Two safeguards:
  1. The translator accepts only a whitelist of function heads and rejects lists,
     parts, and unknown heads with a loud "untranslatable" -- never a guess.
  2. A claim is reported "agree" only when BOTH engines independently confirm the
     equality. If they conflict the status is "disagree" (a real discrepancy OR a
     translation error -- either way NOT verified, and surfaced for a human).

Scope: scalar expressions. Tensors are checked componentwise by the caller if at
all. This gate confirms scalar claims (curvature scalars, integrals, identities).

Usage:
  verify_bridge.py check --wl '<WL result>' --expect '<WL expected>' [--load mauthor]
  verify_bridge.py translate --wl '<WL expr>'
  verify_bridge.py selftest
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import wolfram  # noqa: E402

# verify-math path resolution: env var > config.json > default.
# If absent, cross-engine checks return "unavailable" instead of crashing.
_DEFAULT_VERIFY = Path.home() / ".claude" / "skills" / "verify-math" / "scripts" / "verify.py"


def _resolve_verify_math() -> Path:
    env = os.environ.get("MAUTHOR_VERIFY_MATH_PATH")
    if env:
        return Path(env)
    cfg = wolfram._load_config().get("verify_math_path")
    if cfg:
        return Path(cfg)
    return _DEFAULT_VERIFY


VERIFY_MATH = _resolve_verify_math()

# Wolfram head -> SymPy function name. Anything not here is untranslatable.
_HEADS = {
    "Sqrt": "sqrt", "Exp": "exp", "Log": "log",
    "Sin": "sin", "Cos": "cos", "Tan": "tan",
    "Csc": "csc", "Sec": "sec", "Cot": "cot",
    "ArcSin": "asin", "ArcCos": "acos", "ArcTan": "atan",
    "Sinh": "sinh", "Cosh": "cosh", "Tanh": "tanh",
    "ArcSinh": "asinh", "ArcCosh": "acosh", "ArcTanh": "atanh",
    "Abs": "Abs", "Sign": "sign", "Gamma": "gamma", "Erf": "erf",
    "Factorial": "factorial",
}
# Wolfram constant -> SymPy. (E and I are spelled the same; SymPy's E is exp(1),
# so WL `E^x` survives as `E**x` == exp(x). `^` is handled by verify.py.)
_CONSTS = {"Pi": "pi", "Infinity": "oo", "EulerGamma": "EulerGamma"}


class Untranslatable(Exception):
    pass


def wl_to_sympy(wl: str) -> str:
    """Translate a Wolfram InputForm scalar to SymPy-parseable syntax, or raise."""
    if any(tok in wl for tok in ("{", "}", "[[", "]]")):
        raise Untranslatable("contains a list or Part -- not a scalar")

    # every `Head[` must be a whitelisted function
    for m in re.finditer(r"([A-Za-z][A-Za-z0-9]*)\[", wl):
        if m.group(1) not in _HEADS:
            raise Untranslatable(f"unknown function head {m.group(1)}[")

    s = re.sub(r"([A-Za-z][A-Za-z0-9]*)\[", lambda m: _HEADS[m.group(1)] + "(", wl)
    s = s.replace("]", ")")  # all remaining brackets were function calls
    for wlc, spc in _CONSTS.items():
        s = re.sub(rf"\b{wlc}\b", spc, s)
    return s


def _verify_math_numeric(lhs: str, rhs: str) -> dict:
    """Run verify-math's SymPy numeric check; return its JSON result."""
    if not VERIFY_MATH.exists():
        return {"status": "error", "message": f"verify-math not found at {VERIFY_MATH}"}
    # `--` stops argparse option parsing so a leading-minus expr (e.g. "-12/L^2")
    # is taken as a positional, not a flag.
    proc = subprocess.run(
        [sys.executable, str(VERIFY_MATH), "numeric", "--", lhs, rhs],
        capture_output=True, text=True, timeout=120,
    )
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {"status": "error", "message": (proc.stderr or proc.stdout)[:500]}


def check(wl_result: str, wl_expect: str, loads: list[str] | None = None) -> dict:
    loads = loads or ["mauthor"]

    # SymPy engine (verify-math), via translation.
    try:
        s_result, s_expect = wl_to_sympy(wl_result), wl_to_sympy(wl_expect)
    except Untranslatable as exc:
        sympy_verdict, sympy_detail = "untranslatable", str(exc)
        s_result = s_expect = None
    else:
        vm = _verify_math_numeric(s_result, s_expect)
        sympy_detail = {"sympy": [s_result, s_expect], "result": vm}
        sympy_verdict = {
            "passed": "equal", "failed": "not-equal",
        }.get(vm.get("status"), "inconclusive")

    # Wolfram engine.
    wl = wolfram.run(f"EquivalentQ[({wl_result}),({wl_expect})]", loads=loads, timeout=120)
    wl_verdict = {"True": "equal", "False": "not-equal"}.get(
        wl.get("result"), "inconclusive"
    ) if wl["status"] == "ok" else "inconclusive"

    # Combine: only two independent "equal" verdicts count as verified.
    if wl_verdict == "equal" and sympy_verdict == "equal":
        status = "agree"
    elif "not-equal" in (wl_verdict, sympy_verdict) and "equal" in (wl_verdict, sympy_verdict):
        status = "disagree"  # engines conflict: real discrepancy or mistranslation
    elif wl_verdict == "not-equal" and sympy_verdict == "not-equal":
        status = "agree-not-equal"  # both say the claim is false
    elif sympy_verdict == "untranslatable":
        status = "wolfram-only"  # SymPy could not be consulted
    else:
        status = "inconclusive"

    return {
        "status": status,
        "wolfram": wl_verdict,
        "sympy": sympy_verdict,
        "detail": {"wolfram_status": wl["status"], "sympy": sympy_detail},
    }


_EXIT = {"agree": 0, "agree-not-equal": 0, "wolfram-only": 1,
         "inconclusive": 1, "disagree": 2}


def _cmd_check(args: argparse.Namespace) -> int:
    res = check(args.wl, args.expect, loads=args.load or ["mauthor"])
    print(json.dumps(res, indent=2))
    return _EXIT.get(res["status"], 1)


def _cmd_translate(args: argparse.Namespace) -> int:
    try:
        print(wl_to_sympy(args.wl))
        return 0
    except Untranslatable as exc:
        print(f"untranslatable: {exc}", file=sys.stderr)
        return 2


def _cmd_selftest(args: argparse.Namespace) -> int:
    cases = [
        ("equal via two engines", "Sqrt[Pi]/E^(a^2/4)", "Sqrt[Pi]*Exp[-a^2/4]", "agree"),
        ("AdS4 Ricci scalar", "-12/L^2", "-12/L^2", "agree"),
        ("genuine disagreement flagged", "-12/L^2", "-11/L^2", "agree-not-equal"),
        ("trig identity", "Sin[x]^2 + Cos[x]^2", "1", "agree"),
        ("untranslatable (list)", "{1, 2, 3}", "{1, 2, 3}", "wolfram-only"),
    ]
    ok = True
    for name, wl, exp, want in cases:
        res = check(wl, exp)
        passed = res["status"] == want
        ok = ok and passed
        print(f"[{'PASS' if passed else 'FAIL'}] {name}: status={res['status']} "
              f"(want {want}) wolfram={res['wolfram']} sympy={res['sympy']}")
    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Cross-engine (Wolfram+SymPy) scalar gate.")
    sub = parser.add_subparsers(dest="command", required=True)

    p_check = sub.add_parser("check", help="confirm a WL scalar equality with both engines")
    p_check.add_argument("--wl", required=True, help="the Wolfram result expression")
    p_check.add_argument("--expect", required=True, help="the expected expression (WL)")
    p_check.add_argument("--load", action="append", default=[], choices=["mauthor", "gr", "ogre", "xact"])
    p_check.set_defaults(func=_cmd_check)

    p_tr = sub.add_parser("translate", help="show the SymPy translation of a WL scalar")
    p_tr.add_argument("--wl", required=True)
    p_tr.set_defaults(func=_cmd_translate)

    p_self = sub.add_parser("selftest", help="run a built-in battery")
    p_self.set_defaults(func=_cmd_selftest)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
