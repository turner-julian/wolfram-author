(* ::Package:: *)

(* MAuthor` -- core substrate for the mathematica-author skill library.

   Defines the canonical component-level tensor representation (the interop
   layer that lets OGRe / xAct / built-in computations compose) and the
   equivalence primitive EquivalentQ (the correctness gate the benchmark
   harness uses before any implementation is promoted into the library).

   Deliberately NARROW: a tensor is its components in a coordinate basis plus
   index positions, the metric it lives with, and conventions. This is NOT an
   abstract-index algebra -- that overreach is explicitly out of scope. *)

BeginPackage["MAuthor`"];

CTensor::usage =
  "CTensor[coords, indices, components, metric, conventions] builds a canonical \
tensor record (an Association). indices is a list of \"up\"/\"down\" of length \
rank; components is the array in the coordinate basis; metric is the all-down \
metric components in the same coords; conventions is an Association.";
CTensorQ::usage = "CTensorQ[t] tests whether t is a well-formed canonical tensor.";
CTcoords::usage = "CTcoords[t] gives the coordinate symbols.";
CTcomponents::usage = "CTcomponents[t] gives the component array.";
CTindices::usage = "CTindices[t] gives the list of index positions.";
CTmetric::usage = "CTmetric[t] gives the all-down metric components.";
CTconventions::usage = "CTconventions[t] gives the conventions Association.";
CTdim::usage = "CTdim[t] gives the spacetime dimension (Length of coords).";
CTrank::usage = "CTrank[t] gives the tensor rank (Length of indices).";

(* --- Index manipulation --- *)
CTRaise::usage =
  "CTRaise[t, n] or CTRaise[t, n, g] raises index n of CTensor t using the metric \
(from t's metric field, or the explicit metric g). Index n must be \"down\".";
CTLower::usage =
  "CTLower[t, n] or CTLower[t, n, g] lowers index n. Index n must be \"up\".";

(* --- Contraction / products --- *)
CTTrace::usage =
  "CTTrace[t, {i, j}] contracts (traces) indices i and j of CTensor t. One must be \
\"up\" and the other \"down\". Returns a CTensor of rank r-2, or a scalar if r=2.";
CTProduct::usage =
  "CTProduct[t1, t2] tensor (outer) product. Result has rank r1+r2.";
CTContract::usage =
  "CTContract[t1, i, t2, j] contracts index i of t1 with index j of t2 (one up, \
one down). Equivalent to CTTrace[CTProduct[...], ...] but stated directly.";

(* --- Coordinate transformation --- *)
CTTransform::usage =
  "CTTransform[t, newCoords, rules] transforms CTensor t to new coordinates. \
rules = {old1 -> f1[newCoords], old2 -> f2[newCoords], ...} is the backward map \
(old coords as functions of new). Transforms components and the stored metric.";

(* --- Cache (shared with MAuthorGR) --- *)
$MAuthorCache::usage = "Internal computation cache. Use CTCacheClear[] to reset.";
CTCacheClear::usage = "CTCacheClear[] clears the computation cache (inverse metrics, Christoffels, etc.).";
CTCacheStore::usage = "CTCacheStore[key, val] stores in the shared cache (internal API for MAuthorGR).";
CTCacheGet::usage = "CTCacheGet[key] retrieves from cache; Missing[] if absent (internal API).";

If[!AssociationQ[$MAuthorCache], $MAuthorCache = <||>];

EquivalentQ::usage =
  "EquivalentQ[a, b] returns True if a and b are equal, False if they provably \
differ, and $Failed if undecided. Scalars/expressions: symbolic zero-difference \
(PossibleZeroQ, then FullSimplify) with a randomized numeric spot-check fallback. \
Arrays: same dimensions, elementwise. Canonical tensors: same coords + index \
positions, components elementwise.";

Begin["`Private`"];

CTensor[coords_List, indices_List, components_, metric_: Automatic,
   conventions_Association: <||>] :=
  <|"type" -> "CTensor", "coords" -> coords, "indices" -> indices,
    "components" -> components, "metric" -> metric, "conventions" -> conventions|>;

CTensorQ[t_] := AssociationQ[t] && Lookup[t, "type", None] === "CTensor" &&
   ListQ[t["coords"]] && ListQ[t["indices"]];

CTcoords[t_] := t["coords"];
CTcomponents[t_] := t["components"];
CTindices[t_] := t["indices"];
CTmetric[t_] := t["metric"];
CTconventions[t_] := t["conventions"];
CTdim[t_] := Length[t["coords"]];
CTrank[t_] := Length[t["indices"]];

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

EquivalentQ[a_?CTensorQ, b_?CTensorQ] :=
   If[a["coords"] =!= b["coords"] || a["indices"] =!= b["indices"],
    False,
    arrayEquivalentQ[a["components"], b["components"]]];
EquivalentQ[a_?CTensorQ, _] := False;
EquivalentQ[_, b_?CTensorQ] := False;
EquivalentQ[a_List, b_List] := arrayEquivalentQ[a, b];
EquivalentQ[a_List, _] := False;
EquivalentQ[_, b_List] := False;
EquivalentQ[a_, b_] := scalarEquivalentQ[a, b];

(* ====================== Cache ============================================= *)

CTCacheClear[] := ($MAuthorCache = <||>);
CTCacheStore[key_, val_] := ($MAuthorCache[key] = val);
CTCacheGet[key_] := $MAuthorCache[key];

cachedInverse[m_] := Module[{key = {"inv", Hash[m]}, c},
  c = $MAuthorCache[key];
  If[MissingQ[c], $MAuthorCache[key] = Inverse[m], c]];

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

CTRaise::nomet = "No metric available; pass it explicitly: CTRaise[t, n, g].";
CTRaise::notdown = "Index `1` is already \"up\"; cannot raise.";
CTLower::nomet = "No metric available; pass it explicitly: CTLower[t, n, g].";
CTLower::notup = "Index `1` is already \"down\"; cannot lower.";

(* Extract the all-down metric matrix from a CTensor.
   For metric tensors themselves (indices {"down","down"}, metric Automatic),
   the components ARE the metric. *)
getMetricDown[t_?CTensorQ] := Module[{m = CTmetric[t]},
  If[m =!= Automatic, m,
    If[CTindices[t] === {"down", "down"}, CTcomponents[t], Automatic]]];

(* Primary entry: explicit metric matrix *)
CTRaise[t_?CTensorQ, n_Integer, gdown_?MatrixQ] := Module[
  {idx = CTindices[t], r = CTrank[t], ginv, arr},
  If[idx[[n]] =!= "down", Message[CTRaise::notdown, n]; Return[$Failed]];
  ginv = cachedInverse[gdown];
  arr = Simplify[contractMatIndex[ginv, CTcomponents[t], n, r]];
  CTensor[CTcoords[t], ReplacePart[idx, n -> "up"], arr, gdown, CTconventions[t]]];

(* Metric passed as CTensor *)
CTRaise[t_?CTensorQ, n_Integer, g_?CTensorQ] :=
  CTRaise[t, n, getMetricDown[g]];

(* Infer metric from tensor *)
CTRaise[t_?CTensorQ, n_Integer] := Module[{gd = getMetricDown[t]},
  If[gd === Automatic, (Message[CTRaise::nomet]; $Failed), CTRaise[t, n, gd]]];

CTLower[t_?CTensorQ, n_Integer, gdown_?MatrixQ] := Module[
  {idx = CTindices[t], r = CTrank[t], arr},
  If[idx[[n]] =!= "up", Message[CTLower::notup, n]; Return[$Failed]];
  arr = Simplify[contractMatIndex[gdown, CTcomponents[t], n, r]];
  CTensor[CTcoords[t], ReplacePart[idx, n -> "down"], arr, gdown, CTconventions[t]]];

CTLower[t_?CTensorQ, n_Integer, g_?CTensorQ] :=
  CTLower[t, n, getMetricDown[g]];

CTLower[t_?CTensorQ, n_Integer] := Module[{gd = getMetricDown[t]},
  If[gd === Automatic, (Message[CTLower::nomet]; $Failed), CTLower[t, n, gd]]];

(* ====================== Trace / contraction =============================== *)

CTTrace::badpair = "Need one \"up\" and one \"down\"; got \"`1`\" and \"`2`\".";

CTTrace[t_?CTensorQ, {i_Integer, j_Integer}] := Module[
  {idx = CTindices[t], contracted, newIdx},
  If[Sort[{idx[[i]], idx[[j]]}] =!= {"down", "up"},
    Message[CTTrace::badpair, idx[[i]], idx[[j]]]; Return[$Failed]];
  contracted = Simplify[TensorContract[CTcomponents[t], {{i, j}}]];
  newIdx = Delete[idx, {{i}, {j}}];
  If[newIdx === {},
    contracted,
    CTensor[CTcoords[t], newIdx, contracted, CTmetric[t], CTconventions[t]]]];

(* ====================== Tensor product ==================================== *)

CTProduct[t1_?CTensorQ, t2_?CTensorQ] :=
  CTensor[CTcoords[t1],
    Join[CTindices[t1], CTindices[t2]],
    Outer[Times, CTcomponents[t1], CTcomponents[t2]],
    CTmetric[t1], CTconventions[t1]];

(* ====================== Contract (product + trace) ======================== *)

CTContract[t1_?CTensorQ, i_Integer, t2_?CTensorQ, j_Integer] :=
  CTTrace[CTProduct[t1, t2], {i, CTrank[t1] + j}];

(* ====================== Coordinate transformation ======================== *)

CTTransform[t_?CTensorQ, newCoords_List, rules_List] := Module[
  {oldCoords = CTcoords[t], idx = CTindices[t], d = CTdim[t], r = CTrank[t],
   oldExprs, backJac, fwdJac, arr, gdown},

  (* Backward map: old coordinates as functions of new *)
  oldExprs = oldCoords /. rules;

  (* Backward Jacobian M_{mu,mu'} = d(old_mu)/d(new_{mu'}) *)
  backJac = Simplify[Table[D[oldExprs[[mu]], newCoords[[mup]]],
    {mu, d}, {mup, d}]];

  (* Forward Jacobian for contravariant indices *)
  fwdJac = Simplify[Inverse[backJac]];

  (* Substitute old -> new in components *)
  arr = CTcomponents[t] /. rules;

  (* Transform each index:
       down  -> contract with Transpose[backJac] (= M^T)
       up    -> contract with fwdJac              (= M^{-1}) *)
  Do[arr = contractMatIndex[
      If[idx[[k]] === "down", Transpose[backJac], fwdJac], arr, k, r],
    {k, r}];
  arr = Simplify[arr];

  (* Transform the stored metric (always all-down rank-2) *)
  gdown = CTmetric[t];
  If[gdown =!= Automatic,
    gdown = Simplify[Transpose[backJac] . (gdown /. rules) . backJac]];

  CTensor[newCoords, idx, arr, gdown, CTconventions[t]]];

End[];
EndPackage[];
