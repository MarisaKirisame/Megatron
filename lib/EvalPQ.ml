open Ast
open Core
open EXN
open Eval
open Metric

module EVAL : Eval = struct
  let name = "PQ"
  let current_time = ref (TotalOrder.create ())

  type meta = { (*time of bbs*)
                time_table : (string, TotalOrder.t) Hashtbl.t }

  let make_node (p : _ prog) (children : meta node list) : meta node =
    ignore p;
    {
      m = { time_table = Hashtbl.create (module String) };
      id = count ();
      dict = Hashtbl.create (module String);
      children;
      parent = None;
      prev = None;
      next = None;
    }

  module PriorityQueue = PrioritySet.Make (struct
    type t = TotalOrder.t * meta node * string

    let compare (l, _, _) (r, _, _) = TotalOrder.compare l r
  end)

  let queue = PriorityQueue.create ()
  let queue_isempty () = PriorityQueue.is_empty queue
  let queue_pop () = PriorityQueue.pop queue
  let queue_peek () = PriorityQueue.peek queue
  let queue_size () = PriorityQueue.size queue

  let queue_push x y z : unit =
    if PriorityQueue.add queue (x, y, z) then () (*print_endline (string_of_int (y.id) ^ "." ^ z ^ " enqueued!")*)
    else ()

  let bb_dirtied (n : meta node) (bb_name : string) (m : metric) : unit =
    meta_write m n.id;
    match Hashtbl.find n.m.time_table bb_name with Some order -> queue_push order n bb_name | None -> panic "?"

  let prop_modified (p : _ prog) (n : meta node) (prop_name : string) (m : metric) : unit =
    Hashtbl.iter p.bbs ~f:(fun (BasicBlock (bb_name, stmts)) ->
        let reads = reads_of_stmts stmts in
        let dirty read =
          match read with
          | ReadProp (path, read_prop_name) ->
              if String.equal prop_name read_prop_name then
                List.iter (reversed_path path n) ~f:(fun dirtied_node -> bb_dirtied dirtied_node bb_name m)
              else ()
          | ReadHasPath _ -> () (*property being changed cannot change haspath status*)
        in
        List.iter reads ~f:dirty)

  let rec eval_stmt (p : _ prog) (n : meta node) (s : stmt) (m : metric) =
    match s with
    | Write (path, prop_name, expr) ->
        write m n.id;
        let new_node = eval_path n path in
        if Option.is_some (Hashtbl.find new_node.dict prop_name) then prop_modified p new_node prop_name m else ();
        Hashtbl.set new_node.dict ~key:prop_name ~data:(eval_expr n expr m)
    | BBCall bb_name ->
        current_time := TotalOrder.add_next !current_time;
        Hashtbl.add_exn n.m.time_table ~key:bb_name ~data:!current_time;
        eval_stmts p n (stmts_of_basic_block p bb_name) m
    | ChildrenCall proc_name ->
        List.iter n.children ~f:(fun new_node -> eval_stmts p new_node (stmts_of_processed_proc p proc_name) m)

  and eval_stmts (p : _ prog) (n : meta node) (s : stmts) (m : metric) : unit =
    List.iter s ~f:(fun stmt -> eval_stmt p n stmt m)

  let eval (p : _ prog) (n : meta node) (m : metric) =
    List.iter p.order ~f:(fun pass_name -> eval_stmts p n (stmts_of_processed_proc p pass_name) m)

  let remove_children (p : _ prog) (x : meta node) (n : int) (m : metric) : unit =
    match List.split_n x.children n with
    | lhs, removed :: rhs ->
        x.children <- List.tl_exn x.children;
        (match removed.prev with Some prev -> prev.next <- removed.next | None -> ());
        (match removed.next with Some next -> next.prev <- removed.prev | None -> ());
        x.children <- List.append lhs rhs;
        Hashtbl.iter p.bbs ~f:(fun (BasicBlock (bb_name, stmts)) ->
            let reads = reads_of_stmts stmts in
            let dirty read =
              match read with
              | ReadHasPath Parent | ReadProp (Parent, _) -> ()
              | ReadHasPath First | ReadHasPath Last -> if List.is_empty x.children then bb_dirtied x bb_name m else ()
              | ReadProp (First, _) -> if List.is_empty lhs then bb_dirtied x bb_name m else ()
              | ReadProp (Last, _) -> if List.is_empty rhs then bb_dirtied x bb_name m else ()
              | ReadHasPath Prev | ReadProp (Prev, _) -> (
                  match removed.next with Some x -> bb_dirtied x bb_name m | None -> ())
              | ReadHasPath Next | ReadProp (Next, _) -> (
                  match removed.prev with Some x -> bb_dirtied x bb_name m | None -> ())
              | ReadProp (Self, _) -> ()
              | _ -> raise (EXN (show_read read))
            in
            List.iter reads ~f:dirty)
    | _ -> panic "bad argument"

  let rec fix_init (current_time : TotalOrder.t ref) (x : meta node) (down : string option) (up : string option) : unit
      =
    (match down with
    | Some d ->
        current_time := TotalOrder.add_next !current_time;
        Hashtbl.add_exn x.m.time_table ~key:d ~data:!current_time;
        queue_push !current_time x d
    | None -> ());
    List.iter x.children ~f:(fun children -> fix_init current_time children down up);
    match up with
    | Some u ->
        current_time := TotalOrder.add_next !current_time;
        Hashtbl.add_exn x.m.time_table ~key:u ~data:!current_time;
        queue_push !current_time x u
    | None -> ()

  let add_children (p : _ prog) (x : meta node) (y : meta node) (n : int) (m : metric) : unit =
    let lhs, rhs = List.split_n x.children n in
    x.children <- List.append lhs (y :: rhs);
    (match List.last lhs with
    | Some tl ->
        y.prev <- Some tl;
        tl.next <- Some y
    | None -> y.prev <- None);
    (match List.hd rhs with
    | Some hd ->
        y.next <- Some hd;
        hd.prev <- Some y
    | None -> y.prev <- None);
    y.parent <- Some x;
    Hashtbl.iter p.bbs ~f:(fun (BasicBlock (bb_name, stmts)) ->
        let reads = reads_of_stmts stmts in
        let dirty read =
          match read with
          | ReadHasPath Parent | ReadProp (Parent, _) -> ()
          | ReadHasPath First | ReadHasPath Last ->
              if phys_equal (List.length x.children) 1 then bb_dirtied x bb_name m else ()
          | ReadProp (First, _) -> if List.is_empty lhs then bb_dirtied x bb_name m else ()
          | ReadProp (Last, _) -> if List.is_empty rhs then bb_dirtied x bb_name m else ()
          | ReadHasPath Prev | ReadProp (Prev, _) -> (
              match y.next with Some x -> bb_dirtied x bb_name m | None -> ())
          | ReadHasPath Next | ReadProp (Next, _) -> (
              match y.prev with Some x -> bb_dirtied x bb_name m | None -> ())
          | ReadProp (Self, _) -> ()
          | _ -> raise (EXN (show_read read))
        in
        List.iter reads ~f:dirty);
    let prev = match y.prev with Some x -> x | None -> x in
    Hashtbl.iter p.procs ~f:(fun (ProcessedProc (proc, _)) ->
        let down, up = get_bb_from_proc p proc in
        let time : TotalOrder.t =
          match (down, up) with Some d, _ -> Hashtbl.find_exn prev.m.time_table d | _ -> panic "todo"
        in
        fix_init (ref time) y down up)

  let total_queue_size = ref 0
  let queue_size_count = ref 0

  let queue_size_stat () =
    total_queue_size := !total_queue_size + queue_size ();
    queue_size_count := !queue_size_count + 1;
    print_endline (string_of_int (queue_size ()));
    print_endline (string_of_int (!total_queue_size / !queue_size_count))

  let rec recalculate_aux (p : _ prog) (m : metric) =
    if queue_isempty () then ()
    else
      let x, y, z = queue_peek () in
      meta_read m y.id;
      (*print_endline ("peek " ^ (string_of_int y.id) ^ "." ^ z);*)
      eval_stmts p y (stmts_of_basic_block p z) m;
      let x', y', z' = queue_pop () in
      ignore (y', z');
      (*print_endline ("pop  " ^ (string_of_int y'.id) ^ "." ^ z');*)
      assert (phys_equal (TotalOrder.compare x x') 0);
      recalculate_aux p m

  let recalculate (p : _ prog) (_ : meta node) (m : metric) = recalculate_aux p m
end
