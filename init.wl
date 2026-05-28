(* ::Package:: *)

(* init.wl -- load the CT + GRT tensor algebra library.

   Get this file from any Mathematica script or notebook to set up the
   library. It sets $CTLibDir (the absolute path to lib/) so that
   CT.wl, GRT.wl, and everything they depend on resolve correctly
   regardless of where the repo is cloned.

   Usage (from a script or notebook):
     Get["/path/to/grt/init.wl"];

   After this call, CT` and GRT` are loaded and ready:
     g = CT`Tensor[coords, {"down","down"}, gdown, Automatic, <||>];
     riem = GRT`RiemannFromMetric[g];
*)

$CTLibDir = FileNameJoin[{DirectoryName[$InputFileName], "lib"}];
Get[FileNameJoin[{$CTLibDir, "CT.wl"}]];
Get[FileNameJoin[{$CTLibDir, "GRT.wl"}]];
