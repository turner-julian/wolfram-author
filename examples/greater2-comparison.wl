(* ::Package:: *)

(* ============================================================================
   Head-to-head comparison: CT+GRT vs GREATER2
   ============================================================================

   Tests every shared feature on the Schwarzschild metric.
   For each operation: time both, verify agreement via EquivalentQ.

   Convention note: GREATER2's Riemann is R^a_{bcd} (first index UP);
   GRT's RiemannFromMetric returns R_{abcd} (all DOWN). We raise GRT's
   first index for the comparison, or lower GREATER2's — whichever is
   cheaper. We also check scalar invariants that are convention-independent.

   Shared features tested:
     1. Christoffel symbols
     2. Riemann tensor
     3. Ricci tensor
     4. Ricci scalar
     5. Index raising
     6. Contraction / trace
     7. Coordinate transformation
     8. Covariant derivative
     9. Geodesic equations

   Run:  wolframscript -file greater2-comparison.wl
   ============================================================================ *)

(* --- load ---------------------------------------------------------------- *)
Get[FileNameJoin[{ParentDirectory[DirectoryName[$InputFileName]], "init.wl"}]];
Get[FileNameJoin[{$HomeDirectory, "Library", "Mathematica", "Applications", "GREATER2.m"}]];

(* --- Schwarzschild metric ------------------------------------------------ *)
coords = {t, r, th, ph};
$Assumptions = M > 0 && r > 2 M && th > 0 && th < Pi;
f = 1 - 2 M/r;
gdown = DiagonalMatrix[{-f, 1/f, r^2, r^2 Sin[th]^2}];
gup = Inverse[gdown];

(* CT+GRT tensor object *)
g = Tensor`Field[coords, {"down", "down"}, gdown, Automatic,
   <|"signature" -> "mostly-plus"|>];

Print["=== Schwarzschild metric loaded ===\n"];

(* ===== Helper: clear GREATER2 memoization =============================== *)
(* GREATER2 memoizes Christoffel via DownValues. Clear between timing runs. *)
clearGR2Cache[] := (
  DownValues[GREATER2`Christoffel] =
    Select[DownValues[GREATER2`Christoffel], !FreeQ[#, HoldPattern] &]);

(* ===== 1. CHRISTOFFEL ==================================================== *)
Print["=== 1. Christoffel symbols ==="];

Core`CacheClear[];
tGRT1 = First@RepeatedTiming[GR`Christoffel[g]];
grtChris = Tensor`Components[GR`Christoffel[g]];

clearGR2Cache[];
tGR2c1 = First@RepeatedTiming[GREATER2`Christoffel[gdown, coords]];
gr2Chris = GREATER2`Christoffel[gdown, coords];

(* Both return Gamma^a_{bc} — same index structure *)
chrisAgree = Core`EquivalentQ[grtChris, gr2Chris];
Print["  GRT:      ", 1000 tGRT1, " ms"];
Print["  GREATER2: ", 1000 tGR2c1, " ms"];
Print["  speedup:  ", tGR2c1/tGRT1, "x"];
Print["  agree:    ", chrisAgree];

(* ===== 2. RIEMANN ======================================================== *)
Print["\n=== 2. Riemann tensor ==="];

Core`CacheClear[];
tGRT2 = First@RepeatedTiming[GR`Riemann[g]];
grtRiem = Tensor`Components[GR`Riemann[g]]; (* R_{abcd} all down *)

clearGR2Cache[];
tGR2c2 = First@RepeatedTiming[GREATER2`Riemann[gdown, coords]];
gr2Riem = GREATER2`Riemann[gdown, coords]; (* R^a_{bcd} first up *)

(* Lower GREATER2's first index for comparison *)
gr2RiemDown = Table[
  Sum[gdown[[a, s]] gr2Riem[[s, b, c, d]], {s, 4}],
  {a, 4}, {b, 4}, {c, 4}, {d, 4}] // Simplify;
riemAgree = Core`EquivalentQ[grtRiem, gr2RiemDown];

Print["  GRT:      ", 1000 tGRT2, " ms"];
Print["  GREATER2: ", 1000 tGR2c2, " ms"];
Print["  speedup:  ", tGR2c2/tGRT2, "x"];
Print["  agree (after lowering): ", riemAgree];

(* ===== 3. RICCI ========================================================== *)
Print["\n=== 3. Ricci tensor ==="];

Core`CacheClear[];
tGRT3 = First@RepeatedTiming[GR`Ricci[g]];
grtRicci = Tensor`Components[GR`Ricci[g]];

clearGR2Cache[];
tGR2c3 = First@RepeatedTiming[GREATER2`Ricci[gdown, coords]];
gr2Ricci = GREATER2`Ricci[gdown, coords];

ricciAgree = Core`EquivalentQ[grtRicci, gr2Ricci];
Print["  GRT:      ", 1000 tGRT3, " ms"];
Print["  GREATER2: ", 1000 tGR2c3, " ms"];
Print["  speedup:  ", tGR2c3/tGRT3, "x"];
Print["  agree:    ", ricciAgree];

(* ===== 4. RICCI SCALAR =================================================== *)
Print["\n=== 4. Ricci scalar ==="];

Core`CacheClear[];
tGRT4 = First@RepeatedTiming[GR`RicciScalar[g]];
grtR = GR`RicciScalar[g];

clearGR2Cache[];
tGR2c4 = First@RepeatedTiming[GREATER2`SCurvature[gdown, coords]];
gr2R = GREATER2`SCurvature[gdown, coords];

rAgree = Core`EquivalentQ[grtR, gr2R];
Print["  GRT:      ", 1000 tGRT4, " ms"];
Print["  GREATER2: ", 1000 tGR2c4, " ms"];
Print["  agree:    ", rAgree];
Print["  GRT value:  ", grtR];
Print["  GR2 value:  ", gr2R, "  (both should be 0 for vacuum)"];

(* ===== 5. INDEX RAISING ================================================== *)
Print["\n=== 5. Index raising (Riemann, 1st index) ==="];

grtRiemObj = GR`Riemann[g]; (* all-down CTensor *)
tGRT5 = First@RepeatedTiming[Tensor`Raise[grtRiemObj, 1, g]];
grtRaised = Tensor`Components[Tensor`Raise[grtRiemObj, 1, g]]; (* R^a_{bcd} *)

(* GREATER2`Raise[T, i, Guu] — takes the inverse metric directly *)
tGR2c5 = First@RepeatedTiming[GREATER2`Raise[grtRiem, 1, gup]];
gr2Raised = GREATER2`Raise[grtRiem, 1, gup];

(* Compare to GREATER2's native Riemann (which is already R^a_{bcd}) *)
raiseAgree = Core`EquivalentQ[grtRaised, gr2Riem];
Print["  GRT:      ", 1000 tGRT5, " ms"];
Print["  GREATER2: ", 1000 tGR2c5, " ms"];
Print["  GRT raised == GREATER2 native R^a_{bcd}: ", raiseAgree];

(* ===== 6. CONTRACTION / TRACE ============================================ *)
Print["\n=== 6. Trace: R^a_{bac} -> Ricci ==="];

grtRiemUp = Tensor`Raise[grtRiemObj, 1, g];
tGRT6 = First@RepeatedTiming[Tensor`Trc[grtRiemUp, {1, 3}]];
grtTraced = Tensor`Components[Tensor`Trc[grtRiemUp, {1, 3}]];

(* GREATER2: SelfContract[T, ind1, ind2] with ind1 < ind2 *)
tGR2c6 = First@RepeatedTiming[GREATER2`SelfContract[gr2Riem, 1, 3]];
gr2Traced = GREATER2`SelfContract[gr2Riem, 1, 3];

traceAgree = Core`EquivalentQ[grtTraced, gr2Traced];
Print["  GRT:      ", 1000 tGRT6, " ms"];
Print["  GREATER2: ", 1000 tGR2c6, " ms"];
Print["  agree:    ", traceAgree];
Print["  == Ricci:  ", Core`EquivalentQ[grtTraced, grtRicci]];

(* ===== 7. COORDINATE TRANSFORMATION ===================================== *)
Print["\n=== 7. Coordinate transform: Schwarzschild -> EF ==="];

efCoords = {v, r, th, ph};
efRules = {t -> v - r - 2 M Log[r/(2 M) - 1]};
efTrans = {t == v - r - 2 M Log[r/(2 M) - 1], r == r, th == th, ph == ph};

tGRT7 = First@RepeatedTiming[
  Tensor`Transform[g, efCoords, efRules]];
grtEF = Tensor`Components[Tensor`Transform[g, efCoords, efRules]];

tGR2c7 = First@RepeatedTiming[
  GREATER2`ChangeCoords[gdown, coords, efCoords, efTrans, {-1, -1}]];
gr2EF = GREATER2`ChangeCoords[gdown, coords, efCoords, efTrans, {-1, -1}];

efExpected = {{-(1 - 2 M/r), 1, 0, 0}, {1, 0, 0, 0},
  {0, 0, r^2, 0}, {0, 0, 0, r^2 Sin[th]^2}};
grtEFok = Core`EquivalentQ[grtEF, efExpected];
gr2EFok = Core`EquivalentQ[gr2EF, efExpected];
Print["  GRT:      ", 1000 tGRT7, " ms"];
Print["  GREATER2: ", 1000 tGR2c7, " ms"];
Print["  GRT matches known EF:  ", grtEFok];
Print["  GR2 matches known EF:  ", gr2EFok];

(* ===== 8. COVARIANT DERIVATIVE ========================================== *)
Print["\n=== 8. Covariant derivative of a vector ==="];

(* Use a simple vector field: the coordinate basis vector d/dr *)
vComps = {0, 1, 0, 0};
vObj = Tensor`Field[coords, {"up"}, vComps, gdown, <||>];

Core`CacheClear[];
tGRT8 = First@RepeatedTiming[
  GR`CovariantD[vObj, g]];
grtCovD = Tensor`Components[GR`CovariantD[vObj, g]]; (* nabla_mu v^nu: {mu, nu} *)

clearGR2Cache[];
tGR2c8 = First@RepeatedTiming[
  GREATER2`CoD[vComps, gdown, coords, {1}]];
gr2CovD = GREATER2`CoD[vComps, gdown, coords, {1}]; (* same: {mu, nu} *)

covDAgree = Core`EquivalentQ[grtCovD, gr2CovD];
Print["  GRT:      ", 1000 tGRT8, " ms"];
Print["  GREATER2: ", 1000 tGR2c8, " ms"];
Print["  agree:    ", covDAgree];

(* ===== 9. GEODESIC EQUATIONS ============================================ *)
Print["\n=== 9. Geodesic equations ==="];

Core`CacheClear[];
tGRT9 = First@RepeatedTiming[
  GR`Geodesic[g, \[Lambda]]];
grtGeod = GR`Geodesic[g, \[Lambda]];

(* GREATER2 takes precomputed Christoffel *)
gr2ChrisForGeod = GREATER2`Christoffel[gdown, coords];
tGR2c9 = First@RepeatedTiming[
  GREATER2`GeodesicEquation[gr2ChrisForGeod, coords, \[Lambda]]];
gr2Geod = GREATER2`GeodesicEquation[gr2ChrisForGeod, coords, \[Lambda]];

(* Both return lists of expressions == 0; compare term by term *)
geodAgree = And @@ Table[
  Core`EquivalentQ[Simplify[grtGeod[[i]] - gr2Geod[[i]]], 0],
  {i, 4}];
Print["  GRT:      ", 1000 tGRT9, " ms"];
Print["  GREATER2: ", 1000 tGR2c9, " ms"];
Print["  agree:    ", geodAgree];

(* ===== SUMMARY =========================================================== *)
Print["\n=== SUMMARY ==="];
Print["                    GRT (ms)    GREATER2 (ms)    speedup    agree"];
Print["  Christoffel:   ", 1000 tGRT1, "      ", 1000 tGR2c1, "      ", tGR2c1/tGRT1, "x   ", chrisAgree];
Print["  Riemann:       ", 1000 tGRT2, "      ", 1000 tGR2c2, "      ", tGR2c2/tGRT2, "x   ", riemAgree];
Print["  Ricci:         ", 1000 tGRT3, "      ", 1000 tGR2c3, "      ", tGR2c3/tGRT3, "x   ", ricciAgree];
Print["  Ricci scalar:  ", 1000 tGRT4, "      ", 1000 tGR2c4, "      ", "    ", rAgree];
Print["  Raise index:   ", 1000 tGRT5, "      ", 1000 tGR2c5, "      ", tGR2c5/tGRT5, "x   ", raiseAgree];
Print["  Trace:         ", 1000 tGRT6, "      ", 1000 tGR2c6, "      ", tGR2c6/tGRT6, "x   ", traceAgree];
Print["  Coord xform:   ", 1000 tGRT7, "      ", 1000 tGR2c7, "      ", tGR2c7/tGRT7, "x   ", grtEFok && gr2EFok];
Print["  Covariant D:   ", 1000 tGRT8, "      ", 1000 tGR2c8, "      ", tGR2c8/tGRT8, "x   ", covDAgree];
Print["  Geodesics:     ", 1000 tGRT9, "      ", 1000 tGR2c9, "      ", tGR2c9/tGRT9, "x   ", geodAgree];
