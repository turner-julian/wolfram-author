# Evals (milestone 6)

Two independent loops harden the skill. They are deliberately separate because
they measure different things and have very different cost.

1. **Code-gen quality** — does a generated script actually compute the right
   thing? Graded by machine checks (real kernel + convention-independent
   invariants + cross-engine scalar confirmation), never by an LLM judge. This
   is the skill's structural advantage: correctness here is mechanically
   decidable, so we decide it mechanically.
2. **Triggering accuracy** — does Claude reach for this skill on the right
   requests and *not* on verify-math's (audit an existing result) or on
   non-Mathematica work? Optimized with the skill-creator description loop.

## 1. Code-gen quality — `evals/run_codegen_eval.py`

```
python3 evals/run_codegen_eval.py run evals/cases/<case>.json   # one case
python3 evals/run_codegen_eval.py selftest                      # every case
```

Exit 0 iff all assertions pass (same convention as `scripts/*.py selftest`).
The harness reuses `scripts/wolfram.py` (kernel) and `scripts/verify_bridge.py`
(Wolfram+SymPy scalar gate) — it adds no new checking logic.

### Case schema (`evals/cases/*.json`)

```json
{
  "id": "schwarzschild-kretschmann",
  "prompt": "<the natural-language request the skill answers>",
  "conventions": "<pinned conventions the answer assumes>",
  "script": "schwarzschild-kretschmann.wl",   // path RELATIVE to this case file
  "loads": [],                                  // extra wolfram.py --load names
  "timeout": 150,                               // optional, seconds
  "assertions": [ ... ]
}
```

`script` is the generated artifact under test. The bundled scripts double as
golden fixtures (they prove the assertions are satisfiable and act as library
regression tests); to grade a freshly generated script, point `script` at it.

Each assertion is evaluated by prepending `Get["<script>"];` to the kernel
payload, so assertions read the globals the script assigns (`ricciScalar`,
`kretschmann`, …). Three kinds:

| `type`   | fields            | passes when |
|----------|-------------------|-------------|
| `wl`     | `expr`, `expect` (default `"True"`) | `expr` evaluates clean and equals `expect` — use for boolean invariants, e.g. `EquivalentQ[riem, <max-symmetric form>]` |
| `scalar` | `wl`, `expect`    | `wl`'s value equals `expect` by `MAuthor`EquivalentQ` in a clean kernel — **Wolfram only**, no second engine; scalars only |
| `head`   | `wl`, `expect`    | `Head[wl] == expect` — assert an honesty signal, e.g. a no-closed-form integral comes back with head `Integrate` |

Every case also gets an automatic **"script runs clean"** check (status `ok`:
no WL messages, not `$Failed`) unless it sets `"skip_clean_check": true`.

### Current cases

- `ads-riemann` — AdS4 Riemann (reuses `examples/ads-poincare-riemann.wl`):
  max-symmetric form, R=-12/L², K=24/L⁴.
- `ads5-riemann` — AdS5 Riemann, **delivered-script pattern** (self-loads
  `lib/` by absolute path, full context prefixes, no `--load`): R=-20/L²,
  K=40/L⁴, Ricci=-(4/L²)g. Regression guard for the Cowork AdS5 failure.
- `schwarzschild-kretschmann` — vacuum (R=0) and K=48M²/r⁶.
- `symbolic-gaussian` — non-GR breadth: ∫e^{-ax²}=√(π/a), Wolfram EquivalentQ.
- `cold-nonclosure` — honesty: ∫e^{x^x} has no closed form; head stays
  `Integrate` and is reported as such, not faked.

### Adding a case

1. Write the prompt + a reference `.wl` in the skill's documented style.
2. Pick convention-independent assertions (invariants/scalars), not
   coordinate-dependent component values.
3. Prefer `scalar` for any mechanically checkable scalar (two engines > one).
4. `python3 evals/run_codegen_eval.py run evals/cases/<new>.json` until green.

## 2. Triggering accuracy — skill-creator loop

`evals/trigger-eval.json` holds 20 queries (10 should-trigger codegen requests,
10 should-not: verify-math audits, proofs, non-Mathematica coding, conceptual
questions). The should-not half is loaded with near-misses against verify-math
because mis-triggering there is the named top risk.

Run the skill-creator optimization loop (it does its own train/test split and
returns a `best_description`):

```
SC=<path-to-skill-creator>   # e.g. ~/.claude/plugins/.../skill-creator/skills/skill-creator
cd "$SC"
python -m scripts.run_loop \
  --eval-set <repo>/evals/trigger-eval.json \
  --skill-path <repo> \
  --model <session-model-id> \
  --max-iterations 5 --verbose
```

Apply the proposed `best_description` to `SKILL.md` **only if** the test-split
score improves over the current description. A quick triggering snapshot without
the full loop: `python -m scripts.run_eval --eval-set <trigger-eval.json>
--skill-name mathematica-author --model <id>`.

## Why not skill-creator's with-skill-vs-baseline benchmark

That flow grades against natural-language expectations with an LLM judge. For
this skill correctness is a kernel computation, so machine checks (loop 1) are a
strictly stronger and cheaper signal. The skill-creator benchmark is reserved
for triggering/description work, where there is no kernel oracle.

## Verification is Wolfram-only

The grader and the skill workflow decide correctness in the Wolfram kernel and
nowhere else. `MAuthor`EquivalentQ` returns True / False / `$Failed`; only an
explicit True passes, so an undecided check fails honestly rather than being
rubber-stamped. SymPy is never consulted automatically. `scripts/verify_bridge.py`
remains on disk for the occasions a user explicitly wants a second-engine
cross-check, but no eval and no workflow step calls it.
