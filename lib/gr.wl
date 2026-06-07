(* ::Package:: *)

(* GR` -- general-relativity curvature operators on the Tensor` representation.

   This is the from-scratch reimplementation (zero package dependencies). The
   independent cross-check oracles (OGRe-backed and xAct/xCoba-backed variants,
   the *ViaOGRe / *ViaXAct functions) are the second-library evidence the gate
   uses; they are deferred to the multi-oracle pillar and will be added back
   here, kept equivalent by bench.py + Core`EquivalentQ.

   Sign/index conventions: Christoffel is Levi-Civita,
     Gamma^a_bc = 1/2 g^as (d_b g_sc + d_c g_sb - d_s g_bc),
   Riemann (mixed) R^r_smn = d_m Gamma^r_ns - d_n Gamma^r_ms
       + Gamma^r_ml Gamma^l_ns - Gamma^r_nl Gamma^l_ms,
   lowered R_rsmn = g_ra R^a_smn; Ricci R_sn = R^m_smn; scalar R = g^sn R_sn.
   Matches OGRe's convention (verified componentwise on AdS4). *)

BeginPackage["GR`", {"Core`", "Tensor`"}];

Christoffel::usage =
  "Christoffel[g] gives the Christoffel symbols Gamma^a_bc of a metric Field g \
(indices {down,down}), as a Field with index positions {up,down,down}.";
Riemann::usage =
  "Riemann[g] gives the all-lower Riemann tensor R_{rho sigma mu nu} as a Field \
{down,down,down,down}.";
Ricci::usage = "Ricci[g] gives the Ricci tensor R_{mu nu} as a Field {down,down}.";
RicciScalar::usage = "RicciScalar[g] gives the Ricci scalar (a scalar expression).";
Kretschmann::usage =
  "Kretschmann[g] gives the Kretschmann scalar R_{abcd}R^{abcd} (a \
convention-independent invariant).";
Weyl::usage =
  "Weyl[g] gives the Weyl (conformal) tensor C_{rho sigma mu nu} as a Field \
{down,down,down,down}. Vanishes identically in D<=3.";
Einstein::usage =
  "Einstein[g] gives the Einstein tensor G_{mu nu} = R_{mu nu} - (1/2) R g_{mu nu}.";
TracelessRicci::usage =
  "TracelessRicci[g] gives S_{mu nu} = R_{mu nu} - (1/D) R g_{mu nu} (trace-free).";
Killing::usage =
  "Killing[g] returns the Killing equation system as {eq1 == 0, ...} for D \
unknown functions \\[Xi][1][coords], ..., \\[Xi][D][coords]. D(D+1)/2 equations.";
CovariantD::usage =
  "CovariantD[t, g] covariant derivative of Field t w.r.t. the Levi-Civita \
connection of g; prepends one \"down\" (derivative) index.";
Geodesic::usage =
  "Geodesic[g] or Geodesic[g, param] returns the geodesic equations as a list of \
expressions equal to zero (coordinates promoted to functions of the parameter).";
Hamiltonian::usage =
  "Hamiltonian[g, p] gives H = g^{mu nu} p_mu p_nu for a momentum covector p \
(length-D list of lower components p_mu).";

Begin["`Private`"];

(* ------------------------- built-in array implementations ----------------- *)

(* Christoffel: pre-Christoffel (derivatives only) then contract with g^{-1}. *)
christoffelArray[coords_, gdown_] := Module[{ginv, d = Length[coords], preChris},
  ginv = cachedInverse[gdown];
  preChris = Table[
    D[gdown[[k, i]], coords[[j]]] + D[gdown[[j, k]], coords[[i]]]
      - D[gdown[[i, j]], coords[[k]]],
    {k, d}, {i, d}, {j, d}];
  preChris = Core`$Simplify[preChris];
  Core`$Simplify[(1/2) ginv . preChris]];

(* PreRiemann antisymmetrization: kernel d_m Gamma^r_ns + Gamma^r_ml Gamma^l_ns,
   then R^r_smn = PreR[r,s,m,n] - PreR[r,s,n,m]. *)
riemannUpArray[coords_, gamma_] := Module[{d = Length[coords], preR},
  preR = Table[
    D[gamma[[r, n, s]], coords[[m]]]
      + Sum[gamma[[r, m, l]] gamma[[l, n, s]], {l, d}],
    {r, d}, {s, d}, {m, d}, {n, d}];
  Core`$Simplify[preR - Transpose[preR, {1, 2, 4, 3}]]];

riemannDownArray[gdown_, rup_] := Core`$Simplify[gdown . rup];

(* Direct Ricci from Christoffel: R^m_{smn} summed over m, no full Riemann. *)
ricciDirectArray[coords_, gamma_] := Module[{d = Length[coords]},
  Core`$Simplify[Table[
    Sum[D[gamma[[m, n, s]], coords[[m]]] - D[gamma[[m, m, s]], coords[[n]]]
      + Sum[gamma[[m, m, l]] gamma[[l, n, s]] - gamma[[m, n, l]] gamma[[l, m, s]], {l, d}],
    {m, d}],
  {s, d}, {n, d}]]];

(* Share Core's cache so Christoffel is computed once, reused downstream. *)
cachedChristoffel[coords_, gdown_] := Module[
  {key = {"christoffel", Hash[{coords, gdown}]}, c},
  c = CacheGet[key];
  If[MissingQ[c], CacheStore[key, christoffelArray[coords, gdown]], c]];

Christoffel[g_?FieldQ] := With[{coords = Coords[g]},
  Field[coords, {"up", "down", "down"},
   cachedChristoffel[coords, Components[g]], Components[g], Conventions[g]]];

Riemann[g_?FieldQ] := Module[{coords = Coords[g], gdown = Components[g], gamma, rup},
  gamma = cachedChristoffel[coords, gdown];
  rup = riemannUpArray[coords, gamma];
  Field[coords, {"down", "down", "down", "down"},
   riemannDownArray[gdown, rup], gdown, Conventions[g]]];

Ricci[g_?FieldQ] := Module[{coords = Coords[g], gdown = Components[g], gamma},
  gamma = cachedChristoffel[coords, gdown];
  Field[coords, {"down", "down"}, ricciDirectArray[coords, gamma], gdown, Conventions[g]]];

RicciScalar[g_?FieldQ] := Module[{gdown = Components[g], ric},
  ric = Components[Ricci[g]];
  Core`$Simplify[Total[cachedInverse[gdown] ric, 2]]];

(* Kretschmann: raise last 2 indices, then pair symmetry R_{abcd}=R_{cdab}. *)
Kretschmann[g_?FieldQ] := Module[{gdown = Components[g], ginv, rdown, rmixed},
  ginv = cachedInverse[gdown];
  rdown = Components[Riemann[g]];
  rmixed = rdown;
  Do[rmixed = contractMatIndex[ginv, rmixed, k, 4], {k, 3, 4}];
  Core`$Simplify[Total[Transpose[rmixed, {3, 4, 1, 2}] rmixed, 4]]];

(* Weyl: C = R - (1/(D-2)) s1 + (R/((D-1)(D-2))) s2. *)
Weyl[g_?FieldQ] := Module[
  {coords = Coords[g], gdown = Components[g], dim = Dim[g],
   rdown, ricdown, rscalar, s1, s2, weyl},
  If[dim <= 2, Return[Field[coords, {"down","down","down","down"},
    ConstantArray[0, {dim,dim,dim,dim}], gdown, Conventions[g]]]];
  rdown = Components[Riemann[g]];
  ricdown = Components[Ricci[g]];
  rscalar = RicciScalar[g];
  s1 = Table[
    gdown[[aa,cc]] ricdown[[dd,bb]] - gdown[[aa,dd]] ricdown[[cc,bb]]
    - gdown[[bb,cc]] ricdown[[dd,aa]] + gdown[[bb,dd]] ricdown[[cc,aa]],
    {aa, dim}, {bb, dim}, {cc, dim}, {dd, dim}];
  s2 = Table[
    gdown[[aa,cc]] gdown[[bb,dd]] - gdown[[aa,dd]] gdown[[bb,cc]],
    {aa, dim}, {bb, dim}, {cc, dim}, {dd, dim}];
  weyl = rdown - (1/(dim - 2)) s1 + (rscalar/((dim - 1)(dim - 2))) s2;
  Field[coords, {"down","down","down","down"}, Core`$Simplify[weyl], gdown, Conventions[g]]];

Einstein[g_?FieldQ] := Module[
  {coords = Coords[g], gdown = Components[g], ricdown, rscalar},
  ricdown = Components[Ricci[g]];
  rscalar = RicciScalar[g];
  Field[coords, {"down","down"},
   Core`$Simplify[ricdown - (1/2) rscalar gdown], gdown, Conventions[g]]];

TracelessRicci[g_?FieldQ] := Module[
  {coords = Coords[g], gdown = Components[g], dim = Dim[g], ricdown, rscalar},
  ricdown = Components[Ricci[g]];
  rscalar = RicciScalar[g];
  Field[coords, {"down","down"},
   Core`$Simplify[ricdown - (1/dim) rscalar gdown], gdown, Conventions[g]]];

(* Killing: d_mu xi_nu + d_nu xi_mu - 2 Gamma^a_{mu nu} xi_a = 0. *)
Killing[g_?FieldQ] := Module[
  {coords = Coords[g], gdown = Components[g], dim = Dim[g], gamma, xiLow},
  gamma = cachedChristoffel[coords, gdown];
  xiLow = Table[Global`\[Xi][mu] @@ coords, {mu, dim}];
  Flatten@Table[
    Core`$Simplify[
      D[xiLow[[nu]], coords[[mu]]] + D[xiLow[[mu]], coords[[nu]]]
      - 2 Sum[gamma[[aa, mu, nu]] xiLow[[aa]], {aa, dim}]] == 0,
    {mu, dim}, {nu, mu, dim}]];

(* ----------------------- Covariant Derivative ---------------------------- *)

CovariantD[t_?FieldQ, g_?FieldQ] := Module[
  {coords = Coords[g], gdown = Components[g], gamma,
   arr = Components[t], idx = Indices[t], d = Dim[g], r = Rank[t], pd, result},
  gamma = cachedChristoffel[coords, gdown];
  pd = Table[D[arr, coords[[mu]]], {mu, d}];
  result = pd;
  Do[result += gammaCorrectionCD[arr, gamma, idx[[k]], k, r, d], {k, r}];
  result = Core`$Simplify[result];
  Field[coords, Join[{"down"}, idx], result, gdown, Conventions[g]]];

gammaCorrectionCD[arr_, gamma_, idxType_String, k_Integer, rank_Integer, d_Integer] :=
 Module[{moved, correction, perm},
  If[rank > 1,
    perm = Join[{k}, Delete[Range[rank], k]];
    moved = Transpose[arr, perm],
    moved = arr];
  If[idxType === "up",
    correction = Table[gamma[[All, mu, All]] . moved, {mu, d}],
    correction = -Table[Transpose[gamma[[All, mu, All]]] . moved, {mu, d}]];
  If[rank > 1 && k > 1,
    Module[{cperm = Join[{1}, Range[3, k + 1], {2}, Range[k + 2, rank + 1]]},
      correction = Transpose[correction, cperm]]];
  correction];

(* ----------------------- Geodesic Equations ------------------------------ *)

Geodesic[g_?FieldQ] := Geodesic[g, Global`\[Lambda]];

Geodesic[g_?FieldQ, param_] := Module[
  {coords = Coords[g], gamma, d = Dim[g], xfuncs, xdot, xddot, gammaOnCurve},
  gamma = cachedChristoffel[coords, Components[g]];
  xfuncs = Through[coords[param]];
  xdot = D[xfuncs, param];
  xddot = D[xdot, param];
  gammaOnCurve = gamma /. Thread[coords -> xfuncs];
  Core`$Simplify[Table[
    xddot[[mu]] + Sum[gammaOnCurve[[mu, a, b]] xdot[[a]] xdot[[b]], {a, d}, {b, d}],
    {mu, d}]]];

(* ----------------------- Geodesic Hamiltonian ---------------------------- *)

Hamiltonian::baddim = "Momentum covector length `1` does not match metric dimension `2`.";
Hamiltonian[g_?FieldQ, p_List] := Module[{ginv, d = Dim[g]},
  If[Length[p] =!= d,
    Message[Hamiltonian::baddim, Length[p], d]; Return[$Failed]];
  ginv = cachedInverse[Components[g]];
  Core`$Simplify[p . ginv . p]];

End[];
EndPackage[];
