(* ::Package:: *)

(* ============================================================================
   Riemann tensor of AdS in Poincare coordinates
   ============================================================================

   Goal. Compute the curvature of (d+1)-dimensional anti-de Sitter space in the
   Poincare patch and confirm it is maximally symmetric.

   Geometry. With AdS radius L and coordinates (t, x, y, z), z > 0 the Poincare
   radial coordinate, the metric is conformally flat:

       ds^2 = (L^2 / z^2) ( -dt^2 + dx^2 + dy^2 + dz^2 ),

   i.e. g_{mu nu} = (L^2/z^2) eta_{mu nu} with eta = diag(-1,1,1,1). (This file
   does AdS_4; to change dimension, edit `coords` and `eta` below -- nothing
   else is dimension-specific.)

   Conventions (see lib/index.json):
     Christoffel  Gamma^a_bc = 1/2 g^as (d_b g_sc + d_c g_sb - d_s g_bc)
     Riemann      R^r_smn = d_m Gamma^r_ns - d_n Gamma^r_ms + Gamma^r_ml Gamma^l_ns - Gamma^r_nl Gamma^l_ms
     lowered      R_rsmn = g_ra R^a_smn
     Ricci        R_sn = R^m_smn,   scalar R = g^sn R_sn

   Expected (maximally symmetric, curvature radius L, dimension D):
     R_{rho sigma mu nu} = -(1/L^2)(g_{rho mu} g_{sigma nu} - g_{rho nu} g_{sigma mu})
     R = -D(D-1)/L^2,    Kretschmann R_{abcd}R^{abcd} = 2 D(D-1)/L^4.
   For D = 4: R = -12/L^2, Kretschmann = 24/L^4.

   Run:  wolframscript -file ads-poincare-riemann.wl
   ============================================================================ *)

(* --- load the curated library (canonical representation + GR operators) --- *)
libDir = FileNameJoin[{ParentDirectory[DirectoryName[$InputFileName]], "lib"}];
Get[FileNameJoin[{libDir, "CT.wl"}]];
Get[FileNameJoin[{libDir, "GRT.wl"}]];

(* --- 1. the metric ------------------------------------------------------- *)
coords = {t, x, y, z};
eta = DiagonalMatrix[{-1, 1, 1, 1}];
gComponents = (L^2/z^2) eta;
g = CT`Tensor[coords, {"down", "down"}, gComponents, Automatic,
   <|"signature" -> "mostly-plus", "spacetime" -> "AdS4 Poincare"|>];

Print["Metric g_{mu nu}:"];
Print[MatrixForm[gComponents]];

(* --- 2. curvature, composed from library primitives ---------------------- *)
gamma = GRT`ChristoffelFromMetric[g];
riem = GRT`RiemannFromMetric[g];           (* R_{rho sigma mu nu} *)
ricci = GRT`RicciFromMetric[g];            (* R_{mu nu} *)
ricciScalar = GRT`RicciScalarFromMetric[g];
kretschmann = GRT`KretschmannFromMetric[g];

Print["\nNonzero Christoffel symbols Gamma^a_{bc}:"];
Do[With[{val = CT`Components[gamma][[a, b, c]]},
   If[val =!= 0,
    Print["  Gamma^", coords[[a]], "_{", coords[[b]], coords[[c]], "} = ", val]]],
  {a, 4}, {b, 4}, {c, b, 4}];

Print["\nRicci tensor R_{mu nu} = ", MatrixForm[CT`Components[ricci]]];
Print["Ricci scalar R = ", ricciScalar];
Print["Kretschmann K = ", kretschmann];

(* --- 3. sanity checks (independent of the curvature code above) ---------- *)
(* maximally-symmetric Riemann built directly from the metric *)
gdown = gComponents;
maxSymRiemann = Table[
   -(1/L^2) (gdown[[r, m]] gdown[[s, n]] - gdown[[r, n]] gdown[[s, m]]),
   {r, 4}, {s, 4}, {m, 4}, {n, 4}];

checks = <|
   "Riemann == maximally-symmetric form"
     -> CT`EquivalentQ[CT`Components[riem], maxSymRiemann],
   "Ricci scalar == -12/L^2" -> CT`EquivalentQ[ricciScalar, -12/L^2],
   "Kretschmann == 24/L^4" -> CT`EquivalentQ[kretschmann, 24/L^4]
|>;

Print["\nSanity checks:"];
KeyValueMap[Print["  [", If[#2 === True, "PASS", "FAIL"], "] ", #1] &, checks];

Print["\nAll checks passed: ", AllTrue[Values[checks], # === True &]];
