open Core.Std
open Counters
open Regexcontext
open Language_equivalences
open Lenscontext
open Lang
open Util
open Permutation
open Normalized_lang


let rec or_size (r:regex) : int =
  begin match r with
  | RegExEmpty -> 0
  | RegExBase _ -> 1
  | RegExConcat (r1,r2) -> (or_size r1) * (or_size r2)
  | RegExOr (r1,r2) -> (or_size r1) + (or_size r2)
  | RegExStar r' -> or_size r'
  | RegExVariable _ -> 1
  end

let rec true_max_size (c:RegexContext.t) (r:regex) : int =
  begin match r with
  | RegExEmpty -> 0
  | RegExBase _ -> 1
  | RegExConcat (r1,r2) -> (true_max_size c r1) * (true_max_size c r2)
  | RegExOr (r1,r2) -> (true_max_size c r1) + (true_max_size c r2)
  | RegExStar r' -> true_max_size c r'
  | RegExVariable t ->
      begin match RegexContext.lookup_for_expansion_exn c t with
      | None -> 1
      | Some r' -> true_max_size c r'
      end
  end


type synth_problem = (RegexContext.t * string * regex * regex * (string * string) list)

let problems_to_problem_list ((ds,ss):synth_problems) : synth_problem list =
  let rc = RegexContext.create_from_list_exn ds in
  List.map ~f:(fun (n,r1,r2,exl) -> (rc,n,r1,r2,exl)) ss



let empty_string = RegExBase ""

let rec exponentiate (r:regex) (n:int) : regex =
  if n < 0 then
    failwith "invalid exponential"
  else if n = 0 then
    empty_string
  else
    RegExConcat
      (exponentiate r (n-1)
      ,r)

let calculate_userdef_distribution (lc:LensContext.t) (r:regex) : ((string * int) Counters.t) *
float =
  let rec calculate_userdef_distribution_internal (r:regex) (depth:int)
    : ((string * int) Counters.t) * float =
      begin match r with
      | RegExEmpty -> (Counters.create comparison_compare,0.0)
      | RegExBase _ -> (Counters.create comparison_compare,1.0)
      | RegExVariable s ->
        let rep_elt = fst (LensContext.shortest_path_to_rep_elt lc s) in
            (Counters.add
                         (Counters.create (comparison_compare))
                         (rep_elt,depth),1.0)
      | RegExOr (r1,r2) ->
          let (counters_r1,width1) =
            calculate_userdef_distribution_internal r1 depth in
          let (counters_r2,width2) =
            calculate_userdef_distribution_internal r2 depth in
          (Counters.merge (fun x y -> x +. y) counters_r1 counters_r2,width1+.width2)
      | RegExConcat (r1,r2) ->
          let (counters_r1,width1) =
            calculate_userdef_distribution_internal r1 depth in
          let (counters_r2,width2) =
            calculate_userdef_distribution_internal r2 depth in
          (Counters.merge (fun x y -> (x*.width2 +. y*.width1)) counters_r1
          counters_r2,width1*.width2)
      | RegExStar r' ->
          (fst (calculate_userdef_distribution_internal r' (depth+1)),1.0)
      end
  in
  calculate_userdef_distribution_internal r 0
  (*let rec calculate_atom_userdef_distribution (a:atom) (depth:int) : (string * int) Counters.t =
    begin match a with
    | AUserDefined s ->
        Counters.add
          (Counters.create (comparison_compare))
          (s,depth)
    | AStar r' -> calculate_dnf_userdef_distribution r' (depth+1)
    end
  and calculate_clause_userdef_distribution ((atoms,strings):clause) (depth:int) : (string * int) Counters.t =
    List.fold_left
      ~f:(fun acc a ->
        Counters.merge
          acc
          (calculate_atom_userdef_distribution a depth))
      ~init:(Counters.create comparison_compare)
      atoms
  and calculate_dnf_userdef_distribution (clauses:dnf_regex) (depth:int) : (string * int) Counters.t =
    List.fold_left
      ~f:(fun acc c ->
        Counters.merge
          acc
          (calculate_clause_userdef_distribution c depth))
      ~init:(Counters.create comparison_compare)
      clauses
  in

  calculate_dnf_userdef_distribution (to_dnf_regex r) 0*)

  (*begin match r with
  | RegExBase _ -> Counters.create (comparison_compare)
  | RegExOr (r1,r2) ->
      let r1_counter = calculate_userdef_distribution r1 in
      let r2_counter = calculate_userdef_distribution r2 in
      Counters.merge r1_counter r2_counter
  | RegExConcat (r1,r2) ->
      let r1_counter = calculate_userdef_distribution r1 in
      let r2_counter = calculate_userdef_distribution r2 in
      Counters.merge r1_counter r2_counter
  | RegExStar (r') -> calculate_userdef_distribution r'
  | RegExVariable s ->
      Counters.add
        (Counters.create (comparison_compare))
        s
  end*)

let retrieve_priority (lc:LensContext.t) (r1:regex) (r2:regex) (expansions_preformed:int): float =
  let rec retrieve_priority_internal (cs1:((string * int) * float) list)
                                 (cs2:((string * int) * float) list)
                                 : float =
    begin match (cs1,cs2) with
    | ((s1,c1)::t1,(s2,c2)::t2) ->
        begin match comparison_compare s1 s2 with
        | EQ -> ((Float.abs (c1 -. c2))) +.
                (retrieve_priority_internal t1 t2)
        | LT -> (c1) +.
                (retrieve_priority_internal t1 cs2)
        | GT -> (c2) +.
                (retrieve_priority_internal cs1 t2)
        end
    | (_,[]) ->
        List.fold_left
        ~f:(fun acc (_,c) -> (c) +. acc)
        ~init:0.0
        cs1
    | ([],_) ->
        List.fold_left
        ~f:(fun acc (_,c) -> (c) +. acc)
        ~init:0.0
        cs2
    end
  in
  let userdef_dist_r1 = Counters.as_ordered_assoc_list (fst (
    (calculate_userdef_distribution lc r1)) )in
  let userdef_dist_r2 = Counters.as_ordered_assoc_list (fst (
    (calculate_userdef_distribution lc r2)) )in
  let ans = ((retrieve_priority_internal
    userdef_dist_r1
    userdef_dist_r2) *. 2.0)
    +. ((Float.of_int (abs ((or_size r1) - (or_size r2))))) in
  ans +. (Float.of_int (expansions_preformed*8))

let rec quotiented_star (r:regex) (n:int) : regex =
  if n < 1 then
    failwith "invalid modulation"
  else if n = 1 then
    empty_string
  else
    RegExOr
      ((quotiented_star r (n-1))
      ,(exponentiate r (n-1)))

let empty_or_not_star_expansion_right (r:regex) : regex =
  RegExOr
    (RegExBase ""
    ,RegExConcat
      (RegExStar r
      ,r))


let empty_or_not_star_expansion_left (r:regex) : regex =
  RegExOr
    (RegExBase ""
    ,RegExConcat
      (r
      ,RegExStar r))

let quotient_product_expansion_right (n:int) (r:regex) : regex =
  RegExConcat
    ((quotiented_star r n)
    ,(RegExStar
      (exponentiate r n)))

let quotient_product_expansion_left (n:int) (r:regex) : regex =
  RegExConcat
    ((RegExStar
      (exponentiate r n))
    ,(quotiented_star r n))

let expand_stars (transformation:regex -> regex) (r:regex) : regex list =
  (*let transformations = empty_or_not_star_expansion_left::
    empty_or_not_star_expansion_right::
    List.concat_map
      ~f:(fun p ->
        [quotient_product_expansion_left p;
         quotient_product_expansion_right p])
      relevant_primes in*)
  let rec expand_stars_internal (r:regex) : regex list =
    begin match r with
    | RegExEmpty -> []
    | RegExBase _ -> []
    | RegExConcat (r1,r2) ->
        let r1_expansions = expand_stars_internal r1 in
        let r2_expansions = expand_stars_internal r2 in
        (List.map
          ~f:(fun expansion -> RegExConcat (expansion,r2))
          r1_expansions)
        @
        (List.map
          ~f:(fun expansion -> RegExConcat (r1,expansion))
          r2_expansions)
    | RegExOr (r1,r2) ->
        let r1_expansions = expand_stars_internal r1 in
        let r2_expansions = expand_stars_internal r2 in
        (List.map
          ~f:(fun expansion -> RegExOr (expansion,r2))
          r1_expansions)
        @
        (List.map
          ~f:(fun expansion -> RegExOr (r1,expansion))
          r2_expansions)
    | RegExStar (r') ->
        (transformation r')::
        (List.map ~f:(fun r'' -> RegExStar r'') (expand_stars_internal r'))
    | RegExVariable _ -> []
    end
  in
  expand_stars_internal r

let rec expand_userdefs (c:RegexContext.t) (r:regex)
                            : regex list =
  begin match r with
  | RegExEmpty -> []
  | RegExBase _ -> []
  | RegExConcat (r1,r2) ->
      let r1_expansions = expand_userdefs c r1 in
      let r2_expansions = expand_userdefs c r2 in
      (List.map
        ~f:(fun expansion -> RegExConcat (expansion,r2))
        r1_expansions)
      @
      (List.map
        ~f:(fun expansion -> RegExConcat (r1,expansion))
        r2_expansions)
  | RegExOr (r1,r2) ->
      let r1_expansions = expand_userdefs c r1 in
      let r2_expansions = expand_userdefs c r2 in
      (List.map
        ~f:(fun expansion -> RegExOr (expansion,r2))
        r1_expansions)
      @
      (List.map
        ~f:(fun expansion -> RegExOr (r1,expansion))
        r2_expansions)
  | RegExStar (r') ->
      List.map
        ~f:(fun expansion -> RegExStar expansion)
        (expand_userdefs c r')
  | RegExVariable t ->
      begin match RegexContext.lookup_for_expansion_exn c t with
      | Some rex -> [rex]
      | None -> []
      end
  end

let expand_required_expansions (rc:RegexContext.t) (lc:LensContext.t) (r1:regex) (r2:regex)
                            : (regex * regex) option =
  let rec retrieve_transitive_userdefs (r:regex) : string list =
    begin match r with
    | RegExEmpty -> []
    | RegExBase _ -> []
    | RegExConcat (r1,r2) -> (retrieve_transitive_userdefs r1) @
        (retrieve_transitive_userdefs r2)
    | RegExOr (r1,r2) -> (retrieve_transitive_userdefs r1) @
        (retrieve_transitive_userdefs r2)
    | RegExStar r' -> retrieve_transitive_userdefs r'
    | RegExVariable t -> (fst (LensContext.shortest_path_to_rep_elt lc t))::
      (begin match RegexContext.lookup_for_expansion_exn rc t with
      | None -> []
      | Some rex -> retrieve_transitive_userdefs rex
      end)
    end
  in
  let rec expand_required_expansions (bad_userdefs:string list)
                                 (r:regex)
                                 : regex option =
    begin match r with
    | RegExEmpty -> Some r
    | RegExBase _ -> Some r
    | RegExConcat (r1,r2) -> 
        begin match (expand_required_expansions bad_userdefs r1,
                     expand_required_expansions bad_userdefs r2) with
        | (Some r1', Some r2') -> Some (RegExConcat (r1',r2'))
        | _ -> None
        end
    | RegExOr (r1,r2) -> 
        begin match (expand_required_expansions bad_userdefs r1,
                     expand_required_expansions bad_userdefs r2) with
        | (Some r1', Some r2') -> Some (RegExOr (r1',r2'))
        | _ -> None
        end
    | RegExStar r' ->
        begin match expand_required_expansions bad_userdefs r' with
        | Some r'' -> Some (RegExStar r'')
        | _ -> None
        end
    | RegExVariable t ->
        if List.mem bad_userdefs t then
          begin match RegexContext.lookup_for_expansion_exn rc (fst (LensContext.shortest_path_to_rep_elt lc t)) with
          | None -> None
          | Some r' -> expand_required_expansions bad_userdefs r'
          end
        else
          Some r
    end
  in

  let r1_transitive_userdefs = retrieve_transitive_userdefs r1 in
  let r2_transitive_userdefs = retrieve_transitive_userdefs r2 in
  (*print_endline (String.concat ~sep:";\n" r1_transitive_userdefs);
  print_endline "\n\n";
  print_endline (String.concat ~sep:";\n" r2_transitive_userdefs);*)
  let r1trans_not_in_r2trans = set_minus_lose_order comparison_compare
      r1_transitive_userdefs
      r2_transitive_userdefs in
  let r2trans_not_in_r1trans = set_minus_lose_order comparison_compare
      r2_transitive_userdefs
      r1_transitive_userdefs in
  (*print_endline "\n\n";
  print_endline (String.concat ~sep:";\n" r1trans_not_in_r2trans);
  print_endline "\n\n";
  print_endline (String.concat ~sep:";\n" r2trans_not_in_r1trans);*)
  begin match (expand_required_expansions r1trans_not_in_r2trans r1,
               expand_required_expansions r2trans_not_in_r1trans r2) with
  | (Some r1', Some r2') -> Some (r1',r2')
  | _ -> None
  end

let retrieve_userdefs (r:regex) : id list =
  let rec retrieve_userdefs_internal (r:regex) : id list =
    begin match r with
      | RegExBase _ -> []
      | RegExConcat (r1,r2) ->
        (retrieve_userdefs_internal r1) @
        (retrieve_userdefs_internal r2)
      | RegExOr (r1,r2) ->
        (retrieve_userdefs_internal r1) @
        (retrieve_userdefs_internal r2)
      | RegExStar r' -> retrieve_userdefs_internal r'
      | RegExVariable u -> [u]
      | RegExEmpty -> []
    end
  in
  List.dedup (retrieve_userdefs_internal r)

let requires_userdef_expansions (r1:regex) (r2:regex) : bool =
  let r1_userdefs = retrieve_userdefs r1 in
  let r2_userdefs = retrieve_userdefs r2 in
  let r1_not_r2 =
    set_minus_lose_order
      comparison_compare
      r1_userdefs
      r2_userdefs
  in
  let r2_not_r1 =
    set_minus_lose_order
      comparison_compare
      r1_userdefs
      r2_userdefs
  in
  begin match (r1_not_r2,r2_not_r1) with
    | ([],[]) -> true
    | _ -> false
  end
  

let expand_once (_:int) (rc:RegexContext.t) (lc:LensContext.t) (r1:regex) (r2:regex)
(expansions_preformed:int)
                            : (queue_element * float) list =
  let retrieve_expansions_from_transform (transform:regex -> regex list):
    (regex * regex) list =
      (List.map
        ~f:(fun le -> (le, r2))
        (transform r1))
      @
      (List.map
        ~f:(fun re -> (r1, re))
        (transform r2))
  in

  let all_immediate_expansions =
    (retrieve_expansions_from_transform (expand_userdefs rc))
    @ (retrieve_expansions_from_transform (expand_userdefs rc))
    @ (retrieve_expansions_from_transform
      (expand_stars empty_or_not_star_expansion_right))
    @ (retrieve_expansions_from_transform
      (expand_stars empty_or_not_star_expansion_left))
  in

  let turn_regex_double_into_queue_element_priority
    ((r1,r2):regex*regex)
    : queue_element * float =
      (QERegexCombo
        (r1,r2,expansions_preformed+1),
        (retrieve_priority lc r1 r2 expansions_preformed))
  in


  let rec infinitary_expansion (min:int) (max:int) (_:unit)
    : (queue_element * float) list =
      let transformations =
        List.concat_map
        ~f:(fun p ->
          [expand_stars (quotient_product_expansion_left p);
          expand_stars (quotient_product_expansion_right p)])
        (primes_between min max)
      in
      (List.map
      ~f:turn_regex_double_into_queue_element_priority
      (List.concat_map
      ~f:(fun transform -> retrieve_expansions_from_transform transform)
      transformations))
      @
      [(QEGenerator (infinitary_expansion max (max + max-min)),Float.of_int max
      *. 100.0)]
  in
(QEGenerator (infinitary_expansion 1 5),2.0)::
  (List.map
    ~f:turn_regex_double_into_queue_element_priority
    all_immediate_expansions)
  (*List.dedup
  (((List.map ~f:(fun le -> (le,r2)) left_expansions)
    @ (List.map ~f:(fun re -> (r1,re)) right_expansions)))*)

let search_expand_userdefs
    (_:RegexContext.t)
    (_:LensContext.t)
    (r1:regex)
    (r2:regex)
    (_:int)
  : (queue_element * float) list =
  let r1_userdefs = retrieve_userdefs r1 in
  let r2_userdefs = retrieve_userdefs r2 in
  let elements_r1_missing =
    set_minus_lose_order
      comparison_compare
      r1_userdefs
      r2_userdefs
  in
  if elements_r1_missing = [] then
    (*let elements_r2_missing = 
      set_minus_lose_order
        comparison_compare
        r2_userdefs
        r1_userdefs
    in
    let missing_count = List.length elements_r2_missing in*)
    []
  else
    []
    

let retrieve_transformation_queue_elements
        (max_size:int)
        (rc:RegexContext.t)
        (lc:LensContext.t)
        (r1:regex)
        (r2:regex)
        (expansions_preformed:int)
  : (queue_element * float) list =
  if (requires_userdef_expansions r1 r2) then
    (*(search_expand_userdefs rc lc r1 r2 expansions_preformed)*)
    (expand_once max_size rc lc r1 r2 expansions_preformed)
  else 
    (expand_once max_size rc lc r1 r2 expansions_preformed)
  (*let max_size = max (size r1) (size r2) in
  let splits = List.map ~f:(fun m -> (m,n-m)) (range 0 n) in
  List.concat_map
    ~f:(fun (ln,rn) ->
      let left_exps = expand_stars r1 ln max_size in
      let right_exps = expand_stars r2 rn max_size in
      cartesian_map (fun x y -> (x,y)) left_exps right_exps)
    splits*)


let rec atom_lens_to_lens (a:atom_lens) : lens =
  begin match a with
    | AtomLensIterate d -> LensIterate (dnf_lens_to_lens d)
    | AtomLensVariable l -> l
  end

and clause_lens_to_lens ((atoms,permutation,strings1,strings2):clause_lens)
  : lens =
    let rec combine_scct_and_atom_lenses
            (atom_lenses:lens list)
            (scct:swap_concat_compose_tree)
            : (lens * lens list) =
      begin match scct with
      | SCCTSwap (s1,s2) ->
          let (l1,remaining_left) =
            combine_scct_and_atom_lenses
              atom_lenses
              s1 in
          let (l2,remaining_total) =
            combine_scct_and_atom_lenses
              remaining_left
              s2 in
          (LensSwap(l1,l2),remaining_total)
      | SCCTConcat (s1,s2) ->
          let (l1,remaining_left) =
            combine_scct_and_atom_lenses
              atom_lenses
              s1 in
          let (l2,remaining_total) =
            combine_scct_and_atom_lenses
              remaining_left
              s2 in
          (LensConcat(l1,l2),remaining_total)
      | SCCTCompose _ ->
        failwith "compose is too ugly, should have failed faster"
          (*let s2size = size_scct s2 in
          let identity_copies = duplicate (LensIdentity (RegExBase "TODO")) s2size in
          let (l1,_) =
            combine_scct_and_atom_lenses
              identity_copies
              s1 in
          let (l2,remaining_total) =
            combine_scct_and_atom_lenses
              atom_lenses
              s2 in
            (LensCompose(l1,l2),remaining_total)*)
      | SCCTLeaf -> split_by_first_exn atom_lenses
      end
    in
    let (string1h,string1t) = split_by_first_exn strings1 in
    let (string2h,string2t) = split_by_first_exn strings2 in
    let (string2t_invperm) =
      Permutation.apply_inverse_to_list_exn
        permutation
        string2t
    in
    let string_lss_hd = LensConst (string1h, string2h) in
    let string_tl_combos = List.zip_exn string1t string2t_invperm in
    let string_lss_tl =
      List.map
        ~f:(fun (x,y) -> LensConst (x,y))
        string_tl_combos
    in
    let atom_lenses =
      List.map ~f:atom_lens_to_lens atoms in
    let atom_string_zips = List.zip_exn atom_lenses string_lss_tl in
    let atom_string_concats =
      List.map ~f:(fun (x,y) -> LensConcat (x,y)) atom_string_zips in
    begin match atom_string_concats with
    | [] -> string_lss_hd
    | _ ->
      let permutation_scct =
        Permutation.to_swap_concat_compose_tree permutation in
      if has_compose permutation_scct then
        LensConcat(string_lss_hd,
                   LensPermute (permutation,atom_string_concats))
      else
        LensConcat(string_lss_hd,
                   (fst (combine_scct_and_atom_lenses
                           atom_string_concats
                           permutation_scct)))
    end

and dnf_lens_to_lens ((clauses,_):dnf_lens) : lens =
  let clause_lenses = List.map ~f:clause_lens_to_lens clauses in
  List.fold_left
    ~f:(fun acc l -> LensUnion (acc, l))
    ~init:(LensIdentity (RegExEmpty))
    clause_lenses
    

let rec iteratively_deepen (r:regex) : regex * RegexContext.t =
  begin match r with
  | RegExEmpty -> (r,RegexContext.empty)
  | RegExBase _ -> (r,RegexContext.empty)
  | RegExConcat (r1,r2) ->
      let (r1',c1) = iteratively_deepen r1 in
      let (r2',c2) = iteratively_deepen r2 in
      let context = RegexContext.merge_contexts_exn c1 c2 in
      let regex_definition = RegExConcat(r1',r2') in
      let regex_variable =
        RegexContext.autogen_id
          context
          regex_definition
      in
      let context =
        RegexContext.insert_exn
          context
          regex_variable
          regex_definition
          false
        in
      (RegExVariable regex_variable,context)
  | RegExOr (r1,r2) ->
      let (r1',c1) = iteratively_deepen r1 in
      let (r2',c2) = iteratively_deepen r2 in
      let context = RegexContext.merge_contexts_exn c1 c2 in
      let regex_definition = RegExOr(r1',r2') in
      let regex_variable =
        RegexContext.autogen_id
          context
          regex_definition
      in
      let context =
        RegexContext.insert_exn
          context
          regex_variable
          regex_definition
          false
        in
      (RegExVariable regex_variable,context)
  | RegExStar r' ->
      let (r'',c) = iteratively_deepen r' in
      let regex_definition = RegExStar r'' in
      let regex_variable =
        RegexContext.autogen_id
          c
          regex_definition
      in
      let context =
        RegexContext.insert_exn
          c
          regex_variable
          regex_definition
          false
        in
      (RegExVariable regex_variable,context)
  | RegExVariable _ ->
      (r,RegexContext.empty)
  end

(*let rec ordered_exampled_dnf_regex_to_regex
    (r:ordered_exampled_dnf_regex) : regex =
  dnf_regex_to_regex (ordered_exampled_dnf_regex_to_dnf_regex r)*)



