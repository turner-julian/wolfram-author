(* ::Package:: *)

(* init.wl -- load the Core + Tensor + GR capability library from wolfram-core/lib.

   Get this from any Mathematica script or notebook to load the shared
   wolfram-core verified-math library. It sets $CTLibDir to this directory
   so the modules resolve regardless of where wolfram-core is vendored.

   Usage (from a script or notebook):
     Get["/path/to/wolfram-core/lib/init.wl"];

   After this call, Core`, Tensor`, and GR` are loaded and ready:
     g    = Tensor`Field[coords, {"down","down"}, gdown, Automatic, <||>];
     riem = GR`Riemann[g];

   The wolfram.py harness loads the same modules via `--load core` / `--load gr`
   for ad-hoc one-liners; a delivered standalone script uses this init.wl
   instead (so it runs under a bare `wolframscript -file`, no --load needed). *)

$CTLibDir = DirectoryName[$InputFileName];
Get[FileNameJoin[{$CTLibDir, "core.wl"}]];
Get[FileNameJoin[{$CTLibDir, "tensor.wl"}]];
Get[FileNameJoin[{$CTLibDir, "gr.wl"}]];
Get[FileNameJoin[{$CTLibDir, "decide.wl"}]];
Get[FileNameJoin[{$CTLibDir, "derivation.wl"}]];
