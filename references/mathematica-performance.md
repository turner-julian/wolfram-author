# Mathematica performance guide

Concrete techniques for speeding up symbolic computation in Wolfram
Language, grounded in benchmarked experience from the CT+GRT tensor
algebra library. Every claim cites a measured speedup or regression;
reproduce with `examples/greater2-comparison.wl`.

---

## 1. Exploit algebraic structure before optimizing the evaluator

The biggest wins come from computing less, not computing faster.

### Antisymmetrize once instead of writing redundant terms

The Riemann tensor R^r_{smn} has four terms per component: two
derivatives and two bilinear sums. But the two derivative terms are
the same rank-4 array with indices 3 and 4 swapped, and the two
bilinear terms likewise. Writing all four in a Table body forces
Mathematica to evaluate D[] twice per cell and Sum[] twice per cell.

Instead, build one "PreRiemann" kernel with one derivative + one
bilinear per cell, then recover the full result via Transpose-subtract:

```wolfram
preR = Table[
  D[gamma[[r, n, s]], coords[[m]]]
    + Sum[gamma[[r, m, l]] gamma[[l, n, s]], {l, d}],
  {r, d}, {s, d}, {m, d}, {n, d}];
riemann = $Simplify[preR - Transpose[preR, {1, 2, 4, 3}]];
```

The Transpose-subtract is pure array bookkeeping (no symbolic work).
D[] evaluations drop from 2d^4 to d^4; bilinear Sums from 2d^5 to d^5.
**Measured: 1.4x Riemann speedup on Schwarzschild D=4.**

This generalizes: any quantity built from terms related by a known
symmetry (antisymmetric pairs, cyclic identities) can be computed as
one unsymmetrized kernel plus a cheap symmetry projection.

### Use tensor symmetries in contractions

The Kretschmann scalar K = R_{abcd} R^{abcd} appears to require
raising all 4 indices of R_{abcd} (4 sequential matrix-tensor Dot
contractions). But the Riemann pair symmetry R_{abcd} = R_{cdab}
means:

```
K = Sum R^{ab}_{cd} * R_{ab}^{cd}
```

Only the last 2 indices need raising. The first-pair-raised copy is
obtained by transposing:

```wolfram
rmixed = rdown;
Do[rmixed = contractMatIndex[ginv, rmixed, k, 4], {k, 3, 4}];
K = $Simplify[Total[Transpose[rmixed, {3, 4, 1, 2}] rmixed, 4]];
```

2 Dot contractions instead of 4. Transpose is free.
**Measured: 1.6x Kretschmann speedup.**

### Skip intermediate objects the caller doesn't need

GREATER2 computes Ricci by building the full rank-4 Riemann (256
components in D=4) then tracing. Our RicciFromMetric computes
R^m_{smn} directly as a rank-2 Sum over m — never materializing the
rank-4 array. **Measured: 2.7x faster than GREATER2 on Ricci.**

General principle: if the caller only needs a contraction or trace
of a large intermediate, compute the contracted result directly.

---

## 2. Dot-based contraction vs Table[Sum[...]]

Mathematica's `Dot` uses optimized internal paths (BLAS for packed
numeric arrays, well-tuned symbolic path for explicit expressions).
`Table[Sum[...]]` builds the loop in the evaluator.

To contract a d x d matrix M with the k-th index of a rank-r array
A, use the Transpose-Dot-Transpose pattern:

```wolfram
contractMatIndex[mat_, arr_, k_, rank_] :=
  If[rank <= 1 || k == 1,
    mat . arr,
    Module[{perm = Join[Range[2, k], {1}, Range[k + 1, rank]]},
      Transpose[mat . Transpose[arr, perm], Ordering[perm]]]];
```

This moves index k to position 1 (where Dot contracts it), multiplies,
then moves it back. Cost: O(d^{r+1}) — same asymptotic as
Table[Sum[...]], but with a much smaller constant factor.

**When it wins:** any contraction of a rank-2 object (metric, Jacobian)
with one index of a higher-rank array. Index raising, lowering,
coordinate transformation, metric contraction.

**Caveat:** get the Transpose permutation right. Mathematica's
`Transpose[arr, perm]` sends level p of arr to level perm[[p]] of the
result. The inverse permutation that undoes it is `Ordering[perm]`.
Verify on a small symbolic example before deploying on rank-4 tensors.

---

## 3. Simplify is amortized cost, not waste

This is the most counterintuitive finding.

### The failed experiment

Hypothesis: intermediate Simplify calls are wasteful when the result
feeds more computation. Replace `Simplify[#, TimeConstraint -> 1]&`
with `Cancel[Together[#]]&` on intermediates (pre-Christoffel
derivatives, Riemann lowering, Jacobians). Cancel+Together is O(n)
for rational expressions.

Result: **every downstream operation got slower.**

| Operation       | Regression |
|-----------------|------------|
| Christoffel     | 2.6x slower |
| Kretschmann     | 2.0x slower |
| CoordTransform  | 4.0x slower |

### Why it fails

In a multi-stage symbolic pipeline (Christoffel -> Riemann -> Ricci ->
scalar), each stage's output feeds the next stage's algebra. When stage
N's output is fully simplified, the Dot products and Sums in stage N+1
produce simpler expressions, making N+1's Simplify cheaper. The cost
of intermediate Simplify is recovered — and then some — by reduced
downstream Simplify cost.

Cancel+Together normalizes rationals (common denominator, cancel common
factors) but does not:
- Factor polynomials
- Reduce trigonometric expressions (Sin^2 + Cos^2 -> 1)
- Recognize structural zeros
- Simplify nested radicals

The un-normalized intermediates compound through Dot products, producing
bloated expressions that hit Simplify's TimeConstraint at the next
stage.

### When Cancel+Together IS appropriate

- Final scalar results where no further symbolic algebra follows
- Expressions known to be purely rational (no trig, no roots, no
  special functions)
- Quick normalization before a numeric evaluation

### Simplify tuning knobs

**TimeConstraint.** `Simplify[#, TimeConstraint -> 1]&` caps time
spent on each transformation attempt. Good default for GR pipelines
where most components are simple but a few can be complex. For
scalar-only final results, consider removing the cap.

The two-argument form `TimeConstraint -> {t_local, t_total}` caps both
per-transformation and total time. Useful when you want to allow more
exploration but still bound total wall-clock.

**TransformationFunctions.** Restricting to an explicit list like
`{Factor, Expand, Together, Cancel, TrigReduce}` is the single most
effective per-call speed lever — it prevents Simplify from exploring
irrelevant transformation paths. But it risks missing needed transforms
for non-standard expressions (Bessel functions, hypergeometrics).
**Benchmark on your actual expressions before committing to a restricted
set.**

**ComplexityFunction.** Custom complexity penalties can steer Simplify
away from unwanted forms (e.g., penalize Csc/Sec if you want Sin/Cos).
Rarely needed for GR.

---

## 4. Memoization and caching

### Two patterns

**Hash-keyed Association cache (CT+GRT approach):**

```wolfram
cachedChristoffel[coords_, gdown_] := Module[
  {key = {"christoffel", Hash[{coords, gdown}]}, c},
  c = $Cache[key];
  If[MissingQ[c], $Cache[key] = christoffelArray[coords, gdown], c]];
```

Explicit cache stored in a package-level Association `$Cache`. Cleared
by `CacheClear[]`. Advantages: clearable per-key or globally,
inspectable, shareable across packages (CT and GRT share one cache).

**DownValues idiom (GREATER2 approach):**

```wolfram
Christoffel[metric_, x_] := Christoffel[metric, x] =
  (* compute and return *);
```

Simpler. The result is stored as a DownValue of the function itself.
Advantages: zero boilerplate. Disadvantages: hard to clear selectively
(must filter DownValues), hard to share across functions, and it
**pollutes benchmarks** — see below.

### Cache pollution in benchmarks

Both packages memoize Christoffel. When `RepeatedTiming` runs the
expression multiple times, only the first call does real work;
subsequent calls return the cached result in microseconds. The reported
time is dominated by cache hits, not the algorithm.

**Always clear caches before timing for algorithmic comparisons:**

```wolfram
CacheClear[];                      (* CT+GRT *)
clearGR2Cache[];                   (* GREATER2 DownValues *)
timing = First@RepeatedTiming[f[args]];
```

For the DownValues idiom, clearing requires filtering:

```wolfram
DownValues[Christoffel] =
  Select[DownValues[Christoffel], !FreeQ[#, HoldPattern] &];
```

This keeps the definition patterns and removes memoized results.

For cold algorithmic comparison, use `AbsoluteTiming` with
`CacheClear[]` before each call, median of 5+ runs.

---

## 5. Transpose semantics

Mathematica's `Transpose[arr, perm]` is not intuitive. The rule:

> Level p of arr goes to level perm[[p]] of the result.

To swap indices 3 and 4 of a rank-4 array (e.g., antisymmetrize the
last pair of Riemann):

```wolfram
Transpose[arr, {1, 2, 4, 3}]
(* Level 3 -> position 4, level 4 -> position 3 *)
```

To move index k to position 1 (for a Dot contraction):

```wolfram
perm = Join[Range[2, k], {1}, Range[k + 1, rank]];
(* perm[[k]] = 1: level k goes to position 1 *)
(* Inverse: Ordering[perm] undoes the move *)
```

The `Ordering[perm]` trick: if `perm` moves indices around,
`Ordering[perm]` is the inverse permutation that moves them back.
`Transpose[Transpose[arr, perm], Ordering[perm]] === arr`.

**Test on small examples.** A wrong Transpose permutation in rank-4
code produces silently wrong results (the array has the right shape,
just wrong values). Verify against a brute-force Table[Sum[...]]
implementation on a 2x2x2x2 symbolic example before deploying.

---

## 6. Benchmark methodology

### Cold vs warm

- **Cold timing** (CacheClear[] + AbsoluteTiming): measures algorithmic
  cost. Use for comparing implementations.
- **Warm timing** (RepeatedTiming without clearing): measures throughput
  including cache benefits. Use for user-facing performance claims.

### Median-of-N

Single AbsoluteTiming runs have high variance from GC pauses, kernel
warmup, and OS scheduling. Median of 5 is reliable for ms-scale
operations:

```wolfram
times = Table[CacheClear[]; AbsoluteTiming[f[args]][[1]], {5}];
Median[times]
```

### Diagonal vs dense metrics

Schwarzschild is diagonal — most Christoffel symbols are zero, most
Riemann components are zero. Algorithmic wins that reduce the number of
non-zero evaluations look dramatic on Schwarzschild but may be smaller
on dense metrics (Kerr, Godel, general perturbation theory).

Conversely, optimizations that reduce Simplify calls (like
direct-path Ricci) have a *larger* payoff on dense metrics because
there are more non-trivial components to simplify.

Always benchmark on at least one diagonal and one non-diagonal metric
before claiming a speedup.

---

## Summary of measured results (Schwarzschild D=4)

| Technique | Target | Speedup | Status |
|-----------|--------|---------|--------|
| PreRiemann antisymmetrization | Riemann | 1.4x | Shipped |
| Pair-symmetry 2-raise | Kretschmann | 1.6x | Shipped |
| Direct-path Ricci (skip rank-4) | Ricci | 2.7x vs GREATER2 | Shipped |
| Dot-based contraction | Raise/Lower/Transform | 10-20x vs OGRe | Shipped |
| Cancel+Together on intermediates | Christoffel | **2.6x regression** | Reverted |
| Cancel+Together on intermediates | Kretschmann | **2.0x regression** | Reverted |
| Cancel+Together on intermediates | CoordTransform | **4.0x regression** | Reverted |
| Remove "double-simplify" | Pipeline | **Regression** | Reverted |

Reproduce: `wolframscript -file examples/greater2-comparison.wl`
