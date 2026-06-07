---
name: wolfram-author
description: >-
  Write good, well-documented, runnable Wolfram Language / Mathematica code for a
  computational request, and return the code (not just an answer) so the user can
  run, read, and extend it. Use this whenever the user asks you to *produce
  Mathematica/Wolfram code* or to *compute something in Mathematica/Wolfram* —
  "write Mathematica code to…", "give me Wolfram Language for…", "compute the
  Riemann/Ricci/Einstein tensor of this metric", "set up this calculation in
  Mathematica", tensor/GR computations (metrics, curvature, OGRe/xAct), symbolic
  integrals/series/algebra meant to be run, etc. Distinct from verify-math: this
  GENERATES code for the user to own; verify-math CHECKS a claim the user already
  has. If the user only wants their existing result audited, prefer verify-math.
---

# wolfram-author

## Why this skill exists

Base Claude can already write Wolfram Language. The one thing this skill adds is a
**curated, benchmark-gated library** (`lib/`) that makes generated code faster and
lets multi-package computations compose — plus the discipline to hand the user
*auditable code*, not a black-box answer.

That is the load-bearing idea: **the code is the product.** The user reads it,
runs it, and extends it, so *the user is the verification layer*. Your job is not
to be trusted — it is to produce code that is correct by construction, idiomatic,
documented, and runnable, and to be honest about what you did and didn't confirm.

A result is only "right" once it has been run and sanity-checked — your confidence
does not make it so. Where the kernel can decide a claim (a scalar identity, a
curvature invariant), check it **in the Wolfram kernel** and report the verdict
honestly. If the kernel can't run or can't close the check, the result is *not
verified* — say so. Never reach for a second engine to paper over a missing or
failed Wolfram run.

## The deliverable contract

Every response produces a **runnable, well-documented script** (or notebook-ready
cell sequence), not a bare answer. It must:

- open with a short header stating the **math and the conventions** (signature,
  index order, coordinates, parameters) — see `references/wolfram-conventions.md`;
- be **composed from library primitives** where they exist, and runnable as-is;
- show the **result** and the **sanity checks** you ran;
- end with an explicit **verification status**: what was confirmed (ran clean,
  sanity-checked in-kernel) and what the user must still check themselves — and
  if it could not be run, say that plainly instead.

The answer itself is a byproduct — always give the user the code that produced it.

## Notebook (.nb) output

`.nb` files are read-only display artifacts; all computation happens in `.wl`
files. When generating a `.nb`, optimize for visual clarity:

- **Notebook-level options**: `DefaultOutputFormatType -> TraditionalForm`,
  `DefaultNewCellStyle -> "Input"`, `StyleDefinitions -> "Default.nb"`.
- **Named characters** for Greek coordinates: `\[Theta]`, `\[Phi]`, etc.
- **No Print for results.** Use `Column`/`Row`/`Grid` so output goes to Output
  cells where TraditionalForm applies. Print produces plain-text cells that
  bypass TraditionalForm. Print is acceptable only for status messages and
  per-operation timing lines.
- **Typeset math in labels** via `HoldForm[Subsuperscript[...]]`, etc.
- **MatrixForm** for component display: `expr // MatrixForm`.

## Per-request workflow

1. **Restate** the request and fix conventions (metric signature, index ordering,
   coordinate names, AdS radius, branch/domain). State each as given or assumed.
2. **Decompose** into the operations needed (e.g. metric → Christoffel → Riemann).
3. **Reuse the library.** Check `lib/registry.json` for primitives that cover the
   operations; compose them. Prefer the registered winner (it is the fast,
   equivalence-verified implementation).
4. **New primitive? Gate it.** If an operation is missing *and* it is (a) needed
   by this real request and (b) likely to recur or benefits from interop/speed:
   write ≥2 candidate implementations, run `bench.py` to time + verify
   equivalence, and **only if `promotable`** add the winner to `lib/` and register
   it in `registry.json` (with its benchmark + equivalence record). Otherwise write
   it inline in the generated script and do **not** promote it. No speculative
   library entries — see Governance.
5. **Assemble** the top-level script: documented header, composed from primitives,
   readable. **Load the library via `init.wl`** — begin the script with
   `Get["/path/to/wolfram-author/init.wl"]` which sets `$CTLibDir`
   and loads Core`, Tensor`, and GR`. Call functions with their **full
   context prefixes** (`Tensor`Field`, `GR`Riemann`). The
   delivered file must run as-is with a bare `wolframscript -file script.wl`,
   no flags. `--load` is only for ad-hoc `run --code` one-liners; **never let
   a delivered script depend on `--load` or on `Needs` of an unloaded context**
   — that is exactly the AdS5 failure. See `references/wolfram-conventions.md`
   for detail.
6. **Quality gate — Wolfram only.** Run the script with `wolfram.py` against the
   local kernel and sanity-check in-kernel via `Core`EquivalentQ`: dimensions,
   limiting cases, symmetry, known special cases (e.g. AdS maximally symmetric:
   `R = -D(D-1)/L²`, Kretschmann `2D(D-1)/L⁴`). **There is no second engine.** If
   `wolfram.py` returns `no-kernel` (no `wolframscript` on PATH), `timeout`,
   `failed`, `messages`, or a `head` equal to the operator you asked to evaluate
   (non-closure), the result is **not verified** — state that plainly and stop.
   Do **not** substitute SymPy, and do **not** present an unrun script as if it
   were confirmed. `scripts/verify_bridge.py` (Wolfram + SymPy) exists only as an
   explicit, user-requested cross-check — never invoke it automatically, and
   never as a fallback when the kernel is unavailable.
7. **Deliver**: the documented code + the result + how to run it + the
   verification status split.

## Using the tools

Run from this skill's directory.

**Kernel harness** — `scripts/wolfram.py` (stdlib only; needs `wolframscript`):

```
python3 scripts/wolfram.py run --code '<WL>' [--load core|tensor|gr|qec] [--timeout N]
python3 scripts/wolfram.py run --file payload.wl
python3 scripts/wolfram.py selftest
```

Returns JSON `{status, result, tex, head, messages, seconds}`. **Honesty signals
you must respect:** `status` of `messages`/`failed`/`timeout`/`error` is not a
clean result; and a `head` equal to the operator you asked to evaluate
(`Integrate`, `Solve`, `Sum`…) means it *did not close* — never report that as an
answer. Full protocol: `references/wolfram-harness.md`.

**Tensor algebra** — `lib/tensor.wl` (context `Tensor``) index manipulation,
contraction, and coordinate transforms (all use Dot-based contraction for speed):

```
Tensor`Field[coords, indices, components, metric, conventions]
Tensor`Raise[t, n]           (* raise index n; infers metric from t *)
Tensor`Raise[t, n, g]       (* raise using explicit metric g *)
Tensor`Lower[t, n]           (* lower index n *)
Tensor`Trc[t, {i, j}]       (* contract indices i,j (one up, one down) *)
Tensor`Prod[t1, t2]         (* tensor (outer) product *)
Tensor`Contract[t1, i, t2, j]  (* contract index i of t1 with j of t2 *)
Tensor`Transform[t, newCoords, rules]  (* coord transform; rules = backward map *)
```

**GR operations** — `lib/gr.wl` (context `GR``) curvature decomposition,
covariant derivative, geodesics, and symmetry analysis (cached Christoffels):

```
GR`Christoffel[g]         (* Christoffel symbols Gamma^a_bc *)
GR`Riemann[g]             (* all-lower Riemann R_{rho sigma mu nu} *)
GR`Ricci[g]               (* Ricci tensor R_{mu nu} *)
GR`RicciScalar[g]         (* Ricci scalar *)
GR`Kretschmann[g]         (* Kretschmann scalar R_{abcd}R^{abcd} *)
GR`Weyl[g]                (* Weyl tensor C_{rho sigma mu nu} *)
GR`Einstein[g]            (* Einstein tensor G_{mu nu} *)
GR`TracelessRicci[g]      (* traceless Ricci S_{mu nu} *)
GR`Killing[g]             (* Killing equation PDE system *)
GR`CovariantD[t, g]       (* nabla of t w.r.t. metric g; prepends down index *)
GR`Geodesic[g]            (* geodesic ODEs; coords -> functions of lambda *)
GR`Hamiltonian[g, p]      (* geodesic Hamiltonian g^{mu nu} p_mu p_nu *)
```

**Core** — `lib/core.wl` (context `Core``): `Core`EquivalentQ[a, b]` (True /
False / $Failed), `Core`CacheClear[]`, conventions, shared computation cache.

**Cache** — `Core`CacheClear[]` resets the shared cache (inverse metrics +
Christoffels). Christoffel computation is shared across `GR`Christoffel`,
`GR`Riemann`, `GR`CovariantD`, and `GR`Geodesic`.

**Promotion gate** — `scripts/bench.py` (the only way code enters `lib/`):

```
python3 scripts/bench.py run spec.json   # {"setup","loads","candidates":[{"id","expr"}]}
```

Times each candidate with `RepeatedTiming`, checks all are `EquivalentQ` to the
reference, returns the winner and `promotable` (true only if ≥2 candidates, all
clean, all equivalent). Disagreement or undecided equivalence blocks promotion.

**Cross-engine scalar gate (opt-in only, currently inert)** — `scripts/verify_bridge.py`:

```
python3 scripts/verify_bridge.py check --wl '<WL result>' --expect '<WL expected>'
```

Confirms a scalar equality in **both** Wolfram (`EquivalentQ`) and SymPy. This is
**not** part of the default workflow and is **never** an automatic step or a
fallback — invoke it only when the user explicitly asks for a SymPy second
opinion. Default verification is Wolfram-only (step 6). **As of 2026-06-07
verify-math is removed (archived), so this bridge returns "unavailable" unless
`MAUTHOR_VERIFY_MATH_PATH` points at an external `verify.py`.**

## Evals

Two loops harden the skill (detail in `references/evals.md`):

- **Code-gen quality** — `evals/run_codegen_eval.py` runs a generated script in
  a real kernel and confirms its values against convention-independent
  assertions (curvature invariants, scalars via `Core`EquivalentQ`), Wolfram
  only. Machine-graded, never an LLM judge — correctness here is mechanically
  decidable. `python3 evals/run_codegen_eval.py selftest`; cases in
  `evals/cases/*.json`. Add a case when you cover a new computation worth
  regression-protecting.
- **Triggering** — `evals/trigger-eval.json` (20 queries, near-misses vs
  verify-math) feeds the skill-creator description loop; update the description
  only if the test-split score improves.

## Governance — hard rules for `lib/`

The library earns its place on exactly two grounds: **interop/universality**
(a canonical component representation + thin per-package adapters, so OGRe / xAct /
built-in computations compose) and **speed** (Mathematica is slow when used
wrong). A function enters `lib/` only if **all** hold (full detail in
`references/library.md`):

1. **needed by a real problem** — no speculative entries; one-off code stays inline;
2. **benchmarked** against ≥1 alternative via `bench.py`;
3. **equivalence-verified** to a reference (`EquivalentQ` → True for all pairs);
4. **documented** with its representation contract + conventions, registered in
   `registry.json`.

Keep the representation **narrow** — a tensor is components + index positions +
metric + conventions. Do **not** build a grand unified abstract-index algebra.

## Speed discipline

Carry the practices in `references/wolfram-harness.md`: vectorized/`Listable` over
`Table`/`Do`, `SymmetrizedArray`/sparse for high-rank tensors, compute shared
intermediates once, targeted `Simplify`+`Assumptions` rather than reflexive
`FullSimplify`, `RepeatedTiming` for any speed claim. When two idioms are
plausible, don't guess — benchmark them.

## What this skill cannot do

Be honest about the boundary. It produces *code*; it does not guarantee the code
is correct — that is why the deliverable is auditable and sanity-checked, and why
the user runs it. Cold requests with no library coverage get cold-quality code.
It does not do proofs, modeling judgment, or conceptual arguments; for those, say
so and route them to the user. Overstating what was verified is the one failure
that destroys the skill's value.

## Conventions & packages

GR sign/index conventions are pinned and verified against OGRe on AdS4 (see
`references/wolfram-conventions.md`, which also lists the OGRe gotchas that will
bite if ignored). Follow the user's standing physics conventions (natural units,
mostly-plus signature) unless the request says otherwise, and state any you rely
on. Packages load via `--load`: `core` (equality, cache), `tensor` (index
algebra; implies core), `gr` (GR curvature; implies core + tensor), `qec`
(finite-dim operators; implies core).
