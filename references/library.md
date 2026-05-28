# The curated library (`lib/`)

The library is the only thing `mathematica-author` adds over "base Claude writes
Wolfram Language." It earns its place on exactly two grounds, and nothing enters
it that does not serve both:

1. **Interop / universality.** Packages use incompatible representations (OGRe's
   object system, xAct's abstract indices, raw arrays). The library is a
   *canonical component-level representation* + thin per-package adapters +
   pinned conventions, so a computation can flow across packages without
   re-encoding at every seam. **Narrow by design** -- not a unified abstract
   tensor algebra.
2. **Speed.** Mathematica is slow when used wrong. Every primitive is the winner
   of a `RepeatedTiming` bake-off among >= 2 candidates -- and only after it is
   verified to agree with the others.

Worked demonstration: `examples/ogre-vs-builtin-benchmark.nb` computes AdS5
curvature both ways, confirms built-in `EquivalentQ` OGRe (correctness), and
tables/charts the RepeatedTiming speedup (≈7-11x on an explicit metric).
Regenerate it with `wolframscript -file examples/ogre-vs-builtin-benchmark.wl`.

## Canonical representation (`CT.wl`)

A tensor in a coordinate basis is fully specified by its components, index
positions, the metric it lives with, and conventions. `Tensor` packages this as
a self-contained Association (self-contained so it survives the stateless,
one-shot kernel calls the harness makes):

```
Tensor[coords, indices, components, metric, conventions]
  coords       e.g. {t, r, \[Theta], \[Phi]}
  indices      list of "up"/"down", length = rank
  components   array in the coordinate basis
  metric       all-down metric components in the same coords (or Automatic)
  conventions  <|"signature" -> ..., "riemann" -> ..., ...|>
```

Accessors: `Coords Components Indices Metric Conventions Dim Rank`.
Predicate: `TensQ`.

Per-package adapters (`canonical <-> OGRe`, `canonical <-> built-in`, and
`canonical <-> xAct` on demand) are added in later milestones, each gated by the
promotion rules below.

## `EquivalentQ` -- the correctness gate

`EquivalentQ[a, b]` -> `True` / `False` / `$Failed` (undecided):
- **scalars / expressions**: `PossibleZeroQ[a-b]`, then `FullSimplify[a-b]===0`,
  then a randomized numeric spot-check (12 positive-real samples; positive to
  dodge spurious branch-cut values). Symbolic *and* numeric must agree.
- **arrays**: same `Dimensions`, then elementwise.
- **canonical tensors**: same coords + index positions, then components
  elementwise. Metric/conventions are metadata, not part of identity.

`$Failed` (undecided) is a first-class outcome: it blocks promotion rather than
faking certainty.

## Tensor algebra operations (added 2026-05-28)

**CT.wl** additions — general tensor algebra on the canonical Tensor:
- `Raise[t, n]` / `Lower[t, n]` — index raising/lowering. Dot-based:
  `Transpose` target index to position 1, `Dot` with `ginv`, `Transpose` back.
  Inverse metric cached in `$Cache`.
- `Trace[t, {i,j}]` — trace over one up + one down index. `TensorContract`.
- `Product[t1, t2]` — outer product (`Outer[Times, ...]`).
- `Contract[t1, i, t2, j]` — contract two tensors. `Trace[Product[...]]`.
- `Transform[t, newCoords, rules]` — coordinate transform. `rules` is the
  backward map. Computes backward Jacobian, substitutes, contracts each index.

**GRT.wl** additions — connection-dependent operations:
- `CovariantDFromMetric[t, g]` — partial derivative + Gamma corrections (one
  per tensor index, each via Dot). Prepends one "down" derivative index.
- `GeodesicEquationsFromMetric[g, param]` — geodesic ODEs as expressions == 0.

**Cache** — `$Cache` (shared Association). Stores inverse metrics +
Christoffel arrays. Keyed by `Hash`. `CacheClear[]` resets. Cross-package
access via `CacheStore`/`CacheGet`.

**Testing notebook**: `examples/tensor-algebra-tests.nb` — exercises all
operations on Schwarzschild + AdS4 with correctness checks and timing.

## Promotion gate (`bench.py`) -- hard rules

A function enters `lib/` only if **all** hold:

1. **Needed by a real problem** -- no speculative entries. One-off or
   domain-novel code stays in the generated script; it is not promoted.
2. **Benchmarked** against >= 1 alternative via `bench.py` (`RepeatedTiming`).
3. **Verified equivalent** to a reference implementation (`EquivalentQ` -> True
   for every candidate pair; any `False`/`$Failed` blocks it).
4. **Documented** with its representation contract and conventions, and
   registered in `index.json`.

`bench.py` returns `promotable: true` only when 2--4 are satisfied for the
candidate set. Library internals are optimized + tested; the top-level code
emitted to the user stays documented + readable.

## `index.json` -- the manifest

`{"entries": [ <entry>, ... ]}`. Each entry records what the function is, its
representation contract, and the benchmark + equivalence evidence that justified
promotion:

```json
{
  "name": "RiemannFromMetric",
  "file": "GR/Curvature.wl",
  "context": "CT`",
  "signature": "RiemannFromMetric[metric_?TensQ]",
  "summary": "Riemann tensor R[down,down,down,down] from a canonical metric.",
  "representation": "input + output are canonical CTensors",
  "conventions": {"signature": "mostly-plus", "riemann": "MTW"},
  "depends_on": ["CT", "ChristoffelFromMetric"],
  "packages": ["ogre"],
  "benchmark": {
    "date": "2026-05-28",
    "problem": "AdS4 in Poincare coordinates",
    "method": "RepeatedTiming",
    "candidates": [
      {"id": "ogre", "seconds": 0.42},
      {"id": "builtin-array", "seconds": 0.07}
    ],
    "winner": "builtin-array"
  },
  "equivalence": {"verified": true, "method": "EquivalentQ", "reference": "ogre"}
}
```

Required fields: `name`, `file`, `context`, `signature`, `summary`,
`representation`, `conventions`, `depends_on`, `benchmark` (with `winner`),
`equivalence` (with `verified: true`).
