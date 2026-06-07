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

End[];
EndPackage[];
