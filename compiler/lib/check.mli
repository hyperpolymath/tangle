(* SPDX-License-Identifier: MPL-2.0 *)
(* check.mli — Single source of truth for Tangle diagnostics (TG-9).
 *
 * Both `tanglec --check` and the LSP server consume `check_source`, so LSP
 * diagnostics are by construction a subset of the compiler's parse / HasType
 * failures. *)

type level = Error | Warning

type diag = {
  level   : level;
  line    : int;   (** 1-based source line *)
  col     : int;   (** 0-based byte offset within the line *)
  message : string;
}

(** All diagnostics for a source string: parse diagnostics (with recovery)
    followed by type-checker diagnostics. *)
val check_source : string -> diag list

(** Machine-readable rendering: ["SEVERITY\tLINE\tCOL\tMESSAGE"]. *)
val format_diag : diag -> string

(** Whether any diagnostic is an error (as opposed to a warning). *)
val has_error : diag list -> bool
