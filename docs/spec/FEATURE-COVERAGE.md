# TANGLE Feature Coverage in DECISIONS-LOCKED.md

This document maps language features to design decisions.

## Core Features vs Decisions

| Feature | Covered in Decisions? | Location | Notes |
|---------|----------------------|----------|-------|
| ✓ **Named definitions with parameters** | ✅ YES | D1.3, D1.13 | `def f(x) = ...` |
| ✓ **Five composition operators** | ⚠️ PARTIAL | D1.6, D1.7, D1.8, D1.8.5 | Need explicit section |
| ✓ **Six built-in transforms** | ❌ NO | Missing | Need D1.14 |
| ✓ **Crossing interaction (> <)** | ✅ YES | D1.10 | Boundary inference |
| ✓ **Twist operator (~)** | ❌ NO | Missing | Need type rule |
| ✓ **Invariant computation** | ✅ YES | D1.12 | `compute jones(...)` |
| ✓ **Equivalence assertions** | ✅ YES | D1.2 | `assert ... ~ ...` |
| ✓ **Structured I/O blocks** | ✅ YES | D1.9-D1.11 | `weave ... yield` |
| ✓ **Optional type annotations** | ✅ YES | D1.10 | `x:Bit` in strands |
| ✓ **Two comment styles** | ✅ YES | Grammar only | Lexical, not semantic |

---

## Missing: D1.14 Core Tangle Operations

**Need to add**: Explicit typing rules for all built-in operations.

### Proposed D1.14: Core Tangle Operations

**Decision**: Standard tangle operations with typed signatures.

**Unary Operations**:
```
close(t)    : Tangle[𝐀,𝐀] → Tangle[I,I]         (close all strands)
mirror(t)   : Tangle[𝐀,𝐁] → Tangle[𝐀',𝐁']      (horizontal reflection)
reverse(t)  : Tangle[𝐀,𝐁] → Tangle[𝐁,𝐀]        (swap input/output)
simplify(t) : Tangle[𝐀,𝐁] → Tangle[𝐀,𝐁]        (apply Reidemeister moves)
cap(x,y)    : Creates cup (U-shaped connection)
cup(x,y)    : Creates cap (∩-shaped connection)
(~x)        : Tangle twist on strand x
```

**Binary Operations**:
```
f >> g  ≜  f . g                                 (pipeline is syntactic sugar)
f . g   : Tangle[𝐀,𝐁] × Tangle[𝐁,𝐂] → Tangle[𝐀,𝐂]  (vertical composition)
f | g   : Tangle[𝐀,𝐁] × Tangle[𝐂,𝐃] → Tangle[𝐀++𝐂, 𝐁++𝐃]  (horizontal tensor)
f + g   : Tangle[I,I] × Tangle[I,I] → Tangle[I,I]  (disjoint union - D1.7)
```

**Crossing Operations** (in weave context):
```
(a > b)  : Creates positive crossing of strands a, b
(a < b)  : Creates negative crossing of strands a, b
```

**Rationale**: Makes type system complete, enables type checking all operations.

---

## Summary

**Well-Covered** (8/10):
- Named definitions ✅
- Crossings ✅
- Invariants ✅
- Assertions ✅
- Weave blocks ✅
- Type annotations ✅
- Comments ✅
- Composition operators ⚠️ (partial)

**Missing** (2/10):
- Built-in transforms (close, mirror, etc.) ❌
- Twist operator ❌

**Action**: Add D1.14 to complete feature coverage.
