<!--
SPDX-License-Identifier: MPL-2.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# Tangle Playground

A local PWA playground for the Tangle topological programming language.

## Status

**Scaffold.** The directory structure is in place. The interactive playground
itself is not yet built.

## Intended architecture (pattern mirrors sibling language playgrounds)

- **Compiler backend:** `compiler/tangle-wasm/` compiled to WASM
- **Runtime:** Deno or Bun serving the PWA shell + static assets
- **UI:** ReScript + React SPA with Monaco editor
- **Execution modes:**
  - `parse` — show AST
  - `typecheck` — show type errors + inferred types
  - `compile` — PlanarDiagram / TangleIR output
  - `eval` — step-through evaluator (PanLL timeline if available)
- **Share-by-URL:** URL-encoded source for sharing snippets
- **Examples:** `playground/examples/` — starter programs

## Directory layout

```
playground/
├── README.md          (this file)
├── public/            (static assets; PWA shell goes here when built)
└── examples/          (starter .tangle programs)
```

## Next steps to build this out

1. Write a minimal Deno server that serves `public/` + a `/run` endpoint
2. Build tangle-wasm to WASM with `wasm-pack` or similar
3. Add Monaco editor with Tangle syntax highlighting
4. Add execution-mode tabs
5. Add example loader wiring up `playground/examples/`

See sibling playgrounds for patterns:
- `/var/mnt/eclipse/repos/nextgen-languages/eclexia/playground/`
- `/var/mnt/eclipse/repos/nextgen-languages/betlang/playground/`
