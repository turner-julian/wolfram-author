(* ::Package:: *)

(* ============================================================================
   Honesty case: an integral with no elementary closed form
   ============================================================================

   Goal. Not every request has an answer. Integrate[Exp[x^x], x] has no closed
   form Mathematica can produce, so it comes back UNEVALUATED. The honest
   deliverable runs cleanly and reports the non-closure plainly rather than
   dressing up the unevaluated expression as a result. The eval asserts the
   non-closure signal directly: Head[coldIntegral] == Integrate.

   Run:  wolframscript -file cold-nonclosure.wl
   ============================================================================ *)

coldIntegral = Integrate[Exp[x^x], x];

closed = Head[coldIntegral] =!= Integrate;
Print["Closed form found: ", closed];
If[! closed,
   Print["No elementary antiderivative -- Integrate returned unevaluated."],
   Print["Result: ", coldIntegral]];
