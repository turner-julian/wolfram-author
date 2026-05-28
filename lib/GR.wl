(* ::Package:: *)

(* MAuthorGR` -- general-relativity curvature operators on the canonical tensor
   representation, plus the canonical <-> OGRe adapter.

   Two implementations of each operator coexist on purpose: a built-in array
   implementation (zero package dependencies, the from-scratch reference) and an
   OGRe-backed one (the *OGRe-suffixed functions). They are kept equivalent by
   the benchmark gate (bench.py + MAuthor`EquivalentQ); the faster one is what a
   generated script composes, the other is the cross-check.

   Sign/index conventions: Christoffel is Levi-Civita,
     Gamma^a_bc = 1/2 g^as (d_b g_sc + d_c g_sb - d_s g_bc),
   Riemann (mixed) uses
     R^r_smn = d_m Gamma^r_ns - d_n Gamma^r_ms + Gamma^r_ml Gamma^l_ns - Gamma^r_nl Gamma^l_ms,
   lowered to R_rsmn = g_ra R^a_smn; Ricci R_sn = R^m_smn; scalar R = g^sn R_sn.
   This matches OGRe's convention (verified componentwise on AdS4). *)

BeginPackage["MAuthorGR`", {"MAuthor`"}];

ChristoffelFromMetric::usage =
  "ChristoffelFromMetric[g] gives the Christoffel symbols Gamma^a_bc of a \
canonical metric CTensor g (indices {down,down}), as a CTensor with index \
positions {up,down,down}. (Connection coefficients, not a tensor, stored in \
CTensor form for uniformity.)";
RiemannFromMetric::usage =
  "RiemannFromMetric[g] gives the all-lower Riemann tensor R_{rho sigma mu nu} \
of a canonical metric g, as a CTensor with indices {down,down,down,down}.";
RicciFromMetric::usage =
  "RicciFromMetric[g] gives the Ricci tensor R_{mu nu} as a CTensor {down,down}.";
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
and returns it as a canonical CTensor. Requires OGRe.";
RicciFromMetricOGRe::usage = "Ricci tensor via OGRe, as a canonical CTensor.";
ChristoffelFromMetricOGRe::usage =
  "Christoffel symbols via OGRe, as a canonical CTensor {up,down,down}.";
RicciScalarFromMetricOGRe::usage = "Ricci scalar via OGRe (a scalar expression).";

CovariantDFromMetric::usage =
  "CovariantDFromMetric[t, g] computes the covariant derivative of CTensor t \
with respect to the Levi-Civita connection of metric g. Returns a CTensor with \
one extra \"down\" index prepended (the derivative index). Uses cached Christoffels.";

GeodesicEquationsFromMetric::usage =
  "GeodesicEquationsFromMetric[g] or GeodesicEquationsFromMetric[g, param] \
returns the geodesic equations as a list of expressions equal to zero. \
Coordinates are promoted to functions of the affine parameter.";

(* OGRe comparison functions for benchmarking *)
CovariantDFromMetricOGRe::usage =
  "CovariantDFromMetricOGRe[t, g] covariant derivative via OGRe. Requires OGRe.";
GeodesicEquationsFromMetricOGRe::usage =
  "GeodesicEquationsFromMetricOGRe[g] geodesic equations via OGRe. Requires OGRe.";

Begin["`Private`"];

(* ------------------------- built-in array implementations ----------------- *)

christoffelArray[coords_, gdown_] := Module[{gup = Inverse[gdown], d = Length[coords]},
  Table[
   (1/2) Sum[
     gup[[a, s]] (D[gdown[[s, c]], coords[[b]]] + D[gdown[[s, b]], coords[[c]]]
        - D[gdown[[b, c]], coords[[s]]]), {s, d}],
   {a, d}, {b, d}, {c, d}] // Simplify];

riemannUpArray[coords_, gamma_] := Module[{d = Length[coords]},
  Table[
   D[gamma[[r, n, s]], coords[[m]]] - D[gamma[[r, m, s]], coords[[n]]]
     + Sum[gamma[[r, m, l]] gamma[[l, n, s]] - gamma[[r, n, l]] gamma[[l, m, s]], {l, d}],
   {r, d}, {s, d}, {m, d}, {n, d}] // Simplify];

riemannDownArray[coords_, gdown_, rup_] := Module[{d = Length[coords]},
  Table[Sum[gdown[[r, a]] rup[[a, s, m, n]], {a, d}], {r, d}, {s, d}, {m, d}, {n, d}]
   // Simplify];

ricciArray[rup_, d_] := Table[Sum[rup[[m, s, m, n]], {m, d}], {s, d}, {n, d}] // Simplify;

ChristoffelFromMetric[g_?CTensorQ] := With[{coords = CTcoords[g]},
  CTensor[coords, {"up", "down", "down"},
   cachedChristoffel[coords, CTcomponents[g]], CTcomponents[g], CTconventions[g]]];

RiemannFromMetric[g_?CTensorQ] := Module[{coords = CTcoords[g], gdown = CTcomponents[g], gamma, rup},
  gamma = cachedChristoffel[coords, gdown];
  rup = riemannUpArray[coords, gamma];
  CTensor[coords, {"down", "down", "down", "down"},
   riemannDownArray[coords, gdown, rup], gdown, CTconventions[g]]];

RicciFromMetric[g_?CTensorQ] := Module[{coords = CTcoords[g], gdown = CTcomponents[g], gamma, rup},
  gamma = cachedChristoffel[coords, gdown];
  rup = riemannUpArray[coords, gamma];
  CTensor[coords, {"down", "down"}, ricciArray[rup, Length[coords]], gdown, CTconventions[g]]];

RicciScalarFromMetric[g_?CTensorQ] := Module[{gdown = CTcomponents[g], ric},
  ric = CTcomponents[RicciFromMetric[g]];
  Simplify[Total[Inverse[gdown] ric, 2]]];

KretschmannFromMetric[g_?CTensorQ] := Module[{gdown = CTcomponents[g], gup, rdown, rup, d = CTdim[g]},
  gup = Inverse[gdown];
  rdown = CTcomponents[RiemannFromMetric[g]];
  rup = Table[
    Sum[gup[[r, a]] gup[[s, b]] gup[[m, c]] gup[[n, e]] rdown[[a, b, c, e]],
     {a, d}, {b, d}, {c, d}, {e, d}], {r, d}, {s, d}, {m, d}, {n, d}];
  Simplify[Total[rdown rup, 4]]];

(* ------------------------- OGRe-backed implementations -------------------- *)

(* OGRe`TNewCoordinates is HoldRest (it clears/protects the coordinate symbols),
   so the symbol list must be injected literally via With -- passing CTcoords[g]
   directly would hand it the unevaluated expression, not {t,x,y,z}. A unique ID
   per call is required so RepeatedTiming re-runs don't collide on OGRe's
   uniqueness constraint. *)
ogreMetric[g_?CTensorQ] := With[{c = CTcoords[g], comps = CTcomponents[g]},
  Module[{id = ToString[Unique["MAm"]]},
   OGRe`TNewCoordinates[id <> "Coords", c];
   OGRe`TNewMetric[id, id <> "Coords", comps];
   id]];

ToOGReMetric[g_?CTensorQ] := ogreMetric[g];

ChristoffelFromMetricOGRe[g_?CTensorQ] := Module[{id = ogreMetric[g], cid},
  cid = OGRe`TCalcChristoffel[id];
  CTensor[CTcoords[g], {"up", "down", "down"},
   OGRe`TGetComponents[cid, {1, -1, -1}, id <> "Coords"], CTcomponents[g], CTconventions[g]]];

RiemannFromMetricOGRe[g_?CTensorQ] := Module[{id = ogreMetric[g], rid},
  rid = OGRe`TCalcRiemannTensor[id];
  CTensor[CTcoords[g], {"down", "down", "down", "down"},
   OGRe`TGetComponents[rid, {-1, -1, -1, -1}, id <> "Coords"], CTcomponents[g], CTconventions[g]]];

RicciFromMetricOGRe[g_?CTensorQ] := Module[{id = ogreMetric[g], rid},
  rid = OGRe`TCalcRicciTensor[id];
  CTensor[CTcoords[g], {"down", "down"},
   OGRe`TGetComponents[rid, {-1, -1}, id <> "Coords"], CTcomponents[g], CTconventions[g]]];

RicciScalarFromMetricOGRe[g_?CTensorQ] := Module[{id = ogreMetric[g], sid},
  sid = OGRe`TCalcRicciScalar[id];
  First@Flatten@{OGRe`TGetComponents[sid, {}, id <> "Coords"]}];

(* ----------------------- Cached Christoffel ------------------------------ *)

(* Share MAuthor's cache so Christoffel is computed once, reused by
   Riemann, Ricci, covariant derivative, and geodesic equations. *)
cachedChristoffel[coords_, gdown_] := Module[
  {key = {"christoffel", Hash[{coords, gdown}]}, c},
  c = CTCacheGet[key];
  If[MissingQ[c], CTCacheStore[key, christoffelArray[coords, gdown]], c]];

(* ----------------------- Covariant Derivative ---------------------------- *)

(* Result indices: {"down"} (derivative) ++ original indices.
   For each upper index of t: +Gamma correction.
   For each lower index of t: -Gamma correction.
   Uses Dot-based contraction (contractMatIndex from MAuthor) for speed. *)

CovariantDFromMetric[t_?CTensorQ, g_?CTensorQ] := Module[
  {coords = CTcoords[g], gdown = CTcomponents[g], gamma,
   arr = CTcomponents[t], idx = CTindices[t],
   d = CTdim[g], r = CTrank[t], pd, result},

  gamma = cachedChristoffel[coords, gdown];

  (* Partial derivative: pd[[mu, i1, ...]] = D[arr[[i1,...]], coords[[mu]]] *)
  pd = Table[D[arr, coords[[mu]]], {mu, d}];
  result = pd;

  (* Gamma corrections for each tensor index *)
  Do[result += gammaCorrectionCD[arr, gamma, idx[[k]], k, r, d], {k, r}];

  result = Simplify[result];
  CTensor[coords, Join[{"down"}, idx], result, gdown, CTconventions[g]]];

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

GeodesicEquationsFromMetric[g_?CTensorQ] :=
  GeodesicEquationsFromMetric[g, Global`\[Lambda]];

GeodesicEquationsFromMetric[g_?CTensorQ, param_] := Module[
  {coords = CTcoords[g], gamma, d = CTdim[g],
   xfuncs, xdot, xddot, gammaOnCurve, eqs},

  gamma = cachedChristoffel[coords, CTcomponents[g]];

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

  Simplify[eqs]];

(* ----------------------- OGRe comparison functions ----------------------- *)

(* Covariant derivative via OGRe *)
CovariantDFromMetricOGRe[t_?CTensorQ, g_?CTensorQ] := Module[
  {metID = ogreMetric[g], tID, covdID, ogreIdx, resultIdx, coords = CTcoords[g]},
  (* Create OGRe tensor from CTensor t *)
  tID = With[{c = CTcoords[t], comps = CTcomponents[t]},
    Module[{id = ToString[Unique["MAcd"]]},
      OGRe`TNewTensor[id, metID <> "Coords",
        Map[If[# === "up", 1, -1] &, CTindices[t]], comps];
      id]];
  covdID = OGRe`TCalcCovariantDerivative[tID, metID];
  (* Result indices: derivative index (down=-1) prepended *)
  ogreIdx = Join[{-1}, Map[If[# === "up", 1, -1] &, CTindices[t]]];
  resultIdx = Join[{"down"}, CTindices[t]];
  CTensor[coords, resultIdx,
    OGRe`TGetComponents[covdID, ogreIdx, metID <> "Coords"],
    CTcomponents[g], CTconventions[g]]];

(* Geodesic equations via OGRe *)
GeodesicEquationsFromMetricOGRe[g_?CTensorQ] :=
  GeodesicEquationsFromMetricOGRe[g, Global`\[Lambda]];

GeodesicEquationsFromMetricOGRe[g_?CTensorQ, param_] := Module[
  {metID = ogreMetric[g]},
  OGRe`TCalcGeodesicEquations[metID, param]];

End[];
EndPackage[];
