(* ::Package:: *)

(* Decide` -- the soundness core: classify ONE assertion under the domain Gamma
   into a verification tier.

   The invariant (preserved from verify-math domains.py): `proved` is ALWAYS a
   symbolic decision under Gamma; `refuted` is ALWAYS a real Gamma-respecting
   numeric counterexample. An identity the engine cannot close symbolically
   degrades to `spot-checked` (held at sampled points) or `unchecked:undecided`,
   never a false `refuted`.

   This ports _equality_payload / _inequality_payload from domains.py, made
   Gamma-aware (Core`'s EquivalentQ is NOT -- it samples a fixed positive box and
   ignores assumptions, so it cannot back a domain-respecting verdict). The author
   writes the assertion directly in Wolfram (`lhs == rhs`, `lhs <= rhs`, or a
   boolean predicate like an operator identity); slDecide applies the uniform
   sound classification. Equality threads over arrays, so a tensor/operator
   identity (Ricci components == 0, two operators equal) is one assertion. *)

BeginPackage["Decide`"];

slDecide::usage =
  "slDecide[assertion, gamma] -> <|\"tier\", \"holds\", \"tex\", \"detail\"|>. \
assertion is a Wolfram relation held by slDecide (Equal / Less / LessEqual / \
Greater / GreaterEqual) or a boolean predicate; gamma is a Wolfram boolean \
domain (default True). Equality: FullSimplify[lhs-rhs, gamma] symbolically zero \
(elementwise for arrays) -> proved; else a gamma-filtered numeric probe -> \
refuted / spot-checked / unchecked:undecided. Inequality: Reduce of the negation \
over gamma -> proved; else the probe. Predicate: evaluated under gamma to \
True/False. `tex` is the engine TeXForm of the verified RHS (render-from-checked).";

Begin["`Private`"];

$nSamples = 40;
$box = {-2, 2};

texOf[e_] := Quiet@Check[ToString[TeXForm[e]], "<texform-failed>"];

(* Gamma-respecting sample points for the given variables (drop the ones that
   violate the domain), exactly as domains.py's probe does. *)
gammaPoints[vars_, gamma_] := Select[
   Table[Thread[vars -> RandomReal[$box, Length[vars]]], {$nSamples}],
   TrueQ[gamma /. #] &];

result[tier_, holds_, tex_, detail_] :=
  <|"tier" -> tier, "holds" -> holds, "tex" -> tex, "detail" -> detail|>;

(* ---- equality (scalar OR array), Gamma-aware ---- *)
decideEqual[a_, b_, gamma_] := Module[{comps, vars, pts, vals, tex},
   tex = texOf[b];
   comps = Flatten[{a - b}];
   If[AllTrue[comps, TrueQ[PossibleZeroQ[FullSimplify[#, gamma]]] &],
     Return[result["proved", True, tex, ""]]];
   vars = Variables[{a, b}];
   pts = gammaPoints[vars, gamma];
   vals = (Quiet[Check[Max[Abs[N[comps /. #]]], $Failed]]) & /@ pts;
   Which[
     AnyTrue[vals, (NumericQ[#] && # > 10^-6) &],
       result["refuted", False, tex, "numeric counterexample on the stated domain"],
     pts =!= {} && AllTrue[vals, (NumericQ[#] && # < 10^-9) &],
       result["spot-checked", Null, tex,
         "held at " <> ToString[Length[pts]] <> " sampled points in the domain"],
     True,
       result["unchecked:undecided", Null, tex,
         "FullSimplify did not decide; numeric probe inconclusive"]]];

(* ---- inequality, Gamma-aware (semialgebraic Reduce of the negation) ---- *)
decideIneq[head_, a_, b_, gamma_] := Module[{vars, dec, pts, vals, tex},
   tex = texOf[head[a, b]];
   vars = Variables[{a, b}];
   dec = With[{v = vars}, Reduce[gamma && Not[head[a, b]], v, Reals]];
   If[dec === False, Return[result["proved", True, tex, ""]]];
   pts = gammaPoints[vars, gamma];
   vals = (Quiet[Check[TrueQ[N[head[a, b] /. #]], $Failed]]) & /@ pts;
   Which[
     pts =!= {} && AnyTrue[vals, # === False &],
       result["refuted", False, tex, "numeric counterexample on the stated domain"],
     pts =!= {} && AllTrue[vals, # === True &],
       result["spot-checked", Null, tex,
         "held at " <> ToString[Length[pts]] <> " sampled points in the domain"],
     True,
       result["unchecked:undecided", Null, tex,
         "Reduce did not decide; numeric probe inconclusive"]]];

(* ---- predicate (exact boolean: operator identities, etc.) ---- *)
decidePredicate[p_, gamma_] := Module[{ev, tex},
   tex = texOf[HoldForm[p]];
   ev = Assuming[gamma, Simplify[p]];
   Which[
     ev === True,  result["proved", True, tex, ""],
     ev === False, result["refuted", False, tex, "predicate is False"],
     True,         result["unchecked:undecided", Null, tex,
                     "predicate did not reduce to True or False"]]];

SetAttributes[slDecide, HoldFirst];
slDecide[lhs_ == rhs_,  gamma_: True] := decideEqual[lhs, rhs, gamma];
slDecide[lhs_ <  rhs_,  gamma_: True] := decideIneq[Less, lhs, rhs, gamma];
slDecide[lhs_ <= rhs_,  gamma_: True] := decideIneq[LessEqual, lhs, rhs, gamma];
slDecide[lhs_ >  rhs_,  gamma_: True] := decideIneq[Greater, lhs, rhs, gamma];
slDecide[lhs_ >= rhs_,  gamma_: True] := decideIneq[GreaterEqual, lhs, rhs, gamma];
(* A held assertion (slVerifyDerivation carries each claim as Hold[lhs == rhs] or
   HoldComplete[lhs == rhs] so it survives list construction with its objects
   unbound) unwraps to the bare relation, which HoldFirst then keeps held for
   the right equality/ineq dispatch.  HoldComplete (14.2) is strictly stronger
   than Hold: it also blocks Condition matching and Sequence flattening. *)
slDecide[Hold[a_],         gamma_: True] := slDecide[a, gamma];
slDecide[HoldComplete[a_], gamma_: True] := slDecide[a, gamma];
slDecide[p_,               gamma_: True] := decidePredicate[p, gamma];

End[];
EndPackage[];
