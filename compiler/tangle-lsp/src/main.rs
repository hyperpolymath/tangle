// SPDX-License-Identifier: MPL-2.0
//! tangle-lsp — Language Server Protocol server for the Tangle language.
//!
//! Provides diagnostics, hover, completion, go-to-definition, and document
//! symbol support for `.tangle` files.  The server communicates over stdin/stdout
//! using the LSP JSON-RPC protocol.

#![forbid(unsafe_code)]
mod backend;

use tower_lsp::{LspService, Server};

#[tokio::main]
async fn main() {
    let stdin = tokio::io::stdin();
    let stdout = tokio::io::stdout();

    let (service, socket) = LspService::new(|client| backend::TangleBackend::new(client));
    Server::new(stdin, stdout, socket).serve(service).await;
}
