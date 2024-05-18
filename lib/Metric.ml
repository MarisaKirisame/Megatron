type metric = {
  mutable read_count : int;
  mutable meta_read_count : int;
  mutable write_count : int;
  mutable meta_write_count : int;
}
[@@deriving show]

let read (m : metric) (id : int) : unit = m.read_count <- m.read_count + 1

let meta_read (m : metric) (id : int) : unit =
  m.meta_read_count <- m.meta_read_count + 1

let write (m : metric) (id : int) : unit = m.write_count <- m.write_count + 1

let meta_write (m : metric) (id : int) : unit =
  m.meta_write_count <- m.meta_write_count + 1

let fresh_metric () =
  { read_count = 0; meta_read_count = 0; write_count = 0; meta_write_count = 0 }

let reset_metric m =
  m.read_count <- 0;
  m.meta_read_count <- 0;
  m.write_count <- 0;
  m.meta_write_count <- 0
