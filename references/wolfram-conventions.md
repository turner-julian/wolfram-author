# Wolfram Language conventions, GR conventions, and OGRe gotchas

## GR sign / index conventions (pinned, verified against OGRe on AdS4)

The library's curvature operators use these, and they match OGRe componentwise
(checked on AdS4 Poincaré — built-in `EquivalentQ` OGRe is True):

- **Christoffel** (Levi-Civita): `Gamma^a_bc = 1/2 g^as (d_b g_sc + d_c g_sb - d_s g_bc)`.
- **Riemann (mixed)**: `R^r_smn = d_m Gamma^r_ns - d_n Gamma^r_ms + Gamma^r_ml Gamma^l_ns - Gamma^r_nl Gamma^l_ms`.
- **Riemann (lowered)**: `R_rsmn = g_ra R^a_smn`, index order `(rho sigma mu nu)`.
- **Ricci**: `R_sn = R^m_smn`. **Ricci scalar**: `R = g^sn R_sn`.
- **Weyl**: `C_{abcd} = R_{abcd} - (2/(D-2))(g_{a[c}R_{d]b} - g_{b[c}R_{d]a}) + (2/((D-1)(D-2))) R g_{a[c}g_{d]b}`.
  Vanishes identically in D<=3. For conformally flat spaces (includes all maximally symmetric): C=0.
  For vacuum (Ricci-flat): C = R (Weyl equals Riemann).
- **Einstein**: `G_{mu nu} = R_{mu nu} - (1/2) R g_{mu nu}`.
  Trace: `g^{mn} G_{mn} = -(D-2)/2 R`. For vacuum without cosmological constant: G=0.
- **Traceless Ricci**: `S_{mu nu} = R_{mu nu} - (1/D) R g_{mu nu}`.
  Trace: `g^{mn} S_{mn} = 0` by construction.
- **Killing equation**: `nabla_(mu) xi_(nu) + nabla_(nu) xi_(mu) = 0`, or in Christoffel form:
  `d_mu xi_nu + d_nu xi_mu - 2 Gamma^a_{mu nu} xi_a = 0`.
  D(D+1)/2 independent equations for D unknown functions.

Convention-independent invariants for a maximally symmetric space (curvature
radius L, dimension D) — use as sanity checks:
`R = -D(D-1)/L^2`, Kretschmann `R_{abcd}R^{abcd} = 2 D(D-1)/L^4`. AdS4: `-12/L^2`,
`24/L^4`. The Kretschmann scalar is fully convention-independent (sum of squares),
so it is the most robust check that curvature code is right.

Default physics conventions (unless the request overrides): natural units
ℏ = c = 1, mostly-plus signature `(-,+,+,+)`. State any convention you rely on.

## OGRe gotchas (these cost real debugging — don't re-hit them)

- **`TNewCoordinates` is `HoldRest`** (it clears/protects the coordinate symbols).
  You must inject the coordinate list literally, e.g.
  `With[{c = Coords[g]}, OGRe`TNewCoordinates[id<>"Coords", c]; ...]`.
  Passing `OGRe`TNewCoordinates[id, Coords[g]]` hands it the *unevaluated*
  `Coords[g]` and OGRe aborts with `TMessage::ErrorDoesNotExist`.
- **Unique object IDs per call.** OGRe enforces unique IDs; reusing an ID (e.g.
  under `RepeatedTiming`, which re-runs many times) errors. Generate
  `ToString[Unique["MAm"]]` per invocation (or `TSetAllowOverwrite[True]`).
- **Do not empty the message channel while OGRe computes.** OGRe drives its
  simplification-progress through messages; evaluating under `Block[{$Messages = {}}, …]`
  makes it `Abort[]`. The harness payload block uses only `$MessageList = {}`
  (capture) and never rebinds `$Messages`. Package *loading* may suppress
  `$Output` (the banner) — that is fine; the abort is specific to compute time.
- **Auto-update check on load** is disabled persistently via `TSetAutoUpdates[False]`
  (the harness's `ogre` loader does this), avoiding a network call at startup.
- OGRe is component-based and easy, but its object-system overhead makes it
  *slower than plain array math* for explicit known metrics (≈9–10× on AdS4). It
  wins on convenience and on harder symbolic simplification, not raw speed here.

## Loading the library in a delivered script

A delivered script must run as-is with a bare `wolframscript -file script.wl` —
no `--load` flags, no reliance on anything being pre-loaded. Load via `init.wl`
at the repo root and call functions with **full context prefixes**:

```wolfram
Get["/path/to/mathematica-author/init.wl"];
(* This sets $CTLibDir and loads CT.wl + GR.wl *)

riem = GRT`RiemannFromMetric[g];   (* full prefix, not bare Needs *)
```

For scripts that live inside the repo (examples, evals), use a relative path:
```wolfram
Get[FileNameJoin[{ParentDirectory[DirectoryName[$InputFileName]], "init.wl"}]];
```

**What went wrong in the "Riemann tensor AdS 5" session** (the bug `init.wl`
prevents): the script used `Needs["GRT`"]` and ran with `--load mauthor`.
But the GR operators live in `GR.wl`, which only `--load gr` loads; `GRT``
is not on `$Path`, so the operators were undefined. `init.wl` loads both packages
unconditionally.

- **Rule:** `--load ct|grt|ogre|xact` is only for ad-hoc `wolfram.py run
  --code '<one-liner>'`. A delivered file never depends on `--load` — it loads
  via `init.wl`.
- Quality-gate the file exactly as the user will run it: `wolfram.py run --file
  script.wl` with **no** `--load`.

## No second engine

Verification is Wolfram-only. If the kernel can't run (`wolfram.py` status
`no-kernel`) or can't close a check, report "not verified" and stop — never fall
back to SymPy. `verify_bridge.py` is opt-in, for when the user explicitly asks
for a cross-engine check; it is never automatic.

## Output marshaling

- Machine-readable: `ToString[expr, InputForm]`. Display: `ToString[TeXForm[expr]]`.
  Bare `Print[InputForm[expr]]` / `Print[TeXForm[expr]]` do **not** render the
  wrapper in `wolframscript` — they print `InputForm[…]` literally. The harness
  marshals correctly; if you print yourself, use `ToString[…, form]`.
- `MatrixForm`/`TableForm` render as grids in a notebook but show as the literal
  wrapper in `wolframscript` text output. Fine for notebook-bound deliverables;
  for CLI-readable output print the raw list or `ToString[…, InputForm]`.

## Speed idioms (preserve accuracy)

- vectorized / `Listable` operations over `Table`/`Do` loops;
- `SymmetrizedArray` / sparse arrays for high-rank tensors;
- compute shared intermediates once (Christoffels once, reuse for Riemann/Ricci);
- targeted simplification: `Simplify[expr, Assumptions -> …]` / `Refine`, not
  reflexive `FullSimplify` (often 10–100× slower);
- `$HistoryLength = 0` in scripts to avoid `Out[]` memory growth;
- measure with `RepeatedTiming` (median of many), never a single noisy `Timing`.

## xAct (installed, deferred to on-demand)

xAct/xTensor (v1.3.0) is the abstract-index, canonicalization-heavy suite — add it
as a benchmark candidate (and write a `canonical <-> xAct` adapter) the moment a
request involves abstract/symbolic tensor work where component methods blow up.
For explicit-coordinate curvature of a known metric it is overkill.
