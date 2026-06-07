#!/usr/bin/env python3
"""Vendor wolfram-core's shared engine into wolfram-author.

wolfram-author ships as a self-contained skill bundle (a CLI symlink AND a
Cowork zip). The Cowork sandbox has no `~/code/wolfram-core` to reference, so
the shared engine -- the WL library, the kernel harness, the registry tooling,
and the capability catalog -- is COPIED in rather than imported by path. That is
why these files are duplicates of wolfram-core's; the bundle must stand alone.

This script is the ONLY sanctioned way to refresh those copies. Run it after
wolfram-core changes; never hand-edit a vendored file (the change would be lost
on the next sync and would fail `--check`).

    python3 scripts/vendor.py            # copy the canonical files in (sync)
    python3 scripts/vendor.py --check    # exit 1 if any copy drifted (drift test)

Source repo: $WOLFRAM_CORE_DIR (default ~/code/wolfram-core). When it is absent
-- e.g. inside the Cowork sandbox, which only has the already-vendored copies --
both modes no-op with exit 0. Drift is an authoring-time invariant checked where
the canonical source exists (local / CI), not in the consumer sandbox.
"""
from __future__ import annotations

import filecmp
import os
import shutil
import sys
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
CORE = Path(os.environ.get("WOLFRAM_CORE_DIR", Path.home() / "code" / "wolfram-core"))

# Files vendored verbatim from wolfram-core (identical relative path in each
# repo). The WL library, the three harness/tooling scripts, and the registry.
# NOT vendored: session.py (wolfram-core-only), verify_bridge.py (wolfram-author
# owns it), wolfram-core's own test_*.py.
VENDORED = [
    "lib/core.wl", "lib/tensor.wl", "lib/gr.wl", "lib/qec.wl",
    "lib/decide.wl", "lib/derivation.wl", "lib/display.wl", "lib/init.wl",
    "scripts/wolfram.py", "scripts/registry.py", "scripts/gate.py", "scripts/bench.py",
    "registry.json",
]


def main() -> int:
    check = "--check" in sys.argv[1:]
    if not CORE.is_dir():
        print(f"wolfram-core not found at {CORE} (set WOLFRAM_CORE_DIR); skipping.",
              file=sys.stderr)
        return 0  # absent upstream is not a drift failure (e.g. Cowork sandbox)

    drift: list[str] = []
    copied: list[str] = []
    for rel in VENDORED:
        src, dst = CORE / rel, SKILL_DIR / rel
        if not src.is_file():
            print(f"MISSING upstream: {rel}", file=sys.stderr)
            drift.append(rel)
            continue
        same = dst.is_file() and filecmp.cmp(src, dst, shallow=False)
        if check:
            if not same:
                drift.append(rel)
        elif not same:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            copied.append(rel)

    if check:
        if drift:
            print("vendor DRIFT (run: python3 scripts/vendor.py)")
            for rel in drift:
                print(f"  {rel}")
            return 1
        print(f"vendor: in sync ({len(VENDORED)} files)")
        return 0

    if copied:
        print(f"vendored {len(copied)} file(s) from {CORE}:")
        for rel in copied:
            print(f"  {rel}")
    else:
        print(f"vendor: already in sync with {CORE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
