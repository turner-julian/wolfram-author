(* ::Package:: *)

(* ============================================================================
   A symbolic integral (non-GR breadth case)
   ============================================================================

   Goal. Evaluate a parametric Gaussian integral in closed form and expose the
   result as a scalar a downstream cross-engine check can confirm. This case
   exists to exercise the skill outside differential geometry: no library
   primitive is needed, just clean, documented, runnable Wolfram.

       gaussInt = Integrate[ Exp[-a x^2], {x, -Infinity, Infinity} ]  with a > 0
                = Sqrt[Pi / a].

   Run:  wolframscript -file symbolic-gaussian.wl
   ============================================================================ *)

a; (* symbolic positive parameter *)

gaussInt = Integrate[Exp[-a x^2], {x, -Infinity, Infinity},
   Assumptions -> a > 0];

Print["gaussInt = ", gaussInt];

(* --- sanity check -------------------------------------------------------- *)
check = Simplify[gaussInt - Sqrt[Pi/a]] === 0;
Print["[", If[check, "PASS", "FAIL"], "] gaussInt == Sqrt[Pi/a]"];
