(* ::Package:: *)

(* init.wl -- load the MAuthor tensor algebra library.

   Get this file from any Mathematica script or notebook to set up the
   library. It sets $MAuthorLibDir (the absolute path to lib/) so that
   MAuthor.wl, GR.wl, and everything they depend on resolve correctly
   regardless of where the repo is cloned.

   Usage (from a script or notebook):
     Get["/path/to/mathematica-author/init.wl"];

   After this call, MAuthor` and MAuthorGR` are loaded and ready:
     g = MAuthor`CTensor[coords, {"down","down"}, gdown, Automatic, <||>];
     riem = MAuthorGR`RiemannFromMetric[g];
*)

$MAuthorLibDir = FileNameJoin[{DirectoryName[$InputFileName], "lib"}];
Get[FileNameJoin[{$MAuthorLibDir, "MAuthor.wl"}]];
Get[FileNameJoin[{$MAuthorLibDir, "GR.wl"}]];
