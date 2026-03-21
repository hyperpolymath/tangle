# TANGLE & TANGLE-JTV Feature Coverage

SPDX-License-Identifier: PMPL-1.0-or-later

Last updated: 2026-02-12

This document maps language features to design decisions and formal rules.

---

## TANGLE Core Features

| Feature | Decisions | Typing Rules | Eval Rules | Status |
|---------|-----------|-------------|------------|--------|
| Named definitions with parameters | D1.3, D1.13 | T-Def-Fun, T-Def-Val | E-App | Complete |
| Braid literals (Word[n]) | D1.1, D1.14 | T-Braid, T-Braid-Empty, T-Identity | E-Braid, E-Identity | Complete |
| Vertical composition (`.`) | D1.8, D1.8.5 | T-Compose-Word, T-Compose-Tangle | E-Compose-Word, E-Compose-Tangle | Complete |
| Horizontal tensor (`\|`) | D1.8 | T-Tensor-Word, T-Tensor-Tangle | E-Tensor-Word | Complete |
| Pipeline (`>>`) | D1.20 | T-Pipeline | E-Pipeline | Complete |
| Addition (`+`) | D1.6, D1.7 | T-Add-Num, T-Add-Tangle | E-Add-Num, E-Add-Tangle | Complete |
| Arithmetic (`-`, `*`, `/`) | D1.6 | T-Arith | E-Arith, E-Div-Zero | Complete |
| Structural equality (`==`) | D1.2 | T-Eq-Word, T-Eq-Num, T-Eq-Str | E-Eq-Word, E-Eq-Num, E-Eq-Str | Complete |
| Isotopy equivalence (`~`) | D1.2 | T-Isotopy | E-Isotopy | Complete |
| Crossings (`>`, `<`) | D1.10 | T-Cross-Over, T-Cross-Under | E-Cross | Complete |
| Twist (`~`) | D1.18, D1.19 | T-Twist-Word, T-Twist-Tangle, T-Twist-Strand, T-Self-Cross | E-Twist-Standalone | Complete |
| close() | D1.17 | T-Close-Tangle, T-Close-Word | E-Close-Word, E-Close-Tangle | Complete |
| mirror() | D1.16 | T-Mirror-Tangle, T-Mirror-Word | E-Mirror-Word | Complete |
| reverse() | D1.16 | T-Reverse | E-Reverse | Complete |
| simplify() | D1.16 | T-Simplify-Word, T-Simplify-Tangle | E-Simplify | Complete |
| cap/cup | D1.16 | T-Cap, T-Cup, T-Cap-Typed, T-Cup-Typed | — | Complete |
| Pattern matching | D1.3, D1.4 | T-Match, P-Identity, P-Cons, P-Var, P-Wildcard | E-Match-Hit, E-Match-Fail, M-* | Complete |
| Let binding | D1.4.5 | T-Let | E-Let | Complete |
| Weave blocks | D1.9-D1.11, D2.8 | T-Weave | E-Cross, E-Yield-Mismatch | Complete |
| Assertions | D1.15, D1.15.1 | T-Assert | E-Assert-Pass, E-Assert-Fail | Complete |
| Invariant computation | D1.12, D1.16 | T-Compute | E-Compute | Complete |
| Auto-widening | D1.8.5, D1.14 | T-Compose-Word | E-Compose-Word | Complete |
| Word→Tangle coercion | D1.1 | T-Realize, T-Realize-Default | — | Complete |
| Width inference | D1.21 | §3.14 | — | Complete |
| Two-pass program typing | D1.13 | T-Program | §4.16 | Complete |
| Boolean literals | — | T-True, T-False | E-True, E-False | Complete |
| Error propagation | D1.15 | — | E-Halt-Left, E-Halt-Right | Complete |

## TANGLE-JTV Extension Features

| Feature | Decisions | Typing Rules | Eval Rules | Status |
|---------|-----------|-------------|------------|--------|
| add{} blocks | D2.1, D2.4 | T-Add, HD-* | E-Add, EHD-* | Complete |
| harvard{} blocks | D2.1 | T-Harvard | E-Harvard | Complete |
| Three environments (Γ, Δ, Π) | D2.2, D2.3 | §8 | §10 | Complete |
| Embed/Unembed | D2.4, D2.10 | T-Unembed, §7.2 | E-Unembed-* | Complete |
| Harvard data expr | D2.1 | HD-Num, HD-Str, HD-Bool, HD-Var, HD-App, HD-Arith, HD-Compare, HD-And, HD-Or, HD-Not, HD-Neg, HD-If | EHD-Num, EHD-App, EHD-If-* | Complete |
| Harvard control stmts | D2.1 | §6.3 | §10.4 | Complete |
| Harvard calling TANGLE | D2.9 | HC-Call-Tangle-Pure, HC-Call-Tangle-Impure | — | Complete |
| Purity markers | D2.3, D2.9 | §9.5 | — | Complete |
| Module system | D2.6, D2.11 | HC-Import, HC-Import-Alias | — | Complete |
| Reversible blocks | D2.1 | §6.3 | — | Specified in grammar |

---

## Coverage Summary

**TANGLE Core**: 27/27 features fully specified (100%)
**TANGLE-JTV**: 10/10 features fully specified (100%)
**Total decisions referenced**: 44 (D1.1-D1.25, D2.1-D2.11)
**Total typing rules**: 37+
**Total evaluation rules**: 26+

All features have corresponding grammar productions in EBNF, typing rules in
FORMAL-SEMANTICS.md, and evaluation rules where applicable.
