// SPDX-License-Identifier: MPL-2.0
// Owner: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// differential.rs — TG-6 differential rung for the Tangle WASM backend.
//
// The backend (`WasmBackend::generate`) lowers braids to a WASM module whose
// braid functions allocate a strand array (identity [0,1,..,n-1]) and call
// `tangle_rt.swap_strands(ptr, i, i+1)` once per generator, in order, returning
// the array pointer.  A braid's denotation is exactly the permutation obtained
// by applying those adjacent transpositions to the identity.
//
// This test EXECUTES the generated module with the `wasmi` interpreter, supplying
// reference host primitives (`alloc_strands` initialises identity; `swap_strands`
// swaps two cells), then checks the executed result equals the permutation
// computed independently in Rust.  It therefore validates that the *codegen*
// preserves the braid's strand-permutation semantics — catching wrong crossing
// indices, wrong call order, miscounted strands, or an invalid/​non-instantiable
// module.
//
// Scope (honest): this diffs WASM execution against an in-Rust reference model of
// the permutation semantics (the same semantics `compiler/lib/eval.ml` realises),
// not against the OCaml evaluator binary directly, and covers the
// generator/braid permutation path (not the Markov-move helpers).  A full
// source↔wasm bisimulation proof remains the research-grade rung (PROOF-NEEDS TG-6).

use tangle_wasm::{BraidGenerator, CompiledBraid, TangleProgram, WasmBackend};
use wasmi::{Caller, Engine, Extern, Linker, Module, Store};

struct Host {
    next_ptr: u32,
}

/// Reference model: apply each generator's adjacent transposition to identity.
fn reference_permutation(
    generators: &[BraidGenerator],
    braid: &CompiledBraid,
) -> Vec<i32> {
    let mut strands: Vec<i32> = (0..braid.strand_count as i32).collect();
    for gname in &braid.generators {
        let g = generators
            .iter()
            .find(|g| &g.name == gname)
            .expect("generator referenced by braid must exist");
        let i = g.crossing_index as usize;
        strands.swap(i, i + 1);
    }
    strands
}

/// Generate, instantiate with reference host primitives, run `braid.name`, and
/// read back the resulting strand array.
fn run_in_wasm(program: &TangleProgram, braid: &CompiledBraid) -> Vec<i32> {
    let mut backend = WasmBackend::new();
    let module_ir = backend.generate(program).expect("codegen");
    let bytes = module_ir.to_bytes().to_vec();

    let engine = Engine::default();
    let module = Module::new(&engine, &bytes[..]).expect("generated module must validate");
    let mut store = Store::new(&engine, Host { next_ptr: 64 });
    let mut linker = <Linker<Host>>::new(&engine);

    // alloc_strands(count) -> ptr : bump-allocate and initialise identity.
    linker
        .func_wrap(
            "tangle_rt",
            "alloc_strands",
            |mut caller: Caller<'_, Host>, count: i32| -> i32 {
                let mem = match caller.get_export("memory") {
                    Some(Extern::Memory(m)) => m,
                    _ => panic!("module must export memory"),
                };
                let ptr = caller.data().next_ptr;
                caller.data_mut().next_ptr += (count.max(0) as u32) * 4;
                let data = mem.data_mut(&mut caller);
                for k in 0..count.max(0) {
                    let off = ptr as usize + (k as usize) * 4;
                    data[off..off + 4].copy_from_slice(&k.to_le_bytes());
                }
                ptr as i32
            },
        )
        .unwrap();

    // swap_strands(ptr, a, b) : swap the two i32 cells.
    linker
        .func_wrap(
            "tangle_rt",
            "swap_strands",
            |mut caller: Caller<'_, Host>, ptr: i32, a: i32, b: i32| {
                let mem = match caller.get_export("memory") {
                    Some(Extern::Memory(m)) => m,
                    _ => panic!("module must export memory"),
                };
                let data = mem.data_mut(&mut caller);
                let pa = (ptr + a * 4) as usize;
                let pb = (ptr + b * 4) as usize;
                let mut va = [0u8; 4];
                let mut vb = [0u8; 4];
                va.copy_from_slice(&data[pa..pa + 4]);
                vb.copy_from_slice(&data[pb..pb + 4]);
                data[pa..pa + 4].copy_from_slice(&vb);
                data[pb..pb + 4].copy_from_slice(&va);
            },
        )
        .unwrap();

    let instance = linker
        .instantiate_and_start(&mut store, &module)
        .expect("instantiate");

    let func = instance
        .get_typed_func::<(), i32>(&store, &braid.name)
        .expect("braid export");
    let ptr = func.call(&mut store, ()).expect("call braid");

    let mem = match instance.get_export(&store, "memory") {
        Some(Extern::Memory(m)) => m,
        _ => panic!("memory export"),
    };
    let n = braid.strand_count as usize;
    let mut buf = vec![0u8; n * 4];
    mem.read(&store, ptr as usize, &mut buf).expect("read mem");
    (0..n)
        .map(|k| i32::from_le_bytes(buf[k * 4..k * 4 + 4].try_into().unwrap()))
        .collect()
}

fn gens3() -> Vec<BraidGenerator> {
    vec![
        BraidGenerator { name: "sigma1".into(), strand_count: 3, crossing_index: 0, positive: true },
        BraidGenerator { name: "sigma2".into(), strand_count: 3, crossing_index: 1, positive: true },
    ]
}

fn check(program: &TangleProgram, braid: &CompiledBraid) {
    let expected = reference_permutation(&program.generators, braid);
    let got = run_in_wasm(program, braid);
    assert_eq!(
        got, expected,
        "braid {:?}: wasm exec {:?} != reference permutation {:?}",
        braid.name, got, expected
    );
}

#[test]
fn differential_trefoil_and_friends() {
    let generators = gens3();
    let braids = vec![
        CompiledBraid { name: "identity".into(), strand_count: 3, generators: vec![] },
        CompiledBraid { name: "s1".into(), strand_count: 3, generators: vec!["sigma1".into()] },
        CompiledBraid { name: "s2".into(), strand_count: 3, generators: vec!["sigma2".into()] },
        CompiledBraid {
            name: "trefoil".into(),
            strand_count: 3,
            generators: vec!["sigma1".into(), "sigma2".into(), "sigma1".into()],
        },
        // non-commuting: s1 s2 vs s2 s1 must give different permutations
        CompiledBraid { name: "s1s2".into(), strand_count: 3, generators: vec!["sigma1".into(), "sigma2".into()] },
        CompiledBraid { name: "s2s1".into(), strand_count: 3, generators: vec!["sigma2".into(), "sigma1".into()] },
        // braid relation: s1 s2 s1 and s2 s1 s2 must give the SAME permutation
        CompiledBraid { name: "lhs".into(), strand_count: 3, generators: vec!["sigma1".into(), "sigma2".into(), "sigma1".into()] },
        CompiledBraid { name: "rhs".into(), strand_count: 3, generators: vec!["sigma2".into(), "sigma1".into(), "sigma2".into()] },
    ];
    let program = TangleProgram { generators: generators.clone(), braids: braids.clone(), string_constants: vec![] };
    for b in &program.braids {
        check(&program, b);
    }

    // sanity on the reference expectations themselves
    assert_eq!(reference_permutation(&generators, &program.braids[3]), vec![2, 1, 0]); // trefoil
    assert_ne!(
        reference_permutation(&generators, &program.braids[4]),
        reference_permutation(&generators, &program.braids[5]),
        "s1s2 and s2s1 are different permutations"
    );
    assert_eq!(
        reference_permutation(&generators, &program.braids[6]),
        reference_permutation(&generators, &program.braids[7]),
        "braid relation: s1s2s1 == s2s1s2 as permutations"
    );
}

#[test]
fn differential_wider_braid() {
    let generators = vec![
        BraidGenerator { name: "a".into(), strand_count: 5, crossing_index: 0, positive: true },
        BraidGenerator { name: "b".into(), strand_count: 5, crossing_index: 1, positive: true },
        BraidGenerator { name: "c".into(), strand_count: 5, crossing_index: 2, positive: true },
        BraidGenerator { name: "d".into(), strand_count: 5, crossing_index: 3, positive: true },
    ];
    let braid = CompiledBraid {
        name: "weave".into(),
        strand_count: 5,
        generators: vec!["a".into(), "c".into(), "b".into(), "d".into(), "a".into(), "c".into()],
    };
    let program = TangleProgram { generators, braids: vec![braid.clone()], string_constants: vec![] };
    check(&program, &braid);
}
