(* ::Package:: *)

(* Derivation` -- slVerifyDerivation: walk a WHOLE derivation in one evaluation so
   `define` bindings persist (object-flow), each `assert` is classified by
   Decide`slDecide under the shared domain Gamma, and the result is one delimited
   string of per-claim records.

   The single-Module walk is what makes object reuse possible: define the Kerr
   metric once, then ask several questions of it. The old one-eval-per-claim model
   could not (the sandbox is Module-local per eval), so every gr step re-pasted the
   whole metric inline. Author-first falls out: a claim with no checkable assertion
   is `unchecked:not-encoded`, never rejected.

   Capability admission (the registry gate) is enforced UPSTREAM in Python
   (verify_derivation), which marks an assert that names an unadmitted GR`/QEC`
   primitive as `kind -> "skip"` BEFORE it reaches here -- so this walker never runs
   an unadmitted primitive, exactly as gr.py/qec refuse to. *)

BeginPackage["Derivation`", {"Decide`"}];

slVerifyDerivation::usage =
  "slVerifyDerivation[claims, gamma] walks an ordered list of claim Associations \
<|\"id\", \"kind\" (\"define\"|\"assert\"|\"skip\"|other), \"wl\" -> Hold[expr]|> in \
one evaluation under the domain gamma. define binds its symbol (object-flow); \
assert -> slDecide[held assertion, gamma] under a per-assert TimeConstrained; \
skip -> unchecked:no-capability (gated out upstream); anything else -> \
unchecked:not-encoded. Inconsistent gamma (Reduce[gamma] === False) blocks all. \
Returns records (id|kind|status|tier|holds|tex|detail, SEP-joined) REC-joined. \
Defined symbols are Removed on exit so they cannot leak into the next derivation \
evaluated on the same session.";

Begin["`Private`"];

$perAssert = 30;               (* seconds; one slow assert degrades, not the whole run *)
$SEP = "@@@SLF@@@";            (* field separator; no TeXForm output contains '@' *)
$REC = "@@@SLR@@@";            (* record separator *)

texOf[e_] := Quiet@Check[ToString[TeXForm[e]], "<texform-failed>"];

statusOf["proved"] = "passed";
statusOf["refuted"] = "failed";
statusOf["spot-checked"] = "spot-checked";
statusOf[_] = "unchecked";

rec[id_, kind_, status_, tier_, holds_, tex_, detail_] :=
  StringRiffle[{id, kind, status, tier, ToString[holds], tex, detail}, $SEP];

slVerifyDerivation[claims_List, gamma_: True] := Module[
  {records, defSyms = {}, gateDecision},
  (* gate: contradictory assumptions make every downstream verdict vacuous *)
  gateDecision = TimeConstrained[Quiet@Check[Reduce[gamma, Reals], $Failed], 15, $Failed];
  If[gateDecision === False,
    Return[StringRiffle[
      Function[c, rec[c["id"], c["kind"], "blocked", "unchecked:blocked-gamma",
        Null, "", "the assumptions are inconsistent (Reduce[Gamma] === False)"]] /@ claims,
      $REC]]];
  records = Table[
    With[{c = claims[[i]]},
      Switch[c["kind"],
        "define",
          AppendTo[defSyms,
            c["wl"] /. (Hold | HoldComplete)[(Set | SetDelayed)[s_, _]] :> Hold[s]];
          Quiet[ReleaseHold[c["wl"]]];
          rec[c["id"], "define", "given", "given", Null, "", ""],
        "assert",
          Module[{d},
            d = TimeConstrained[
                  With[{w = c["wl"]}, Decide`slDecide[w, gamma]],
                  $perAssert,
                  <|"tier" -> "unchecked:timeout", "holds" -> Null, "tex" -> "",
                    "detail" -> "assert exceeded " <> ToString[$perAssert] <> " s"|>];
            rec[c["id"], "assert", statusOf[d["tier"]], d["tier"], d["holds"],
                d["tex"], d["detail"]]],
        "skip",
          rec[c["id"], "skip", "unchecked", "unchecked:no-capability", Null, "",
              "uses an unadmitted discipline primitive"],
        _,
          rec[c["id"], "null", "unchecked", "unchecked:not-encoded", Null, "",
              "no checkable assertion"]]],
    {i, Length[claims]}];
  (* Defines intern in Global` at parse time, so a runtime context switch cannot
     isolate them; Removing them on exit is the sound equivalent -- the next
     derivation on this session sees fresh symbols, not stale bindings. *)
  Scan[(# /. Hold[s_] :> Quiet[ClearAll[s]; Remove[s]]) &, defSyms];
  StringRiffle[records, $REC]];

End[];
EndPackage[];
