(* ::Package:: *)

(* Tensor` -- the tensor-field datatype + index algebra, built on Core`.

   A tensor is its components in a coordinate basis, the index positions, the
   metric it lives with, and conventions. This is the component-level interop
   layer (the form OGRe / xAct / built-in computations compose through). It is
   NOT an abstract-index algebra. Shared by GR` and any indexed-tensor
   discipline; finite-dim disciplines (QEC, ...) do not load it. *)

BeginPackage["Tensor`", {"Core`"}];

Field::usage =
  "Field[coords, indices, components, metric:Automatic, conventions:<||>] builds \
a tensor object (a Core verified-object whose payload holds coords/indices/\
components/metric). indices: list of \"up\"/\"down\"; components: array in the \
coordinate basis; metric: all-down metric components.";
FieldQ::usage = "FieldQ[t] tests for a tensor object.";
Coords::usage = "Coords[t] gives the coordinate symbols.";
Components::usage = "Components[t] gives the component array.";
Indices::usage = "Indices[t] gives the list of index positions.";
Metric::usage = "Metric[t] gives the all-down metric components.";
Dim::usage = "Dim[t] gives the spacetime dimension.";
Rank::usage = "Rank[t] gives the tensor rank.";

Raise::usage = "Raise[t, n] or Raise[t, n, g] raises index n (must be \"down\").";
Lower::usage = "Lower[t, n] or Lower[t, n, g] lowers index n (must be \"up\").";
Trc::usage = "Trc[t, {i, j}] contracts indices i and j (one up, one down).";
Prod::usage = "Prod[t1, t2] tensor (outer) product.";
Contract::usage = "Contract[t1, i, t2, j] contracts index i of t1 with index j of t2.";
Transform::usage = "Transform[t, newCoords, rules] coordinate transformation.";
contractMatIndex::usage = "contractMatIndex[mat, arr, k, rank] contracts a d*d matrix with the k-th index of a rank-r array.";

Begin["`Private`"];

Field[coords_List, indices_List, components_, metric_: Automatic,
   conventions_Association: <||>] :=
  <|"type" -> "Tensor", "rep" -> "components",
    "payload" -> <|"coords" -> coords, "indices" -> indices,
       "components" -> components, "metric" -> metric|>,
    "conventions" -> conventions, "provenance" -> <||>|>;

FieldQ[t_] := AssociationQ[t] && Lookup[t, "type", None] === "Tensor" &&
   AssociationQ[Lookup[t, "payload", None]] &&
   ListQ[t["payload"]["coords"]] && ListQ[t["payload"]["indices"]];

Coords[t_] := t["payload"]["coords"];
Components[t_] := t["payload"]["components"];
Indices[t_] := t["payload"]["indices"];
Metric[t_] := t["payload"]["metric"];
Dim[t_] := Length[Coords[t]];
Rank[t_] := Length[Indices[t]];

(* ---- EquivalentQ method for tensors (a downvalue on Core's symbol) ---- *)
Core`EquivalentQ[a_?FieldQ, b_?FieldQ] :=
   If[Coords[a] =!= Coords[b] || Indices[a] =!= Indices[b],
    False,
    Core`arrayEquivalentQ[Components[a], Components[b]]];
Core`EquivalentQ[a_?FieldQ, _] := False;
Core`EquivalentQ[_, b_?FieldQ] := False;

(* ---- core helper: contract a d*d matrix with the k-th index of a rank-r array.
   Transpose arr to move index k to position 1, Dot, Transpose back (BLAS path
   for packed numerics). perm = {2,...,k,1,k+1,...,rank}. ---- *)
contractMatIndex[mat_, arr_, k_, rank_] :=
  If[rank <= 1 || k == 1,
    mat . arr,
    Module[{perm = Join[Range[2, k], {1}, Range[k + 1, rank]]},
      Transpose[mat . Transpose[arr, perm], Ordering[perm]]]];

(* ---- index raising / lowering ---- *)
Raise::nomet = "No metric available; pass it explicitly: Raise[t, n, g].";
Raise::notdown = "Index `1` is already \"up\"; cannot raise.";
Lower::nomet = "No metric available; pass it explicitly: Lower[t, n, g].";
Lower::notup = "Index `1` is already \"down\"; cannot lower.";

(* the all-down metric matrix from a Tensor; for a metric tensor itself
   (indices {down,down}, metric Automatic) the components ARE the metric. *)
getMetricDown[t_?FieldQ] := Module[{m = Metric[t]},
  If[m =!= Automatic, m,
    If[Indices[t] === {"down", "down"}, Components[t], Automatic]]];

Raise[t_?FieldQ, n_Integer, gdown_?MatrixQ] := Module[
  {idx = Indices[t], r = Rank[t], ginv, arr},
  If[idx[[n]] =!= "down", Message[Raise::notdown, n]; Return[$Failed]];
  ginv = Core`cachedInverse[gdown];
  arr = Core`$Simplify[contractMatIndex[ginv, Components[t], n, r]];
  Field[Coords[t], ReplacePart[idx, n -> "up"], arr, gdown, Core`Conventions[t]]];

Raise[t_?FieldQ, n_Integer, g_?FieldQ] := Raise[t, n, getMetricDown[g]];

Raise[t_?FieldQ, n_Integer] := Module[{gd = getMetricDown[t]},
  If[gd === Automatic, (Message[Raise::nomet]; $Failed), Raise[t, n, gd]]];

Lower[t_?FieldQ, n_Integer, gdown_?MatrixQ] := Module[
  {idx = Indices[t], r = Rank[t], arr},
  If[idx[[n]] =!= "up", Message[Lower::notup, n]; Return[$Failed]];
  arr = Core`$Simplify[contractMatIndex[gdown, Components[t], n, r]];
  Field[Coords[t], ReplacePart[idx, n -> "down"], arr, gdown, Core`Conventions[t]]];

Lower[t_?FieldQ, n_Integer, g_?FieldQ] := Lower[t, n, getMetricDown[g]];

Lower[t_?FieldQ, n_Integer] := Module[{gd = getMetricDown[t]},
  If[gd === Automatic, (Message[Lower::nomet]; $Failed), Lower[t, n, gd]]];

(* ---- trace / contraction ---- *)
Trc::badpair = "Need one \"up\" and one \"down\"; got \"`1`\" and \"`2`\".";

Trc[t_?FieldQ, {i_Integer, j_Integer}] := Module[
  {idx = Indices[t], contracted, newIdx},
  If[Sort[{idx[[i]], idx[[j]]}] =!= {"down", "up"},
    Message[Trc::badpair, idx[[i]], idx[[j]]]; Return[$Failed]];
  Module[{ii, jj, perm, rank = Rank[t], arr = Components[t]},
    {ii, jj} = Sort[{i, j}];
    If[rank == 2,
      contracted = Core`$Simplify[Tr[arr]],
      perm = Join[{ii, jj}, Delete[Range[rank], {{ii}, {jj}}]];
      contracted = Core`$Simplify[Tr[Transpose[arr, perm], Plus, 2]]]];
  newIdx = Delete[idx, {{i}, {j}}];
  If[newIdx === {},
    contracted,
    Field[Coords[t], newIdx, contracted, Metric[t], Core`Conventions[t]]]];

(* ---- tensor product ---- *)
Prod[t1_?FieldQ, t2_?FieldQ] :=
  Field[Coords[t1], Join[Indices[t1], Indices[t2]],
    Outer[Times, Components[t1], Components[t2]],
    Metric[t1], Core`Conventions[t1]];

(* ---- contract (product + trace) ---- *)
Contract[t1_?FieldQ, i_Integer, t2_?FieldQ, j_Integer] :=
  Trc[Prod[t1, t2], {i, Rank[t1] + j}];

(* ---- coordinate transformation ---- *)
Transform[t_?FieldQ, newCoords_List, rules_List] := Module[
  {oldCoords = Coords[t], idx = Indices[t], d = Dim[t], r = Rank[t],
   oldExprs, backJac, fwdJac, arr, gdown},
  oldExprs = oldCoords /. rules;
  backJac = Core`$Simplify[Table[D[oldExprs[[mu]], newCoords[[mup]]], {mu, d}, {mup, d}]];
  fwdJac = Core`$Simplify[Inverse[backJac]];
  arr = Components[t] /. rules;
  Do[arr = contractMatIndex[
      If[idx[[k]] === "down", Transpose[backJac], fwdJac], arr, k, r], {k, r}];
  arr = Core`$Simplify[arr];
  gdown = Metric[t];
  If[gdown =!= Automatic,
    gdown = Core`$Simplify[Transpose[backJac] . (gdown /. rules) . backJac]];
  Field[newCoords, idx, arr, gdown, Core`Conventions[t]]];

End[];
EndPackage[];
