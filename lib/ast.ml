open Core
(** The type of binary operators. *)
type bop = 
  | Add
  | Mult
  | Leq
  | Lt
  | Geq
  | Gt
  | IEq
  | Iff
[@@deriving show]

type path =
  | Self
  | Parent
  | First
  | Next
  | Last
  | Prev
[@@deriving show]

(** The type of the abstract syntax tree (AST). *)
type expr =
  | Var of string
  | Int of int
  | Bool of bool  
  | Binop of expr * bop * expr
  | Let of string * expr * expr
  | HasPath of path
  | Children
  | Len
  | Map
  | Sum
  | Read of path * string
  | Index of expr * expr
  | IfExpr of expr * expr * expr
[@@deriving show]

type stmt = 
  | LocalDef of string * expr
  | Seq of stmt * stmt
  | Skip
  | ChildrenCall of string
  | TailCall of path * string
  | IfStmt of expr * stmt * stmt
  | Write of path * string * expr
[@@deriving show]

type prop_decl = PropDecl of string
[@@deriving show]
let prop_decl_name (PropDecl(n)) = n
type proc_decl = ProcDecl of string * stmt
[@@deriving show]

let stmt_of_proc_decl (ProcDecl(_, x)) = x

type prog_decl = { prop_decls: prop_decl list; proc_decls: proc_decl list }
[@@deriving show]

type prog = { props: prop_decl list; procs: (string, proc_decl) Hashtbl.t }

let prog_of_prog_decl (p: prog_decl): prog = { 
  props = p.prop_decls;
  procs = Hashtbl.of_alist_exn (module String) (List.map p.proc_decls ~f:(fun (ProcDecl(name, stmt)as p) -> (name, p)))
}