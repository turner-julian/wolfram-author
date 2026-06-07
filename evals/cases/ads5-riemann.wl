(* ::Package:: *)

(* ============================================================================
   Riemann tensor of AdS5 in Poincare coordinates  (delivered-script pattern)
   ============================================================================

   This is the corrected form of the script the "Riemann tensor AdS 5" Cowork
   session produced. That one began with  Needs["GRT`"]  and was run with
   `--load mauthor`, so the GR operators (which live in GR.wl, loaded only by
   `--load gr`) were never defined -- the run would fail even with a kernel.

   The fix, and the standing convention for every DELIVERED script: load the
   curated library yourself, by ABSOLUTE path, and call functions with their
   full context prefixes. A delivered script must be runnable as-is with a bare
       wolframscript -file <this>.wl
   with no `--load` flags to remember. (`--load` is only for ad-hoc one-liners.)

   Geometry. AdS radius L, coords (t,x1,x2,x3,z), z>0, mostly-plus:
       ds^2 = (L^2/z^2)(-dt^2 + dx1^2 + dx2^2 + dx3^2 + dz^2).
   Expected (maximally symmetric, D=5):  R = -20/L^2,  Kretschmann = 40/L^4,
       R_{mu nu} = -(4/L^2) g_{mu nu}.
   ============================================================================ *)

(* --- load the curated library via init.wl (repo-relative) ---------------- *)
(* evals/cases/ is 2 levels below repo root *)
Get[FileNameJoin[{ParentDirectory[ParentDirectory[
   DirectoryName[$InputFileName]]], "init.wl"}]];

(* --- metric -------------------------------------------------------------- *)
coords = {t, x1, x2, x3, z};
$Assumptions = L > 0 && z > 0;
gComponents = (L^2/z^2) DiagonalMatrix[{-1, 1, 1, 1, 1}];
g = Tensor`Field[coords, {"down", "down"}, gComponents, Automatic,
   <|"signature" -> "mostly-plus", "spacetime" -> "AdS5 Poincare"|>];

(* --- curvature, composed from library primitives (full context prefixes) -- *)
riem = GR`Riemann[g];          (* R_{rho sigma mu nu}, all down *)
ricci = GR`Ricci[g];           (* R_{mu nu} *)
ricciScalar = GR`RicciScalar[g];
kretschmann = GR`Kretschmann[g];

Print["Ricci scalar R = ", ricciScalar, "   (expect -20/L^2)"];
Print["Kretschmann  K = ", kretschmann, "   (expect 40/L^4)"];

(* --- sanity checks ------------------------------------------------------- *)
maxSymRiemann = Table[
   -(1/L^2) (gComponents[[r, m]] gComponents[[s, n]]
           - gComponents[[r, n]] gComponents[[s, m]]),
   {r, 5}, {s, 5}, {m, 5}, {n, 5}];

checks = <|
   "Riemann == maximally-symmetric form"
     -> Core`EquivalentQ[Tensor`Components[riem], maxSymRiemann],
   "Ricci == -(4/L^2) g"
     -> Core`EquivalentQ[Tensor`Components[ricci], -(4/L^2) gComponents],
   "Ricci scalar == -20/L^2" -> Core`EquivalentQ[ricciScalar, -20/L^2],
   "Kretschmann == 40/L^4" -> Core`EquivalentQ[kretschmann, 40/L^4]
|>;

Print["\nSanity checks:"];
KeyValueMap[Print["  [", If[#2 === True, "PASS", "FAIL"], "] ", #1] &, checks];
Print["\nAll checks passed: ", AllTrue[Values[checks], # === True &]];
