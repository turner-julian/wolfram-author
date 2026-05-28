(* ::Package:: *)

(* ============================================================================
   Curvature of the Schwarzschild metric
   ============================================================================

   Goal. Compute the Ricci scalar and Kretschmann scalar of the Schwarzschild
   solution and confirm the two convention-independent facts: it is Ricci-flat
   (vacuum) and its Kretschmann scalar is 48 M^2 / r^6 (curvature singularity at
   r -> 0, regular at the horizon r = 2M).

   Geometry. Mass M, coordinates (t, r, th, ph), f(r) = 1 - 2 M / r:

       ds^2 = -f dt^2 + f^(-1) dr^2 + r^2 (dth^2 + sin(th)^2 dph^2).

   Conventions (see lib/index.json, references/wolfram-conventions.md):
     same Christoffel/Riemann/Ricci sign + index convention as the AdS example.

   Expected (convention-independent invariants):
     Ricci scalar  R = 0        (vacuum / Ricci-flat),
     Kretschmann   K = 48 M^2 / r^6.

   Run:  wolframscript -file schwarzschild-kretschmann.wl
   ============================================================================ *)

(* --- load the curated library (canonical representation + GR operators) --- *)
libDir = FileNameJoin[{ParentDirectory[ParentDirectory[DirectoryName[$InputFileName]]], "lib"}];
Get[FileNameJoin[{libDir, "CT.wl"}]];
Get[FileNameJoin[{libDir, "GRT.wl"}]];

(* --- 1. the metric ------------------------------------------------------- *)
coords = {t, r, th, ph};
f = 1 - 2 M/r;
gComponents = DiagonalMatrix[{-f, 1/f, r^2, r^2 Sin[th]^2}];
g = CT`Tensor[coords, {"down", "down"}, gComponents, Automatic,
   <|"signature" -> "mostly-plus", "spacetime" -> "Schwarzschild"|>];

Print["Metric g_{mu nu}:"];
Print[MatrixForm[gComponents]];

(* --- 2. curvature scalars, composed from library primitives -------------- *)
ricciScalar = Simplify[GRT`RicciScalarFromMetric[g]];
kretschmann = Simplify[GRT`KretschmannFromMetric[g]];

Print["\nRicci scalar R = ", ricciScalar];
Print["Kretschmann  K = ", kretschmann];

(* --- 3. sanity checks ---------------------------------------------------- *)
checks = <|
   "Ricci scalar == 0 (vacuum)" -> CT`EquivalentQ[ricciScalar, 0],
   "Kretschmann == 48 M^2/r^6" -> CT`EquivalentQ[kretschmann, 48 M^2/r^6]
|>;

Print["\nSanity checks:"];
KeyValueMap[Print["  [", If[#2 === True, "PASS", "FAIL"], "] ", #1] &, checks];

Print["\nAll checks passed: ", AllTrue[Values[checks], # === True &]];
