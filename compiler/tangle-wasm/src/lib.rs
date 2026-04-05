// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell

//! WebAssembly backend for Tangle.
//!
//! Compiles braid operations to WASM linear memory and function calls.
//! Braid generators become WASM functions, and braid composition maps
//! to sequential function execution.
//!
//! ## Output format
//!
//! Generates valid `.wasm` modules (binary format) containing:
//! - Type section (function signatures for braid generators)
//! - Import section (runtime support: strand allocation, crossing operations)
//! - Function section (compiled braid generators)
//! - Memory section (linear memory for strand/crossing state)
//! - Export section (top-level braids + memory)
//! - Data section (braid metadata / string constants)
//!
//! ## Braid representation
//!
//! - Strands: i32 indices into a strand table in linear memory
//! - Crossings: pairs of strand indices (i32, i32) stored contiguously
//! - Generators: WASM functions that mutate strand state in linear memory
//! - Composition: sequential calls to generator functions
//!
//! ## Limitations
//!
//! - No garbage collection (bump allocator for strand state)
//! - Braid isotopy checks not performed at WASM level (compile-time only)
//!
//! ## Markov moves (WASM helper functions)
//!
//! Two Markov move helpers are emitted as WASM functions:
//!
//! - `markov_type_i(braid_ptr, len) -> new_len`: Type I moves remove
//!   adjacent σᵢσᵢ⁻¹ or σᵢ⁻¹σᵢ pairs (identity crossings) from the
//!   braid word array in linear memory.
//! - `markov_type_ii(braid_ptr, len, pos) -> new_len`: Type II moves
//!   slide a crossing past a non-adjacent crossing at the given position.
//!
//! ## Braid group inverse
//!
//! - `braid_inverse(src_ptr, len, dst_ptr)`: For braid word σ₁σ₂σ₁,
//!   writes σ₁⁻¹σ₂⁻¹σ₁⁻¹ to `dst_ptr` (reversed order, negated
//!   exponents).

#![forbid(unsafe_code)]
use std::collections::HashMap;

use wasm_encoder::{
    CodeSection, DataSection, EntityType, ExportKind, ExportSection,
    Function as WasmFunc, FunctionSection, ImportSection, Instruction,
    MemorySection, MemoryType, Module, TypeSection, ValType,
};

/// Errors specific to the Tangle WASM backend.
#[derive(Debug, Clone, thiserror::Error)]
pub enum WasmError {
    /// A braid generator references a strand index out of range.
    #[error("strand index {index} exceeds strand count {count}")]
    StrandIndexOutOfRange { index: u32, count: u32 },

    /// Data section offset exceeds linear memory bounds.
    #[error("data section offset {offset} exceeds linear memory capacity ({capacity} bytes)")]
    DataSectionOverflow { offset: u32, capacity: u32 },

    /// Bump allocator ran out of linear memory.
    #[error("heap allocation of {requested} bytes exceeds capacity (offset {current}, capacity {capacity})")]
    HeapOverflow {
        requested: u32,
        current: u32,
        capacity: u32,
    },

    /// A function name collision was detected.
    #[error("duplicate function name: \"{name}\"")]
    DuplicateFunctionName { name: String },

    /// An import required by a braid operation is missing.
    #[error("missing import: \"{module}.{name}\" required for braid operation")]
    MissingImport { module: String, name: String },
}

/// WASM value type subset used by Tangle.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WasmType {
    I32,
    I64,
    F64,
}

impl WasmType {
    fn to_val_type(self) -> ValType {
        match self {
            Self::I32 => ValType::I32,
            Self::I64 => ValType::I64,
            Self::F64 => ValType::F64,
        }
    }
}

/// A compiled WASM function representing a braid generator or composition.
#[derive(Debug, Clone)]
pub struct WasmFunction {
    /// Function name (braid generator name).
    pub name: String,
    /// Parameter types.
    pub params: Vec<WasmType>,
    /// Return type.
    pub result: Option<WasmType>,
    /// Compiled bytecode size.
    pub code_size: usize,
}

/// A WASM import declaration.
#[derive(Debug, Clone)]
pub struct WasmImport {
    /// Module name (e.g., "tangle_rt").
    pub module: String,
    /// Function name (e.g., "alloc_strands").
    pub name: String,
    /// Parameter types.
    pub params: Vec<WasmType>,
    /// Return type (None = void).
    pub result: Option<WasmType>,
}

/// Output of the Tangle WASM backend.
#[derive(Debug, Clone)]
pub struct WasmModule {
    /// Compiled functions.
    pub functions: Vec<WasmFunction>,
    /// Required imports.
    pub imports: Vec<WasmImport>,
    /// Initial memory pages (64KB each).
    pub initial_memory_pages: u32,
    /// Maximum memory pages.
    pub max_memory_pages: u32,
    /// The WASM binary module bytes.
    binary: Vec<u8>,
}

impl WasmModule {
    /// Get the WASM binary bytes.
    pub fn to_bytes(&self) -> &[u8] {
        &self.binary
    }

    /// Consume and return the WASM binary bytes.
    pub fn into_bytes(self) -> Vec<u8> {
        self.binary
    }
}

/// Bump allocator for WASM linear memory.
#[allow(dead_code)]
struct BumpAllocator {
    next_offset: u32,
    capacity: u32,
}

#[allow(dead_code)]
impl BumpAllocator {
    fn new(initial_offset: u32, initial_pages: u32) -> Self {
        Self {
            next_offset: initial_offset,
            capacity: initial_pages.saturating_mul(65536),
        }
    }

    fn alloc(&mut self, size: u32) -> Result<u32, WasmError> {
        let aligned = (self.next_offset + 7) & !7;
        let new_offset = aligned.checked_add(size).ok_or(WasmError::HeapOverflow {
            requested: size,
            current: self.next_offset,
            capacity: self.capacity,
        })?;
        if new_offset > self.capacity {
            return Err(WasmError::HeapOverflow {
                requested: size,
                current: self.next_offset,
                capacity: self.capacity,
            });
        }
        self.next_offset = new_offset;
        Ok(aligned)
    }
}

/// A braid generator: an elementary crossing operation on strands.
#[derive(Debug, Clone)]
pub struct BraidGenerator {
    /// Generator name.
    pub name: String,
    /// Number of strands this generator operates on.
    pub strand_count: u32,
    /// Crossing index (which pair of adjacent strands to cross).
    pub crossing_index: u32,
    /// Whether this is a positive (over) or negative (under) crossing.
    pub positive: bool,
}

/// A compiled braid: a sequence of generator applications.
#[derive(Debug, Clone)]
pub struct CompiledBraid {
    /// Braid name.
    pub name: String,
    /// Number of strands.
    pub strand_count: u32,
    /// Sequence of generator names to apply in order.
    pub generators: Vec<String>,
}

/// Input to the Tangle WASM backend.
#[derive(Debug, Clone)]
pub struct TangleProgram {
    /// Braid generators (elementary operations).
    pub generators: Vec<BraidGenerator>,
    /// Composed braids (sequences of generators).
    pub braids: Vec<CompiledBraid>,
    /// String constants for metadata.
    pub string_constants: Vec<String>,
}

/// WASM backend for Tangle.
///
/// Modelled after the Eclexia WASM backend pattern: collects imports,
/// compiles functions, builds a complete WASM binary module.
pub struct WasmBackend {
    initial_memory_pages: u32,
    max_memory_pages: u32,
    warnings: Vec<String>,
}

impl WasmBackend {
    /// Create a new WASM backend with default memory settings.
    pub fn new() -> Self {
        Self {
            initial_memory_pages: 4, // 256KB initial
            max_memory_pages: 64,    // 4MB max
            warnings: Vec::new(),
        }
    }

    /// Retrieve any warnings generated during the last `generate()` call.
    pub fn warnings(&self) -> &[String] {
        &self.warnings
    }

    /// Set initial memory pages.
    pub fn with_initial_memory(mut self, pages: u32) -> Self {
        self.initial_memory_pages = pages;
        self
    }

    /// Set maximum memory pages.
    pub fn with_max_memory(mut self, pages: u32) -> Self {
        self.max_memory_pages = pages;
        self
    }

    /// Generate a WASM module from a Tangle program.
    ///
    /// Each braid generator compiles to a WASM function that performs a
    /// crossing operation on strand state in linear memory. Composed
    /// braids compile to functions that sequentially call their generators.
    pub fn generate(&mut self, program: &TangleProgram) -> Result<WasmModule, WasmError> {
        self.warnings.clear();

        // Validate generator crossing indices
        for generator in &program.generators {
            if generator.crossing_index >= generator.strand_count.saturating_sub(1) {
                return Err(WasmError::StrandIndexOutOfRange {
                    index: generator.crossing_index,
                    count: generator.strand_count,
                });
            }
        }

        // Check for duplicate function names
        let mut seen_names: HashMap<&str, bool> = HashMap::new();
        for generator in &program.generators {
            if seen_names.contains_key(generator.name.as_str()) {
                return Err(WasmError::DuplicateFunctionName {
                    name: generator.name.clone(),
                });
            }
            seen_names.insert(&generator.name, true);
        }
        for braid in &program.braids {
            if seen_names.contains_key(braid.name.as_str()) {
                return Err(WasmError::DuplicateFunctionName {
                    name: braid.name.clone(),
                });
            }
            seen_names.insert(&braid.name, true);
        }

        // Collect string constants and compute data section
        let string_offsets = self.collect_strings(&program.string_constants)?;

        // Build imports: runtime support for strand operations
        let imports = vec![
            WasmImport {
                module: "tangle_rt".into(),
                name: "alloc_strands".into(),
                params: vec![WasmType::I32], // strand count
                result: Some(WasmType::I32), // pointer to strand array
            },
            WasmImport {
                module: "tangle_rt".into(),
                name: "swap_strands".into(),
                params: vec![WasmType::I32, WasmType::I32, WasmType::I32], // ptr, idx_a, idx_b
                result: None,
            },
        ];
        let import_count = imports.len() as u32;

        // Compile generator functions
        let mut compiled_funcs: Vec<(Vec<WasmType>, Option<WasmType>, WasmFunc)> = Vec::new();
        let mut wasm_functions: Vec<WasmFunction> = Vec::new();

        // Build a name-to-index map for generators so braids can call them
        let mut gen_index_map: HashMap<&str, u32> = HashMap::new();

        for (i, generator) in program.generators.iter().enumerate() {
            gen_index_map.insert(&generator.name, import_count + i as u32);

            let mut func_body = WasmFunc::new(vec![]);
            // Generator function: takes strand array pointer (i32), returns void
            // Body: call swap_strands(ptr, crossing_index, crossing_index + 1)
            func_body.instruction(&Instruction::LocalGet(0)); // strand array ptr
            func_body.instruction(&Instruction::I32Const(generator.crossing_index as i32));
            func_body.instruction(&Instruction::I32Const(generator.crossing_index as i32 + 1));
            func_body.instruction(&Instruction::Call(1)); // swap_strands import index
            func_body.instruction(&Instruction::End);

            let code_size = 5; // approximate instruction count
            compiled_funcs.push((vec![WasmType::I32], None, func_body));
            wasm_functions.push(WasmFunction {
                name: generator.name.clone(),
                params: vec![WasmType::I32],
                result: None,
                code_size,
            });
        }

        // Compile composed braids: sequential calls to generators
        for braid in &program.braids {
            // local 0 stores the allocated strand pointer
            let mut func_body = WasmFunc::new(vec![(1, ValType::I32)]);

            // Allocate strands first
            func_body.instruction(&Instruction::I32Const(braid.strand_count as i32));
            func_body.instruction(&Instruction::Call(0)); // alloc_strands import
            // Store pointer in local 0 (first param position, but we use it as a local)
            // Actually, the result is on the stack. We store it as local 1.
            func_body.instruction(&Instruction::LocalSet(0));

            // Call each generator in sequence
            for gen_name in &braid.generators {
                if let Some(&func_idx) = gen_index_map.get(gen_name.as_str()) {
                    func_body.instruction(&Instruction::LocalGet(0)); // strand ptr
                    func_body.instruction(&Instruction::Call(func_idx));
                } else {
                    return Err(WasmError::MissingImport {
                        module: "braid".into(),
                        name: gen_name.clone(),
                    });
                }
            }

            // Return the strand array pointer
            func_body.instruction(&Instruction::LocalGet(0));
            func_body.instruction(&Instruction::End);

            let code_size = 3 + braid.generators.len() * 2;
            compiled_funcs.push((vec![], Some(WasmType::I32), func_body));
            wasm_functions.push(WasmFunction {
                name: braid.name.clone(),
                params: vec![],
                result: Some(WasmType::I32),
                code_size,
            });
        }

        // === Markov Type I move ===
        // Scans braid word array (i32 elements at braid_ptr) for adjacent
        // σᵢσᵢ⁻¹ or σᵢ⁻¹σᵢ pairs and removes them in-place.
        // Signature: (braid_ptr: i32, len: i32) -> i32 (new length)
        {
            // Locals: [read_idx (local 2), write_idx (local 3), val_a (local 4), val_b (local 5)]
            let mut func_body = WasmFunc::new(vec![
                (1, ValType::I32), // local 2: read_idx
                (1, ValType::I32), // local 3: write_idx
                (1, ValType::I32), // local 4: val_a
                (1, ValType::I32), // local 5: val_b
            ]);

            // read_idx = 0; write_idx = 0;
            func_body.instruction(&Instruction::I32Const(0));
            func_body.instruction(&Instruction::LocalSet(2));
            func_body.instruction(&Instruction::I32Const(0));
            func_body.instruction(&Instruction::LocalSet(3));

            // Loop over elements
            func_body.instruction(&Instruction::Block(wasm_encoder::BlockType::Empty)); // block $break
            func_body.instruction(&Instruction::Loop(wasm_encoder::BlockType::Empty));  // loop $continue

            // if read_idx >= len - 1, break
            func_body.instruction(&Instruction::LocalGet(2)); // read_idx
            func_body.instruction(&Instruction::LocalGet(1)); // len
            func_body.instruction(&Instruction::I32Const(1));
            func_body.instruction(&Instruction::I32Sub);
            func_body.instruction(&Instruction::I32GeS);
            func_body.instruction(&Instruction::BrIf(1)); // br $break

            // val_a = mem[braid_ptr + read_idx * 4]
            func_body.instruction(&Instruction::LocalGet(0)); // braid_ptr
            func_body.instruction(&Instruction::LocalGet(2)); // read_idx
            func_body.instruction(&Instruction::I32Const(4));
            func_body.instruction(&Instruction::I32Mul);
            func_body.instruction(&Instruction::I32Add);
            func_body.instruction(&Instruction::I32Load(wasm_encoder::MemArg {
                offset: 0, align: 2, memory_index: 0,
            }));
            func_body.instruction(&Instruction::LocalSet(4)); // val_a

            // val_b = mem[braid_ptr + (read_idx + 1) * 4]
            func_body.instruction(&Instruction::LocalGet(0));
            func_body.instruction(&Instruction::LocalGet(2));
            func_body.instruction(&Instruction::I32Const(1));
            func_body.instruction(&Instruction::I32Add);
            func_body.instruction(&Instruction::I32Const(4));
            func_body.instruction(&Instruction::I32Mul);
            func_body.instruction(&Instruction::I32Add);
            func_body.instruction(&Instruction::I32Load(wasm_encoder::MemArg {
                offset: 0, align: 2, memory_index: 0,
            }));
            func_body.instruction(&Instruction::LocalSet(5)); // val_b

            // if val_a + val_b == 0 (i.e. σᵢ and σᵢ⁻¹ cancel), skip both
            func_body.instruction(&Instruction::LocalGet(4));
            func_body.instruction(&Instruction::LocalGet(5));
            func_body.instruction(&Instruction::I32Add);
            func_body.instruction(&Instruction::I32Eqz);
            func_body.instruction(&Instruction::If(wasm_encoder::BlockType::Empty));
            // Skip: advance read_idx by 2
            func_body.instruction(&Instruction::LocalGet(2));
            func_body.instruction(&Instruction::I32Const(2));
            func_body.instruction(&Instruction::I32Add);
            func_body.instruction(&Instruction::LocalSet(2));
            func_body.instruction(&Instruction::Br(1)); // br $continue
            func_body.instruction(&Instruction::End); // end if

            // No cancellation: copy val_a to write position
            func_body.instruction(&Instruction::LocalGet(0)); // braid_ptr
            func_body.instruction(&Instruction::LocalGet(3)); // write_idx
            func_body.instruction(&Instruction::I32Const(4));
            func_body.instruction(&Instruction::I32Mul);
            func_body.instruction(&Instruction::I32Add);
            func_body.instruction(&Instruction::LocalGet(4)); // val_a
            func_body.instruction(&Instruction::I32Store(wasm_encoder::MemArg {
                offset: 0, align: 2, memory_index: 0,
            }));

            // write_idx++; read_idx++
            func_body.instruction(&Instruction::LocalGet(3));
            func_body.instruction(&Instruction::I32Const(1));
            func_body.instruction(&Instruction::I32Add);
            func_body.instruction(&Instruction::LocalSet(3));
            func_body.instruction(&Instruction::LocalGet(2));
            func_body.instruction(&Instruction::I32Const(1));
            func_body.instruction(&Instruction::I32Add);
            func_body.instruction(&Instruction::LocalSet(2));

            func_body.instruction(&Instruction::Br(0)); // br $continue
            func_body.instruction(&Instruction::End); // end loop
            func_body.instruction(&Instruction::End); // end block

            // Copy last element if read_idx == len - 1 (odd element remaining)
            func_body.instruction(&Instruction::LocalGet(2));
            func_body.instruction(&Instruction::LocalGet(1));
            func_body.instruction(&Instruction::I32LtS);
            func_body.instruction(&Instruction::If(wasm_encoder::BlockType::Empty));
            func_body.instruction(&Instruction::LocalGet(0));
            func_body.instruction(&Instruction::LocalGet(3));
            func_body.instruction(&Instruction::I32Const(4));
            func_body.instruction(&Instruction::I32Mul);
            func_body.instruction(&Instruction::I32Add);
            func_body.instruction(&Instruction::LocalGet(0));
            func_body.instruction(&Instruction::LocalGet(2));
            func_body.instruction(&Instruction::I32Const(4));
            func_body.instruction(&Instruction::I32Mul);
            func_body.instruction(&Instruction::I32Add);
            func_body.instruction(&Instruction::I32Load(wasm_encoder::MemArg {
                offset: 0, align: 2, memory_index: 0,
            }));
            func_body.instruction(&Instruction::I32Store(wasm_encoder::MemArg {
                offset: 0, align: 2, memory_index: 0,
            }));
            func_body.instruction(&Instruction::LocalGet(3));
            func_body.instruction(&Instruction::I32Const(1));
            func_body.instruction(&Instruction::I32Add);
            func_body.instruction(&Instruction::LocalSet(3));
            func_body.instruction(&Instruction::End); // end if

            // Return write_idx (new length)
            func_body.instruction(&Instruction::LocalGet(3));
            func_body.instruction(&Instruction::End);

            compiled_funcs.push((vec![WasmType::I32, WasmType::I32], Some(WasmType::I32), func_body));
            wasm_functions.push(WasmFunction {
                name: "markov_type_i".into(),
                params: vec![WasmType::I32, WasmType::I32],
                result: Some(WasmType::I32),
                code_size: 60,
            });
        }

        // === Markov Type II move ===
        // Slides a crossing past a non-adjacent crossing at the given position.
        // For generators σᵢ and σⱼ where |i - j| >= 2, they commute:
        // σᵢσⱼ = σⱼσᵢ. This swaps adjacent array entries at pos and pos+1.
        // Signature: (braid_ptr: i32, len: i32, pos: i32) -> i32 (len unchanged)
        {
            let mut func_body = WasmFunc::new(vec![
                (1, ValType::I32), // local 3: tmp
            ]);

            // Bounds check: pos must be < len - 1
            func_body.instruction(&Instruction::LocalGet(2)); // pos
            func_body.instruction(&Instruction::LocalGet(1)); // len
            func_body.instruction(&Instruction::I32Const(1));
            func_body.instruction(&Instruction::I32Sub);
            func_body.instruction(&Instruction::I32GeS);
            func_body.instruction(&Instruction::If(wasm_encoder::BlockType::Empty));
            func_body.instruction(&Instruction::LocalGet(1)); // return len unchanged
            func_body.instruction(&Instruction::Return);
            func_body.instruction(&Instruction::End);

            // tmp = mem[braid_ptr + pos * 4]
            func_body.instruction(&Instruction::LocalGet(0));
            func_body.instruction(&Instruction::LocalGet(2));
            func_body.instruction(&Instruction::I32Const(4));
            func_body.instruction(&Instruction::I32Mul);
            func_body.instruction(&Instruction::I32Add);
            func_body.instruction(&Instruction::I32Load(wasm_encoder::MemArg {
                offset: 0, align: 2, memory_index: 0,
            }));
            func_body.instruction(&Instruction::LocalSet(3)); // tmp

            // mem[braid_ptr + pos * 4] = mem[braid_ptr + (pos+1) * 4]
            func_body.instruction(&Instruction::LocalGet(0));
            func_body.instruction(&Instruction::LocalGet(2));
            func_body.instruction(&Instruction::I32Const(4));
            func_body.instruction(&Instruction::I32Mul);
            func_body.instruction(&Instruction::I32Add);
            func_body.instruction(&Instruction::LocalGet(0));
            func_body.instruction(&Instruction::LocalGet(2));
            func_body.instruction(&Instruction::I32Const(1));
            func_body.instruction(&Instruction::I32Add);
            func_body.instruction(&Instruction::I32Const(4));
            func_body.instruction(&Instruction::I32Mul);
            func_body.instruction(&Instruction::I32Add);
            func_body.instruction(&Instruction::I32Load(wasm_encoder::MemArg {
                offset: 0, align: 2, memory_index: 0,
            }));
            func_body.instruction(&Instruction::I32Store(wasm_encoder::MemArg {
                offset: 0, align: 2, memory_index: 0,
            }));

            // mem[braid_ptr + (pos+1) * 4] = tmp
            func_body.instruction(&Instruction::LocalGet(0));
            func_body.instruction(&Instruction::LocalGet(2));
            func_body.instruction(&Instruction::I32Const(1));
            func_body.instruction(&Instruction::I32Add);
            func_body.instruction(&Instruction::I32Const(4));
            func_body.instruction(&Instruction::I32Mul);
            func_body.instruction(&Instruction::I32Add);
            func_body.instruction(&Instruction::LocalGet(3)); // tmp
            func_body.instruction(&Instruction::I32Store(wasm_encoder::MemArg {
                offset: 0, align: 2, memory_index: 0,
            }));

            // Return len (unchanged)
            func_body.instruction(&Instruction::LocalGet(1));
            func_body.instruction(&Instruction::End);

            compiled_funcs.push((vec![WasmType::I32, WasmType::I32, WasmType::I32], Some(WasmType::I32), func_body));
            wasm_functions.push(WasmFunction {
                name: "markov_type_ii".into(),
                params: vec![WasmType::I32, WasmType::I32, WasmType::I32],
                result: Some(WasmType::I32),
                code_size: 30,
            });
        }

        // === Braid group inverse ===
        // For braid word σ₁σ₂σ₁ the inverse is σ₁⁻¹σ₂⁻¹σ₁⁻¹ (reverse
        // order, negate each exponent). Generator indices are stored as
        // signed i32: positive = over-crossing, negative = under-crossing.
        // Signature: (src_ptr: i32, len: i32, dst_ptr: i32) -> void
        {
            let mut func_body = WasmFunc::new(vec![
                (1, ValType::I32), // local 3: loop counter i
            ]);

            // i = 0
            func_body.instruction(&Instruction::I32Const(0));
            func_body.instruction(&Instruction::LocalSet(3));

            func_body.instruction(&Instruction::Block(wasm_encoder::BlockType::Empty));
            func_body.instruction(&Instruction::Loop(wasm_encoder::BlockType::Empty));

            // if i >= len, break
            func_body.instruction(&Instruction::LocalGet(3));
            func_body.instruction(&Instruction::LocalGet(1));
            func_body.instruction(&Instruction::I32GeS);
            func_body.instruction(&Instruction::BrIf(1));

            // dst[i] = -src[len - 1 - i]
            // dst addr: dst_ptr + i * 4
            func_body.instruction(&Instruction::LocalGet(2)); // dst_ptr
            func_body.instruction(&Instruction::LocalGet(3)); // i
            func_body.instruction(&Instruction::I32Const(4));
            func_body.instruction(&Instruction::I32Mul);
            func_body.instruction(&Instruction::I32Add);

            // src addr: src_ptr + (len - 1 - i) * 4
            func_body.instruction(&Instruction::I32Const(0)); // for negation: 0 - val
            func_body.instruction(&Instruction::LocalGet(0)); // src_ptr
            func_body.instruction(&Instruction::LocalGet(1)); // len
            func_body.instruction(&Instruction::I32Const(1));
            func_body.instruction(&Instruction::I32Sub);
            func_body.instruction(&Instruction::LocalGet(3)); // i
            func_body.instruction(&Instruction::I32Sub);
            func_body.instruction(&Instruction::I32Const(4));
            func_body.instruction(&Instruction::I32Mul);
            func_body.instruction(&Instruction::I32Add);
            func_body.instruction(&Instruction::I32Load(wasm_encoder::MemArg {
                offset: 0, align: 2, memory_index: 0,
            }));
            func_body.instruction(&Instruction::I32Sub); // 0 - val = negated

            func_body.instruction(&Instruction::I32Store(wasm_encoder::MemArg {
                offset: 0, align: 2, memory_index: 0,
            }));

            // i++
            func_body.instruction(&Instruction::LocalGet(3));
            func_body.instruction(&Instruction::I32Const(1));
            func_body.instruction(&Instruction::I32Add);
            func_body.instruction(&Instruction::LocalSet(3));

            func_body.instruction(&Instruction::Br(0)); // continue
            func_body.instruction(&Instruction::End); // end loop
            func_body.instruction(&Instruction::End); // end block
            func_body.instruction(&Instruction::End); // end function

            compiled_funcs.push((vec![WasmType::I32, WasmType::I32, WasmType::I32], None, func_body));
            wasm_functions.push(WasmFunction {
                name: "braid_inverse".into(),
                params: vec![WasmType::I32, WasmType::I32, WasmType::I32],
                result: None,
                code_size: 25,
            });
        }

        // Build the WASM binary module
        let binary = self.build_module(&imports, &compiled_funcs, &string_offsets, &wasm_functions);

        Ok(WasmModule {
            functions: wasm_functions,
            imports,
            initial_memory_pages: self.initial_memory_pages,
            max_memory_pages: self.max_memory_pages,
            binary,
        })
    }

    /// Collect string constants and assign data section offsets.
    fn collect_strings(&mut self, strings: &[String]) -> Result<Vec<(String, u32)>, WasmError> {
        let mut result = Vec::new();
        let mut offset: u32 = 0;
        let capacity = self.initial_memory_pages.saturating_mul(65536);

        for s in strings {
            let entry_size = s.len() as u32 + 1; // +1 for null terminator
            let new_offset = offset.checked_add(entry_size).ok_or(
                WasmError::DataSectionOverflow { offset, capacity },
            )?;
            if new_offset > capacity {
                return Err(WasmError::DataSectionOverflow {
                    offset: new_offset,
                    capacity,
                });
            }
            result.push((s.clone(), offset));
            offset = new_offset;
        }

        if capacity > 0 && offset > capacity * 3 / 4 {
            self.warnings.push(format!(
                "data section uses {offset}/{capacity} bytes ({:.0}% of initial memory)",
                offset as f64 / capacity as f64 * 100.0
            ));
        }

        Ok(result)
    }

    /// Build the complete WASM binary module.
    fn build_module(
        &self,
        imports: &[WasmImport],
        compiled_funcs: &[(Vec<WasmType>, Option<WasmType>, WasmFunc)],
        string_data: &[(String, u32)],
        wasm_functions: &[WasmFunction],
    ) -> Vec<u8> {
        let mut module = Module::new();
        let import_count = imports.len() as u32;

        // === Type section ===
        let mut types = TypeSection::new();
        for imp in imports {
            let params: Vec<ValType> = imp.params.iter().map(|t| t.to_val_type()).collect();
            let results: Vec<ValType> = imp.result.iter().map(|t| t.to_val_type()).collect();
            types.ty().function(params, results);
        }
        for (params, result, _) in compiled_funcs {
            let wasm_params: Vec<ValType> = params.iter().map(|t| t.to_val_type()).collect();
            let wasm_results: Vec<ValType> = result.iter().map(|t| t.to_val_type()).collect();
            types.ty().function(wasm_params, wasm_results);
        }
        module.section(&types);

        // === Import section ===
        if !imports.is_empty() {
            let mut import_section = ImportSection::new();
            for (i, imp) in imports.iter().enumerate() {
                import_section.import(
                    &imp.module,
                    &imp.name,
                    EntityType::Function(i as u32),
                );
            }
            module.section(&import_section);
        }

        // === Function section ===
        let mut func_section = FunctionSection::new();
        for i in 0..compiled_funcs.len() {
            func_section.function(import_count + i as u32);
        }
        module.section(&func_section);

        // === Memory section ===
        let mut memory_section = MemorySection::new();
        memory_section.memory(MemoryType {
            minimum: self.initial_memory_pages as u64,
            maximum: Some(self.max_memory_pages as u64),
            memory64: false,
            shared: false,
            page_size_log2: None,
        });
        module.section(&memory_section);

        // === Export section ===
        let mut export_section = ExportSection::new();
        for (i, func) in wasm_functions.iter().enumerate() {
            export_section.export(
                &func.name,
                ExportKind::Func,
                import_count + i as u32,
            );
        }
        export_section.export("memory", ExportKind::Memory, 0);
        module.section(&export_section);

        // === Code section ===
        let mut code_section = CodeSection::new();
        for (_, _, func_body) in compiled_funcs {
            code_section.function(func_body);
        }
        module.section(&code_section);

        // === Data section ===
        if !string_data.is_empty() {
            let mut data_section = DataSection::new();
            for (s, offset) in string_data {
                let mut bytes = s.as_bytes().to_vec();
                bytes.push(0); // null terminator
                data_section.active(
                    0, // memory index
                    &wasm_encoder::ConstExpr::i32_const(*offset as i32),
                    bytes,
                );
            }
            module.section(&data_section);
        }

        module.finish()
    }
}

impl Default for WasmBackend {
    fn default() -> Self {
        Self::new()
    }
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    /// Helper: create an empty Tangle program.
    fn empty_program() -> TangleProgram {
        TangleProgram {
            generators: vec![],
            braids: vec![],
            string_constants: vec![],
        }
    }

    /// Helper: create a simple program with one generator.
    fn simple_program() -> TangleProgram {
        TangleProgram {
            generators: vec![BraidGenerator {
                name: "sigma1".into(),
                strand_count: 3,
                crossing_index: 0,
                positive: true,
            }],
            braids: vec![],
            string_constants: vec![],
        }
    }

    #[test]
    fn test_empty_program_generates_valid_wasm() {
        let mut backend = WasmBackend::new();
        let module = backend.generate(&empty_program()).unwrap();
        let bytes = module.to_bytes();
        // Valid WASM magic number
        assert_eq!(&bytes[0..4], b"\0asm");
        // WASM version 1
        assert_eq!(bytes[4], 1);
        // Runtime helper exports are always emitted.
        assert_eq!(module.functions.len(), 3);
        assert_eq!(module.functions[0].name, "markov_type_i");
        assert_eq!(module.functions[1].name, "markov_type_ii");
        assert_eq!(module.functions[2].name, "braid_inverse");
    }

    #[test]
    fn test_simple_generator_compiles() {
        let mut backend = WasmBackend::new();
        let module = backend.generate(&simple_program()).unwrap();
        // 1 generator + 3 runtime helpers
        assert_eq!(module.functions.len(), 4);
        assert_eq!(module.functions[0].name, "sigma1");
        assert_eq!(module.functions[0].params, vec![WasmType::I32]);
        assert_eq!(module.functions[0].result, None);
        assert_eq!(module.functions[1].name, "markov_type_i");
        assert_eq!(module.functions[2].name, "markov_type_ii");
        assert_eq!(module.functions[3].name, "braid_inverse");
        let bytes = module.to_bytes();
        assert_eq!(&bytes[0..4], b"\0asm");
    }

    #[test]
    fn test_braid_composition_compiles() {
        let program = TangleProgram {
            generators: vec![
                BraidGenerator {
                    name: "sigma1".into(),
                    strand_count: 3,
                    crossing_index: 0,
                    positive: true,
                },
                BraidGenerator {
                    name: "sigma2".into(),
                    strand_count: 3,
                    crossing_index: 1,
                    positive: true,
                },
            ],
            braids: vec![CompiledBraid {
                name: "trefoil".into(),
                strand_count: 3,
                generators: vec!["sigma1".into(), "sigma2".into(), "sigma1".into()],
            }],
            string_constants: vec![],
        };

        let mut backend = WasmBackend::new();
        let module = backend.generate(&program).unwrap();
        // 2 generators + 1 composed braid + 3 runtime helpers
        assert_eq!(module.functions.len(), 6);
        assert_eq!(module.functions[2].name, "trefoil");
        assert_eq!(module.functions[2].result, Some(WasmType::I32));
        assert_eq!(module.functions[3].name, "markov_type_i");
        assert_eq!(module.functions[4].name, "markov_type_ii");
        assert_eq!(module.functions[5].name, "braid_inverse");
    }

    #[test]
    fn test_invalid_crossing_index_errors() {
        let program = TangleProgram {
            generators: vec![BraidGenerator {
                name: "bad".into(),
                strand_count: 3,
                crossing_index: 5, // out of range (max is 1 for 3 strands)
                positive: true,
            }],
            braids: vec![],
            string_constants: vec![],
        };

        let mut backend = WasmBackend::new();
        let result = backend.generate(&program);
        assert!(result.is_err());
        match result.unwrap_err() {
            WasmError::StrandIndexOutOfRange { index, count } => {
                assert_eq!(index, 5);
                assert_eq!(count, 3);
            }
            other => panic!("Expected StrandIndexOutOfRange, got: {other}"),
        }
    }

    #[test]
    fn test_duplicate_function_name_errors() {
        let program = TangleProgram {
            generators: vec![
                BraidGenerator {
                    name: "sigma1".into(),
                    strand_count: 3,
                    crossing_index: 0,
                    positive: true,
                },
                BraidGenerator {
                    name: "sigma1".into(), // duplicate
                    strand_count: 3,
                    crossing_index: 1,
                    positive: true,
                },
            ],
            braids: vec![],
            string_constants: vec![],
        };

        let mut backend = WasmBackend::new();
        let result = backend.generate(&program);
        assert!(result.is_err());
        match result.unwrap_err() {
            WasmError::DuplicateFunctionName { name } => {
                assert_eq!(name, "sigma1");
            }
            other => panic!("Expected DuplicateFunctionName, got: {other}"),
        }
    }

    #[test]
    fn test_binary_output_is_deterministic() {
        let program = simple_program();
        let mut backend1 = WasmBackend::new();
        let mut backend2 = WasmBackend::new();
        let module1 = backend1.generate(&program).unwrap();
        let module2 = backend2.generate(&program).unwrap();
        assert_eq!(module1.to_bytes(), module2.to_bytes());
    }

    #[test]
    fn test_module_structure_has_imports() {
        let mut backend = WasmBackend::new();
        let module = backend.generate(&simple_program()).unwrap();
        // Should have 2 runtime imports: alloc_strands and swap_strands
        assert_eq!(module.imports.len(), 2);
        assert_eq!(module.imports[0].name, "alloc_strands");
        assert_eq!(module.imports[1].name, "swap_strands");
    }

    #[test]
    fn test_bump_allocator_bounds_check() {
        let mut alloc = BumpAllocator::new(65530, 1); // near end of 1 page
        let result = alloc.alloc(16);
        assert!(result.is_err());
        match result.unwrap_err() {
            WasmError::HeapOverflow { requested, .. } => assert_eq!(requested, 16),
            other => panic!("Expected HeapOverflow, got: {other}"),
        }
    }

    #[test]
    fn test_error_display_messages() {
        let err = WasmError::StrandIndexOutOfRange { index: 5, count: 3 };
        let msg = err.to_string();
        assert!(msg.contains("5") && msg.contains("3"), "Error: {msg}");

        let err = WasmError::DuplicateFunctionName { name: "sigma".into() };
        assert!(err.to_string().contains("sigma"));

        let err = WasmError::HeapOverflow {
            requested: 100,
            current: 65000,
            capacity: 65536,
        };
        assert!(err.to_string().contains("100"));
    }

    #[test]
    fn test_string_constants_in_data_section() {
        let program = TangleProgram {
            generators: vec![],
            braids: vec![],
            string_constants: vec!["trefoil".into(), "figure-eight".into()],
        };

        let mut backend = WasmBackend::new();
        let module = backend.generate(&program).unwrap();
        let bytes = module.to_bytes();
        assert_eq!(&bytes[0..4], b"\0asm");
        // The binary should be larger with string data
        assert!(bytes.len() > 20);
    }
}
