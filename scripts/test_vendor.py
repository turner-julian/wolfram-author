#!/usr/bin/env python3
"""Drift test: wolfram-author's vendored copies must match wolfram-core.

The skill bundles copies of wolfram-core's shared engine (see vendor.py for
why). They rot silently when wolfram-core changes and no one re-syncs -- which
is exactly how a removed `--load` bundle and a stale lib slipped in before. This
test fails when any vendored file drifts from the canonical source, so the rot
is caught at authoring time instead of at runtime.

It is a thin wrapper over `vendor.py --check`: pure file comparison, no kernel,
no deps. When wolfram-core is absent (the Cowork sandbox), vendor.py exits 0 and
this test passes vacuously -- the consumer sandbox has nothing to compare against.

    python3 -m pytest scripts/test_vendor.py
    # or, without pytest:
    python3 scripts/vendor.py --check
"""
import subprocess
import sys
from pathlib import Path

VENDOR = Path(__file__).resolve().parent / "vendor.py"


def test_vendored_files_match_wolfram_core():
    proc = subprocess.run([sys.executable, str(VENDOR), "--check"],
                          capture_output=True, text=True)
    assert proc.returncode == 0, (
        "vendored copies have drifted from wolfram-core; "
        "run `python3 scripts/vendor.py` to re-sync.\n" + proc.stdout + proc.stderr)


if __name__ == "__main__":
    raise SystemExit(test_vendored_files_match_wolfram_core() or 0)
