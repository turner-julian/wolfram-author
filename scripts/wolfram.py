#!/usr/bin/env python3
"""Shared Wolfram Language kernel harness for wolfram-core.

Vendored into verify-math and wolfram-author (ADR-0007 / ADR-0009). The CLI, the
JSON shape below, and the `--load` bundle names already in use (`ct`, `gr`, ...)
are a FROZEN contract: verify-math's `_wolfram_run` and its escalation ladder
depend on them. Internals may be refactored; the interface may not change.

Runs a WL payload through `wolframscript` and prints one JSON object:

    {"status": "ok|messages|failed|timeout|error|no-kernel",
     "result": "<InputForm string>",   # machine-readable
     "tex":    "<TeXForm string>",      # display
     "head":   "Integrate",             # Head of the result
     "messages": ["Power::infy", ...],  # WL messages emitted (empty == clean)
     "seconds": 0.013}                  # kernel evaluation time

Exit code: 0 if ok, 1 if messages/failed, 2 if timeout/error/no-kernel.

Why this exists (honesty contract). A Wolfram result is only trustworthy if it
actually evaluated cleanly, and a naive shell-out hides two failure modes:
  * wolframscript prints messages (e.g. `Power::infy`) to STDOUT, not stderr,
    so they read as ordinary output;
  * an unevaluated expression (`Integrate[...]` returned verbatim) looks exactly
    like a successful result.
This harness captures messages via $MessageList, flags $Failed/$Aborted and
timeouts, surfaces the result `head` (so a caller can detect non-closure when
the head equals the operator it asked to evaluate), and delimits its JSON with
sentinels so package banners never corrupt the payload. The harness never
decides whether `messages`/`failed` is fatal -- it only guarantees they are
never hidden. That judgment belongs to the caller.

Speed practices baked in (Mathematica is slow when used wrong):
  * $HistoryLength = 0          -- no Out[] accumulation / memory bloat
  * message output redirected   -- skip console formatting on every message
  * packages loaded with output suppressed; the run() API is shaped so a
    persistent kernel (wolframclient WolframLanguageSession) can back it later
    without changing callers -- deferred until batches justify it
  * NO automatic FullSimplify   -- the classic slow trap; simplification level
    is always the caller's explicit choice, never imposed here.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_DIR = SCRIPT_DIR.parent
LIB_DIR = REPO_DIR / "lib"


def _load_config() -> dict:
    """Load config.json from the repo root, if it exists."""
    cfg = REPO_DIR / "config.json"
    if cfg.exists():
        try:
            return json.loads(cfg.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            pass
    return {}


def _resolve_ogre_path() -> str:
    """Resolve OGRe .m path: WOLFRAM_CORE_OGRE_PATH / MAUTHOR_OGRE_PATH env >
    config.json > default. MAUTHOR_OGRE_PATH is honored for back-compat with
    existing wolfram-author configs."""
    env = os.environ.get("WOLFRAM_CORE_OGRE_PATH") or os.environ.get("MAUTHOR_OGRE_PATH")
    if env:
        return env
    cfg = _load_config().get("ogre_path")
    if cfg:
        return cfg
    # Default: standard macOS user notebook folder.
    return str(Path.home() / "Documents" / "Wolfram Mathematica" / "OGRe.m")


OGRE_PATH = _resolve_ogre_path()

_SENTINEL_BEGIN = "<<<WLJSON>>>"
_SENTINEL_END = "<<<WLEND>>>"

# Package loaders. Output and message streams are muted during load so banners
# never reach stdout; a network/time guard prevents a hung update check.
_LOADS = {
    "ogre": (
        "Quiet[Block[{$Output = {}, $Messages = {}},"
        f' TimeConstrained[Get["{OGRE_PATH}"], 90];'
        " Check[TSetAutoUpdates[False], Null]]];"
    ),
    "xact": (
        "Quiet[Block[{$Output = {}, $Messages = {}},"
        ' TimeConstrained[Needs["xAct`xTensor`"], 120]]];'
    ),
    # the skill's own curated library (canonical representation + EquivalentQ)
    "ct": f'Get["{LIB_DIR / "CT.wl"}"];',
    # GR curvature operators; implies ct (loads it first).
    "grt": f'Get["{LIB_DIR / "CT.wl"}"];\nGet["{LIB_DIR / "GRT.wl"}"];',
    # aliases used by bench.py and verify_bridge.py
    "mauthor": f'Get["{LIB_DIR / "CT.wl"}"];',
    "gr": f'Get["{LIB_DIR / "CT.wl"}"];\nGet["{LIB_DIR / "GRT.wl"}"];',
    # xCoba component computation (extends xact with coordinate-basis tools)
    "xcoba": (
        "Quiet[Block[{$Output = {}, $Messages = {}},"
        ' TimeConstrained[Needs["xAct`xTensor`"], 120];'
        ' TimeConstrained[Needs["xAct`xCoba`"], 120]]];'
    ),
}

# %%LOADS%% and %%PAYLOAD%% are substituted (not .format: WL is full of braces).
_WRAPPER = r"""
$HistoryLength = 0;
%%LOADS%%
Module[{wlRes, wlT, wlMsgs, wlInform, wlTex, wlAssoc, wlJson},
  wlMsgs = {};
  wlT = First[AbsoluteTiming[Block[{$MessageList = {}, $Messages = {}},
      wlRes = ( %%PAYLOAD%% );
      wlMsgs = ToString[#, InputForm] & /@ $MessageList;
  ]]];
  wlInform = ToString[wlRes, InputForm];
  wlTex = Block[{$Messages = {}}, Check[ToString[TeXForm[wlRes]], "<texform-failed>"]];
  wlAssoc = <|
     "result_inputform" -> wlInform,
     "result_tex" -> wlTex,
     "head" -> ToString[Head[wlRes]],
     "messages" -> wlMsgs,
     "failed" -> TrueQ[wlRes === $Failed || wlRes === $Aborted || ! FreeQ[wlRes, $Failed | $Aborted]],
     "seconds" -> wlT
  |>;
  wlJson = ExportString[wlAssoc, "JSON", "Compact" -> True];
  WriteString[$Output, "%%BEGIN%%\n" <> wlJson <> "\n%%END%%\n"];
];
"""


def build_program(payload: str, loads: list[str]) -> str:
    load_block = "\n".join(_LOADS[name] for name in loads)
    return (
        _WRAPPER.replace("%%LOADS%%", load_block)
        .replace("%%PAYLOAD%%", payload)
        .replace("%%BEGIN%%", _SENTINEL_BEGIN)
        .replace("%%END%%", _SENTINEL_END)
    )


def run(payload: str, loads: list[str] | None = None, timeout: float = 60.0) -> dict:
    """Evaluate a WL payload; return the structured result dict described above."""
    loads = loads or []

    # Preflight: no kernel == no result. Say so plainly with a dedicated status
    # rather than crashing on FileNotFoundError; the skill never falls back to a
    # second engine, so the honest answer here is "could not run".
    if shutil.which("wolframscript") is None:
        return {
            "status": "no-kernel",
            "result": None,
            "tex": None,
            "head": None,
            "messages": [],
            "seconds": None,
            "detail": "wolframscript not found on PATH -- no Wolfram kernel available "
                      "to run this. Nothing was verified.",
        }

    program = build_program(payload, loads)

    with tempfile.NamedTemporaryFile(
        "w", suffix=".wl", delete=False, encoding="utf-8"
    ) as fh:
        fh.write(program)
        script_path = fh.name

    try:
        proc = subprocess.run(
            ["wolframscript", "-file", script_path],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return {
            "status": "timeout",
            "result": None,
            "tex": None,
            "head": None,
            "messages": [],
            "seconds": None,
            "detail": f"wolframscript exceeded {timeout}s",
        }
    finally:
        Path(script_path).unlink(missing_ok=True)

    out = proc.stdout
    begin = out.find(_SENTINEL_BEGIN)
    end = out.find(_SENTINEL_END)
    if begin == -1 or end == -1 or end < begin:
        # No sentinel block: a parse error or hard kernel failure.
        return {
            "status": "error",
            "result": None,
            "tex": None,
            "head": None,
            "messages": [],
            "seconds": None,
            "detail": (proc.stderr or out or "no output from kernel").strip()[:2000],
        }

    raw = out[begin + len(_SENTINEL_BEGIN) : end].strip()
    try:
        assoc = json.loads(raw)
    except json.JSONDecodeError as exc:
        return {
            "status": "error",
            "result": None,
            "tex": None,
            "head": None,
            "messages": [],
            "seconds": None,
            "detail": f"could not parse kernel JSON: {exc}",
        }

    messages = assoc.get("messages") or []
    if assoc.get("failed"):
        status = "failed"
    elif messages:
        status = "messages"
    else:
        status = "ok"

    return {
        "status": status,
        "result": assoc.get("result_inputform"),
        "tex": assoc.get("result_tex"),
        "head": assoc.get("head"),
        "messages": messages,
        "seconds": assoc.get("seconds"),
    }


_EXIT = {"ok": 0, "messages": 1, "failed": 1, "timeout": 2, "error": 2, "no-kernel": 2}


def _read_payload(args: argparse.Namespace) -> str:
    if args.code is not None:
        return args.code
    if args.file is not None:
        return Path(args.file).read_text(encoding="utf-8")
    return sys.stdin.read()


def _cmd_run(args: argparse.Namespace) -> int:
    result = run(_read_payload(args), loads=args.load, timeout=args.timeout)
    print(json.dumps(result, indent=2 if args.pretty else None))
    return _EXIT[result["status"]]


def _cmd_selftest(args: argparse.Namespace) -> int:
    cases = [
        ("clean eval", "1 + 1", [], "ok"),
        (
            "definite integral -> tex",
            "Integrate[Exp[-x^2]*Cos[a*x], {x, -Infinity, Infinity},"
            " Assumptions -> a \\[Element] Reals]",
            [],
            "ok",
        ),
        ("message surfaced", "1/0", [], "messages"),
        ("unevaluated (head reveals non-closure)", "Integrate[Sin[x^x], x]", [], "ok"),
        ("ogre loads (suppressed)", "Length[Names[\"OGRe`*\"]]", ["ogre"], "ok"),
        ("xact loads (suppressed)", "Length[Names[\"xAct`xTensor`*\"]]", ["xact"], "ok"),
    ]
    ok = True
    for name, payload, loads, expect in cases:
        res = run(payload, loads=loads, timeout=150)
        passed = res["status"] == expect
        ok = ok and passed
        flag = "PASS" if passed else "FAIL"
        print(
            f"[{flag}] {name}: status={res['status']} (want {expect}) "
            f"head={res['head']} result={res['result']} "
            f"msgs={res['messages']} t={res['seconds']}"
        )
        if res["tex"]:
            print(f"         tex: {res['tex']}")
    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Wolfram Language kernel harness.")
    sub = parser.add_subparsers(dest="command", required=True)

    p_run = sub.add_parser("run", help="evaluate a WL payload")
    src = p_run.add_mutually_exclusive_group()
    src.add_argument("--code", help="WL payload as a string")
    src.add_argument("--file", help="path to a file containing the WL payload")
    p_run.add_argument(
        "--load",
        action="append",
        default=[],
        choices=sorted(_LOADS),
        help="package(s) to load before the payload (repeatable)",
    )
    p_run.add_argument("--timeout", type=float, default=60.0)
    p_run.add_argument("--pretty", action="store_true")
    p_run.set_defaults(func=_cmd_run)

    p_self = sub.add_parser("selftest", help="run a built-in battery of checks")
    p_self.set_defaults(func=_cmd_selftest)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
