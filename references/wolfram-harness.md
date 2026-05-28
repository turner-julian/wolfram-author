# Wolfram kernel harness (`scripts/wolfram.py`)

The shared substrate every higher layer of `mathematica-author` runs WL through.
Stdlib-only Python (no venv); requires `wolframscript` on PATH.

## Invocation

```bash
# evaluate a payload
python3 scripts/wolfram.py run --code '<WL>' [--load ogre] [--load xact] [--timeout 60] [--pretty]
python3 scripts/wolfram.py run --file payload.wl
echo '<WL>' | python3 scripts/wolfram.py run

# built-in battery (proves the harness works end to end)
python3 scripts/wolfram.py selftest
```

Importable too: `from wolfram import run; run(payload, loads=["ogre"], timeout=60)`.

## Result protocol

```json
{"status": "ok|messages|failed|timeout|error",
 "result": "<InputForm string>", "tex": "<TeXForm string>",
 "head": "Integrate", "messages": ["HoldForm[Power::infy]"], "seconds": 0.013}
```

Exit code: `0` ok, `1` messages/failed, `2` timeout/error.

Status meaning:
- `ok` — evaluated, no messages, not `$Failed`/`$Aborted`.
- `messages` — evaluated but WL emitted messages (recorded in `messages`).
- `failed` — result is `$Failed`/`$Aborted` or contains one.
- `timeout` — kernel exceeded `--timeout`.
- `error` — nonzero exit, parse error, or no result block (hard failure).

## Honesty contract (why the harness is shaped this way)

A naive `wolframscript` shell-out hides two failure modes; the harness exposes
both and hides neither:

1. **Messages print to stdout, not stderr.** Captured via a `$MessageList`
   block and returned in `messages`; message *output* is muted only to avoid
   console-format cost, never to discard the record.
2. **An unevaluated expression looks like a real answer.** `Integrate[Sin[x^x],x]`
   comes back verbatim with no message. The harness can't know generically that
   this is non-closure, so it surfaces `head`: when `head` equals the operator
   the caller asked to evaluate (`Integrate`, `Sum`, `Solve`, ...), treat it as
   *did not close*, not a result.

The harness never decides whether `messages`/`failed`/a suspicious `head` is
fatal — that judgment is the caller's. The harness only guarantees the signals
are present. JSON is delimited by `<<<WLJSON>>>`/`<<<WLEND>>>` sentinels so
package banners before it are harmless.

## Speed practices

Baked into the harness:
- `$HistoryLength = 0` — no `Out[]` accumulation.
- message stream redirected during evaluation — no per-message console format.
- packages loaded with output suppressed; OGRe load also persists
  `TSetAutoUpdates[False]` so later loads skip the network update check.
- **no automatic `FullSimplify`** — the classic slow trap. Simplification level
  is always the caller's explicit choice.

Required of library code that runs through it (Mathematica is slow when used
wrong — these preserve speed at no cost to accuracy):
- vectorized / `Listable` ops over `Table`/`Do` loops;
- `SymmetrizedArray` / sparse for high-rank tensors;
- compute shared intermediates once (e.g. Christoffels) and reuse;
- target simplification (`Simplify` with `Assumptions`, `Refine`) rather than
  reflexive `FullSimplify`;
- `RepeatedTiming` (not single `Timing`) for benchmark decisions.

## Packages

- `--load ogre` — OGRe v1.7.0, `Get` from `~/Documents/Wolfram Mathematica/OGRe.m`
  (loose `.m`, not on the app path). Component-based GR.
- `--load xact` — xAct/xTensor v1.3.0 via `Needs["xAct`xTensor`"]` (on the app
  path). Abstract-index tensor algebra + canonicalization.

## Deferred

Persistent kernel via `wolframclient` `WolframLanguageSession` — load OGRe/xAct
once and keep state across evaluations. `run()` is shaped so this can back it
without changing callers. Add when batch / tensor-heavy work makes per-call
kernel startup and package reload the bottleneck.
