open Lang
open Pp
open Gen
open Lens
open Core.Std
open Consts
open Lang
open Consts

exception Arg_exception

type driver_mode =
  | Default
  | Parse
  | Data
  | Synth

let usage_msg = "synml [-help | opts...] <src>"
let filename : string option ref = ref None
let mode : driver_mode ref = ref Default

let parse_file (f:string) : synth_problems =
  Preproc.preprocess_file f
    |> Lexing.from_string
    |> Parser.synth_problems Lexer.token

let set_opt (d:driver_mode) =
  match !mode with
  | Default -> mode := d
  | _ -> raise Arg_exception

let args =
  [ ( "-parse"
    , Arg.Unit (fun _ -> set_opt Parse)
    , " Parse only"
    )
  ; ( "-synth"
    , Arg.Unit (fun _ -> set_opt Synth)
    , " Synthesize"
    )
  ; ( "-data"
    , Arg.Unit (fun _ -> set_opt Data)
    , " Synthesize and collect statistics (name, #/exs, size, time)"
    )
  ]
  |> Arg.align

let print_lenses (lss:(string * dnf_lens option) list) : unit =
  List.iter
    ~f:(fun (s,lo) ->
      print_endline "\n\n";
      print_endline (s ^ ":");
      begin match lo with
      | None -> print_endline "no lens found"
      | Some ls -> print_endline (Pp.pp_dnf_lens ls)
      end)
    lss

let ignore (x:'a) : unit =
  ()

let synthesize_prog (ps:synth_problems) : (string * dnf_lens option) list =
  let problem_list = problems_to_problem_list ps in
  List.map
    ~f:(fun (c,e_c,n,r1,r2,exs) -> (n,(gen_dnf_lens c e_c r1 
    r2 exs)))
    problem_list
  
  (*let (s, g, env, x, t, es, vs, tree) = process_preamble p in
  begin match Synth.synthesize s env tree with
  | Some e ->
      Printf.printf "%s\n" (Translate.to_top_level x t e |> Pp.pp_decl)
  | None -> begin
      Printf.printf "No expression found!\n";
      Printf.printf "final rtree size = %d\n" (Rtree.rtree_size tree)
    end
  end;
  pTODO*)

let collect_data (p:synth_problems) : (string * dnf_lens option) list =
  (*let (time, (x, vs, e)) = Util.time_action (fun _ ->
    let (s, g, env, x, t, es, vs, tree) = process_preamble p in
    (x, List.map ~f:snd vs, Synth.synthesize s env tree))
  in
    begin match e with
    | Some e ->
      Printf.printf "%s,%d,%d,%.3f\n%!"
        x (List.fold_left ~f:(fun n v -> n + examples_count v) ~init:0 vs)
        (size e) time
    | None ->
      Printf.printf "<<< %s: error during synthesis >>>\n%!" x
    end; pTODO*) []

let main () =
  begin try
    Arg.parse args (fun s ->
      match !filename with
      | Some f -> raise Arg_exception
      | None -> filename := Some s) usage_msg
  with
    Arg_exception -> Arg.usage args usage_msg
  end;
  match !filename with
  | None   -> Arg.usage args usage_msg
  | Some f ->
    print_time_if_timing begin fun _ ->
      begin match Sys.file_exists f with
      | `No | `Unknown -> Arg.usage args ("File not found: " ^ f)
      | `Yes -> begin match !mode with
        | Parse ->
            let _ = parse_file f in (*TODO: pp*) ()(*Printf.printf "%s\n"
            (Pp.pp_prog prog)*)
        | Data -> parse_file f |> collect_data |> print_lenses
        | Default | Synth ->
            parse_file f |> synthesize_prog |> print_lenses
        end
      end
    end

let () = if not !Sys.interactive then main ()
