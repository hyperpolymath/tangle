# TANGLE & TANGLE-JTV — Questions Status

Last updated: 2026-02-12

---

## ALL QUESTIONS RESOLVED

All 21 questions have been answered and locked into DECISIONS-LOCKED.md.

### Resolution Summary

| # | Question | Decision | Locked As |
|---|----------|----------|-----------|
| A1.1 | Identity width | Word[0] + auto-widening | D1.14 |
| A1.2 | Close validation | No permutation check | D1.17 |
| A1.3 | Polymorphic boundaries | Width inference, no HM | D1.21 |
| A2.1 | Exhaustiveness scope | Width-aware warning | D1.4 (updated) |
| A2.2 | Self-crossings | Allow, warn, desugar to (~a) | D1.19 |
| A3.1 | Name conflicts | Unified namespace, warn on shadow | D1.15.3 |
| A3.2 | Weave visibility | Can see all of Γ | D2.8 |
| A3.3 | Module system | Flat for MVP | D1.22 |
| A4.1 | Length function | Standard library (Tier 3) | D1.23 |
| A4.2 | Pipeline precedence | Lower than `.`, readability sugar | D1.20 |
| A4.3 | Twist operator | Context-dependent (standalone vs weave) | D1.18 |
| A4.4 | Assertion decidability | Runtime only MVP; future: assert vs prove | D1.15.1 |
| A5.1 | Error handling | Halt/panic MVP; noted for future review | D1.15 |
| A5.2 | Error messages | Name-based with positional hints | D1.15.2 |
| A6.1 | Primitives vs library | Three-tier split | D1.16 |
| B1.1 | Harvard calling TANGLE | Yes, @pure only non-recursive | D2.9 |
| B1.2 | Reverse embedding | Implicit scalar Unembed | D2.10 |
| B1.3 | Turing completeness | Via pattern matching + recursion | D1.24 |
| B2.1 | Data encoding | JTV for complex data, TANGLE = topology | D1.25 |
| B2.2 | Generator partitioning | N/A — resolved by B2.1 | D1.25 |
| B3.1 | Module re-exports | Private for MVP; noted for future review | D2.11 |

### Future Review Items

These were explicitly flagged for post-MVP reconsideration:
1. **A5.1 / D1.15**: Richer error handling model (exceptions, Result types)
2. **A4.4 / D1.15.1**: `assert` vs `prove` split for static verification
3. **B3.1 / D2.11**: Module re-exports (Rust-style `pub use`)

---

See `DECISIONS-LOCKED.md` for full details on every decision.
