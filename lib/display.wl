(* ::Package:: *)

(* Display` -- static notebook generation for read-only .nb display artifacts.

   .nb files produced by wolfram-author and verify-math are read-only: the user
   views them, never evaluates them. Live Column/Row/Grid in Output cells
   triggers a "potentially unsafe dynamic content" warning in Wolfram Player and
   untrusted directories. This module avoids that by freezing every expression
   into pre-rendered box structures at generation time via ToBoxes. The .nb file
   stores Cell[BoxData[...], "Output"] with those boxes; Wolfram renders them
   without evaluating anything.

   Usage (from a .wl script that generates a notebook):

     Get["/path/to/wolfram-core/lib/init.wl"];
     cells = {
       Cell["Ricci scalar", "Section"],
       Display`StaticOutput[rscalar],
       Display`LabeledOutput["R = ", rscalar],
       Display`StaticGrid[componentTable, Alignment -> Left]
     };
     Display`ExportStaticNB["output.nb", cells];

   Any generated plots should use PlotInteractivity -> False (14.3) to avoid
   dynamic content in the plot itself. *)

BeginPackage["Display`"];

StaticOutput::usage =
  "StaticOutput[expr] or StaticOutput[expr, form] freezes expr into a static \
Output cell via ToBoxes. form defaults to TraditionalForm. The cell contains \
pre-rendered boxes; no evaluation occurs when the notebook is opened.";

LabeledOutput::usage =
  "LabeledOutput[label, expr] or LabeledOutput[label, expr, form] freezes \
Row[{label, expr}] into a static Output cell. label is a plain string; expr \
is typeset in the given form (default TraditionalForm).";

StaticGrid::usage =
  "StaticGrid[data, opts] freezes Grid[data, opts] into a static Output cell. \
data is a 2D list; opts are passed to Grid (e.g. Alignment -> Left, \
Spacings -> {2, 0.5}).";

StaticNotebook::usage =
  "StaticNotebook[cells] or StaticNotebook[cells, opts] builds a Notebook \
expression from a list of Cell objects with default display options \
(TraditionalForm output, 900x800 window, Default.nb stylesheet). Additional \
opts override the defaults.";

ExportStaticNB::usage =
  "ExportStaticNB[path, cells] or ExportStaticNB[path, cells, opts] writes a \
static notebook to disk. Equivalent to Export[path, StaticNotebook[cells, opts]].";

StaticInput::usage =
  "StaticInput[code_String] creates an Input cell from a string of Wolfram code. \
The cell is inert (CellOpen -> True, Evaluatable -> False by default).";

Begin["`Private`"];

(* ---- single expression -> frozen Output cell ---- *)
StaticOutput[expr_, form_: TraditionalForm] :=
  Cell[BoxData[ToBoxes[expr, form]], "Output"];

(* ---- labeled result: "R = -12/L^2" with typeset math ---- *)
LabeledOutput[label_String, expr_, form_: TraditionalForm] :=
  Cell[BoxData[ToBoxes[Row[{label, expr}], form]], "Output"];

(* ---- grid/table -> frozen Output cell ---- *)
StaticGrid[data_, opts___] :=
  Cell[BoxData[ToBoxes[Grid[data, opts], TraditionalForm]], "Output"];

(* ---- frozen Input cell (display only, not evaluatable) ---- *)
StaticInput[code_String] :=
  Cell[code, "Input", Evaluatable -> False];

(* ---- assemble a complete notebook ---- *)
StaticNotebook[cells_List, opts___] :=
  Notebook[cells,
    WindowSize -> {900, 800},
    DefaultNewCellStyle -> "Input",
    DefaultOutputFormatType -> TraditionalForm,
    StyleDefinitions -> "Default.nb",
    opts];

(* ---- write to disk ---- *)
ExportStaticNB[path_String, cells_List, opts___] :=
  Export[path, StaticNotebook[cells, opts]];

End[];
EndPackage[];
