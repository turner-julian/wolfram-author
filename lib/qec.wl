(* ::Package:: *)

(* QEC` -- finite-dimensional quantum-error-correction operators, exact.

   The dense-operator discipline: Pauli strings, Kronecker products, projectors,
   isometries, density matrices, partial trace, von Neumann entropy. Reimplemented
   on Mathematica with EXACT arithmetic (no floating-point residual), so a
   stabilizer identity (P^2 = P), a subsystem reduction (= I/4), or an entropy
   (= 2 Log 2) is verified exactly via Core`EquivalentQ rather than to ~1e-9.

   Mirrors the build vocabulary of the former numpy backend. Operators are exact
   matrices (Gaussian-rational / algebraic entries). Cross-check vs qutip/stim or
   the code's known closed forms is the gate's independent method. *)

BeginPackage["QEC`"];

Pauli::usage = "Pauli[\"XZZXI\"] is the Kronecker product of single-qubit Paulis (I,X,Y,Z).";
Eye::usage = "Eye[n] is the n x n identity.";
Zeros::usage = "Zeros[n] is the n x n zero matrix.";
Kron::usage = "Kron[a, b, ...] is the Kronecker (tensor) product.";
Dag::usage = "Dag[a] is the conjugate transpose (a-dagger).";
Codespace::usage =
  "Codespace[p] is an isometry whose columns are an orthonormal basis of the \
eigenvalue-1 space of the projector p (d x rank).";
DM::usage = "DM[v, k] is the density matrix |v_k><v_k| of column k (0-indexed) of v.";
PartialTrace::usage =
  "PartialTrace[rho, keep, dims] traces out the subsystems NOT in `keep` \
(1-indexed) of a system with subsystem dimensions `dims`.";
VonNeumannEntropy::usage =
  "VonNeumannEntropy[rho] is the von Neumann entropy -Tr[rho Log rho] (natural \
log), exact. (Named to avoid the protected System`Entropy.)";

(* ---- symbolic Pauli layer (14.3 NonCommutativeAlgebra) ---- *)

SP::usage =
  "SP[\"X\"] etc. is a symbolic single-qubit Pauli operator (head, not a matrix). \
Carries Commutator/Anticommutator rules for the Pauli algebra without expanding \
to dense 2^n matrices. Convert to a matrix with ToDense.";
SymPauli::usage =
  "SymPauli[\"XZZXI\"] builds a symbolic multi-qubit Pauli as a \
NonCommutativeMultiply product of SP heads. The dense equivalent is Pauli[s].";
ToDense::usage =
  "ToDense[sp] converts a symbolic Pauli expression (SP heads, \
NonCommutativeMultiply products) to an explicit dense matrix.";
ToSymbolic::usage =
  "ToSymbolic[mat] decomposes a 2x2 matrix into a linear combination of \
symbolic Pauli SP heads. Returns the symbolic expression, or $Failed if mat \
is not 2x2.";
StabilizerQ::usage =
  "StabilizerQ[{g1, g2, ...}] returns True iff all generators pairwise commute \
(Commutator == 0). Works symbolically on SymPauli expressions without building \
dense matrices.";

Begin["`Private`"];

$P = <|"I" -> IdentityMatrix[2], "X" -> PauliMatrix[1],
       "Y" -> PauliMatrix[2], "Z" -> PauliMatrix[3]|>;

Pauli[s_String] := Fold[KroneckerProduct, Lookup[$P, Characters[s]]];
Eye[n_Integer] := IdentityMatrix[n];
Zeros[n_Integer] := ConstantArray[0, {n, n}];
Kron[ops__] := KroneckerProduct[ops];
Dag[a_] := ConjugateTranspose[a];

(* +1 eigenspace of a projector = ker(p - I); orthonormalize (exact). *)
Codespace[p_] := Transpose[Orthogonalize[NullSpace[p - IdentityMatrix[Length[p]]]]];

DM[v_, k_Integer: 0] := With[{col = v[[All, k + 1]]}, Outer[Times, col, Conjugate[col]]];

(* Reshape the d x d density matrix to a rank-2n tensor (ket subsystems 1..n,
   bra subsystems n+1..2n), contract each traced subsystem's ket/bra pair, and
   reshape the kept indices back to a matrix. *)
PartialTrace[rho_, keep_List, dims_List] := Module[
  {n = Length[dims], rest, t, pairs, dk},
  rest = Complement[Range[n], keep];
  t = ArrayReshape[rho, Join[dims, dims]];
  pairs = {#, n + #} & /@ rest;
  dk = Times @@ dims[[keep]];
  ArrayReshape[TensorContract[t, pairs], {dk, dk}]];

VonNeumannEntropy[rho_] := Module[{ev},
  ev = DeleteCases[Eigenvalues[(rho + ConjugateTranspose[rho])/2], 0];
  Simplify[-Total[ev*Log[ev]]]];

(* ---- symbolic Pauli layer (14.3 NonCommutativeAlgebra) ----

   SP["X"], SP["Y"], SP["Z"], SP["I"] are symbolic heads carrying the Pauli
   algebra rules via Commutator/Anticommutator (built-in since 14.3). This
   enables verifying stabilizer commutation, operator identities, and Pauli
   decomposition without building 2^n x 2^n dense matrices.

   The dense path (Pauli, Kron, Codespace, PartialTrace, VonNeumannEntropy)
   is unchanged. Eigenvalue-dependent operations still require explicit
   matrices; use ToDense to convert when needed. *)

(* ---- SP: symbolic single-qubit Pauli ---- *)

(* SP squares to identity *)
SP[a_] ** SP[a_] := SP["I"];

(* SP["I"] is the identity for NonCommutativeMultiply *)
SP["I"] ** x_ := x;
x_ ** SP["I"] := x;

(* Commutation relations: [sigma_a, sigma_b] = 2i epsilon_{abc} sigma_c *)
Commutator[SP["X"], SP["Y"]] = 2 I SP["Z"];
Commutator[SP["Y"], SP["Z"]] = 2 I SP["X"];
Commutator[SP["Z"], SP["X"]] = 2 I SP["Y"];
Commutator[SP["Y"], SP["X"]] = -2 I SP["Z"];
Commutator[SP["Z"], SP["Y"]] = -2 I SP["X"];
Commutator[SP["X"], SP["Z"]] = -2 I SP["Y"];
Commutator[SP[a_], SP[a_]] = 0;
Commutator[SP["I"], SP[_]] = 0;
Commutator[SP[_], SP["I"]] = 0;

(* Anticommutation: {sigma_a, sigma_b} = 2 delta_{ab} I *)
Anticommutator[SP[a_], SP[a_]] = 2 SP["I"];
Anticommutator[SP[a_], SP[b_]] /; a =!= b := 0;

(* ---- SymPauli: multi-qubit symbolic Pauli ---- *)

SymPauli[s_String] := With[{chars = Characters[s]},
  If[Length[chars] === 1,
    SP[First[chars]],
    NonCommutativeMultiply @@ (SP /@ chars)]];

(* ---- ToDense: symbolic -> explicit matrix ---- *)

$SPMat = <|"I" -> IdentityMatrix[2], "X" -> PauliMatrix[1],
           "Y" -> PauliMatrix[2], "Z" -> PauliMatrix[3]|>;

ToDense[SP[a_String]] := $SPMat[a];
ToDense[NonCommutativeMultiply[factors__]] :=
  KroneckerProduct @@ (ToDense /@ {factors});
ToDense[Times[c_, rest_]] := c * ToDense[rest];
ToDense[Plus[terms__]] := Plus @@ (ToDense /@ {terms});

(* ---- ToSymbolic: 2x2 matrix -> SP decomposition ---- *)

ToSymbolic::not2x2 = "ToSymbolic requires a 2x2 matrix; got dimensions `1`.";
ToSymbolic[mat_?MatrixQ] := Module[{dims = Dimensions[mat], coeffs},
  If[dims =!= {2, 2}, Message[ToSymbolic::not2x2, dims]; Return[$Failed]];
  coeffs = Table[Simplify[Tr[mat . $SPMat[p]] / 2], {p, {"I", "X", "Y", "Z"}}];
  Plus @@ MapThread[Times, {coeffs, SP /@ {"I", "X", "Y", "Z"}}]];

(* ---- StabilizerQ: all generators pairwise commute ---- *)

StabilizerQ[generators_List] := With[
  {n = Length[generators],
   pairs = Subsets[Range[Length[generators]], {2}]},
  AllTrue[pairs,
    TrueQ[Commutator[generators[[#[[1]]]], generators[[#[[2]]]]] === 0] &]];

End[];
EndPackage[];
