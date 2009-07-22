open Flx_util
open Flx_list
open Flx_types
open Flx_mtypes2
open Flx_print
open Flx_typing
open Flx_name
open Flx_unify
open Flx_exceptions
open Flx_display
open List
open Flx_label
open Flx_unravel
open Flx_ogen
open Flx_ctypes
open Flx_cexpr
open Flx_maps
open Flx_egen
open Flx_pgen
open Flx_ctorgen
open Flx_child
open Flx_beta

let find_variable_indices syms (child_map,bbdfns) index =
  let children = find_children child_map index in
  filter
  (fun i ->
    try match Hashtbl.find bbdfns i with _,_,_,entry ->
      match entry with
      | `BBDCL_var _
      | `BBDCL_ref _
      | `BBDCL_val _ ->
        true
      | _ -> false
    with Not_found -> false
  )
  children

let get_variable_typename syms bbdfns i ts =
  let id,parent,sr,entry =
    try Hashtbl.find bbdfns i
    with Not_found -> failwith ("[get_variable_typename] can't find index " ^ si i)
  in
  let rt vs t = reduce_type (beta_reduce syms sr  (tsubst vs ts t)) in
  match entry with
  | `BBDCL_var (vs,t)
  | `BBDCL_val (vs,t)
  | `BBDCL_tmp (vs,t)
  | `BBDCL_ref (vs,t)
  ->
    if length ts <> length vs then
    failwith
    (
      "[get_variable_typename} wrong number of args, expected vs = " ^
      si (length vs) ^
      ", got ts=" ^
      si (length ts)
    );
    let t = rt vs t in
    let n = cpp_typename syms t in
    n

  | _ ->
    failwith "[get_variable_typename] Expected variable"

let format_vars syms bbdfns vars ts =
  catmap  ""
  (fun idx ->
    let instname =
      try Some (cpp_instance_name syms bbdfns idx ts)
      with _ -> None
    in
      match instname with
      | Some instname ->
        let typename = get_variable_typename syms bbdfns idx ts in
        "  " ^ typename ^ " " ^ instname ^ ";\n"
      | None -> "" (* ignore unused variables *)
  )
  vars

let find_members syms (child_map,bbdfns) index ts =
  let variables = find_variable_indices syms (child_map,bbdfns) index in
  match format_vars syms bbdfns variables ts with
  | "" -> ""
  | x ->
  (*
  "  //variables\n" ^
  *)
  x

let typeof_bparams bps: btypecode_t  =
  typeoflist  (typeofbps bps)

let get_type bbdfns index =
  let id,parent,sr,entry =
    try Hashtbl.find bbdfns index
    with _ -> failwith ("[get_type] Can't find index " ^ si index)
  in
  match entry with
  | `BBDCL_function (props,vs,(ps,_),ret,_) ->
      `BTYP_function (typeof_bparams ps,ret)
  | `BBDCL_procedure (props,vs,(ps,_),_) ->
      `BTYP_function (typeof_bparams ps,`BTYP_void)
  | _ -> failwith "Only function and procedure types handles by get_type"


let is_gc_pointer syms bbdfns sr t =
  (*
  print_endline ("[is_gc_ptr] Checking type " ^ sbt syms.dfns t);
  *)
  match t with
  | `BTYP_function _ -> true
  | `BTYP_pointer _ -> true
  | `BTYP_inst (i,_) ->
    let id,sr,parent,entry =
      try Hashtbl.find bbdfns i
      with Not_found ->
        clierr sr ("[is_gc_pointer] Can't find nominal type " ^ si i);
   in
   begin match entry with
   | `BBDCL_abs (_,tqs,_,_) -> mem `GC_pointer tqs
   | _ -> false
   end
  | _ -> false

let gen_C_function syms (child_map,bbdfns) props index id sr vs bps ret' ts instance_no =
  let rt vs t = reduce_type (beta_reduce syms sr  (tsubst vs ts t)) in
  let requires_ptf = mem `Requires_ptf props in
  (*
  print_endline ("C Function " ^ id ^ " " ^ if requires_ptf then "requires ptf" else "does NOT require ptf");
  *)
  let ps = map (fun {pid=id; pindex=ix; ptyp=t} -> id,t) bps in
  let params = map (fun {pindex=ix} -> ix) bps in
  if syms.compiler_options.print_flag then
  print_endline
  (
    "//Generating C function inst " ^
    si instance_no ^ "=" ^
    id ^ "<" ^si index^">" ^
    (
      if length ts = 0 then ""
      else "[" ^ catmap "," (string_of_btypecode syms.dfns) ts ^ "]"
    )
  );
  let argtype = typeof_bparams bps in
  if length ts <> length vs then
  failwith
  (
    "[gen_function} wrong number of args, expected vs = " ^
    si (length vs) ^
    ", got ts=" ^
    si (length ts)
  );
  let argtype = rt vs argtype in
  let rt' vs t = reduce_type (beta_reduce syms sr  (tsubst vs ts t)) in
  let ret = rt' vs ret' in
  if ret = `BTYP_tuple [] then "// elided (returns unit)\n" else

  let funtype = fold syms.counter syms.dfns (`BTYP_function (argtype, ret)) in

  (* let argtypename = cpp_typename syms argtype in *)
  let display = get_display_list syms bbdfns index in
  assert (length display = 0);
  let name = cpp_instance_name syms bbdfns index ts in
  let rettypename = cpp_typename syms ret in
  rettypename ^ " " ^
  (if mem `Cfun props then "" else "FLX_REGPARM ")^
  name ^ "(" ^
  (
    let s =
      match length params with
      | 0 -> ""
      | 1 ->
        let ix = hd params in
        if Hashtbl.mem syms.instances (ix, ts)
        && not (argtype = `BTYP_tuple [] or argtype = `BTYP_void)
        then cpp_typename syms argtype else ""
      | _ ->
        let counter = ref 0 in
        fold_left
        (fun s {pindex=i; ptyp=t} ->
          let t = rt vs t in
          if Hashtbl.mem syms.instances (i,ts) && not (t = `BTYP_tuple [])
          then s ^
            (if String.length s > 0 then ", " else " ") ^
            cpp_typename syms t
          else s (* elide initialisation of elided variable *)
        )
        ""
        bps
    in
      (
        if (not (mem `Cfun props)) then
        (
          if String.length s > 0
          then (if requires_ptf then "FLX_FPAR_DECL " else "") ^s
          else (if requires_ptf then "FLX_FPAR_DECL_ONLY" else "")
        ) else s
      )
  ) ^
  ");\n"

let gen_class syms (child_map,bbdfns) props index id sr vs ts instance_no =
  let rt vs t = reduce_type (beta_reduce syms sr  (tsubst vs ts t)) in
  let requires_ptf = mem `Requires_ptf props in
  if syms.compiler_options.print_flag then
  print_endline
  (
    "//Generating class inst " ^
    si instance_no ^ "=" ^
    id ^ "<" ^si index^">" ^
    (
      if length ts = 0 then ""
      else "[" ^ catmap "," (string_of_btypecode syms.dfns) ts ^ "]"
    )
  );
  if length ts <> length vs then
  failwith
  (
    "[gen_function} wrong number of args, expected vs = " ^
    si (length vs) ^
    ", got ts=" ^
    si (length ts)
  );
  let display = get_display_list syms bbdfns index in
  let frame_dcls =
    if requires_ptf then
    "  FLX_FMEM_DECL\n"
    else ""
  in
  let display_string = match display with
    | [] -> ""
    | display ->
      cat ""
      (
        map
        (fun (i, vslen) ->
         try
         let instname = cpp_instance_name syms bbdfns i (list_prefix ts vslen) in
         "  " ^ instname ^ " *ptr" ^ instname ^ ";\n"
         with _ -> failwith "Can't cal display name"
         )
        display
      )
  and ctor_dcl name =
    "  " ^name^
    (if length display = 0
    then (if requires_ptf then "(FLX_FPAR_DECL_ONLY);\n" else "();\n")
    else (
    "  (" ^
    (if requires_ptf then
    "FLX_FPAR_DECL "
    else ""
    )
    ^
    cat ","
      (
        map
        (
          fun (i,vslen) ->
          let instname = cpp_instance_name syms bbdfns i (list_prefix ts vslen) in
          instname ^ "*"
        )
        display
      )^
      ");\n"
    ))
  (*
  and dtor_dcl name =
    "  ~" ^ name ^"();\n"
  *)
  in
  let members = find_members syms (child_map,bbdfns) index ts in
  let name = cpp_instance_name syms bbdfns index ts in
    let ctor = ctor_dcl name in
  "struct " ^ name ^
  " {\n" ^
  (*
  "  //os frames\n" ^
  *)
  frame_dcls ^
  (*
  "  //display\n" ^
  *)
  (
    if String.length display_string = 0 then "" else
    display_string ^ "\n"
  )
  ^
  members ^
  (*
  "  //constructor\n" ^
  *)
  ctor ^
  (
    if mem `Heap_closure props then
    (*
    "  //clone\n" ^
    *)
    "  " ^name^"* clone();\n"
    else ""
  )
  ^
  (*
  "  //call\n" ^
  *)
  "};\n"


(* vs here is the (name,index) list of type variables *)
let gen_function syms (child_map,bbdfns) props index id sr vs bps ret' ts instance_no =
  let stackable = mem `Stack_closure props in
  let heapable = mem `Heap_closure props in
  (*
  let strb x y = (if x then " is " else " is not " ) ^ y in
  print_endline ("The function " ^ id ^ strb stackable "stackable");
  print_endline ("The function " ^ id ^ strb heapable "heapable");
  *)
  (*
  let heapable = not stackable or heapable in
  *)
  let rt vs t = reduce_type (beta_reduce syms sr  (tsubst vs ts t)) in
  let requires_ptf = mem `Requires_ptf props in
  let yields = mem `Yields props in
  (*
  print_endline ("The function " ^ id ^ (if requires_ptf then " REQUIRES PTF" else "DOES NOT REQUIRE PTF"));
  *)
  let ps = map (fun {pid=id; pindex=ix; ptyp=t} -> id,t) bps in
  if syms.compiler_options.print_flag then
  print_endline
  (
    "//Generating function inst " ^
    si instance_no ^ "=" ^
    id ^ "<" ^si index^">" ^
    (
      if length ts = 0 then ""
      else "[" ^ catmap "," (string_of_btypecode syms.dfns) ts ^ "]"
    )
  );
  let argtype = typeof_bparams bps in
  if length ts <> length vs then
  failwith
  (
    "[gen_function} wrong number of args, expected vs = " ^
    si (length vs) ^
    ", got ts=" ^
    si (length ts)
  );
  let argtype = rt vs argtype in
  let rt' vs t = reduce_type (beta_reduce syms sr  (tsubst vs ts t)) in
  let ret = rt' vs ret' in
  if ret = `BTYP_tuple [] then "// elided (returns unit)\n" else

  let funtype = fold syms.counter syms.dfns (`BTYP_function (argtype, ret)) in

  let argtypename = cpp_typename syms argtype in
  let funtypename =
    if mem `Heap_closure props then
      try Some (cpp_type_classname syms funtype)
      with _ -> None
    else None
  in
  let display = get_display_list syms bbdfns index in
  let frame_dcls =
    if requires_ptf then
    "  FLX_FMEM_DECL\n"
    else ""
  in
  let pc_dcls =
    if yields then
    "  FLX_PC_DECL\n"
    else ""
  in
  let display_string = match display with
    | [] -> ""
    | display ->
      cat ""
      (
        map
        (fun (i, vslen) ->
         try
         let instname = cpp_instance_name syms bbdfns i (list_prefix ts vslen) in
         "  " ^ instname ^ " *ptr" ^ instname ^ ";\n"
         with _ -> failwith "Can't cal display name"
         )
        display
      )
  and ctor_dcl name =
    "  " ^name^
    (if length display = 0
    then (if requires_ptf then "(FLX_FPAR_DECL_ONLY);\n" else "();\n")
    else (
    "  (" ^
    (if requires_ptf then
    "FLX_FPAR_DECL "
    else ""
    )
    ^
    cat ", "
      (
        map
        (
          fun (i,vslen) ->
          let instname = cpp_instance_name syms bbdfns i (list_prefix ts vslen) in
          instname ^ "*"
        )
        display
      )^
      ");\n"
    ))
  (*
  and dtor_dcl name =
    "  ~" ^ name ^"();\n"
  *)
  in
  let members = find_members syms (child_map,bbdfns) index ts in
  match ret with
  | `BTYP_void ->
    let name = cpp_instance_name syms bbdfns index ts in
    let ctor = ctor_dcl name in
    "struct " ^ name ^
    (match funtypename with
    | Some x -> ": "^x
    | None -> if not heapable then "" else ": con_t"
    )
    ^
    " {\n" ^
    (*
    "  //os frames\n" ^
    *)
    frame_dcls ^
    (*
    "  //display\n" ^
    *)
    display_string ^ "\n" ^
    members ^
    (*
    "  //constructor\n" ^
    *)
    ctor ^
    (
      if mem `Heap_closure props then
      (*
      "  //clone\n" ^
      *)
      "  " ^name^"* clone();\n"
      else ""
    )
    ^
    (*
    "  //call\n" ^
    *)
    (if argtype = `BTYP_tuple [] or argtype = `BTYP_void
    then
      (if stackable then "  void stack_call();\n" else "") ^
      (if heapable then "  con_t *call(con_t*);\n" else "")
    else
      (if stackable then "  void stack_call("^argtypename^" const &);\n" else "") ^
      (if heapable then "  con_t *call(con_t*,"^argtypename^" const &);\n" else "")
    ) ^
    (*
    "  //resume\n" ^
    *)
    (if heapable then "  con_t *resume();\n" else "")
    ^
    "};\n"

  | _ ->
    let name = cpp_instance_name syms bbdfns index ts in
    let rettypename = cpp_typename syms ret in
    let ctor = ctor_dcl name in
    "struct " ^ name ^
    (match funtypename with
    | Some x -> ": "^x
    | None -> ""
    )
    ^
    " {\n" ^
    (*
    "  //os frames\n" ^
    *)
    frame_dcls ^
    pc_dcls ^
    (*
    "  //display\n" ^
    *)
    display_string ^ "\n" ^
    members ^
    (*
    "  //constructor\n" ^
    *)
    ctor ^
    (
      if mem `Heap_closure props then
      (*
      "  //clone\n" ^
      *)
      "  " ^name^"* clone();\n"
      else ""
    )
    ^
    (*
    "  //apply\n" ^
    *)
    "  "^rettypename^
    " apply(" ^
    (if argtype = `BTYP_tuple[] or argtype = `BTYP_void then ""
    else argtypename^" const &")^
    ");\n"  ^
    "};\n"


let gen_function_names syms (child_map,bbdfns) =
  let xxdfns = ref [] in
  Hashtbl.iter
  (fun x i ->
    (* if proper_descendant syms.dfns parent then  *)
    xxdfns := (i,x) :: !xxdfns
  )
  syms.instances
  ;

  let s = Buffer.create 2000 in
  iter
  (fun (i,(index,ts)) ->
    let tss =
      if length ts = 0 then "" else
      "[" ^ catmap "," (string_of_btypecode syms.dfns) ts^ "]"
    in
    match
      try Hashtbl.find bbdfns index
      with Not_found -> failwith ("[gen_functions] can't find index " ^ si index)
    with (id,parent,sr,entry) ->
    match entry with
    | `BBDCL_function (props,vs,(ps,traint), ret, _) ->
      if mem `Cfun props || mem `Pure props && not (mem `Heap_closure props) then begin
      end else begin
        let name = cpp_instance_name syms bbdfns index ts in
        bcat s ("struct " ^ name ^ ";\n");
      end

    | `BBDCL_callback (props,vs,ps_cf,ps_c,_,ret',_,_) ->  ()

    | `BBDCL_procedure (props,vs,(ps,traint),_) ->
      if mem `Cfun props || mem `Pure props && not (mem `Heap_closure props) then begin
      end else begin
        let name = cpp_instance_name syms bbdfns index ts in
        bcat s ("struct " ^ name ^ ";\n");
      end

    | _ -> () (* bcat s ("//SKIPPING " ^ id ^ "\n") *)
  )
  (sort compare !xxdfns)
  ;
  Buffer.contents s

(* This code generates the class declarations *)
let gen_functions syms (child_map,bbdfns) =
  let xxdfns = ref [] in
  Hashtbl.iter
  (fun x i ->
    (* if proper_descendant syms.dfns parent then  *)
    xxdfns := (i,x) :: !xxdfns
  )
  syms.instances
  ;

  let s = Buffer.create 2000 in
  iter
  (fun (i,(index,ts)) ->
    let tss =
      if length ts = 0 then "" else
      "[" ^ catmap "," (string_of_btypecode syms.dfns) ts^ "]"
    in
    match
      try Hashtbl.find bbdfns index
      with Not_found -> failwith ("[gen_functions] can't find index " ^ si index)
    with (id,parent,sr,entry) ->
    match entry with
    | `BBDCL_function (props,vs,(ps,traint), ret, _) ->
      bcat s ("\n//------------------------------\n");
      if mem `Cfun props || mem `Pure props && not (mem `Heap_closure props) then begin
        bcat s ("//PURE C FUNCTION <" ^si index^ ">: " ^ qualified_name_of_bindex syms.dfns bbdfns index ^ tss ^ "\n");
        bcat s
        (gen_C_function syms (child_map,bbdfns) props index id sr vs ps ret ts i)
      end else begin
        bcat s ("//FUNCTION <"^si index^">: " ^ qualified_name_of_bindex syms.dfns bbdfns index ^ tss ^ "\n");
        bcat s
        (gen_function syms (child_map,bbdfns) props index id sr vs ps ret ts i)
      end

    | `BBDCL_callback (props,vs,ps_cf,ps_c,_,ret',_,_) ->
      let instance_no = i in
      bcat s ("\n//------------------------------\n");
      if ret' = `BTYP_void then begin
        bcat s ("//CALLBACK C PROC <"^si index^">: " ^ qualified_name_of_bindex syms.dfns bbdfns index ^ tss ^ "\n");
      end else begin
        bcat s ("//CALLBACK C FUNCTION <"^si index^">: " ^ qualified_name_of_bindex syms.dfns bbdfns index ^ tss ^ "\n");
      end
      ;
      let rt vs t = reduce_type (beta_reduce syms sr  (tsubst vs ts t)) in
      if syms.compiler_options.print_flag then
      print_endline
      (
        "//Generating C callback function inst " ^
        si instance_no ^ "=" ^
        id ^ "<" ^si index^">" ^
        (
          if length ts = 0 then ""
          else "[" ^ catmap "," (string_of_btypecode syms.dfns) ts ^ "]"
        )
      );
      if length ts <> length vs then
      failwith
      (
        "[gen_function} wrong number of args, expected vs = " ^
        si (length vs) ^
        ", got ts=" ^
        si (length ts)
      );
      let ret = rt vs ret' in
      (*
      let name = cpp_instance_name syms bbdfns index ts in
      *)
      let name = id in (* callbacks can't be polymorphic .. for now anyhow *)
      let rettypename = cpp_typename syms ret in
      let sss =
        "extern \"C\" " ^
        rettypename ^ " " ^
        name ^ "(" ^
        (
          match length ps_c with
          | 0 -> ""
          | 1 -> cpp_typename syms (hd ps_c)
          | _ ->
            fold_left
            (fun s t ->
              let t = rt vs t in
              s ^
              (if String.length s > 0 then ", " else "") ^
              cpp_typename syms t
            )
            ""
            ps_c
        ) ^
        ");\n"
      in bcat s sss

    | `BBDCL_procedure (props,vs,(ps,traint),_) ->
      bcat s ("\n//------------------------------\n");
      (*
      print_endline ("Procedure " ^ qualified_name_of_bindex syms.dfns bbdfns index);
      print_endline ("properties: " ^ string_of_properties props);
      *)
      if mem `Cfun props || mem `Pure props && not (mem `Heap_closure props) then begin
        bcat s ("//PURE C PROC <"^si index^">: " ^ qualified_name_of_bindex syms.dfns bbdfns index ^ tss ^ "\n");
        bcat s
        (gen_C_function syms (child_map,bbdfns) props index id sr vs ps `BTYP_void ts i)
      end else begin
        bcat s ("//PROC <"^si index^">: " ^ qualified_name_of_bindex syms.dfns bbdfns index ^ tss ^ "\n");
        bcat s
        (gen_function syms (child_map,bbdfns) props index id sr vs ps `BTYP_void ts i)
      end

    | _ -> () (* bcat s ("//SKIPPING " ^ id ^ "\n") *)
  )
  (sort compare !xxdfns)
  ;
  Buffer.contents s

(*
let gen_dtor syms bbdfns name display ts =
  name^"::~"^name^"(){}\n"
*)
let is_closure_var bbdfns index =
  let var_type bbdfns index =
    let id,_,entry =
      try Hashtbl.find bbdfns index
      with Not_found -> failwith ("[var_type] ]Can't get index " ^ si index)
    in match entry with
    | `BBDCL_var (_,t)
    | `BBDCL_ref (_,t)  (* ?? *)
    | `BBDCL_val (_,t) -> t
    | _ -> failwith ("[var_type] expected "^id^" to be variable")
  in
  match var_type bbdfns index with
  | `BTYP_function _ -> true
  | _ -> false

(* NOTE: it isn't possible to pass an explicit tuple as a single
argument to a primitive, nor a single value of tuple/array type.
In the latter case a cast/abstraction can defeat this, for the
former you'll need to make a dummy variable.
*)



type kind_t = Function | Procedure

let gen_exe filename syms
  (child_map,bbdfns) (label_map,label_usage_map)
  counter this vs ts instance_no needs_switch stackable (exe:bexe_t) : string =
  let sr = Flx_types.src_of_bexe exe in
  if length ts <> length vs then
  failwith
  (
    "[gen_exe} wrong number of args, expected vs = " ^
    si (length vs) ^
    ", got ts=" ^
    si (length ts)
  );
  let src_str = string_of_bexe syms.dfns bbdfns 0 exe in
  let with_comments = syms.compiler_options.with_comments in
  (*
  print_endline ("generating exe " ^ string_of_bexe syms.dfns bbdfns 0 exe);
  print_endline ("vs = " ^ catmap "," (fun (s,i) -> s ^ "->" ^ si i) vs);
  print_endline ("ts = " ^ catmap ","  (string_of_btypecode syms.dfns) ts);
  *)
  let tsub t = reduce_type (beta_reduce syms sr  (tsubst vs ts t)) in
  let ge sr e : string = gen_expr syms bbdfns this e vs ts sr in
  let ge' sr e : cexpr_t = gen_expr' syms bbdfns this e vs ts sr in
  let tn t : string = cpp_typename syms (tsub t) in
  let id,parent,parent_sr,entry =
    try Hashtbl.find bbdfns this
    with _ -> failwith ("[gen_exe] Can't find this " ^ si this)
  in
  let our_display = get_display_list syms bbdfns this in
  let kind = match entry with
    | `BBDCL_function (_,_,_,_,_) -> Function
    | `BBDCL_procedure (_,_,_,_) -> Procedure
    | _ -> failwith "Expected executable code to be in function or procedure"
  in let our_level = length our_display in

  let rec handle_closure sr is_jump index ts subs' a stack_call =
    let index',ts' = index,ts in
    let index, ts = Flx_typeclass.fixup_typeclass_instance syms bbdfns index ts in
    if index <> index' then
      clierr sr ("Virtual call of " ^ si index' ^ " dispatches to " ^ si index')
    ;
    let subs =
      catmap ""
      (fun ((_,t) as e,s) ->
        let t = cpp_ltypename syms t in
        let e = ge sr e in
        "      " ^ t ^ " " ^ s ^ " = " ^ e ^ ";\n"
      )
      subs'
    in
    let sub_start =
      if String.length subs = 0 then ""
      else "      {\n" ^ subs
    and sub_end =
      if String.length subs = 0 then ""
      else "      }\n"
    in
    let id,parent,sr2,entry =
      try Hashtbl.find bbdfns index
      with _ -> failwith ("[gen_exe(call)] Can't find index " ^ si index)
    in
    begin
    match entry with
    | `BBDCL_proc (props,vs,_,ct,_) ->
      assert (not is_jump);

      if length vs <> length ts then
      clierr sr "[gen_prim_call] Wrong number of type arguments"
      ;

      let ws s =
        let s = sc "expr" s in
        (if with_comments then "      // " ^ src_str ^ "\n" else "") ^
        sub_start ^
        "      " ^ s ^ "\n" ^
        sub_end
      in
      begin match ct with
      | `Identity -> syserr sr "Identity proc is nonsense"
      | `Virtual ->
          clierr2 sr sr2 ("Instantiate virtual procedure(1) " ^ id) ;
      | `Str s -> ws (ce_expr "expr" s)
      | `StrTemplate s ->
        let ss = gen_prim_call syms bbdfns tsub ge' s ts a "Error" sr sr2 "atom"  in
        ws ss
      end

    | `BBDCL_callback (props,vs,ps_cf,ps_c,_,ret,_,_) ->
      assert (not is_jump);
      assert (ret = `BTYP_void);

      if length vs <> length ts then
      clierr sr "[gen_prim_call] Wrong number of type arguments"
      ;
      let s = id ^ "($a);" in
      let s =
        gen_prim_call syms bbdfns tsub ge' s ts a "Error" sr sr2 "atom"
      in
      let s = sc "expr" s in
      (if with_comments then "      // " ^ src_str ^ "\n" else "") ^
      sub_start ^
      "      " ^ s ^ "\n" ^
      sub_end


    | `BBDCL_procedure (props,vs,ps,bexes) ->
      if bexes = []
      then
      "      //call to empty procedure " ^ id ^ " elided\n"
      else begin
        let n = !counter in
        incr counter;
        let the_display =
          let d' =
            map (fun (i,vslen) -> "ptr"^cpp_instance_name syms bbdfns i (list_prefix ts vslen))
            (get_display_list syms bbdfns index)
          in
            if length d' > our_level
            then "this" :: tl d'
            else d'
        in
        (* if we're calling from inside a function,
           we pass a 0 continuation as the caller 'return address'
           otherwise pass 'this' as the caller 'return address'
           EXCEPT that stack calls don't pass a return address at all
        *)
        let this = match kind with
          | Function ->
            if is_jump
            then
              clierr sr "can't jump inside function"
            else if stack_call then ""
            else "0"

          | Procedure ->
            if stack_call then "" else
            if is_jump then "tmp"
            else "this"
        in

        let args = match a with
          | _,`BTYP_tuple [] -> this
          | _ ->
            (
              let a = ge sr a in
              if this = "" then a else this ^ ", " ^ a
            )
        in
        let name = cpp_instance_name syms bbdfns index ts in
        if mem `Cfun props then begin
          (if with_comments
          then "      //call cproc " ^ src_str ^ "\n"
          else "") ^
          "      " ^ name ^"(" ^ args ^ ");\n"
        end
        else if stack_call then begin
          (*
          print_endline ("[handle_closure] GENERATING STACK CALL for " ^ id);
          *)
          (if with_comments
          then "      //run procedure " ^ src_str ^ "\n"
          else "") ^
          "      {\n" ^
          subs ^
          "      " ^ name ^ strd the_display props^ "\n" ^
          "      .stack_call(" ^ args ^ ");\n" ^
          "      }\n"
        end
        else
        let ptrmap = name ^ "_ptr_map" in
        begin
          match kind with
          | Function ->
            (if with_comments
            then "      //run procedure " ^ src_str ^ "\n"
            else "") ^
            "      {\n" ^
            subs ^
            "      con_t *_p =\n" ^
            "      (FLX_NEWP(" ^ name ^ ")" ^ strd the_display props^ ")\n" ^
            "      ->call(" ^ args ^ ");\n" ^
            "      while(_p) _p=_p->resume();\n" ^
            "      }\n"

          | Procedure ->
            let call_string =
              "      return (FLX_NEWP(" ^ name ^ ")"^strd the_display props ^ ")" ^
              "\n      ->call(" ^ args ^ ");\n"
            in
            if is_jump
            then
              (if with_comments then
              "      //jump to procedure " ^ src_str ^ "\n"
              else "") ^
              "      {\n" ^
              subs ^
              "      con_t *tmp = _caller;\n" ^
              "      _caller = 0;\n" ^
              call_string ^
              "      }\n"
            else
            (
              needs_switch := true;
              (if with_comments then
              "      //call procedure " ^ src_str ^ "\n"
              else ""
              )
              ^

              sub_start ^
              "      FLX_SET_PC(" ^ si n ^ ")\n" ^
              call_string ^
              sub_end ^
              "    FLX_CASE_LABEL(" ^ si n ^ ")\n"
            )
        end
      end

    | _ ->
      failwith
      (
        "[gen_exe] Expected '"^id^"' to be procedure constant, got " ^
        string_of_bbdcl syms.dfns bbdfns entry index
      )
    end
  in
  let gen_nonlocal_goto pc frame s =
    (* WHAT THIS CODE DOES: we pop the call stack until
       we find the first ancestor containing the target label,
       set the pc there, and return its continuation to the
       driver; we know the address of this frame because
       it must be in this function's display.
    *)
    let target_instance =
      try Hashtbl.find syms.instances (frame, ts)
      with Not_found -> failwith "Woops, bugged code, wrong type arguments for instance?"
    in
    let frame_ptr = "ptr" ^ cpp_instance_name syms bbdfns frame ts in
    "      // non local goto " ^ cid_of_flxid s ^ "\n" ^
    "      {\n" ^
    "        con_t *tmp1 = this;\n" ^
    "        while(tmp1 && " ^ frame_ptr ^ "!= tmp1)\n" ^
    "        {\n" ^
    "          con_t *tmp2 = tmp1->_caller;\n" ^
    "          tmp1 -> _caller = 0;\n" ^
    "          tmp1 = tmp2;\n" ^
    "        }\n" ^
    "      }\n" ^
    "      " ^ frame_ptr ^ "->pc = FLX_FARTARGET("^si pc^","^si target_instance^","^s^");\n" ^
    "      return " ^ frame_ptr ^ ";\n"
  in
  let forget_template sr s = match s with
  | `Identity -> syserr sr "Identity proc is nonsense(2)!"
  | `Virtual -> clierr sr "Instantiate virtual procedure(2)!"
  | `Str s -> s
  | `StrTemplate s -> s
  in
  let rec gexe exe =
    (*
    print_endline (string_of_bexe syms.dfns bbdfns 0 exe);
    *)
    match exe with
    | BEXE_axiom_check _ -> assert false
    | BEXE_code (sr,s) -> forget_template sr s
    | BEXE_nonreturn_code (sr,s) -> forget_template sr s
    | BEXE_comment (_,s) -> "/*" ^ s ^ "*/\n"
    | BEXE_label (_,s) ->
      let local_labels =
        try Hashtbl.find label_map this
        with _ -> failwith ("[gen_exe] Can't find label map of " ^ si this)
      in
      let label_index =
        try Hashtbl.find local_labels s
        with _ -> failwith ("[gen_exe] In " ^ id ^ ": Can't find label " ^ cid_of_flxid s)
      in
      let label_kind = get_label_kind_from_index label_usage_map label_index in
      (match kind with
        | Procedure ->
          begin match label_kind with
          | `Far ->
            needs_switch := true;
            "    FLX_LABEL(" ^ si label_index ^ ","^si instance_no ^"," ^ cid_of_flxid s ^ ")\n"
          | `Near ->
            "    " ^ cid_of_flxid s ^ ":;\n"
          | `Unused -> ""
          end

        | Function ->
          begin match label_kind with
          | `Far -> assert false
          | `Near ->
            "    " ^ cid_of_flxid s ^ ":;\n"
          | `Unused -> ""
          end
      )

    (* FIX THIS TO PUT SOURCE REFERENCE IN *)
    | BEXE_halt (sr,msg) ->
      let msg = Flx_print.string_of_string ("HALT: " ^ msg) in
      let f, sl, sc, el, ec = Flx_srcref.to_tuple sr in
      let s = Flx_print.string_of_string f ^"," ^
        si sl ^ "," ^ si sc ^ "," ^
        si el ^ "," ^ si ec
      in
       "      FLX_HALT(" ^ s ^ "," ^ msg ^ ");\n"

    | BEXE_trace (sr,v,msg) ->
      let msg = Flx_print.string_of_string ("TRACE: " ^ msg) in
      let f, sl, sc, el, ec = Flx_srcref.to_tuple sr in
      let s = Flx_print.string_of_string f ^"," ^
        si sl ^ "," ^ si sc ^ "," ^
        si el ^ "," ^ si ec
      in
       "      FLX_TRACE(" ^ v ^"," ^ s ^ "," ^ msg ^ ");\n"


    | BEXE_goto (sr,s) ->
      begin match find_label bbdfns label_map this s with
      | `Local _ -> "      goto " ^ cid_of_flxid s ^ ";\n"
      | `Nonlocal (pc,frame) -> gen_nonlocal_goto pc frame s
      | `Unreachable ->
        print_endline "LABELS ..";
        let labels = Hashtbl.find label_map this in
        Hashtbl.iter (fun lab lno ->
          print_endline ("Label " ^ lab ^ " -> " ^ si lno);
        )
        labels
        ;
        clierr sr ("Unconditional Jump to unreachable label " ^ cid_of_flxid s)
      end

    | BEXE_ifgoto (sr,e,s) ->
      begin match find_label bbdfns label_map this s with
      | `Local _ ->
        "      if(" ^ ge sr e ^ ") goto " ^ cid_of_flxid s ^ ";\n"
      | `Nonlocal (pc,frame) ->
        let skip = "_" ^ si !(syms.counter) in
        incr syms.counter;
        let not_e = ce_prefix "!" (ge' sr e) in
        let not_e = string_of_cexpr not_e in
        "      if("^not_e^") goto " ^ cid_of_flxid skip ^ ";\n"  ^
        gen_nonlocal_goto pc frame s ^
        "    " ^ cid_of_flxid skip ^ ":;\n"

      | `Unreachable ->
        clierr sr ("Conditional Jump to unreachable label " ^ s)
      end

    (* Hmmm .. stack calls ?? *)
    | BEXE_call_stack (sr,index,ts,a)  ->
      let id,parent,sr2,entry =
        try Hashtbl.find bbdfns index
        with _ -> failwith ("[gen_expr(apply instance)] Can't find index " ^ si index)
      in
      let ge_arg ((x,t) as a) =
        let t = tsub t in
        match t with
        | `BTYP_tuple [] -> ""
        | _ -> ge sr a
      in
      let nth_type ts i = match ts with
        | `BTYP_tuple ts -> nth ts i
        | `BTYP_array (t,`BTYP_unitsum n) -> assert (i<n); t
        | _ -> assert false
      in
      begin match entry with
      | `BBDCL_procedure (props,vs,(ps,traint),_) ->
        assert (mem `Stack_closure props);
        let a = match a with (a,t) -> a, tsub t in
        let ts = map tsub ts in
        (* C FUNCTION CALL *)
        if mem `Cfun props || mem `Pure props && not (mem `Heap_closure props) then
          let display = get_display_list syms bbdfns index in
          let name = cpp_instance_name syms bbdfns index ts in
          let s =
            assert (length display = 0);
            match ps with
            | [] -> ""
            | [{pindex=i; ptyp=t}] ->
              if Hashtbl.mem syms.instances (i,ts)
              && not (t = `BTYP_tuple[])
              then
                ge_arg a
              else ""

            | _ ->
              begin match a with
              | BEXPR_tuple xs,_ ->
                (*
                print_endline ("Arg to C function is tuple " ^ sbe syms.dfns a);
                *)
                fold_left
                (fun s (((x,t) as xt),{pindex=i}) ->
                  let x =
                    if Hashtbl.mem syms.instances (i,ts)
                    && not (t = `BTYP_tuple[])
                    then ge_arg xt
                    else ""
                  in
                  if String.length x = 0 then s else
                  s ^
                  (if String.length s > 0 then ", " else "") ^ (* append a comma if needed *)
                  x
                )
                ""
                (combine xs ps)

              | _,tt ->
                let tt = reduce_type (beta_reduce syms sr  (tsubst vs ts tt)) in
                (* NASTY, EVALUATES EXPR MANY TIMES .. *)
                let n = ref 0 in
                fold_left
                (fun s (i,{pindex=j;ptyp=t}) ->
                  (*
                  print_endline ( "ps = " ^ catmap "," (fun (id,(p,t)) -> id) ps);
                  print_endline ("tt=" ^ sbt syms.dfns tt);
                  *)
                  let t = nth_type tt i in
                  let a' = BEXPR_get_n (i,a),t in
                  let x =
                    if Hashtbl.mem syms.instances (j,ts)
                    && not (t = `BTYP_tuple[])
                    then ge_arg a'
                    else ""
                  in
                  incr n;
                  if String.length x = 0 then s else
                  s ^ (if String.length s > 0 then ", " else "") ^ x
                )
                ""
                (combine (nlist (length ps)) ps)
              end
          in
          let s =
            if mem `Requires_ptf props then
              if String.length s > 0 then "FLX_FPAR_PASS " ^ s
              else "FLX_FPAR_PASS_ONLY"
            else s
          in
            "  " ^ name ^ "(" ^ s ^ ");\n"
        else
          let subs,x = unravel syms bbdfns a in
          let subs = map (fun ((e,t),s) -> (e,tsub t),s) subs in
          handle_closure sr false index ts subs x true
      | _ -> failwith "procedure expected"
      end


    | BEXE_call_prim (sr,index,ts,a)
    | BEXE_call_direct (sr,index,ts,a)
    | BEXE_call (sr,(BEXPR_closure (index,ts),_),a) ->
      let a = match a with (a,t) -> a, tsub t in
      let subs,x = unravel syms bbdfns a in
      let subs = map (fun ((e,t),s) -> (e,tsub t),s) subs in
      let ts = map tsub ts in
      handle_closure sr false index ts subs x false

    (* i1: variable
       i2, class_ts: class closure
       i3: constructor
       a: ctor argument
    *)
    | BEXE_jump (sr,((BEXPR_closure (index,ts),_)),a)
    | BEXE_jump_direct (sr,index,ts,a) ->
      let a = match a with (a,t) -> a, tsub t in
      let subs,x = unravel syms bbdfns a in
      let subs = map (fun ((e,t),s) -> (e,tsub t),s) subs in
      let ts = map tsub ts in
      handle_closure sr true index ts subs x false

    | BEXE_loop (sr,i,a) ->
      let ptr =
        if i= this then "this"
        else "ptr"^cpp_instance_name syms bbdfns i ts
      in
        print_endline ("Looping to " ^ ptr);
        let args = ptr ^ "->" ^
          (match a with
          | _,`BTYP_tuple [] -> "_caller"
          | _ -> "_caller, " ^ ge sr a
          )
        in
        "      //"^ src_str ^ "\n" ^
        (
          if i <> this then
          "      {\n" ^
          "        con_t *res = " ^ ptr ^ "\n      ->call(" ^ args ^");\n" ^
          "        printf(\"unwinding from %p to %p\\n\",this,"^ptr^");\n" ^
          "        con_t *p = this;\n" ^
          "        while(res && res != "^ptr^") { res = p->_caller; printf(\"called by %p\\n\",p); }\n"^
          "        for(con_t *tmp=this; tmp != (con_t*)"^ptr^";){//unwind stack\n" ^
          "           con_t *tmp2 = tmp->_caller;\n" ^
          "           printf(\"unwinding %p, caller is %p\\n\",tmp,tmp2);\n" ^
          "           tmp->_caller = 0;\n" ^
          "           tmp = tmp2;\n"^
          "        }\n" ^
          "        return res;\n" ^
          "      }\n"
          else
          "      return " ^ ptr ^ "\n      ->call(" ^ args ^");\n"
        )

    (* If p is a variable containing a closure,
       and p recursively invokes the same closure,
       then the program counter and other state
       of the closure would be lost, so we clone it
       instead .. the closure variables is never
       used (a waste if it isn't re-entered .. oh well)
     *)

    | BEXE_call (sr,p,a) ->
      let args =
        let this = match kind with
          | Procedure -> "this"
          | Function -> "0"
        in
        match a with
        | _,`BTYP_tuple [] -> this
        | _ -> this ^ ", " ^ ge sr a
      in
      begin let _,t = p in match t with
      | `BTYP_cfunction _ ->
        "    "^ge sr p ^ "("^ge sr a^");\n"
      | _ ->
      match kind with
      | Function ->
        (if with_comments then
        "      //run procedure " ^ src_str ^ "\n"
        else "") ^
        "      {\n" ^
        "        con_t *_p = ("^ge sr p ^ ")->clone()\n      ->call("^args^");\n" ^
        "        while(_p) _p=_p->resume();\n" ^
        "      }\n"



      | Procedure ->
        needs_switch := true;
        let n = !counter in
        incr counter;
        (if with_comments then
        "      //"^ src_str ^ "\n"
        else "") ^
        "      FLX_SET_PC(" ^ si n ^ ")\n" ^
        "      return (" ^ ge sr p ^ ")->clone()\n      ->call(" ^ args ^");\n" ^
        "    FLX_CASE_LABEL(" ^ si n ^ ")\n"
      end

    | BEXE_jump (sr,p,a) ->
      let args = match a with
        | _,`BTYP_tuple [] -> "tmp"
        | _ -> "tmp, " ^ ge sr a
      in
      begin let _,t = p in match t with
      | `BTYP_cfunction _ ->
        "    "^ge sr p ^ "("^ge sr a^");\n"
      | _ ->
      (if with_comments then
      "      //"^ src_str ^ "\n"
      else "") ^
      "      {\n" ^
      "        con_t *tmp = _caller;\n" ^
      "        _caller=0;\n" ^
      "        return (" ^ ge sr p ^ ")\n      ->call(" ^ args ^");\n" ^
      "      }\n"
      end

    | BEXE_proc_return _ ->
      if stackable then
      "      return;\n"
      else
      "      FLX_RETURN\n"

    | BEXE_svc (sr,index) ->
      let id,parent,sr,entry =
        try Hashtbl.find bbdfns index
        with _ -> failwith ("[gen_expr(name)] Can't find index " ^ si index)
      in
      let t =
        match entry with
        | `BBDCL_var (_,t) -> t
        | `BBDCL_val (_,t) -> t
        | _ -> syserr sr "Expected read argument to be variable"
      in
      let n = !counter in incr counter;
      needs_switch := true;
      "      //read variable\n" ^
      "      p_svc = &" ^ get_var_ref syms bbdfns this index ts^";\n" ^
      "      FLX_SET_PC(" ^ si n ^ ")\n" ^
      "      return this;\n" ^
      "    FLX_CASE_LABEL(" ^ si n ^ ")\n"


    | BEXE_yield (sr,e) ->
      let labno = !counter in incr counter;
      let code =
        "      FLX_SET_PC(" ^ si labno ^ ")\n" ^
        (
          let _,t = e in
          (if with_comments then
          "      //" ^ src_str ^ ": type "^tn t^"\n"
          else "") ^
          "      return "^ge sr e^";\n"
        )
        ^
        "    FLX_CASE_LABEL(" ^ si labno ^ ")\n"
      in
      needs_switch := true;
      code

    | BEXE_fun_return (sr,e) ->
      let _,t = e in
      (if with_comments then
      "      //" ^ src_str ^ ": type "^tn t^"\n"
      else "") ^
      "      return "^ge sr e^";\n"

    | BEXE_nop (_,s) -> "      //Nop: " ^ s ^ "\n"

    | BEXE_assign (sr,e1,(( _,t) as e2)) ->
      let t = tsub t in
      begin match t with
      | `BTYP_tuple [] -> ""
      | _ ->
      (if with_comments then "      //"^src_str^"\n" else "") ^
      "      "^ ge sr e1 ^ " = " ^ ge sr e2 ^
      ";\n"
      end

    | BEXE_init (sr,v,((_,t) as e)) ->
      let t = tsub t in
      begin match t with
      | `BTYP_tuple [] -> ""
      | _ ->
        let id,_,_,entry =
          try Hashtbl.find bbdfns v with
          Not_found -> failwith ("[gen_expr(init) can't find index " ^ si v)
        in
        begin match entry with
          | `BBDCL_tmp _ ->
          (if with_comments then "      //"^src_str^"\n" else "") ^
          "      "^
          get_variable_typename syms bbdfns v [] ^
          " " ^
          get_ref_ref syms bbdfns this v ts^
          " = " ^
          ge sr e ^
          ";\n"
          | `BBDCL_val _
          | `BBDCL_ref _
          | `BBDCL_var _ ->
          (*
          print_endline ("INIT of " ^ si v ^ " inside " ^ si this);
          *)
          (if with_comments then "      //"^src_str^"\n" else "") ^
          "      "^
          get_ref_ref syms bbdfns this v ts^
          " = " ^
          ge sr e ^
          ";\n"
          | _ -> assert false
        end
      end

    | BEXE_begin -> "      {\n"
    | BEXE_end -> "      }\n"

    | BEXE_assert (sr,e) ->
       let f, sl, sc, el, ec = Flx_srcref.to_tuple sr in
       let s = string_of_string f ^ "," ^
         si sl ^ "," ^ si sc ^ "," ^
         si el ^ "," ^ si ec
       in
       "      {if(FLX_UNLIKELY(!(" ^ ge sr e ^ ")))\n" ^
       "        FLX_ASSERT_FAILURE("^s^");}\n"

    | BEXE_assert2 (sr,sr2,e1,e2) ->
       let f, sl, sc, el, ec = Flx_srcref.to_tuple sr in
       let s = string_of_string f ^ "," ^
         si sl ^ "," ^ si sc ^ "," ^
         si el ^ "," ^ si ec
       in
       let f2, sl2, sc2, el2, ec2 = Flx_srcref.to_tuple sr2 in
       let s2 = string_of_string f2 ^ "," ^
         si sl2 ^ "," ^ si sc2 ^ "," ^
         si el2 ^ "," ^ si ec2
       in
       (match e1 with
       | None ->
       "      {if(FLX_UNLIKELY(!(" ^ ge sr e2 ^ ")))\n"
       | Some e ->
       "      {if(FLX_UNLIKELY("^ge sr e^" && !(" ^ ge sr e2 ^ ")))\n"
       )
       ^
       "        FLX_ASSERT2_FAILURE("^s^"," ^ s2 ^");}\n"
  in gexe exe

let gen_exes filename syms bbdfns display label_info counter index exes vs ts instance_no stackable =
  let needs_switch = ref false in
  let s = cat ""
    (map (gen_exe filename syms bbdfns label_info counter index vs ts instance_no needs_switch stackable) exes)
  in
  s,!needs_switch

(* PROCEDURES are implemented by continuations.
   The constructor accepts the display vector to
   form the closure object. The call method accepts
   the callers continuation object as a return address,
   and the procedure argument, and returns a continuation.
   The resume method runs the continuation until
   it returns a continuation to some object, possibly
   the same object. A flag in the continuation object
   determines whether the yield of control is a request
   for data or not (if so, the dispatcher must place the data
   in the nominated place before calling the resume method again.
*)

(* FUNCTIONS are implemented as functoids:
  the constructor accepts the display vector so as
  to form a closure object, the apply method
  accepts the argument and runs the function.
  The machine stack is used for functions.
*)
let gen_C_function_body filename syms (child_map,bbdfns)
  label_info counter index ts sr instance_no
=
  let rt vs t = reduce_type (beta_reduce syms sr  (tsubst vs ts t)) in
  let id,parent,sr,entry =
    try Hashtbl.find bbdfns index
    with Not_found -> failwith ("gen_C_function_body] can't find " ^ si index)
  in
  if syms.compiler_options.print_flag then
  print_endline
  (
    "//Generating C function body inst " ^
    si instance_no ^ "=" ^
    id ^ "<" ^si index^">" ^
    (
      if length ts = 0 then ""
      else "[" ^ catmap "," (string_of_btypecode syms.dfns) ts ^ "]"
    )
  );
  match entry with
  | `BBDCL_function (props,vs,(bps,traint),ret',exes) ->
    (*
    print_endline ("Properties=" ^ catmap "," (fun x->st syms.dfns (x:>felix_term_t)) props);
    *)
    let requires_ptf = mem `Requires_ptf props in
    if length ts <> length vs then
    failwith
    (
      "[get_function_methods] wrong number of type args, expected vs = " ^
      si (length vs) ^
      ", got ts=" ^
      si (length ts)
    );
    let name = cpp_instance_name syms bbdfns index ts in

    "//C FUNC <" ^si index^ ">: " ^ name ^ "\n" ^

    let argtype = typeof_bparams bps in
    let argtype = rt vs argtype in
    let rt' vs t = reduce_type (beta_reduce syms sr  (tsubst vs ts t)) in
    let ret = rt' vs ret' in
    if ret = `BTYP_tuple [] then "// elided (returns unit)\n\n" else


    let funtype = fold syms.counter syms.dfns (`BTYP_function (argtype, ret)) in
    (* let argtypename = cpp_typename syms argtype in *)
    let rettypename = cpp_typename syms ret in

    let params = map (fun {pindex=ix} -> ix) bps in
    let exe_string,_ =
      try
        gen_exes filename syms (child_map,bbdfns) [] label_info counter index exes vs ts instance_no true
      with x ->
        print_endline (Printexc.to_string x);
        print_endline (catmap "\n" (string_of_bexe syms.dfns bbdfns 1) exes);
        print_endline "Can't gen exes ..";
        raise x
    in
    let dcl_vars =
      let kids = find_children child_map index in
      let kids =
        fold_left
        (fun lst i ->
          let _,_,_,entry =
            try Hashtbl.find bbdfns i
            with Not_found -> failwith ("[C func body, vars] Can't find index " ^ si i);
          in
          match entry with
          | `BBDCL_val (vs,t)
          | `BBDCL_var (vs,t)
            when not (mem i params) ->
            (i, rt vs t) :: lst
          | `BBDCL_ref (vs,t)
            when not (mem i params) ->
            (i, `BTYP_pointer (rt vs t)) :: lst
          | _ -> lst
        )
        [] kids
      in
      fold_left
      (fun s (i,t) -> s ^ "  " ^
        cpp_typename syms t ^ " " ^
        cpp_instance_name syms bbdfns i ts ^ ";\n"
      )
      "" kids
    in
      rettypename ^ " " ^
      (if mem `Cfun props then "" else "FLX_REGPARM ")^
      name ^ "(" ^
      (
        let s =
          match length params with
          | 0 -> ""
          | 1 ->
            begin match hd bps with
            {pkind=k; pindex=i; ptyp=t} ->
            if Hashtbl.mem syms.instances (i, ts)
            && not (argtype = `BTYP_tuple [] or argtype = `BTYP_void)
            then
              let t = rt vs t in
              let t = match k with
(*                | `PRef -> `BTYP_pointer t *)
                | `PFun -> `BTYP_function (`BTYP_void,t)
                | _ -> t
              in
              cpp_typename syms t ^ " " ^
              cpp_instance_name syms bbdfns i ts
            else ""
            end
          | _ ->
              let counter = ref 0 in
              fold_left
              (fun s {pkind=k; pindex=i; ptyp=t} ->
                let t = rt vs t in
                let t = match k with
(*                  | `PRef -> `BTYP_pointer t *)
                  | `PFun -> `BTYP_function (`BTYP_void,t)
                  | _ -> t
                in
                let n = !counter in incr counter;
                if Hashtbl.mem syms.instances (i,ts) && not (t = `BTYP_tuple [])
                then s ^
                  (if String.length s > 0 then ", " else " ") ^
                  cpp_typename syms t ^ " " ^
                  cpp_instance_name syms bbdfns i ts
                else s (* elide initialisation of elided variable *)
              )
              ""
              bps
        in
          (
            if not (mem `Cfun props) &&
            requires_ptf then
              if String.length s > 0
              then "FLX_APAR_DECL " ^ s
              else "FLX_APAR_DECL_ONLY"
            else s
          )
      )^
      "){\n" ^
      dcl_vars ^
      exe_string ^
      "}\n"

  | _ -> failwith "function expected"

let gen_C_procedure_body filename syms (child_map,bbdfns)
  label_info counter index ts sr instance_no
=
  let rt vs t = reduce_type (beta_reduce syms sr  (tsubst vs ts t)) in
  let id,parent,sr,entry =
    try Hashtbl.find bbdfns index
    with Not_found -> failwith ("gen_C_function_body] can't find " ^ si index)
  in
  if syms.compiler_options.print_flag then
  print_endline
  (
    "//Generating C procedure body inst " ^
    si instance_no ^ "=" ^
    id ^ "<" ^si index^">" ^
    (
      if length ts = 0 then ""
      else "[" ^ catmap "," (string_of_btypecode syms.dfns) ts ^ "]"
    )
  );
  match entry with
  | `BBDCL_procedure (props,vs,(bps,traint),exes) ->
    let requires_ptf = mem `Requires_ptf props in
    if length ts <> length vs then
    failwith
    (
      "[get_function_methods] wrong number of type args, expected vs = " ^
      si (length vs) ^
      ", got ts=" ^
      si (length ts)
    );
    let name = cpp_instance_name syms bbdfns index ts in

    "//C PROC <"^si index^ ">: " ^ name ^ "\n" ^

    let argtype = typeof_bparams bps in
    let argtype = rt vs argtype in

    let funtype = fold syms.counter syms.dfns (`BTYP_function (argtype, `BTYP_void)) in
    (* let argtypename = cpp_typename syms argtype in *)

    let params = map (fun {pindex=ix} -> ix) bps in
    let exe_string,_ =
      try
        gen_exes filename syms (child_map,bbdfns) [] label_info counter index exes vs ts instance_no true
      with x ->
        (*
        print_endline (Printexc.to_string x);
        print_endline (catmap "\n" (string_of_bexe syms.dfns bbdfns 1) exes);
        print_endline "Can't gen exes ..";
        *)
        raise x
    in
    let dcl_vars =
      let kids = find_children child_map index in
      let kids =
        fold_left
        (fun lst i ->
          let _,_,_,entry =
            try Hashtbl.find bbdfns i
            with Not_found -> failwith ("[C func body, vars] Can't find index " ^ si i);
          in
          match entry with
          | `BBDCL_var (vs,t)
          | `BBDCL_val (vs,t)
            when not (mem i params) ->
            (i, rt vs t) :: lst
          | `BBDCL_ref (vs,t)
            when not (mem i params) ->
            (i, `BTYP_pointer (rt vs t)) :: lst
          | _ -> lst
        )
        [] kids
      in
      fold_left
      (fun s (i,t) -> s ^ "  " ^
        cpp_typename syms t ^ " " ^
        cpp_instance_name syms bbdfns i ts ^ ";\n"
      )
      "" kids
    in
      "void " ^
      (if mem `Cfun props then "" else "FLX_REGPARM ")^
      name ^ "(" ^
      (
        let s =
          match length params with
          | 0 -> ""
          | 1 ->
            begin match hd bps with
            {pkind=k; pindex=i; ptyp=t} ->
            if Hashtbl.mem syms.instances (i, ts)
            && not (argtype = `BTYP_tuple [] or argtype = `BTYP_void)
            then
              let t = rt vs t in
              let t = match k with
(*                | `PRef -> `BTYP_pointer t *)
                | `PFun -> `BTYP_function (`BTYP_void,t)
                | _ -> t
              in
              cpp_typename syms t ^ " " ^
              cpp_instance_name syms bbdfns i ts
            else ""
            end
          | _ ->
              let counter = ref 0 in
              fold_left
              (fun s {pkind=k; pindex=i; ptyp=t} ->
                let t = rt vs t in
                let t = match k with
                  | `PFun -> `BTYP_function (`BTYP_void,t)
                  | _ -> t
                in
                let n = !counter in incr counter;
                if Hashtbl.mem syms.instances (i,ts) && not (t = `BTYP_tuple [])
                then s ^
                  (if String.length s > 0 then ", " else " ") ^
                  cpp_typename syms t ^ " " ^
                  cpp_instance_name syms bbdfns i ts
                else s (* elide initialisation of elided variable *)
              )
              ""
              bps
        in
          (
            if (not (mem `Cfun props)) && requires_ptf then
              if String.length s > 0
              then "FLX_APAR_DECL " ^ s
              else "FLX_APAR_DECL_ONLY"
            else s
          )
      )^
      "){\n" ^
      dcl_vars ^
      exe_string ^
      "}\n"

  | _ -> failwith "procedure expected"

let gen_function_methods filename syms (child_map,bbdfns)
  label_info counter index ts sr instance_no : string * string
=
  let id,parent,sr,entry =
    try Hashtbl.find bbdfns index
    with Not_found -> failwith ("[gen_function_methods] can't find " ^ si index)
  in
  let rt vs t = reduce_type (beta_reduce syms sr  (tsubst vs ts t)) in
  if syms.compiler_options.print_flag then
  print_endline
  (
    "//Generating function body inst " ^
    si instance_no ^ "=" ^
    id ^ "<" ^si index^">" ^
    (
      if length ts = 0 then ""
      else "[" ^ catmap "," (string_of_btypecode syms.dfns) ts ^ "]"
    )
  );
  match entry with
  | `BBDCL_function (props,vs,(bps,traint),ret',exes) ->
    if length ts <> length vs then
    failwith
    (
      "[get_function_methods} wrong number of args, expected vs = " ^
      si (length vs) ^
      ", got ts=" ^
      si (length ts)
    );
    let argtype = typeof_bparams bps in
    let argtype = rt vs argtype in
    let rt' vs t = reduce_type (beta_reduce syms sr  (tsubst vs ts t)) in
    let ret = rt' vs ret' in
    if ret = `BTYP_tuple [] then "// elided (returns unit)\n","" else

    let funtype = fold syms.counter syms.dfns (`BTYP_function (argtype, ret)) in

    let argtypename = cpp_typename syms argtype in
    let name = cpp_instance_name syms bbdfns index ts in

    let display = get_display_list syms bbdfns index in

    let rettypename = cpp_typename syms ret in

    let ctor =
      let vars =  find_references syms (child_map,bbdfns) index ts in
      let funs = filter (fun (_,t) -> is_gc_pointer syms bbdfns sr t) vars in
      gen_ctor syms bbdfns name display funs [] [] ts props
    in
    let params = map (fun {pindex=ix} -> ix) bps in
    let exe_string,needs_switch =
      try
        gen_exes filename syms (child_map,bbdfns) display label_info counter index exes vs ts instance_no false
      with x ->
        (*
        print_endline (Printexc.to_string x);
        print_endline (catmap "\n" (string_of_bexe syms.dfns bbdfns 1) exes);
        print_endline "Can't gen exes ..";
        *)
        raise x
    in
    let cont = "con_t *" in
    let apply =
      rettypename^ " " ^name^
      "::apply("^
      (if argtype = `BTYP_tuple [] or argtype = `BTYP_void
      then ""
      else argtypename ^" const &_arg ")^
      "){\n" ^
      (*
      (if mem `Uses_gc props then
      "  gc_profile_t &gc = *PTF gcp;\n"
      else ""
      )
      ^
      *)
      (
        match length params with
        | 0 -> ""
        | 1 ->
          let i = hd params in
          if Hashtbl.mem syms.instances (i, ts)
          && not (argtype = `BTYP_tuple [] or argtype = `BTYP_void)
          then
            "  " ^ cpp_instance_name syms bbdfns i ts ^ " = _arg;\n"
          else ""
        | _ ->
          let counter = ref 0 in fold_left
          (fun s i ->
            let n = !counter in incr counter;
            if Hashtbl.mem syms.instances (i,ts)
            then
              let memexpr =
                match argtype with
                | `BTYP_array _ -> ".data["^si n^"]"
                | `BTYP_tuple _ -> ".mem_"^ si n
                | _ -> assert false
              in
              s ^ "  " ^ cpp_instance_name syms bbdfns i ts ^ " = _arg"^ memexpr ^";\n"
            else s (* elide initialisation of elided variable *)
          )
          "" params
      )^
        (if needs_switch then
        "  FLX_START_SWITCH\n" else ""
        ) ^
        exe_string ^
        "    throw -1; // HACK! \n" ^ (* HACK .. should be in exe_string .. *)
        (if needs_switch then
        "  FLX_END_SWITCH\n" else ""
        )
      ^
      "}\n"
    and clone =
      "  " ^ name ^ "* "^name^"::clone(){\n"^
      (if mem `Generator props then
      "  return this;\n"
      else
      "  return new(*PTF gcp,"^name^"_ptr_map,true) "^name^"(*this);\n"
      )^
      "}\n"
    in
      let q = qualified_name_of_bindex syms.dfns bbdfns index in
      let ctor =
      "//FUNCTION <" ^ si index ^ ">: " ^ q ^ ": Constructor\n" ^
      ctor^ "\n" ^
      (
        if mem `Heap_closure props then
        "\n//FUNCTION <" ^ si index ^ ">: " ^ q ^ ": Clone method\n" ^
        clone^ "\n"
        else ""
      )
      and apply =
      "//FUNCTION <" ^ si index ^">: "  ^ q ^ ": Apply method\n" ^
      apply^ "\n"
      in apply,ctor


  | _ -> failwith "function expected"

let gen_procedure_methods filename syms (child_map,bbdfns)
  label_info counter index ts instance_no : string * string
=
  let id,parent,sr,entry =
    try Hashtbl.find bbdfns index
    with Not_found -> failwith ("[gen_procedure_methods] Can't find index " ^ si index)
  in (* can't fail *)
  let rt vs t = reduce_type (beta_reduce syms sr  (tsubst vs ts t)) in
  if syms.compiler_options.print_flag then
  print_endline
  (
    "//Generating procedure body inst " ^
    si instance_no ^ "=" ^
    id ^ "<" ^si index^">" ^
    (
      if length ts = 0 then ""
      else "[" ^ catmap "," (string_of_btypecode syms.dfns) ts ^ "]"
    )
  );
  match entry with
  | `BBDCL_procedure (props,vs,(bps,traint),exes) ->
    if length ts <> length vs then
    failwith
    (
      "[get_procedure_methods} wrong number of args, expected vs = " ^
      si (length vs) ^
      ", got ts=" ^
      si (length ts)
    );
    let stackable = mem `Stack_closure props in
    let heapable = mem `Heap_closure props in
    (*
    let heapable = not stackable or heapable in
    *)
    let argtype = typeof_bparams bps in
    let argtype = rt vs argtype in
    let funtype = fold syms.counter syms.dfns (`BTYP_function (argtype, `BTYP_void)) in

    let argtypename = cpp_typename syms argtype in
    let name = cpp_instance_name syms bbdfns index ts in

    let display = get_display_list syms bbdfns index in

    let ctor =
      let vars =  find_references syms (child_map,bbdfns) index ts in
      let funs = filter (fun (i,t) -> is_gc_pointer syms bbdfns sr t) vars in
      gen_ctor syms bbdfns name display funs [] [] ts props
    in

    (*
    let dtor = gen_dtor syms bbdfns name display ts in
    *)
    let ps = map (fun {pid=id; pindex=ix; ptyp=t} -> id,t) bps in
    let params = map (fun {pindex=ix} -> ix) bps in
    let exe_string,needs_switch =
      (*
      gen_exes filename syms (child_map,bbdfns) display label_info counter index exes vs ts instance_no (stackable && not heapable)
      *)
      gen_exes filename syms (child_map,bbdfns) display label_info counter index exes vs ts instance_no stackable
    in

    let cont = "con_t *" in
    let heap_call_arg_sig, heap_call_arg =
      match argtype with
      | `BTYP_tuple [] -> cont ^ "_ptr_caller","0"
      | _ -> cont ^ "_ptr_caller, " ^ argtypename ^" const &_arg","0,_arg"
    and stack_call_arg_sig =
      match argtype with
      | `BTYP_tuple [] -> ""
      | _ -> argtypename ^" const &_arg"
    in
    let unpack_args =
        (match length bps with
        | 0 -> ""
        | 1 ->
          let {pindex=i} = hd bps in
          if Hashtbl.mem syms.instances (i,ts)
          && not (argtype = `BTYP_tuple[] or argtype = `BTYP_void)
          then
            "  " ^ cpp_instance_name syms bbdfns i ts ^ " = _arg;\n"
          else ""

        | _ -> let counter = ref 0 in fold_left
          (fun s i ->
            let n = !counter in incr counter;
            if Hashtbl.mem syms.instances (i,ts)
            then
              let memexpr =
                match argtype with
                | `BTYP_array _ -> ".data["^si n^"]"
                | `BTYP_tuple _ -> ".mem_"^ si n
                | _ -> assert false
              in
              s ^ "  " ^ cpp_instance_name syms bbdfns i ts ^ " = _arg" ^ memexpr ^";\n"
            else s (* elide initialisation of elided variables *)
          )
          "" params
          )
    in
    let stack_call =
        "void " ^name^ "::stack_call(" ^ stack_call_arg_sig ^ "){\n" ^
        (
          if not heapable
          then unpack_args ^ exe_string
          else
            "  con_t *cc = call("^heap_call_arg^");\n" ^
            "  while(cc) cc = cc->resume();\n"
        ) ^ "\n}\n"
    and heap_call =
        cont ^ " " ^ name ^ "::call(" ^ heap_call_arg_sig ^ "){\n" ^
        "  _caller = _ptr_caller;\n" ^
        unpack_args ^
        "  INIT_PC\n" ^
        "  return this;\n}\n"
    and resume =
      if exes = []
      then
        cont^name^"::resume(){//empty\n"^
        "     FLX_RETURN\n" ^
        "}\n"
      else
        cont^name^"::resume(){\n"^
        (if needs_switch then
        "  FLX_START_SWITCH\n" else ""
        ) ^
        exe_string ^
        "    FLX_RETURN\n" ^ (* HACK .. should be in exe_string .. *)
        (if needs_switch then
        "  FLX_END_SWITCH\n" else ""
        )^
        "}\n"
    and clone =
      "  " ^name^"* "^name^"::clone(){\n" ^
        "  return new(*PTF gcp,"^name^"_ptr_map,true) "^name^"(*this);\n" ^
        "}\n"
    in
      let q =
        try qualified_name_of_bindex syms.dfns bbdfns index
        with Not_found ->
          si instance_no ^ "=" ^
          id ^ "<" ^si index^">" ^
          (
            if length ts = 0 then ""
            else "[" ^ catmap "," (string_of_btypecode syms.dfns) ts ^ "]"
          )
      in
      let ctor =
      "//PROCEDURE <" ^si index ^ ":> " ^ q ^ ": Constructor\n" ^
      ctor^
      (
        if mem `Heap_closure props then
        "\n//PROCEDURE <" ^si index ^ ":> " ^ q ^ ": Clone method\n" ^
        clone
        else ""
      )
      and call =
      "\n//PROCEDURE <" ^si index ^ ":> " ^ q ^ ": Call method\n" ^
      (if stackable then stack_call else "") ^
      (if heapable then heap_call else "") ^
      (if heapable then
        "\n//PROCEDURE <" ^si index ^ ":> " ^ q ^ ": Resume method\n" ^
        resume
        else ""
      )
      in call,ctor

  | _ -> failwith "procedure expected"


let gen_execute_methods filename syms (child_map,bbdfns) label_info counter bf bf2 =
  let s = Buffer.create 2000 in
  let s2 = Buffer.create 2000 in
  Hashtbl.iter
  (fun (index,ts) instance_no ->
  let id,parent,sr,entry =
    try Hashtbl.find bbdfns index
    with Not_found -> failwith ("[gen_execute_methods] Can't find index " ^ si index)
  in
  begin match entry with
  | `BBDCL_function (props,vs,(ps,traint), ret, _) ->
    bcat s ("//------------------------------\n");
    if mem `Cfun props || mem `Pure props && not (mem `Heap_closure props) then
      bcat s (
        gen_C_function_body filename syms (child_map,bbdfns)
        label_info counter index ts sr instance_no
      )
    else
      let apply,ctor =
        gen_function_methods filename syms (child_map,bbdfns)
        label_info counter index ts sr instance_no
      in
      bcat s2 ctor;
      bcat s apply

  | `BBDCL_callback (props,vs,ps_cf,ps_c,client_data_pos,ret',_,_) ->
      let tss =
        if length ts = 0 then "" else
        "[" ^ catmap "," (string_of_btypecode syms.dfns) ts^ "]"
      in
      bcat s ("\n//------------------------------\n");
      if ret' = `BTYP_void then begin
        bcat s ("//CALLBACK C PROCEDURE <" ^ si index ^ ">: " ^ qualified_name_of_bindex syms.dfns bbdfns index ^ tss ^ "\n");
      end else begin
        bcat s ("//CALLBACK C FUNCTION <" ^ si index ^ ">: " ^ qualified_name_of_bindex syms.dfns bbdfns index ^ tss ^ "\n");
      end
      ;
      let rt vs t = reduce_type (beta_reduce syms sr  (tsubst vs ts t)) in
      let ps_c = map (rt vs) ps_c in
      let ps_cf = map (rt vs) ps_cf in
      let ret = rt vs ret' in
      if syms.compiler_options.print_flag then
      print_endline
      (
        "//Generating C callback function inst " ^
        si instance_no ^ "=" ^
        id ^ "<" ^si index^">" ^
        (
          if length ts = 0 then ""
          else "[" ^ catmap "," (string_of_btypecode syms.dfns) ts ^ "]"
        )
      );
      if length ts <> length vs then
      failwith
      (
        "[gen_function} wrong number of args, expected vs = " ^
        si (length vs) ^
        ", got ts=" ^
        si (length ts)
      );
      (*
      let name = cpp_instance_name syms bbdfns index ts in
      *)
      let name = id in (* callbacks can't be polymorphic .. for now anyhow *)
      let rettypename = cpp_typename syms ret in
      let n = length ps_c in
      let flx_fun_atypes =
        rev
        (
          fold_left
          (fun lst (t,i) ->
            if i = client_data_pos
            then lst
            else (t,i)::lst
          )
          []
          (combine ps_c (nlist n))
        )
      in
      let flx_fun_atype =
        if length flx_fun_atypes = 1 then fst (hd flx_fun_atypes)
        else `BTYP_tuple (map fst flx_fun_atypes)
      in
      let flx_fun_reduced_atype = rt vs flx_fun_atype in
      let flx_fun_atype_name = cpp_typename syms flx_fun_atype in
      let flx_fun_reduced_atype_name = cpp_typename syms flx_fun_reduced_atype in
      let flx_fun_args = map (fun (_,i) -> "_a"^si i) flx_fun_atypes in
      let flx_fun_arg = match length flx_fun_args with
        | 0 -> ""
        | 1 -> hd flx_fun_args
        | _ ->
          (* argument tuple *)
          let a = flx_fun_atype_name ^ "(" ^ String.concat "," flx_fun_args ^")" in
          if flx_fun_reduced_atype_name <> flx_fun_atype_name
          then "reinterpret<" ^ flx_fun_reduced_atype_name ^ ">("^a^")"
          else a

      in
      let sss =
        (* return type *)
        rettypename ^ " " ^

        (* function name *)
        name ^ "(" ^
        (
          (* parameter list *)
          match length ps_c with
          | 0 -> ""
          | 1 -> cpp_typename syms (hd ps_c) ^ " _a0"
          | _ ->
            fold_left
            (fun s (t,j) ->
              s ^
              (if String.length s > 0 then ", " else "") ^
              cpp_typename syms t ^ " _a" ^ si j
            )
            ""
            (combine ps_c (nlist n))
        ) ^
        "){\n"^
        (
          (* body *)
          let flx_fun_type = nth ps_cf client_data_pos in
          let flx_fun_type_name = cpp_typename syms flx_fun_type in
          (* cast *)
          "  " ^ flx_fun_type_name ^ " callback = ("^flx_fun_type_name^")_a" ^ si client_data_pos ^ ";\n" ^
          (
            if ret = `BTYP_void then begin
              "  con_t *p = callback->call(0" ^
              (if String.length flx_fun_arg > 0 then "," ^ flx_fun_arg else "") ^
              ");\n" ^
              "  while(p)p = p->resume();\n"
            end else begin
              "  return callback->apply(" ^ flx_fun_arg ^ ");\n";
            end
          )
        )^
        "  }\n"
      in bcat s sss

  | `BBDCL_procedure (props,vs,(ps,traint),_) ->
    bcat s ("//------------------------------\n");
    if mem `Cfun props || mem `Pure props && not (mem `Heap_closure props) then
      bcat s (
        gen_C_procedure_body filename syms (child_map,bbdfns)
        label_info counter index ts sr instance_no
      )
    else
      let call,ctor =
        gen_procedure_methods filename syms (child_map,bbdfns)
        label_info counter index ts instance_no
      in
      bcat s call;
      bcat s2 ctor

  | _ -> ()
  end
  ;
  output_string bf (Buffer.contents s);
  output_string bf2 (Buffer.contents s2);
  Buffer.clear s;
  Buffer.clear s2;
  )
  syms.instances

let gen_biface_header syms bbdfns biface = match biface with
  | BIFACE_export_python_fun (sr,index, export_name) ->
     "// PYTHON FUNCTION " ^ export_name ^ " header to go here??\n"

  | BIFACE_export_fun (sr,index, export_name) ->
    let id,parent,sr,entry =
      try Hashtbl.find bbdfns index
      with Not_found -> failwith ("[gen_biface_header] Can't find index " ^ si index)
    in
    begin match entry with
    | `BBDCL_function (props,vs,(ps,traint), ret, _) ->
      let display = get_display_list syms bbdfns index in
      if length display <> 0
      then clierr sr "Can't export nested function";

      let arglist =
        map
        (fun {ptyp=t} -> cpp_typename syms t)
        ps
      in
      let arglist = "  " ^
        (if length ps = 0 then "FLX_FPAR_DECL_ONLY"
        else "FLX_FPAR_DECL\n" ^ cat ",\n  " arglist
        )
      in
      let rettypename = cpp_typename syms ret in

      "//EXPORT FUNCTION " ^ cpp_instance_name syms bbdfns index [] ^
      " as " ^ export_name ^ "\n" ^
      "extern \"C\" FLX_EXPORT " ^ rettypename ^" " ^
      export_name ^ "(\n" ^ arglist ^ "\n);\n"

    | `BBDCL_procedure (props,vs,(ps,traint), _) ->
      let display = get_display_list syms bbdfns index in
      if length display <> 0
      then clierr sr "Can't export nested proc";

      let arglist =
        map
        (fun {ptyp=t} -> cpp_typename syms t)
        ps
      in
      let arglist = "  " ^
        (if length ps = 0 then "FLX_FPAR_DECL_ONLY"
        else "FLX_FPAR_DECL\n" ^ cat ",\n  " arglist
        )
      in

      "//EXPORT PROCEDURE " ^ cpp_instance_name syms bbdfns index [] ^
      " as " ^ export_name ^ "\n" ^
      "extern \"C\" FLX_EXPORT con_t * "  ^ export_name ^
      "(\n" ^ arglist ^ "\n);\n"

    | _ -> failwith "Not implemented: export non-function/procedure"
    end

  | BIFACE_export_type (sr, typ, export_name) ->
    "//EXPORT type " ^ sbt  syms.dfns typ ^ " as " ^ export_name  ^ "\n" ^
    "typedef " ^ cpp_type_classname syms typ ^ " " ^ export_name ^ "_class;\n" ^
    "typedef " ^ cpp_typename syms typ ^ " " ^ export_name ^ ";\n"

let gen_biface_body syms bbdfns biface = match biface with
  | BIFACE_export_python_fun (sr,index, export_name) ->
     "// PYTHON FUNCTION " ^ export_name ^ " body to go here??\n"

  | BIFACE_export_fun (sr,index, export_name) ->
    let id,parent,sr,entry =
      try Hashtbl.find bbdfns index
      with Not_found -> failwith ("[gen_biface_body] Can't find index " ^ si index)
    in
    begin match entry with
    | `BBDCL_function (props,vs,(ps,traint), ret, _) ->
      if length vs <> 0
      then clierr sr ("Can't export generic function " ^ id)
      ;
      let display = get_display_list syms bbdfns index in
      if length display <> 0
      then clierr sr "Can't export nested function";
      let arglist =
        map
        (fun {ptyp=t; pid=name} -> cpp_typename syms t ^ " " ^ name)
        ps
      in
      let arglist = "  " ^
        (if length ps = 0 then "FLX_FPAR_DECL_ONLY"
        else "FLX_FPAR_DECL\n  " ^ cat ",\n  " arglist
        )
      in
      (*
      if mem `Stackable props then print_endline ("Stackable " ^ export_name);
      if mem `Stack_closure props then print_endline ("Stack_closure" ^ export_name);
      *)
      let is_C_fun = mem `Pure props && not (mem `Heap_closure props) in
      let requires_ptf = mem `Requires_ptf props in

      let rettypename = cpp_typename syms ret in
      let class_name = cpp_instance_name syms bbdfns index [] in

      "//EXPORT FUNCTION " ^ class_name ^
      " as " ^ export_name ^ "\n" ^
      rettypename ^" " ^ export_name ^ "(\n" ^ arglist ^ "\n){\n" ^
      (if is_C_fun then
      "  return " ^ class_name ^ "(" ^
      (
        if requires_ptf
        then "_PTFV" ^ (if length ps > 0 then "," else "")
        else ""
      )
      ^cat ", " (map (fun {pid=id}->id) ps) ^ ");\n"
      else
      "  return (new(*_PTF gcp,"^class_name^"_ptr_map,true)\n" ^
      "    " ^ class_name ^ "(_PTFV)\n" ^
      "    ->apply(" ^ cat ", " (map (fun{pid=id}->id) ps) ^ ");\n"
      )^
      "}\n"

    | `BBDCL_procedure (props,vs,(ps,traint),_) ->
      let stackable = mem `Stack_closure props in
      if length vs <> 0
      then clierr sr ("Can't export generic procedure " ^ id)
      ;
      let display = get_display_list syms bbdfns index in
      if length display <> 0
      then clierr sr "Can't export nested function";

      let args = rev (fold_left (fun args
        ({ptyp=t; pid=name; pindex=pidx} as arg) ->
        try ignore(cpp_instance_name syms bbdfns pidx []); arg:: args
        with _ -> args
        )
        []
        ps)
      in
      let params =
        map
        (fun {ptyp=t; pindex=pidx; pid=name} ->
          cpp_typename syms t ^ " " ^ name
        )
        ps
      in
      let strparams = "  " ^
        (if length params = 0 then "FLX_FPAR_DECL_ONLY"
        else "FLX_FPAR_DECL\n  " ^ cat ",\n  " params
        )
      in
      let class_name = cpp_instance_name syms bbdfns index [] in
      let strargs =
        let ge sr e : string = gen_expr syms bbdfns index e [] [] sr in
        match ps with
        | [] -> "0"
        | [{ptyp=t; pid=name; pindex=idx}] -> "0" ^ ", " ^ name
        | _ ->
          let a =
            let counter = ref 0 in
            BEXPR_tuple
            (
              map
              (fun {ptyp=t; pid=name; pindex=idx} ->
                BEXPR_expr (name,t),t
              )
              ps
            ),
            let t =
              `BTYP_tuple
              (
                map
                (fun {ptyp=t} -> t)
                ps
              )
            in
            reduce_type t
          in
          "0" ^ ", " ^ ge sr a
      in

      "//EXPORT PROC " ^ cpp_instance_name syms bbdfns index [] ^
      " as " ^ export_name ^ "\n" ^
      "con_t *" ^ export_name ^ "(\n" ^ strparams ^ "\n){\n" ^
      (
        if stackable then
        (
          if mem `Pure props && not (mem `Heap_closure props) then
          (
            "  " ^ class_name ^"(" ^
            (
              if mem `Requires_ptf props then
                if length args = 0
                then "FLX_APAR_PASS_ONLY "
                else "FLX_APAR_PASS "
              else ""
            )
            ^
            cat ", " (map (fun {pid=id}->id) args) ^ ");\n"
          )
          else
          (
            "  " ^ class_name ^ "(_PTFV)\n" ^
            "    .stack_call(" ^ (catmap ", " (fun {pid=id}->id) args) ^ ");\n"
          )
        )
        ^
        "  return 0;\n"
        else
        "  return (new(*_PTF gcp,"^class_name^"_ptr_map,true)\n" ^
        "    " ^ class_name ^ "(_PTFV))" ^
        "\n      ->call(" ^ strargs ^ ");\n"
      )
      ^
      "}\n"

    | _ -> failwith "Not implemented: export non-function/procedure"
    end

  | BIFACE_export_type _ -> ""

let gen_biface_headers syms bbdfns bifaces =
  cat "" (map (gen_biface_header syms bbdfns) bifaces)

let gen_biface_bodies syms bbdfns bifaces =
  cat "" (map (gen_biface_body syms bbdfns) bifaces)

(*  Generate Python module initialisation entry point
if a Python module function is detected as an export
*)

let gen_python_module modname syms bbdfns bifaces =
  let pychk acc elt = match elt with
  | BIFACE_export_python_fun (sr,index,name) ->
    let class_name = cpp_instance_name syms bbdfns index [] in
    let loc = Flx_srcref.short_string_of_src sr in
    let entry = name, class_name, loc in
    entry :: acc
  | _ -> acc
  in
  let funs = fold_left pychk [] bifaces in
  match funs with
  | [] -> ""
  | funs -> 
      "static PyMethodDef " ^ modname ^ "_methods [] = {\n" ^
      cat "" (rev_map (fun (export_name, symbol_name, loc) ->
      "  {" ^ "\"" ^ export_name ^ "\", " ^ symbol_name ^ 
      ", METH_VARARGS, \""^loc^"\"},\n"
      ) funs) ^ 
      "  {NULL, NULL, 0, NULL}\n" ^
      "};\n" ^
      "PyMODINIT_FUNC init" ^ modname ^ "()" ^ 
      " { Py_InitModule(\"" ^ modname ^ "\", " ^ 
      modname ^ "_methods);}\n"

