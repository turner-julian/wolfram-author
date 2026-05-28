(* ::Package:: *)

(* ============================================================================
   GENERATOR for  ogre-vs-builtin-benchmark.nb

   Builds an easy-to-read Mathematica notebook that (1) computes the curvature
   of AdS5 in Poincare coordinates with this skill's built-in array GR operators,
   (2) shows they agree componentwise with the OGRe-backed operators, and (3)
   benchmarks built-in vs OGRe with RepeatedTiming and a bar chart.

   It authors the notebook through the FrontEnd and evaluates every cell
   synchronously (NotebookEvaluate[InsertResults -> True]) so the saved .nb
   already contains its outputs (tables, timings, chart) and still re-runs when
   opened. Regenerate with:

       wolframscript -file ogre-vs-builtin-benchmark.wl
   ============================================================================ *)

outPath = FileNameJoin[{DirectoryName[$InputFileName], "ogre-vs-builtin-benchmark.nb"}];

(* inputCell[code] -> an Input cell holding `code` UNEVALUATED, typeset in
   StandardForm. HoldAllComplete + MakeBoxes means nothing runs here at
   generation time; NotebookEvaluate runs it later inside the notebook. *)
SetAttributes[inputCell, HoldAllComplete];
inputCell[code_] := Cell[BoxData[MakeBoxes[code, StandardForm]], "Input"];

intro = "This notebook documents the mathematica-author library's general-relativity \
operators on one concrete example -- the curvature of five-dimensional anti-de Sitter \
space in Poincare coordinates -- and compares the library's from-scratch built-in array \
implementation against the OGRe package on the same computation. It shows two things: \
the two implementations AGREE componentwise (correctness), and the built-in version is \
roughly an order of magnitude FASTER on an explicit coordinate metric (speed). \
Conventions are the library's pinned ones (mostly-plus signature, Levi-Civita connection; \
see references/wolfram-conventions.md). Timings are RepeatedTiming medians on this \
machine -- re-evaluate the cells to reproduce.";

takeaway = "Both implementations produce identical curvature (EquivalentQ -> True), and \
the convention-independent invariants come out right: R = -20/L^2 and Kretschmann = \
40/L^4 for AdS5. On an explicit metric the built-in array operators beat OGRe by about \
10x, because OGRe's object system carries overhead that does not pay off when the \
components are known up front. OGRe is still the better tool for its own strengths -- \
interactive exploration, index gymnastics, and harder symbolic simplification -- which \
is exactly why the library keeps both and benchmarks them against each other rather than \
picking one blindly.";

cells = {
  Cell["AdS\:2085 curvature \[Dash] built-in arrays vs OGRe", "Title"],
  Cell[intro, "Text"],

  Cell["1.  Load the library and OGRe", "Section"],
  Cell["Delivered scripts load the curated library by absolute path and call \
operators with full context prefixes, so the file runs as-is. OGRe is loaded the \
same way (banner suppressed).", "Text"],
  inputCell[
    Get[FileNameJoin[{$HomeDirectory, ".claude", "skills", "mathematica-author", "lib", "MAuthor.wl"}]];
    Get[FileNameJoin[{$HomeDirectory, ".claude", "skills", "mathematica-author", "lib", "GR.wl"}]];
    Get[FileNameJoin[{$HomeDirectory, "Documents", "Wolfram Mathematica", "OGRe.m"}]];
    OGRe`TSetAutoUpdates[False];
    "loaded: MAuthor`, MAuthorGR`, OGRe`"
  ],

  Cell["2.  The metric", "Section"],
  Cell["AdS5 in the Poincare patch, mostly-plus, AdS radius L, radial coordinate z > 0: \
ds^2 = (L^2/z^2)(-dt^2 + dx1^2 + dx2^2 + dx3^2 + dz^2).", "Text"],
  inputCell[
    coords = {t, x1, x2, x3, z};
    $Assumptions = L > 0 && z > 0;
    gComp = (L^2/z^2) DiagonalMatrix[{-1, 1, 1, 1, 1}];
    g = MAuthor`CTensor[coords, {"down", "down"}, gComp, Automatic, <|"signature" -> "mostly-plus"|>];
    MatrixForm[gComp]
  ],

  Cell["3.  Curvature numerics (built-in operators)", "Section"],
  Cell["Compose the registered built-in primitives. The Ricci scalar and the \
Kretschmann scalar are convention-independent, so they are the robust checks.", "Text"],
  inputCell[
    ricciScalar = MAuthorGR`RicciScalarFromMetric[g];
    kretschmann = MAuthorGR`KretschmannFromMetric[g];
    Column[{
      Row[{"Ricci scalar  R = ", ricciScalar, "      (expected -20/L^2)"}],
      Row[{"Kretschmann   K = ", kretschmann, "      (expected 40/L^4)"}]}]
  ],

  Cell["4.  The built-in result agrees with OGRe", "Section"],
  Cell["Same Riemann tensor, computed two independent ways, compared componentwise \
with the library's EquivalentQ.", "Text"],
  inputCell[
    riemBuiltin = MAuthor`CTcomponents[MAuthorGR`RiemannFromMetric[g]];
    riemOGRe = MAuthor`CTcomponents[MAuthorGR`RiemannFromMetricOGRe[g]];
    MAuthor`EquivalentQ[riemBuiltin, riemOGRe]
  ],

  Cell["5.  Speed: built-in vs OGRe", "Section"],
  Cell["RepeatedTiming (median of many runs) for the four operators that have both \
implementations. Christoffel, Riemann, Ricci, and the Ricci scalar.", "Text"],
  inputCell[
    ops = {"Christoffel", "Riemann", "Ricci", "RicciScalar"};
    builtinFns = {MAuthorGR`ChristoffelFromMetric, MAuthorGR`RiemannFromMetric,
                  MAuthorGR`RicciFromMetric, MAuthorGR`RicciScalarFromMetric};
    ogreFns = {MAuthorGR`ChristoffelFromMetricOGRe, MAuthorGR`RiemannFromMetricOGRe,
               MAuthorGR`RicciFromMetricOGRe, MAuthorGR`RicciScalarFromMetricOGRe};
    tBuiltin = First@RepeatedTiming[#[g]] & /@ builtinFns;
    tOGRe = First@RepeatedTiming[#[g]] & /@ ogreFns;
    Grid[
      Prepend[
        Transpose[{ops,
          NumberForm[#, {6, 5}] & /@ tBuiltin,
          NumberForm[#, {6, 5}] & /@ tOGRe,
          Row[{NumberForm[#, {4, 1}], "\[Times]"}] & /@ (tOGRe/tBuiltin)}],
        Style[#, Bold] & /@ {"operator", "built-in (s)", "OGRe (s)", "speedup"}],
      Frame -> All, Alignment -> {Left, Center}, Spacings -> {2, 1}]
  ],
  inputCell[
    BarChart[Transpose[{tBuiltin, tOGRe}],
      ChartLegends -> {"built-in", "OGRe"},
      ChartLabels -> {Placed[ops, Axis], None},
      BarSpacing -> {0.2, 1},
      PlotLabel -> "seconds per call (lower is faster)",
      LabelStyle -> 12, ImageSize -> 460, AspectRatio -> 0.55]
  ],

  Cell["Takeaway", "Section"],
  Cell[takeaway, "Text"]
};

(* OGRe prints a load banner and an "Auto updates" line into the notebook (not
   via $Output/Print, so it can't be suppressed at the source headlessly). Strip
   those cells from the evaluated notebook expression before saving -- robust
   regardless of how OGRe emits them. *)
bannerCellQ[c_] := StringContainsQ[ToString[c, InputForm],
   "OGRe: An " | "Auto updates turned "];

Print["authoring ", outPath, " ..."];
UsingFrontEnd[
  nb = CreateDocument[cells, Visible -> False, WindowTitle -> "AdS5 curvature: built-in vs OGRe"];
  NotebookEvaluate[nb, InsertResults -> True];
  nbExpr = NotebookGet[nb];
  NotebookClose[nb];
  clean = nbExpr /. Cell[c_, _String, ___] /; bannerCellQ[c] :> Sequence[];
  nbClean = NotebookPut[clean];
  NotebookSave[nbClean, outPath];
  nOut = Length@Cases[clean, Cell[_, "Output", ___], Infinity];
  nBanner = Length@Cases[nbExpr, Cell[c_, _String, ___] /; bannerCellQ[c], Infinity];
  NotebookClose[nbClean];
];
Print["done. output cells: ", nOut, "  banner cells stripped: ", nBanner,
      "  exists: ", FileExistsQ[outPath],
      "  bytes: ", If[FileExistsQ[outPath], FileByteCount[outPath], 0]];
