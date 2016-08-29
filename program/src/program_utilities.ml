open Core.Std
open Lang
open Regexcontext
open Lenscontext
open Eval
open Gen
open Lens_put

let run_declaration
    (rc:RegexContext.t)
    (lc:LensContext.t)
    (d:declaration)
  : RegexContext.t * LensContext.t * declaration =
  begin match d with
    | DeclRegexCreation (n,r,b) ->
      (RegexContext.insert_exn rc n r (not b),lc,d)
    | DeclTestString (r,s) ->
      if fast_eval rc r s then
        (rc,lc,d)
      else
        failwith (s ^ " does not match regex " ^ (regex_to_string r))
    | DeclSynthesizeLens (n,r1,r2,exs) ->
      let lo = gen_lens rc lc r1 r2 exs in
      begin match lo with
        | None -> failwith (n ^ " has no satisfying lens")
        | Some l ->
          (rc,LensContext.insert_exn lc n l r1 r2,DeclLensCreation(n,r1,r2,l))
      end
    | DeclLensCreation (n,r1,r2,l) ->
      (rc,LensContext.insert_exn lc n l r1 r2,d)
    | DeclTestLens (n,exs) ->
      List.iter
        ~f:(fun (lex,rex) ->
            if lens_putr rc lc (LensVariable n) lex <> rex then
              failwith "bad example"
            else
              ())
        exs;
      (rc,lc,d)
  end

let synthesize_and_load_program
    (p:program)
  : RegexContext.t * LensContext.t * program =
  let (rc,lc,p) = List.fold_left
      ~f:(fun (rc,lc,p) d ->
          let (rc,lc,d) = run_declaration rc lc d in
          (rc,lc,d::p))
      ~init:(RegexContext.empty, LensContext.empty, [])
      p
  in
  (rc,lc,List.rev p)

let synthesize_program
    (p:program)
  : program =
  let (_,_,p) = synthesize_and_load_program p in
  p

let load_program
    (p:program)
  : RegexContext.t * LensContext.t =
  let (rc,lc,_) = synthesize_and_load_program p in
  (rc,lc)

let remove_tests : program -> program =
  List.filter
    ~f:(fun d ->
        begin match d with
          | DeclRegexCreation _ -> true
          | DeclTestString _ -> false
          | DeclSynthesizeLens _ -> true
          | DeclLensCreation _ -> false
          | DeclTestLens _ -> false
        end)

let retrieve_last_synthesis_problem_exn
    (p:program)
  : RegexContext.t * LensContext.t * regex * regex * examples =
  let p = remove_tests p in
  let (rc,lc,last_synth_option) = List.fold_left
    ~f:(fun (rc,lc,last_synth_option) d ->
        begin match (d,last_synth_option) with
          | (DeclSynthesizeLens d,None) -> (rc,lc,Some d)
          | (DeclSynthesizeLens spec',Some spec) ->
            let (rc,lc,_) = run_declaration rc lc (DeclSynthesizeLens spec) in
            (rc,lc, Some spec')
          | (_,_) ->
            let (rc,lc,_) = run_declaration rc lc d in
            (rc,lc,last_synth_option)
        end)
    ~init:(RegexContext.empty,LensContext.empty,None)
    p
  in
  let (_,r1,r2,exs) = Option.value_exn last_synth_option in
  (rc,lc,r1,r2,exs)
