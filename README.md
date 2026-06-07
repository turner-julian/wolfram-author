# wolfram-author

A fast, component-level tensor algebra library for Wolfram Language / Mathematica, with a focus on general relativity. Built-in array implementations beat OGRe by 10-20x on explicit-coordinate metrics while maintaining full correctness verification via `Core`EquivalentQ`.

## Prerequisites

- **Mathematica 14+** (or the free [Wolfram Engine](https://www.wolfram.com/engine/) with `wolframscript`)
- **Python 3.7+** (stdlib only; no pip packages)
- **Optional:** [OGRe](https://github.com/bshoshany/OGRe) v1.7+ for cross-checking and benchmarking
- **Optional:** [xAct](http://www.xact.es/) for abstract-index tensor algebra

## Installation

```bash
git clone https://github.com/julianturner/wolfram-author.git
cd wolfram-author
cp config.example.json config.json   # edit paths if you have OGRe/xAct
```

If you have OGRe installed, set its path in `config.json`:
```json
{ "ogre_path": "/path/to/OGRe.m" }
```

## Quick start

From a Mathematica notebook or script:

```wolfram
Get["/path/to/wolfram-author/init.wl"];

(* Define a metric *)
coords = {t, r, th, ph};
f = 1 - 2 M/r;
gdown = DiagonalMatrix[{-f, 1/f, r^2, r^2 Sin[th]^2}];
g = Tensor`Field[coords, {"down", "down"}, gdown, Automatic, <||>];

(* Compute curvature *)
riem   = GR`Riemann[g];
ricci  = GR`Ricci[g];
R      = GR`RicciScalar[g];
K      = GR`Kretschmann[g];

(* Index gymnastics *)
riemUp = Tensor`Raise[riem, 1, g];              (* raise first index *)
ricciFromTrace = Tensor`Trc[riemUp, {1, 3}];    (* trace -> Ricci *)

(* Covariant derivative *)
nablaR = GR`CovariantD[ricci, g];

(* Geodesic equations *)
geod = GR`Geodesic[g, \[Lambda]];
```

## API reference

### Core (`Core``)

| Function | Description |
|---|---|
| `EquivalentQ[a, b]` | `True` / `False` / `$Failed` (undecided). Symbolic + numeric. |
| `CacheClear[]` | Clear cached inverse metrics and Christoffels |

### Tensor representation (`Tensor``)

| Function | Description |
|---|---|
| `Field[coords, indices, components, metric, conventions]` | Canonical tensor record (verified object) |
| `FieldQ[t]` | Predicate |
| `Coords`, `Components`, `Indices`, `Metric`, `Dim`, `Rank` | Accessors |

### Index manipulation (`Tensor``)

| Function | Description |
|---|---|
| `Raise[t, n]` or `Raise[t, n, g]` | Raise index `n` using the metric |
| `Lower[t, n]` or `Lower[t, n, g]` | Lower index `n` |
| `Trc[t, {i, j}]` | Contract indices `i` and `j` (one up, one down) |
| `Prod[t1, t2]` | Tensor (outer) product |
| `Contract[t1, i, t2, j]` | Contract index `i` of `t1` with `j` of `t2` |
| `Transform[t, newCoords, rules]` | Coordinate transformation (`rules` = backward map) |

### GR operations (`GR``)

| Function | Description |
|---|---|
| `Christoffel[g]` | Christoffel symbols (cached) |
| `Riemann[g]` | All-lower Riemann tensor |
| `Ricci[g]` | Ricci tensor |
| `RicciScalar[g]` | Ricci scalar |
| `Kretschmann[g]` | Kretschmann scalar |
| `Weyl[g]` | Weyl (conformal) tensor |
| `Einstein[g]` | Einstein tensor |
| `TracelessRicci[g]` | Traceless Ricci tensor |
| `Killing[g]` | Killing equation PDE system |
| `CovariantD[t, g]` | Covariant derivative (prepends one down index) |
| `Geodesic[g]` | Geodesic equations as ODEs |
| `Hamiltonian[g, p]` | Geodesic Hamiltonian g^{mu nu} p_mu p_nu |

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

## Project structure

```
wolfram-author/
  init.wl                     # Load this to set up everything
  lib/
    core.wl              # Core` -- equality, cache, conventions
    tensor.wl            # Tensor` -- tensor rep + index algebra
    gr.wl                # GR` -- curvature, covariant derivative, geodesics
    init.wl              # Loads all modules
    registry.json         # Registry of all functions with benchmarks
  scripts/
    wolfram.py                # Kernel harness (run WL, capture errors honestly)
    bench.py                  # Benchmark gate for library promotion
    gate.py                   # Admission gate + trust DAG
    registry.py               # Capability check
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
