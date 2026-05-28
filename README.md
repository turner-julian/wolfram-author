# GRT

A fast, component-level tensor algebra library for Wolfram Language / Mathematica, with a focus on general relativity. Built-in array implementations beat OGRe by 10-20x on explicit-coordinate metrics while maintaining full correctness verification via `EquivalentQ`.

## Prerequisites

- **Mathematica 14+** (or the free [Wolfram Engine](https://www.wolfram.com/engine/) with `wolframscript`)
- **Python 3.7+** (stdlib only; no pip packages)
- **Optional:** [OGRe](https://github.com/bshoshany/OGRe) v1.7+ for cross-checking and benchmarking
- **Optional:** [xAct](http://www.xact.es/) for abstract-index tensor algebra

## Installation

```bash
git clone https://github.com/julianturner/mathematica-author.git
cd mathematica-author
cp config.example.json config.json   # edit paths if you have OGRe/xAct
```

If you have OGRe installed, set its path in `config.json`:
```json
{ "ogre_path": "/path/to/OGRe.m" }
```

## Quick start

From a Mathematica notebook or script:

```wolfram
Get["/path/to/mathematica-author/init.wl"];

(* Define a metric *)
coords = {t, r, th, ph};
f = 1 - 2 M/r;
gdown = DiagonalMatrix[{-f, 1/f, r^2, r^2 Sin[th]^2}];
g = CT`Tensor[coords, {"down", "down"}, gdown, Automatic, <||>];

(* Compute curvature *)
riem   = GRT`RiemannFromMetric[g];
ricci  = GRT`RicciFromMetric[g];
R      = GRT`RicciScalarFromMetric[g];
K      = GRT`KretschmannFromMetric[g];

(* Index gymnastics *)
riemUp = CT`Raise[riem, 1, g];              (* raise first index *)
ricciFromTrace = CT`Trace[riemUp, {1, 3}];  (* trace -> Ricci *)

(* Covariant derivative *)
nablaR = GRT`CovariantDFromMetric[ricci, g];

(* Geodesic equations *)
geod = GRT`GeodesicEquationsFromMetric[g, \[Lambda]];
```

## API reference

### Core representation (`CT``)

| Function | Description |
|---|---|
| `Tensor[coords, indices, components, metric, conventions]` | Canonical tensor record (Association) |
| `TensQ[t]` | Predicate |
| `Coords`, `Components`, `Indices`, `Metric`, `Conventions`, `Dim`, `Rank` | Accessors |
| `EquivalentQ[a, b]` | `True` / `False` / `$Failed` (undecided). Symbolic + numeric. |

### Index manipulation (`CT``)

| Function | Description |
|---|---|
| `Raise[t, n]` or `Raise[t, n, g]` | Raise index `n` using the metric |
| `Lower[t, n]` or `Lower[t, n, g]` | Lower index `n` |
| `Trace[t, {i, j}]` | Contract indices `i` and `j` (one up, one down) |
| `Product[t1, t2]` | Tensor (outer) product |
| `Contract[t1, i, t2, j]` | Contract index `i` of `t1` with `j` of `t2` |
| `Transform[t, newCoords, rules]` | Coordinate transformation (`rules` = backward map) |

### GR operations (`GRT``)

| Function | Description |
|---|---|
| `ChristoffelFromMetric[g]` | Christoffel symbols (cached) |
| `RiemannFromMetric[g]` | All-lower Riemann tensor |
| `RicciFromMetric[g]` | Ricci tensor |
| `RicciScalarFromMetric[g]` | Ricci scalar |
| `KretschmannFromMetric[g]` | Kretschmann scalar |
| `CovariantDFromMetric[t, g]` | Covariant derivative (prepends one down index) |
| `GeodesicEquationsFromMetric[g]` | Geodesic equations as ODEs |

### Cache

| Function | Description |
|---|---|
| `CacheClear[]` | Clear cached inverse metrics and Christoffels |

## Benchmarks (Schwarzschild, D=4)

All operations sub-millisecond. Built-in array implementations vs OGRe on explicit-coordinate metrics:

| Operation | Built-in | vs OGRe |
|---|---|---|
| Christoffel | 1.8 ms | 10x faster |
| Riemann | 8.8 ms | 9x faster |
| Index raise (Riemann) | 0.38 ms | -- |
| Trace (Riemann -> Ricci) | 0.53 ms | -- |
| Coordinate transform | 0.12 ms | -- |
| Covariant derivative | 0.18 ms | -- |
| Geodesic equations | 0.15 ms | -- |

Caching (cold -> warm pipeline): 3.4x speedup.

OGRe wins on convenience for exploratory work (automatic index tracking, caching across operations). CT wins on speed for explicit metrics and when you want auditable, documented code.

## Project structure

```
mathematica-author/
  init.wl                     # Load this to set up everything
  lib/
    CT.wl                # Canonical tensor rep + algebra operations
    GRT.wl                     # Curvature, covariant derivative, geodesics
    index.json                # Registry of all functions with benchmarks
  scripts/
    wolfram.py                # Kernel harness (run WL, capture errors honestly)
    bench.py                  # Benchmark gate for library promotion
    verify_bridge.py          # Optional cross-engine check (Wolfram + SymPy)
  examples/
    ads-poincare-riemann.wl   # AdS4 curvature worked example
    tensor-algebra-tests.nb   # Comprehensive test notebook
    tensor-algebra-benchmark.wl  # Speed comparison vs OGRe
  evals/                      # Code-generation eval harness
  references/                 # Design docs and conventions
  config.example.json         # Copy to config.json, set your paths
  SKILL.md                    # Claude Code skill registration (optional)
```

## Conventions

- **Metric signature:** mostly-plus `(-,+,+,+)` unless overridden
- **Christoffel:** Levi-Civita
- **Riemann:** R^r\_smn = d\_m Gamma^r\_ns - d\_n Gamma^r\_ms + ...
- **Riemann (lowered):** R\_rsmn = g\_ra R^a\_smn, index order (rho, sigma, mu, nu)
- **Ricci:** R\_sn = R^m\_smn
- Conventions match OGRe (verified componentwise on AdS4). See `references/wolfram-conventions.md`.

## License

MIT. See [LICENSE](LICENSE).
