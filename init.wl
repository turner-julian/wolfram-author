(* ::Package:: *)

(* init.wl -- load the wolfram-core library (Core` + Tensor` + GR`).

   Get this file from any Mathematica script or notebook to set up the
   library. It delegates to lib/init.wl, which sets $CTLibDir and loads
   all modules.

   Usage (from a script or notebook):
     Get["/path/to/wolfram-author/init.wl"];

   After this call, Core`, Tensor`, and GR` are loaded and ready:
     g    = Tensor`Field[coords, {"down","down"}, gdown, Automatic, <||>];
     riem = GR`Riemann[g];
*)

Get[FileNameJoin[{DirectoryName[$InputFileName], "lib", "init.wl"}]];
