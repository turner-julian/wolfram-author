(* ::Package:: *)

(* Core` -- the discipline-agnostic verification substrate.

   Holds what EVERY discipline needs and nothing physics-specific: the verified-
   object envelope, the equality decision EquivalentQ (extensible per object
   type), conventions, numeric/symbolic zero-testing, the simplify policy, and
   the shared computation cache. Tensor index algebra, GR curvature, QEC, etc.
   live in discipline modules (Tensor`, GR`, QEC`, ...) that build on this.

   The verified-object envelope (the future-proof seam):

     <| "type"        -> String,        (* open tag; Core never enumerates types *)
        "rep"         -> String,        (* representation tag; one rep per object  *)
        "payload"     -> <discipline-specific data>,  (* opaque to Core           *)
        "conventions" -> Association,   (* typed convention tags                   *)
        "provenance"  -> Association |> (* how it was built (op, inputs, oracles)  *)

   Core never inspects payload; each discipline registers its own EquivalentQ
   method (a downvalue on Core`EquivalentQ) and its own accessors. *)

BeginPackage["Core`"];

EquivalentQ::usage =
  "EquivalentQ[a, b] -> True (equal) | False (provably differ) | $Failed \
(undecided). Scalars: symbolic zero-difference (PossibleZeroQ, FullSimplify) \
with a randomized numeric spot-check. Lists: elementwise. Verified objects: \
dispatched by \"type\" -- each discipline module adds its own method.";

ObjectQ::usage = "ObjectQ[o] tests whether o is a verified-object Association (has a \"type\").";
Type::usage = "Type[o] gives the object's type tag.";
Conventions::usage = "Conventions[o] gives the conventions Association.";
Provenance::usage = "Provenance[o] gives the provenance Association.";
WithProvenance::usage = "WithProvenance[o, p] returns o with its provenance set to the Association p.";

$Simplify::usage = "The simplification applied to results. Default Simplify[#, TimeConstraint -> 1]&; \
set to Identity to skip or FullSimplify for hard cases.";
numericZeroQ::usage = "numericZeroQ[d] -> True/False/$Failed: is d identically zero (randomized numeric sampling).";
arrayEquivalentQ::usage = "arrayEquivalentQ[a, b] elementwise EquivalentQ for arrays (for discipline modules).";
scalarEquivalentQ::usage = "scalarEquivalentQ[a, b] scalar EquivalentQ (for discipline modules).";

SimilarQ::usage =
  "SimilarQ[a, b] -> True (similar matrices) | False (not similar). Uses \
FrobeniusDecomposition (rational canonical form): two matrices are similar iff \
they have the same Frobenius form. Exact, no field extension needed (14.3).";

MinPoly::usage =
  "MinPoly[m, x] returns the minimal polynomial of matrix m in the variable x, \
cached. Wrapper around MatrixMinimalPolynomial (14.3). Distinguishes nilpotent \
(x^k), diagonalizable (distinct linear factors), defective (repeated factors).";

$Cache::usage = "Shared computation cache. CacheClear[] resets.";
CacheClear::usage = "CacheClear[] clears the cache.";
CacheStore::usage = "CacheStore[key, val] stores in the cache.";
CacheGet::usage = "CacheGet[key] retrieves; Missing[] if absent.";
cachedInverse::usage = "cachedInverse[m] returns Inverse[m], cached.";

If[! ValueQ[$Simplify], $Simplify = Simplify[#, TimeConstraint -> 1] &];
If[! AssociationQ[$Cache], $Cache = <||>];

Begin["`Private`"];

(* ---- object envelope ---- *)
ObjectQ[o_] := AssociationQ[o] && KeyExistsQ[o, "type"];
Type[o_] := Lookup[o, "type", None];
Conventions[o_] := Lookup[o, "conventions", <||>];
Provenance[o_] := Lookup[o, "provenance", <||>];
WithProvenance[o_?ObjectQ, p_Association] := Append[o, "provenance" -> p];

(* ---- zero testing ---- *)
(* free (user, non-System`) symbols anywhere in an expression *)
freeVars[expr_] := DeleteDuplicates@
   Cases[expr, _Symbol?(Context[#] =!= "System`" &), {0, Infinity}, Heads -> True];

(* numeric spot-check that an expression is identically zero. Samples positive
   reals (physics variables are usually positive, avoiding spurious branch-cut
   values) and requires every sample ~0. *)
numericZeroQ[d_] := Module[{vars = freeVars[d], samples},
   If[vars === {}, Return[TrueQ[Chop[N[d], 10^-10] == 0]]];
   samples = Table[
     Quiet@Check[
       Chop[N[d /. Thread[vars -> RandomReal[{1, 3}, Length[vars]]]], 10^-8],
       $Failed], {12}];
   If[MemberQ[samples, $Failed] || ! VectorQ[samples, NumericQ],
    $Failed, AllTrue[samples, # === 0 &]]];

scalarEquivalentQ[a_, b_] := Module[{d = a - b, num},
   If[TrueQ[PossibleZeroQ[d]], Return[True]];
   If[TrueQ[FullSimplify[d] === 0], Return[True]];
   num = numericZeroQ[d];
   Which[
    num === True, True,    (* symbolic maybe-nonzero, numeric says zero *)
    num === False, False,  (* numerically nonzero -> provably differ *)
    True, $Failed]];       (* undecided *)

arrayEquivalentQ[a_, b_] := Module[{fa, fb, pairs},
   If[Dimensions[a] =!= Dimensions[b], Return[False]];
   fa = Flatten[{a}]; fb = Flatten[{b}];
   pairs = scalarEquivalentQ @@@ Transpose[{fa, fb}];
   Which[
    MemberQ[pairs, False], False,
    MemberQ[pairs, $Failed], $Failed,
    True, True]];

(* ---- EquivalentQ: generic scalar + list; object types add their own methods
   (more-specific downvalues, tried first) ---- *)
EquivalentQ[a_List, b_List] := arrayEquivalentQ[a, b];
EquivalentQ[a_List, _] := False;
EquivalentQ[_, b_List] := False;
EquivalentQ[a_, b_] := scalarEquivalentQ[a, b];

(* ---- cache ---- *)
CacheClear[] := ($Cache = <||>);
CacheStore[key_, val_] := ($Cache[key] = val);
CacheGet[key_] := $Cache[key];

cachedInverse[m_] := Module[{key = {"inv", Hash[m]}, c},
  c = $Cache[key];
  If[MissingQ[c], $Cache[key] = Inverse[m], c]];

(* ---- matrix classification (14.3) ---- *)

SimilarQ::baddim = "Matrices have different dimensions (`1` vs `2`).";
SimilarQ[a_?MatrixQ, b_?MatrixQ] := Module[{da, db},
  da = Dimensions[a]; db = Dimensions[b];
  If[da =!= db, Message[SimilarQ::baddim, da, db]; Return[False]];
  FrobeniusDecomposition[a] === FrobeniusDecomposition[b]];

MinPoly[m_?MatrixQ, x_] := Module[{key = {"minpoly", Hash[m]}, c},
  c = $Cache[key];
  If[MissingQ[c], $Cache[key] = MatrixMinimalPolynomial[m, x], c]];

End[];
EndPackage[];
