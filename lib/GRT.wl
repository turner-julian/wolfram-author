(* ::Package:: *)

(* GRT` -- general-relativity curvature operators on the canonical tensor
   representation, plus the canonical <-> OGRe adapter.

   Two implementations of each operator coexist on purpose: a built-in array
   implementation (zero package dependencies, the from-scratch reference) and an
   OGRe-backed one (the *OGRe-suffixed functions). They are kept equivalent by
   the benchmark gate (bench.py + CT`EquivalentQ); the faster one is what a
   generated script composes, the other is the cross-check.

   Sign/index conventions: Christoffel is Levi-Civita,
     Gamma^a_bc = 1/2 g^as (d_b g_sc + d_c g_sb - d_s g_bc),
   Riemann (mixed) uses
     R^r_smn = d_m Gamma^r_ns - d_n Gamma^r_ms + Gamma^r_ml Gamma^l_ns - Gamma^r_nl Gamma^l_ms,
   lowered to R_rsmn = g_ra R^a_smn; Ricci R_sn = R^m_smn; scalar R = g^sn R_sn.
   This matches OGRe's convention (verified componentwise on AdS4). *)

BeginPackage["GRT`", {"CT`"}];

ChristoffelFromMetric::usage =
  "ChristoffelFromMetric[g] gives the Christoffel symbols Gamma^a_bc of a \
canonical metric Tensor g (indices {down,down}), as a Tensor with index \
positions {up,down,down}. (Connection coefficients, not a tensor, stored in \
Tensor form for uniformity.)";
RiemannFromMetric::usage =
  "RiemannFromMetric[g] gives the all-lower Riemann tensor R_{rho sigma mu nu} \
of a canonical metric g, as a Tensor with indices {down,down,down,down}.";
RicciFromMetric::usage =
  "RicciFromMetric[g] gives the Ricci tensor R_{mu nu} as a Tensor {down,down}.";
RicciScalarFromMetric::usage =
  "RicciScalarFromMetric[g] gives the Ricci scalar (a scalar expression).";
KretschmannFromMetric::usage =
  "KretschmannFromMetric[g] gives the Kretschmann scalar R_{abcd}R^{abcd} (a \
convention-independent invariant, useful as a sanity check).";

ToOGReMetric::usage =
  "ToOGReMetric[g] builds an OGRe metric object from canonical metric g and \
returns its (unique) OGRe ID string. Requires OGRe to be loaded (--load ogre).";
RiemannFromMetricOGRe::usage =
  "RiemannFromMetricOGRe[g] computes the all-lower Riemann tensor of g via OGRe \
and returns it as a canonical Tensor. Requires OGRe.";
RicciFromMetricOGRe::usage = "Ricci tensor via OGRe, as a canonical Tensor.";
ChristoffelFromMetricOGRe::usage =
  "Christoffel symbols via OGRe, as a canonical Tensor {up,down,down}.";
RicciScalarFromMetricOGRe::usage = "Ricci scalar via OGRe (a scalar expression).";

WeylFromMetric::usage =
  "WeylFromMetric[g] gives the Weyl (conformal) tensor C_{rho sigma mu nu} \
as a Tensor {down,down,down,down}. Vanishes identically in D<=3.";
EinsteinFromMetric::usage =
  "EinsteinFromMetric[g] gives the Einstein tensor G_{mu nu} = R_{mu nu} - \
(1/2) R g_{mu nu} as a Tensor {down,down}.";
TracelessRicciFromMetric::usage =
  "TracelessRicciFromMetric[g] gives the traceless Ricci tensor S_{mu nu} = \
R_{mu nu} - (1/D) R g_{mu nu} as a Tensor {down,down}. Trace g^{mu nu} S_{mu nu} = 0.";
KillingEquationsFromMetric::usage =
  "KillingEquationsFromMetric[g] returns the Killing equation system as a list \
of equations {eq1 == 0, eq2 == 0, ...}. Unknowns are D functions \
\\[Xi][1][coords], ..., \\[Xi][D][coords]. Returns D(D+1)/2 independent equations.";

CovariantDFromMetric::usage =
  "CovariantDFromMetric[t, g] computes the covariant derivative of Tensor t \
with respect to the Levi-Civita connection of metric g. Returns a Tensor with \
one extra \"down\" index prepended (the derivative index). Uses cached Christoffels.";

GeodesicEquationsFromMetric::usage =
  "GeodesicEquationsFromMetric[g] or GeodesicEquationsFromMetric[g, param] \
returns the geodesic equations as a list of expressions equal to zero. \
Coordinates are promoted to functions of the affine parameter.";

HamiltonianFromMetric::usage =
  "HamiltonianFromMetric[g, p] gives the geodesic Hamiltonian \
H = g^{mu nu} p_mu p_nu for a momentum covector p (a length-D list of the lower \
components p_mu). Contracts the inverse metric of g with p. For Kerr in \
Boyer-Lindquist with p_t = -E, p_phi = L, the product Sigma*H is Carter-separable \
into R(r) + Theta(theta) (mixed partial d_r d_theta vanishes).";

(* OGRe comparison functions for benchmarking *)
WeylFromMetricOGRe::usage =
  "Weyl tensor via OGRe, as a canonical Tensor.";
EinsteinFromMetricOGRe::usage =
  "Einstein tensor via OGRe, as a canonical Tensor.";
TracelessRicciFromMetricOGRe::usage =
  "Traceless Ricci tensor via OGRe, as a canonical Tensor.";
CovariantDFromMetricOGRe::usage =
  "CovariantDFromMetricOGRe[t, g] covariant derivative via OGRe. Requires OGRe.";
GeodesicEquationsFromMetricOGRe::usage =
  "GeodesicEquationsFromMetricOGRe[g] geodesic equations via OGRe. Requires OGRe.";

(* xAct/xCoba adapter functions for benchmarking *)
RiemannFromMetricXAct::usage =
  "All-lower Riemann tensor via xAct/xCoba, as a canonical Tensor.";
RicciFromMetricXAct::usage =
  "Ricci tensor via xAct/xCoba, as a canonical Tensor.";
RicciScalarFromMetricXAct::usage =
  "Ricci scalar via xAct/xCoba.";
WeylFromMetricXAct::usage =
  "Weyl tensor via xAct/xCoba, as a canonical Tensor.";
EinsteinFromMetricXAct::usage =
  "Einstein tensor via xAct/xCoba, as a canonical Tensor.";
KretschmannFromMetricXAct::usage =
  "Kretschmann scalar via xAct/xCoba.";

Begin["`Private`"];

(* Configurable simplifier — same default as CT. *)
If[!ValueQ[$GRTSimplify], $GRTSimplify = Simplify[#, TimeConstraint -> 1] &];

(* ------------------------- built-in array implementations ----------------- *)

(* Christoffel: split into pre-Christoffel (derivatives only, cheap) then
   contract with g^{-1} via Dot. GREATER2's approach — avoids mixing
   derivative expressions with inverse-metric terms in one Sum, making
   intermediate simplification cheaper. *)
christoffelArray[coords_, gdown_] := Module[{ginv, d = Length[coords], preChris},
  ginv = cachedInverse[gdown];
  preChris = Table[
    D[gdown[[k, i]], coords[[j]]] + D[gdown[[j, k]], coords[[i]]]
      - D[gdown[[i, j]], coords[[k]]],
    {k, d}, {i, d}, {j, d}];
  preChris = $GRTSimplify[preChris];
  $GRTSimplify[(1/2) ginv . preChris]];

(* PreRiemann antisymmetrization: build one kernel array containing
   d_m Gamma^r_ns + Sum_l Gamma^r_ml Gamma^l_ns, then recover the full
   Riemann R^r_smn = PreR[r,s,m,n] - PreR[r,s,n,m] via Transpose-subtract.
   Halves D[] evaluations (d^4 instead of 2d^4) and bilinear Sums
   (d^5 instead of 2d^5). *)
riemannUpArray[coords_, gamma_] := Module[{d = Length[coords], preR},
  preR = Table[
    D[gamma[[r, n, s]], coords[[m]]]
      + Sum[gamma[[r, m, l]] gamma[[l, n, s]], {l, d}],
    {r, d}, {s, d}, {m, d}, {n, d}];
  $GRTSimplify[preR - Transpose[preR, {1, 2, 4, 3}]]];

(* Lowering: gdown . rup contracts via Dot instead of Table[Sum[...]]. *)
riemannDownArray[gdown_, rup_] := $GRTSimplify[gdown . rup];

(* Direct Ricci from Christoffel — avoids building the full rank-4 Riemann
   when only Ricci is needed. Computes R^m_{smn} summed over m directly. *)
ricciDirectArray[coords_, gamma_] := Module[{d = Length[coords]},
  $GRTSimplify[Table[
    Sum[D[gamma[[m, n, s]], coords[[m]]] - D[gamma[[m, m, s]], coords[[n]]]
      + Sum[gamma[[m, m, l]] gamma[[l, n, s]] - gamma[[m, n, l]] gamma[[l, m, s]], {l, d}],
    {m, d}],
  {s, d}, {n, d}]]];

ChristoffelFromMetric[g_?TensQ] := With[{coords = Coords[g]},
  Tensor[coords, {"up", "down", "down"},
   cachedChristoffel[coords, Components[g]], Components[g], Conventions[g]]];

RiemannFromMetric[g_?TensQ] := Module[{coords = Coords[g], gdown = Components[g], gamma, rup},
  gamma = cachedChristoffel[coords, gdown];
  rup = riemannUpArray[coords, gamma];
  Tensor[coords, {"down", "down", "down", "down"},
   riemannDownArray[gdown, rup], gdown, Conventions[g]]];

(* Ricci: direct path from Christoffel, no full Riemann needed. *)
RicciFromMetric[g_?TensQ] := Module[{coords = Coords[g], gdown = Components[g], gamma},
  gamma = cachedChristoffel[coords, gdown];
  Tensor[coords, {"down", "down"}, ricciDirectArray[coords, gamma], gdown, Conventions[g]]];

RicciScalarFromMetric[g_?TensQ] := Module[{gdown = Components[g], ric},
  ric = Components[RicciFromMetric[g]];
  $GRTSimplify[Total[cachedInverse[gdown] ric, 2]]];

(* Kretschmann: raise last 2 indices (O(2 d^5) instead of O(4 d^5)),
   then exploit pair symmetry R_{abcd} = R_{cdab}:
     K = R_{abcd} R^{abcd} = Sum R^{ab}_{cd} R_{ab}^{cd}
   where R^{ab}_{cd} = Transpose[R_{ab}^{cd}, {3,4,1,2}] by pair symmetry. *)
KretschmannFromMetric[g_?TensQ] := Module[{gdown = Components[g], ginv, rdown, rmixed},
  ginv = cachedInverse[gdown];
  rdown = Components[RiemannFromMetric[g]];
  rmixed = rdown;
  Do[rmixed = contractMatIndex[ginv, rmixed, k, 4], {k, 3, 4}];
  $GRTSimplify[Total[Transpose[rmixed, {3, 4, 1, 2}] rmixed, 4]]];

(* Weyl: C_{abcd} = R_{abcd} - (2/(D-2))(g_{a[c}R_{d]b} - g_{b[c}R_{d]a})
                               + (2/((D-1)(D-2))) R g_{a[c}g_{d]b}
   The antisymmetrized products expand as:
     s1_{abcd} = g_{ac}R_{db} - g_{ad}R_{cb} - g_{bc}R_{da} + g_{bd}R_{ca}
               = 2*(g_{a[c}R_{d]b} - g_{b[c}R_{d]a})
     s2_{abcd} = g_{ac}g_{bd} - g_{ad}g_{bc} = 2*g_{a[c}g_{d]b}
   so C = R - (1/(D-2))*s1 + (R/((D-1)(D-2)))*s2. *)
WeylFromMetric[g_?TensQ] := Module[
  {coords = Coords[g], gdown = Components[g], dim = Dim[g],
   rdown, ricdown, rscalar, s1, s2, weyl},

  If[dim <= 2, Return[Tensor[coords, {"down","down","down","down"},
    ConstantArray[0, {dim,dim,dim,dim}], gdown, Conventions[g]]]];

  rdown = Components[RiemannFromMetric[g]];
  ricdown = Components[RicciFromMetric[g]];
  rscalar = RicciScalarFromMetric[g];

  s1 = Table[
    gdown[[aa,cc]] ricdown[[dd,bb]] - gdown[[aa,dd]] ricdown[[cc,bb]]
    - gdown[[bb,cc]] ricdown[[dd,aa]] + gdown[[bb,dd]] ricdown[[cc,aa]],
    {aa, dim}, {bb, dim}, {cc, dim}, {dd, dim}];

  s2 = Table[
    gdown[[aa,cc]] gdown[[bb,dd]] - gdown[[aa,dd]] gdown[[bb,cc]],
    {aa, dim}, {bb, dim}, {cc, dim}, {dd, dim}];

  weyl = rdown - (1/(dim - 2)) s1 + (rscalar/((dim - 1)(dim - 2))) s2;

  Tensor[coords, {"down","down","down","down"},
   $GRTSimplify[weyl], gdown, Conventions[g]]];

(* Einstein: G_{mu nu} = R_{mu nu} - (1/2) R g_{mu nu}. *)
EinsteinFromMetric[g_?TensQ] := Module[
  {coords = Coords[g], gdown = Components[g], ricdown, rscalar},
  ricdown = Components[RicciFromMetric[g]];
  rscalar = RicciScalarFromMetric[g];
  Tensor[coords, {"down","down"},
   $GRTSimplify[ricdown - (1/2) rscalar gdown], gdown, Conventions[g]]];

(* Traceless Ricci: S_{mu nu} = R_{mu nu} - (1/D) R g_{mu nu}.
   Trace g^{mn} S_{mn} = R - R = 0 by construction. *)
TracelessRicciFromMetric[g_?TensQ] := Module[
  {coords = Coords[g], gdown = Components[g], dim = Dim[g],
   ricdown, rscalar},
  ricdown = Components[RicciFromMetric[g]];
  rscalar = RicciScalarFromMetric[g];
  Tensor[coords, {"down","down"},
   $GRTSimplify[ricdown - (1/dim) rscalar gdown], gdown, Conventions[g]]];

(* Killing equations: d_mu xi_nu + d_nu xi_mu - 2 Gamma^a_{mu nu} xi_a = 0.
   Returns D(D+1)/2 independent equations (mu <= nu) for D unknown functions
   xi[k][coords...]. *)
KillingEquationsFromMetric[g_?TensQ] := Module[
  {coords = Coords[g], gdown = Components[g], dim = Dim[g], gamma,
   xiLow, eqs},

  gamma = cachedChristoffel[coords, gdown];

  xiLow = Table[Global`\[Xi][mu] @@ coords, {mu, dim}];

  eqs = Flatten@Table[
    $GRTSimplify[
      D[xiLow[[nu]], coords[[mu]]] + D[xiLow[[mu]], coords[[nu]]]
      - 2 Sum[gamma[[aa, mu, nu]] xiLow[[aa]], {aa, dim}]] == 0,
    {mu, dim}, {nu, mu, dim}];

  eqs];

(* Killing equations via CovariantD (benchmark candidate 2).
   Constructs xi as a rank-1 Tensor, computes nabla xi, symmetrizes. *)
KillingEquationsFromMetricCovD[g_?TensQ] := Module[
  {coords = Coords[g], gdown = Components[g], dim = Dim[g],
   xiLow, xiTens, nablaXi, symm, eqs},

  xiLow = Table[Global`\[Xi][mu] @@ coords, {mu, dim}];
  xiTens = Tensor[coords, {"down"}, xiLow, gdown, Conventions[g]];

  nablaXi = CovariantDFromMetric[xiTens, g];
  symm = Components[nablaXi] + Transpose[Components[nablaXi]];

  eqs = Flatten@Table[
    $GRTSimplify[symm[[mu, nu]]] == 0,
    {mu, dim}, {nu, mu, dim}];

  eqs];

(* ------------------------- OGRe-backed implementations -------------------- *)

(* OGRe`TNewCoordinates is HoldRest (it clears/protects the coordinate symbols),
   so the symbol list must be injected literally via With -- passing Coords[g]
   directly would hand it the unevaluated expression, not {t,x,y,z}. A unique ID
   per call is required so RepeatedTiming re-runs don't collide on OGRe's
   uniqueness constraint. *)
ogreMetric[g_?TensQ] := With[{c = Coords[g], comps = Components[g]},
  Module[{id = ToString[Unique["MAm"]]},
   OGRe`TNewCoordinates[id <> "Coords", c];
   OGRe`TNewMetric[id, id <> "Coords", comps];
   id]];

ToOGReMetric[g_?TensQ] := ogreMetric[g];

ChristoffelFromMetricOGRe[g_?TensQ] := Module[{id = ogreMetric[g], cid},
  cid = OGRe`TCalcChristoffel[id];
  Tensor[Coords[g], {"up", "down", "down"},
   OGRe`TGetComponents[cid, {1, -1, -1}, id <> "Coords"], Components[g], Conventions[g]]];

RiemannFromMetricOGRe[g_?TensQ] := Module[{id = ogreMetric[g], rid},
  rid = OGRe`TCalcRiemannTensor[id];
  Tensor[Coords[g], {"down", "down", "down", "down"},
   OGRe`TGetComponents[rid, {-1, -1, -1, -1}, id <> "Coords"], Components[g], Conventions[g]]];

RicciFromMetricOGRe[g_?TensQ] := Module[{id = ogreMetric[g], rid},
  rid = OGRe`TCalcRicciTensor[id];
  Tensor[Coords[g], {"down", "down"},
   OGRe`TGetComponents[rid, {-1, -1}, id <> "Coords"], Components[g], Conventions[g]]];

RicciScalarFromMetricOGRe[g_?TensQ] := Module[{id = ogreMetric[g], sid},
  sid = OGRe`TCalcRicciScalar[id];
  First@Flatten@{OGRe`TGetComponents[sid, {}, id <> "Coords"]}];

WeylFromMetricOGRe[g_?TensQ] := Module[{id = ogreMetric[g], wid},
  wid = OGRe`TCalcWeylTensor[id];
  Tensor[Coords[g], {"down","down","down","down"},
   OGRe`TGetComponents[wid, {-1,-1,-1,-1}, id <> "Coords"],
   Components[g], Conventions[g]]];

EinsteinFromMetricOGRe[g_?TensQ] := Module[{id = ogreMetric[g], eid},
  eid = OGRe`TCalcEinsteinTensor[id];
  Tensor[Coords[g], {"down","down"},
   OGRe`TGetComponents[eid, {-1,-1}, id <> "Coords"],
   Components[g], Conventions[g]]];

(* OGRe has no direct traceless Ricci; compose from Ricci + scalar. *)
TracelessRicciFromMetricOGRe[g_?TensQ] := Module[
  {id = ogreMetric[g], ricID, scID, ricComps, scVal, dim = Dim[g],
   coords = Coords[g], gdown = Components[g]},
  ricID = OGRe`TCalcRicciTensor[id];
  scID = OGRe`TCalcRicciScalar[id];
  ricComps = OGRe`TGetComponents[ricID, {-1,-1}, id <> "Coords"];
  scVal = First@Flatten@{OGRe`TGetComponents[scID, {}, id <> "Coords"]};
  Tensor[coords, {"down","down"},
   $GRTSimplify[ricComps - (1/dim) scVal gdown], gdown, Conventions[g]]];

(* ----------------------- Cached Christoffel ------------------------------ *)

(* Share CT's cache so Christoffel is computed once, reused by
   Riemann, Ricci, covariant derivative, and geodesic equations. *)
cachedChristoffel[coords_, gdown_] := Module[
  {key = {"christoffel", Hash[{coords, gdown}]}, c},
  c = CacheGet[key];
  If[MissingQ[c], CacheStore[key, christoffelArray[coords, gdown]], c]];

(* ----------------------- Covariant Derivative ---------------------------- *)

(* Result indices: {"down"} (derivative) ++ original indices.
   For each upper index of t: +Gamma correction.
   For each lower index of t: -Gamma correction.
   Uses Dot-based contraction (contractMatIndex from CT) for speed. *)

CovariantDFromMetric[t_?TensQ, g_?TensQ] := Module[
  {coords = Coords[g], gdown = Components[g], gamma,
   arr = Components[t], idx = Indices[t],
   d = Dim[g], r = Rank[t], pd, result},

  gamma = cachedChristoffel[coords, gdown];

  (* Partial derivative: pd[[mu, i1, ...]] = D[arr[[i1,...]], coords[[mu]]] *)
  pd = Table[D[arr, coords[[mu]]], {mu, d}];
  result = pd;

  (* Gamma corrections for each tensor index *)
  Do[result += gammaCorrectionCD[arr, gamma, idx[[k]], k, r, d], {k, r}];

  result = $GRTSimplify[result];
  Tensor[coords, Join[{"down"}, idx], result, gdown, Conventions[g]]];

(* Gamma correction for one index of the tensor.
   Returns an array of shape {d, <original shape>} where the first index
   is the derivative index mu.
   For upper index k: + Sum_lam gamma^{a_k}_{mu lam} T^{..lam..}
   For lower index k: - Sum_lam gamma^{lam}_{mu a_k} T_{..lam..}
   Both reduce to a Dot per mu-slice via contractMatIndex. *)

gammaCorrectionCD[arr_, gamma_, idxType_String, k_Integer, rank_Integer, d_Integer] :=
 Module[{moved, correction, perm, invPerm},
  (* Move index k to position 1 in arr *)
  If[rank > 1,
    perm = Join[{k}, Delete[Range[rank], k]];
    invPerm = Ordering[perm];
    moved = Transpose[arr, perm],
    moved = arr; invPerm = {1}];

  If[idxType === "up",
    (* gamma[[All,mu,All]] is d*d: gamma^a_{mu lam}.
       Dot contracts lam with moved's first index (= original index k). *)
    correction = Table[gamma[[All, mu, All]] . moved, {mu, d}],
    (* For a lower index: need Sum_lam gamma^lam_{mu a_k} * arr_{..lam..}
       = (Transpose[gamma[[All,mu,All]]])_{a_k, lam} . moved_{lam, ...}
       Negate for the lower-index sign. *)
    correction = -Table[Transpose[gamma[[All, mu, All]]] . moved, {mu, d}]];

  (* Permute back: correction is {d_mu, d_a, rest...}.
     Want {d_mu, [rest before k], d_a, [rest after k]}. *)
  If[rank > 1 && k > 1,
    Module[{cperm = Join[{1}, Range[3, k + 1], {2}, Range[k + 2, rank + 1]]},
      correction = Transpose[correction, cperm]]];

  correction];

(* ----------------------- Geodesic Equations ------------------------------ *)

GeodesicEquationsFromMetric[g_?TensQ] :=
  GeodesicEquationsFromMetric[g, Global`\[Lambda]];

GeodesicEquationsFromMetric[g_?TensQ, param_] := Module[
  {coords = Coords[g], gamma, d = Dim[g],
   xfuncs, xdot, xddot, gammaOnCurve, eqs},

  gamma = cachedChristoffel[coords, Components[g]];

  (* Promote coordinate symbols to functions of the affine parameter *)
  xfuncs = Through[coords[param]];     (* {t[lam], x[lam], ...} *)
  xdot = D[xfuncs, param];
  xddot = D[xdot, param];

  (* Evaluate Christoffel along the curve *)
  gammaOnCurve = gamma /. Thread[coords -> xfuncs];

  eqs = Table[
    xddot[[mu]] +
      Sum[gammaOnCurve[[mu, a, b]] xdot[[a]] xdot[[b]], {a, d}, {b, d}],
    {mu, d}];

  $GRTSimplify[eqs]];

(* ----------------------- Geodesic Hamiltonian ---------------------------- *)

(* H = g^{mu nu} p_mu p_nu for a momentum covector p (length-D list of the
   lower components p_mu). The Hamilton-Jacobi / Carter Hamiltonian: contracts
   the cached inverse metric directly, H = p . g^{-1} . p. For Kerr (BL),
   Sigma*H separates as R(r) + Theta(theta). Demanded by spec-loom Phase E
   (Kerr Carter separability), which had to build this externally. *)
HamiltonianFromMetric::baddim =
  "Momentum covector length `1` does not match metric dimension `2`.";
HamiltonianFromMetric[g_?TensQ, p_List] := Module[{ginv, d = Dim[g]},
  If[Length[p] =!= d,
    Message[HamiltonianFromMetric::baddim, Length[p], d]; Return[$Failed]];
  ginv = cachedInverse[Components[g]];
  $GRTSimplify[p . ginv . p]];

(* ----------------------- OGRe comparison functions ----------------------- *)

(* Covariant derivative via OGRe *)
CovariantDFromMetricOGRe[t_?TensQ, g_?TensQ] := Module[
  {metID = ogreMetric[g], tID, covdID, ogreIdx, resultIdx, coords = Coords[g]},
  (* Create OGRe tensor from Tensor t *)
  tID = With[{c = Coords[t], comps = Components[t]},
    Module[{id = ToString[Unique["MAcd"]]},
      OGRe`TNewTensor[id, metID <> "Coords",
        Map[If[# === "up", 1, -1] &, Indices[t]], comps];
      id]];
  covdID = OGRe`TCalcCovariantDerivative[tID, metID];
  (* Result indices: derivative index (down=-1) prepended *)
  ogreIdx = Join[{-1}, Map[If[# === "up", 1, -1] &, Indices[t]]];
  resultIdx = Join[{"down"}, Indices[t]];
  Tensor[coords, resultIdx,
    OGRe`TGetComponents[covdID, ogreIdx, metID <> "Coords"],
    Components[g], Conventions[g]]];

(* Geodesic equations via OGRe *)
GeodesicEquationsFromMetricOGRe[g_?TensQ] :=
  GeodesicEquationsFromMetricOGRe[g, Global`\[Lambda]];

GeodesicEquationsFromMetricOGRe[g_?TensQ, param_] := Module[
  {metID = ogreMetric[g]},
  OGRe`TCalcGeodesicEquations[metID, param]];

(* ----------------------- xAct/xCoba adapter -------------------------------- *)

(* xActMetricSetup: create a fresh xCoba geometric structure from a
   canonical metric Tensor. Returns an Association with handles for
   the manifold, metric symbol, chart, covariant derivative, and the
   curvature tensor symbols (concatenated with the cd name).
   Requires xAct`xTensor` and xAct`xCoba` to be loaded (--load xcoba).

   Index convention: down indices use {k, -chart}, up use {k, chart}.
   xCoba stores computed curvature tensor components as DownValues;
   extract via Last@ComponentValue@TensorSym[{idx, +-chart}, ...].

   Note: Christoffel connection coefficients are NOT stored as tensor
   DownValues by MetricCompute — only true tensors (Riemann, Ricci,
   Weyl, Einstein) and scalars (RicciScalar, Kretschmann) extract
   correctly. *)

xActMetricSetup[g_?TensQ] := Module[
  {coords = Coords[g], gdown = Components[g], dim = Dim[g],
   uid, mfSym, metSym, cdSym, chartSym, abIdx},

  uid = ToString[Unique["xa"]];

  (* Symbols in Global` — unique per call *)
  mfSym = Symbol["Global`M" <> uid];
  metSym = Symbol["Global`met" <> uid];
  cdSym = Symbol["Global`cd" <> uid];
  chartSym = Symbol["Global`ch" <> uid];

  (* Abstract indices: need enough for rank-4 tensors *)
  abIdx = Table[Symbol["Global`idx" <> uid <> ToString[k]], {k, 2 dim}];

  Quiet[Block[{$Output = {}},
    xAct`xTensor`DefManifold[mfSym, dim, abIdx];
    xAct`xTensor`DefMetric[-1, metSym @@ (-Take[abIdx, 2]),
      cdSym, {";", "\[Del]"}];
    With[{ch = chartSym, m = mfSym, c = coords, d = dim},
      xAct`xCoba`DefChart[ch, m, Range[0, d - 1],
        Through[c[]]]];
    (* xCoba coordinates are scalar fields: t[], r[], etc.
       Our metric uses bare symbols: t, r, etc. Substitute. *)
    xAct`xCoba`MetricInBasis[metSym, -chartSym,
      gdown /. Thread[coords -> Through[coords[]]]];
    xAct`xCoba`MetricCompute[metSym, chartSym, All];
  ]];

  (* Rule to convert xCoba scalar fields back to bare symbols:
     t[] -> t, r[] -> r, etc. Applied to extracted components. *)
  <|"metric" -> metSym, "chart" -> chartSym, "cd" -> cdSym,
    "dim" -> dim, "coords" -> coords, "gdown" -> gdown,
    "toBareSym" -> Thread[Through[coords[]] -> coords],
    (* curvature symbols: concatenation of tensor name + cd name *)
    "Riemann" -> Symbol["Global`Riemann" <> uid],
    "Ricci" -> Symbol["Global`Ricci" <> uid],
    "RicciScalar" -> Symbol["Global`RicciScalar" <> uid],
    "Weyl" -> Symbol["Global`Weyl" <> uid],
    "Einstein" -> Symbol["Global`Einstein" <> uid],
    "Kretschmann" -> Symbol["Global`Kretschmann" <> uid]|>];

xActExtractRank2[sym_, ch_, dim_] := Table[
  Simplify@Last@xAct`xCoba`ComponentValue@sym[{aa, -ch}, {bb, -ch}],
  {aa, 0, dim - 1}, {bb, 0, dim - 1}];

xActExtractRank4[sym_, ch_, dim_] := Table[
  Simplify@Last@xAct`xCoba`ComponentValue@sym[{aa, -ch}, {bb, -ch}, {cc, -ch}, {dd, -ch}],
  {aa, 0, dim - 1}, {bb, 0, dim - 1}, {cc, 0, dim - 1}, {dd, 0, dim - 1}];

xActExtractScalar[sym_] := Simplify@Last@xAct`xCoba`ComponentValue@sym[];

(* Curvature tensor symbols are named <TensorName><cdName>.
   DefMetric[..., metSym[...], cdSym, ...] creates RiemanncdSym, etc.
   We find them via GiveSymbol. *)

RiemannFromMetricXAct[g_?TensQ] := Module[
  {setup = xActMetricSetup[g], ch, cdSym, dim, sym, comps, toBare},
  ch = setup["chart"]; cdSym = setup["cd"]; dim = setup["dim"];
  toBare = setup["toBareSym"];
  sym = xAct`xTensor`GiveSymbol[xAct`xTensor`Riemann, cdSym];
  comps = xActExtractRank4[sym, ch, dim] /. toBare;
  Tensor[Coords[g], {"down","down","down","down"},
   comps, Components[g], Conventions[g]]];

RicciFromMetricXAct[g_?TensQ] := Module[
  {setup = xActMetricSetup[g], ch, cdSym, dim, sym, comps, toBare},
  ch = setup["chart"]; cdSym = setup["cd"]; dim = setup["dim"];
  toBare = setup["toBareSym"];
  sym = xAct`xTensor`GiveSymbol[xAct`xTensor`Ricci, cdSym];
  comps = xActExtractRank2[sym, ch, dim] /. toBare;
  Tensor[Coords[g], {"down","down"},
   comps, Components[g], Conventions[g]]];

RicciScalarFromMetricXAct[g_?TensQ] := Module[
  {setup = xActMetricSetup[g], cdSym, sym, toBare},
  cdSym = setup["cd"]; toBare = setup["toBareSym"];
  sym = xAct`xTensor`GiveSymbol[xAct`xTensor`RicciScalar, cdSym];
  xActExtractScalar[sym] /. toBare];

WeylFromMetricXAct[g_?TensQ] := Module[
  {setup = xActMetricSetup[g], ch, cdSym, dim, sym, comps, toBare},
  ch = setup["chart"]; cdSym = setup["cd"]; dim = setup["dim"];
  toBare = setup["toBareSym"];
  sym = xAct`xTensor`GiveSymbol[xAct`xTensor`Weyl, cdSym];
  comps = xActExtractRank4[sym, ch, dim] /. toBare;
  Tensor[Coords[g], {"down","down","down","down"},
   comps, Components[g], Conventions[g]]];

EinsteinFromMetricXAct[g_?TensQ] := Module[
  {setup = xActMetricSetup[g], ch, cdSym, dim, sym, comps, toBare},
  ch = setup["chart"]; cdSym = setup["cd"]; dim = setup["dim"];
  toBare = setup["toBareSym"];
  sym = xAct`xTensor`GiveSymbol[xAct`xTensor`Einstein, cdSym];
  comps = xActExtractRank2[sym, ch, dim] /. toBare;
  Tensor[Coords[g], {"down","down"},
   comps, Components[g], Conventions[g]]];

KretschmannFromMetricXAct[g_?TensQ] := Module[
  {setup = xActMetricSetup[g], cdSym, sym, toBare},
  cdSym = setup["cd"]; toBare = setup["toBareSym"];
  sym = xAct`xTensor`GiveSymbol[xAct`xTensor`Kretschmann, cdSym];
  xActExtractScalar[sym] /. toBare];

End[];
EndPackage[];
