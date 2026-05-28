(* ::Package:: *)

(* ============================================================================
   Tensor algebra benchmark: built-in vs OGRe
   ============================================================================

   Times the six new tensor-algebra operations against OGRe on the
   Schwarzschild metric. Schwarzschild is a better benchmark than AdS:
   the angular block is non-diagonal (sin^2 theta), the lapse/shift
   involve coordinate functions, and the curvature tensors are non-trivial.

   Operations tested:
     1. Index raising   -- raise first index of all-lower Riemann
     2. Index lowering  -- lower it back (round-trip correctness check)
     3. Trace           -- contract R^mu_{sigma mu nu} -> Ricci
     4. Coordinate transform -- Schwarzschild -> isotropic coordinates
     5. Covariant derivative -- nabla_mu R_{alpha beta}
     6. Geodesic equations

   Plus a caching pipeline test: metric -> Christoffel -> Riemann -> Ricci ->
   covariant derivative, timed with cold vs warm cache.

   Run:
     wolframscript -file tensor-algebra-benchmark.wl
   ============================================================================ *)

(* --- load ---------------------------------------------------------------- *)
Get[FileNameJoin[{ParentDirectory[DirectoryName[$InputFileName]], "init.wl"}]];

(* OGRe: try loading from the path wolfram.py would resolve *)
Block[{ogrePath = FileNameJoin[{$HomeDirectory, "Documents",
   "Wolfram Mathematica", "OGRe.m"}]},
  If[FileExistsQ[ogrePath],
    Quiet@Block[{$Output = {}}, Get[ogrePath]; OGRe`TSetAutoUpdates[False]],
    Print["WARNING: OGRe not found -- OGRe benchmarks skipped."]]];

(* --- Schwarzschild metric ------------------------------------------------ *)
coords = {t, r, th, ph};
$Assumptions = M > 0 && r > 2 M && th > 0 && th < Pi;
f = 1 - 2 M/r;
gdown = DiagonalMatrix[{-f, 1/f, r^2, r^2 Sin[th]^2}];
g = MAuthor`CTensor[coords, {"down", "down"}, gdown, Automatic,
   <|"signature" -> "mostly-plus", "spacetime" -> "Schwarzschild"|>];

(* precompute so timing isn't polluted by first-call overhead *)
MAuthor`CTCacheClear[];
riem = MAuthorGR`RiemannFromMetric[g];
ricci = MAuthorGR`RicciFromMetric[g];
Print["Schwarzschild curvature computed."];

(* --- OGRe setup --------------------------------------------------------- *)
ogreID = With[{c = coords, gc = gdown},
  Module[{id = ToString[Unique["bench"]]},
    OGRe`TNewCoordinates[id <> "C", c];
    OGRe`TNewMetric[id, id <> "C", gc];
    id]];
(* Suppress OGRe's progress indicators — they write to $Output and
   corrupt the harness sentinel. Block $Output only during OGRe compute
   calls, NEVER during $Messages (see wolfram-conventions.md). *)
Block[{$Output = {}},
  ogreRiem = OGRe`TCalcRiemannTensor[ogreID];
  ogreRicci = OGRe`TCalcRicciTensor[ogreID]];
Print["OGRe curvature computed.\n"];

(* ===== 1. INDEX RAISING ================================================= *)
Print["=== 1. Raise first index of Riemann ==="];
tBuiltinRaise = First@RepeatedTiming[
  MAuthor`CTRaise[riem, 1, g]];
tOGReRaise = First@RepeatedTiming[
  OGRe`TGetComponents[ogreRiem, {1, -1, -1, -1}, ogreID <> "C"]];
(* correctness *)
builtinRaised = MAuthor`CTcomponents[MAuthor`CTRaise[riem, 1, g]];
ogreRaised = OGRe`TGetComponents[ogreRiem, {1, -1, -1, -1}, ogreID <> "C"];
raiseAgree = MAuthor`EquivalentQ[builtinRaised, ogreRaised];
Print["  built-in: ", NumberForm[tBuiltinRaise, {6, 5}], " s"];
Print["  OGRe:     ", NumberForm[tOGReRaise, {6, 5}], " s"];
Print["  speedup:  ", NumberForm[tOGReRaise/tBuiltinRaise, {4, 1}], "x"];
Print["  agree:    ", raiseAgree];

(* ===== 2. INDEX LOWERING (round-trip) ==================================== *)
Print["\n=== 2. Lower it back (round-trip) ==="];
raised = MAuthor`CTRaise[riem, 1, g];
tBuiltinLower = First@RepeatedTiming[
  MAuthor`CTLower[raised, 1, g]];
tOGReLower = First@RepeatedTiming[
  Block[{$Output = {}}, OGRe`TGetComponents[ogreRiem, {-1, -1, -1, -1}, ogreID <> "C"]]];
lowerRT = MAuthor`EquivalentQ[
  MAuthor`CTcomponents[MAuthor`CTLower[raised, 1, g]],
  MAuthor`CTcomponents[riem]];
Print["  built-in: ", NumberForm[tBuiltinLower, {6, 5}], " s"];
Print["  OGRe:     ", NumberForm[tOGReLower, {6, 5}], " s"];
Print["  round-trip correct: ", lowerRT];

(* ===== 3. TRACE (Riemann -> Ricci) ======================================= *)
Print["\n=== 3. Trace R^m_{sigma m nu} -> Ricci ==="];
riemUp = MAuthor`CTRaise[riem, 1, g];
tBuiltinTrace = First@RepeatedTiming[
  MAuthor`CTTrace[riemUp, {1, 3}]];
(* OGRe: already did TCalcRicciTensor; time getting components *)
tOGReTrace = First@RepeatedTiming[
  OGRe`TGetComponents[ogreRicci, {-1, -1}, ogreID <> "C"]];
traceResult = MAuthor`CTTrace[riemUp, {1, 3}];
traceAgree = MAuthor`EquivalentQ[
  MAuthor`CTcomponents[traceResult],
  MAuthor`CTcomponents[ricci]];
Print["  built-in: ", NumberForm[tBuiltinTrace, {6, 5}], " s"];
Print["  OGRe:     ", NumberForm[tOGReTrace, {6, 5}], " s"];
Print["  trace == Ricci: ", traceAgree];

(* ===== 4. COORDINATE TRANSFORM ========================================== *)
Print["\n=== 4. Transform metric: Schwarzschild -> Eddington-Finkelstein ==="];
(* Ingoing EF: t = v - r - 2M Log[r/(2M) - 1], angular coords unchanged.
   Known result: ds^2 = -(1-2M/r) dv^2 + 2 dv dr + r^2 dOmega^2 *)
efCoords = {v, r, th, ph};
efRules = {t -> v - r - 2 M Log[r/(2 M) - 1]};

tBuiltinTransform = First@RepeatedTiming[
  MAuthor`CTTransform[g, efCoords, efRules]];

(* Verify against the known EF metric *)
efExpected = {{-(1 - 2 M/r), 1, 0, 0}, {1, 0, 0, 0},
  {0, 0, r^2, 0}, {0, 0, 0, r^2 Sin[th]^2}};
builtinEF = MAuthor`CTcomponents[MAuthor`CTTransform[g, efCoords, efRules]];
transformAgree = MAuthor`EquivalentQ[builtinEF, efExpected];

(* OGRe coordinate transforms trigger $Aborted in headless mode
   (progress-indicator channel conflict), so we skip the OGRe timing here
   and verify against the analytic result instead. *)
Print["  built-in: ", NumberForm[tBuiltinTransform, {6, 5}], " s"];
Print["  OGRe:     (skipped: TAddCoordTransformation aborts headless)"];
Print["  matches known EF metric: ", transformAgree];

(* ===== 5. COVARIANT DERIVATIVE ========================================== *)
Print["\n=== 5. Covariant derivative of Ricci tensor ==="];
tBuiltinCovD = First@RepeatedTiming[
  MAuthorGR`CovariantDFromMetric[ricci, g]];

(* OGRe comparison skipped: TNewTensor triggers the progress-channel
   $Aborted in headless mode. Verify instead via physics: Schwarzschild
   is vacuum (R_{mu nu} = 0), so nabla_alpha R_{mu nu} = 0. *)
builtinCovD = MAuthor`CTcomponents[MAuthorGR`CovariantDFromMetric[ricci, g]];
covDZero = MAuthor`EquivalentQ[builtinCovD, ConstantArray[0, {4, 4, 4}]];
Print["  built-in: ", NumberForm[tBuiltinCovD, {6, 5}], " s"];
Print["  OGRe:     (skipped: headless progress-channel conflict)"];
Print["  nabla R_{mu nu} == 0 (vacuum): ", covDZero];

(* ===== 6. GEODESIC EQUATIONS ============================================ *)
Print["\n=== 6. Geodesic equations ==="];
tBuiltinGeod = First@RepeatedTiming[
  MAuthorGR`GeodesicEquationsFromMetric[g, \[Lambda]]];
builtinGeod = MAuthorGR`GeodesicEquationsFromMetric[g, \[Lambda]];
geodCount = Length[builtinGeod] == 4;
(* Verify: the t-geodesic for Schwarzschild should contain (1-2M/r) dt/dlambda *)
geodHasLapse = ! FreeQ[builtinGeod[[1]], 1 - 2 M/r[\[Lambda]]];
Print["  built-in: ", NumberForm[tBuiltinGeod, {6, 5}], " s"];
Print["  OGRe:     (skipped: headless abort)"];
Print["  4 equations: ", geodCount, "  contains lapse: ", geodHasLapse];

(* ===== 7. CACHING: cold vs warm pipeline ================================ *)
Print["\n=== 7. Caching: full pipeline cold vs warm ==="];
MAuthor`CTCacheClear[];
tCold = First@AbsoluteTiming[
  Module[{ch, ri, rc, cd},
    ch = MAuthorGR`ChristoffelFromMetric[g];
    ri = MAuthorGR`RiemannFromMetric[g];
    rc = MAuthorGR`RicciFromMetric[g];
    cd = MAuthorGR`CovariantDFromMetric[rc, g];
    "done"]];
tWarm = First@AbsoluteTiming[
  Module[{ch, ri, rc, cd},
    ch = MAuthorGR`ChristoffelFromMetric[g];
    ri = MAuthorGR`RiemannFromMetric[g];
    rc = MAuthorGR`RicciFromMetric[g];
    cd = MAuthorGR`CovariantDFromMetric[rc, g];
    "done"]];
Print["  cold (no cache): ", NumberForm[tCold, {6, 4}], " s"];
Print["  warm (cached):   ", NumberForm[tWarm, {6, 4}], " s"];
Print["  speedup:         ", NumberForm[tCold/tWarm, {4, 1}], "x"];

Print["\n=== SUMMARY ==="];
Print["All agreement checks: ", And[raiseAgree === True, lowerRT === True,
  traceAgree === True, transformAgree === True, covDZero === True, geodCount]];
