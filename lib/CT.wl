(* ::Package:: *)

(* CT` -- core substrate for the mathematica-author skill library.

   Defines the canonical component-level tensor representation (the interop
   layer that lets OGRe / xAct / built-in computations compose) and the
   equivalence primitive EquivalentQ (the correctness gate the benchmark
   harness uses before any implementation is promoted into the library).

   Deliberately NARROW: a tensor is its components in a coordinate basis plus
   index positions, the metric it lives with, and conventions. This is NOT an
   abstract-index algebra -- that overreach is explicitly out of scope. *)

BeginPackage["CT`"];

Tensor::usage =
  "Tensor[coords, indices, components, metric, conventions] builds a canonical \
tensor record (an Association). indices is a list of \"up\"/\"down\" of length \
rank; components is the array in the coordinate basis; metric is the all-down \
metric components in the same coords; conventions is an Association.";
TensQ::usage = "TensQ[t] tests whether t is a well-formed canonical tensor.";
Coords::usage = "Coords[t] gives the coordinate symbols.";
Components::usage = "Components[t] gives the component array.";
Indices::usage = "Indices[t] gives the list of index positions.";
Metric::usage = "Metric[t] gives the all-down metric components.";
Conventions::usage = "Conventions[t] gives the conventions Association.";
Dim::usage = "Dim[t] gives the spacetime dimension (Length of coords).";
Rank::usage = "Rank[t] gives the tensor rank (Length of indices).";

(* --- Index manipulation --- *)
Raise::usage =
  "Raise[t, n] or Raise[t, n, g] raises index n of Tensor t using the metric \
(from t's metric field, or the explicit metric g). Index n must be \"down\".";
Lower::usage =
  "Lower[t, n] or Lower[t, n, g] lowers index n. Index n must be \"up\".";

(* --- Contraction / products --- *)
Trc::usage =
  "Trc[t, {i, j}] contracts (traces) indices i and j of Tensor t. One must be \
\"up\" and the other \"down\". Returns a Tensor of rank r-2, or a scalar if r=2.";
Prod::usage =
  "Prod[t1, t2] tensor (outer) product. Result has rank r1+r2.";
Contract::usage =
  "Contract[t1, i, t2, j] contracts index i of t1 with index j of t2 (one up, \
one down). Equivalent to Trc[Prod[...], ...] but stated directly.";

(* --- Coordinate transformation --- *)
Transform::usage =
  "Transform[t, newCoords, rules] transforms Tensor t to new coordinates. \
rules = {old1 -> f1[newCoords], old2 -> f2[newCoords], ...} is the backward map \
(old coords as functions of new). Transforms components and the stored metric.";

(* --- Cache (shared with MAuthorGR) --- *)
$Cache::usage = "Internal computation cache. Use CacheClear[] to reset.";
CacheClear::usage = "CacheClear[] clears the computation cache (inverse metrics, Christoffels, etc.).";
CacheStore::usage = "CacheStore[key, val] stores in the shared cache (internal API for MAuthorGR).";
CacheGet::usage = "CacheGet[key] retrieves from cache; Missing[] if absent (internal API).";

If[!AssociationQ[$Cache], $Cache = <||>];

EquivalentQ::usage =
  "EquivalentQ[a, b] returns True if a and b are equal, False if they provably \
differ, and $Failed if undecided. Scalars/expressions: symbolic zero-difference \
(PossibleZeroQ, then FullSimplify) with a randomized numeric spot-check fallback. \
Arrays: same dimensions, elementwise. Canonical tensors: same coords + index \
positions, components elementwise.";

Begin["`Private`"];

Tensor[coords_List, indices_List, components_, metric_: Automatic,
   conventions_Association: <||>] :=
  <|"type" -> "Tensor", "coords" -> coords, "indices" -> indices,
    "components" -> components, "metric" -> metric, "conventions" -> conventions|>;

TensQ[t_] := AssociationQ[t] && Lookup[t, "type", None] === "Tensor" &&
   ListQ[t["coords"]] && ListQ[t["indices"]];

Coords[t_] := t["coords"];
Components[t_] := t["components"];
Indices[t_] := t["indices"];
Metric[t_] := t["metric"];
Conventions[t_] := t["conventions"];
Dim[t_] := Length[t["coords"]];
Rank[t_] := Length[t["indices"]];

(* free (user, non-System`) symbols anywhere in an expression *)
freeVars[expr_] := DeleteDuplicates@
   Cases[expr, _Symbol?(Context[#] =!= "System`" &), {0, Infinity}, Heads -> True];

(* numeric spot-check that an expression is identically zero. Samples positive
   reals (physics variables -- radii, lengths -- are usually positive, which
   avoids spurious branch-cut/complex values) and requires every sample ~0. *)
numericZeroQ[d_] := Module[{vars = freeVars[d], samples},
   If[vars === {},
    Return[TrueQ[Chop[N[d], 10^-10] == 0]]];
   samples = Table[
     Quiet@Check[
       Chop[N[d /. Thread[vars -> RandomReal[{1, 3}, Length[vars]]]], 10^-8],
       $Failed], {12}];
   If[MemberQ[samples, $Failed] || ! VectorQ[samples, NumericQ],
    $Failed,
    AllTrue[samples, # === 0 &]]];

scalarEquivalentQ[a_, b_] := Module[{d = a - b, num},
   If[TrueQ[PossibleZeroQ[d]], Return[True]];
   If[TrueQ[FullSimplify[d] === 0], Return[True]];
   num = numericZeroQ[d];
   Which[
    num === True, True,        (* symbolic said maybe-nonzero, numeric says zero *)
    num === False, False,      (* numerically nonzero -> provably differ *)
    True, $Failed]];           (* undecided *)

arrayEquivalentQ[a_, b_] := Module[{fa, fb, pairs},
   If[Dimensions[a] =!= Dimensions[b], Return[False]];
   fa = Flatten[{a}]; fb = Flatten[{b}];
   pairs = scalarEquivalentQ @@@ Transpose[{fa, fb}];
   Which[
    MemberQ[pairs, False], False,
    MemberQ[pairs, $Failed], $Failed,
    True, True]];

EquivalentQ[a_?TensQ, b_?TensQ] :=
   If[a["coords"] =!= b["coords"] || a["indices"] =!= b["indices"],
    False,
    arrayEquivalentQ[a["components"], b["components"]]];
EquivalentQ[a_?TensQ, _] := False;
EquivalentQ[_, b_?TensQ] := False;
EquivalentQ[a_List, b_List] := arrayEquivalentQ[a, b];
EquivalentQ[a_List, _] := False;
EquivalentQ[_, b_List] := False;
EquivalentQ[a_, b_] := scalarEquivalentQ[a, b];

(* ====================== Cache ============================================= *)

CacheClear[] := ($Cache = <||>);
CacheStore[key_, val_] := ($Cache[key] = val);
CacheGet[key_] := $Cache[key];

cachedInverse[m_] := Module[{key = {"inv", Hash[m]}, c},
  c = $Cache[key];
  If[MissingQ[c], $Cache[key] = Inverse[m], c]];

(* ====================== Core helper ======================================= *)

(* Contract a d*d matrix with the k-th index of a rank-r array.
   mat . arr contracts mat's last index with arr's first, so we
   Transpose arr to move index k to position 1, Dot, Transpose back.
   This leverages Dot's internal optimisation (BLAS path for packed
   numeric arrays, and well-optimised symbolic path). *)
contractMatIndex[mat_, arr_, k_, rank_] :=
  If[rank <= 1 || k == 1,
    mat . arr,
    Module[{perm = Join[{k}, Delete[Range[rank], k]]},
      Transpose[mat . Transpose[arr, perm], Ordering[perm]]]];

(* ====================== Index raising / lowering ========================== *)

Raise::nomet = "No metric available; pass it explicitly: Raise[t, n, g].";
Raise::notdown = "Index `1` is already \"up\"; cannot raise.";
Lower::nomet = "No metric available; pass it explicitly: Lower[t, n, g].";
Lower::notup = "Index `1` is already \"down\"; cannot lower.";

(* Extract the all-down metric matrix from a Tensor.
   For metric tensors themselves (indices {"down","down"}, metric Automatic),
   the components ARE the metric. *)
getMetricDown[t_?TensQ] := Module[{m = Metric[t]},
  If[m =!= Automatic, m,
    If[Indices[t] === {"down", "down"}, Components[t], Automatic]]];

(* Primary entry: explicit metric matrix *)
Raise[t_?TensQ, n_Integer, gdown_?MatrixQ] := Module[
  {idx = Indices[t], r = Rank[t], ginv, arr},
  If[idx[[n]] =!= "down", Message[Raise::notdown, n]; Return[$Failed]];
  ginv = cachedInverse[gdown];
  arr = Simplify[contractMatIndex[ginv, Components[t], n, r]];
  Tensor[Coords[t], ReplacePart[idx, n -> "up"], arr, gdown, Conventions[t]]];

(* Metric passed as Tensor *)
Raise[t_?TensQ, n_Integer, g_?TensQ] :=
  Raise[t, n, getMetricDown[g]];

(* Infer metric from tensor *)
Raise[t_?TensQ, n_Integer] := Module[{gd = getMetricDown[t]},
  If[gd === Automatic, (Message[Raise::nomet]; $Failed), Raise[t, n, gd]]];

Lower[t_?TensQ, n_Integer, gdown_?MatrixQ] := Module[
  {idx = Indices[t], r = Rank[t], arr},
  If[idx[[n]] =!= "up", Message[Lower::notup, n]; Return[$Failed]];
  arr = Simplify[contractMatIndex[gdown, Components[t], n, r]];
  Tensor[Coords[t], ReplacePart[idx, n -> "down"], arr, gdown, Conventions[t]]];

Lower[t_?TensQ, n_Integer, g_?TensQ] :=
  Lower[t, n, getMetricDown[g]];

Lower[t_?TensQ, n_Integer] := Module[{gd = getMetricDown[t]},
  If[gd === Automatic, (Message[Lower::nomet]; $Failed), Lower[t, n, gd]]];

(* ====================== Trace / contraction =============================== *)

Trace::badpair = "Need one \"up\" and one \"down\"; got \"`1`\" and \"`2`\".";

Trc[t_?TensQ, {i_Integer, j_Integer}] := Module[
  {idx = Indices[t], contracted, newIdx},
  If[Sort[{idx[[i]], idx[[j]]}] =!= {"down", "up"},
    Message[Trace::badpair, idx[[i]], idx[[j]]]; Return[$Failed]];
  contracted = Simplify[TensorContract[Components[t], {{i, j}}]];
  newIdx = Delete[idx, {{i}, {j}}];
  If[newIdx === {},
    contracted,
    Tensor[Coords[t], newIdx, contracted, Metric[t], Conventions[t]]]];

(* ====================== Tensor product ==================================== *)

Prod[t1_?TensQ, t2_?TensQ] :=
  Tensor[Coords[t1],
    Join[Indices[t1], Indices[t2]],
    Outer[Times, Components[t1], Components[t2]],
    Metric[t1], Conventions[t1]];

(* ====================== Contract (product + trace) ======================== *)

Contract[t1_?TensQ, i_Integer, t2_?TensQ, j_Integer] :=
  Trc[Prod[t1, t2], {i, Rank[t1] + j}];

(* ====================== Coordinate transformation ======================== *)

Transform[t_?TensQ, newCoords_List, rules_List] := Module[
  {oldCoords = Coords[t], idx = Indices[t], d = Dim[t], r = Rank[t],
   oldExprs, backJac, fwdJac, arr, gdown},

  (* Backward map: old coordinates as functions of new *)
  oldExprs = oldCoords /. rules;

  (* Backward Jacobian M_{mu,mu'} = d(old_mu)/d(new_{mu'}) *)
  backJac = Simplify[Table[D[oldExprs[[mu]], newCoords[[mup]]],
    {mu, d}, {mup, d}]];

  (* Forward Jacobian for contravariant indices *)
  fwdJac = Simplify[Inverse[backJac]];

  (* Substitute old -> new in components *)
  arr = Components[t] /. rules;

  (* Transform each index:
       down  -> contract with Transpose[backJac] (= M^T)
       up    -> contract with fwdJac              (= M^{-1}) *)
  Do[arr = contractMatIndex[
      If[idx[[k]] === "down", Transpose[backJac], fwdJac], arr, k, r],
    {k, r}];
  arr = Simplify[arr];

  (* Transform the stored metric (always all-down rank-2) *)
  gdown = Metric[t];
  If[gdown =!= Automatic,
    gdown = Simplify[Transpose[backJac] . (gdown /. rules) . backJac]];

  Tensor[newCoords, idx, arr, gdown, Conventions[t]]];

End[];
EndPackage[];
