(* Semantic checking for the YAGL compiler *)

open Ast
open Sast

module StringMap = Map.Make(String)

(* Semantic checking of the AST. Returns an SAST if successful,
   throws an exception if something is wrong.

   Check each statement *)

let check (stmts, funcs) =
  let main = 
     {
       typ = Void;
       fname = "main"; 
       formals = [];
       body = stmts
     }

   in

  let functions = main :: funcs

  in

 (*  *)
  let extract_vdecls (stmts : stmt list) =

    List.fold_left (fun bind_list stmt -> 
      match stmt with
        Binding b -> b :: bind_list
      | _ -> bind_list 
    ) [] stmts

  in

  (* Verify a list of bindings has no void types or duplicate names *)
  let check_stmt_binds (kind : string) (stmts : stmt list) =

    let binds = extract_vdecls stmts

    in

    List.iter (function
    (Void, b) -> raise (Failure ("illegal void " ^ kind ^ " " ^ b))
      | _ -> ()) binds;
    let rec dups = function
        [] -> ()
      | ((_,n1) :: (_,n2) :: _) when n1 = n2 ->
    raise (Failure ("duplicate " ^ kind ^ " " ^ n1))
      | _ :: t -> dups t
    in dups (List.sort (fun (_,a) (_,b) -> compare a b) binds)
  in

  (* Verify a list of bindings has no void types or duplicate names *)
  let check_binds (kind : string) (binds : bind list) =
    List.iter (function
  (Void, b) -> raise (Failure ("illegal void " ^ kind ^ " " ^ b))
      | _ -> ()) binds;
    let rec dups = function
        [] -> ()
      | ((_,n1) :: (_,n2) :: _) when n1 = n2 ->
    raise (Failure ("duplicate " ^ kind ^ " " ^ n1))
      | _ :: t -> dups t
    in dups (List.sort (fun (_,a) (_,b) -> compare a b) binds)
  in


  (**** Check variables declared in statements ****)

  check_stmt_binds "stmts" stmts;

  (**** Check functions ****)

  (* Collect function declarations for built-in functions: no bodies *)
  let built_in_decls = 
    let add_bind map (name, ty) = StringMap.add name {
      typ = Void;
      fname = name; 
      formals = [(ty, "x")];
      body = [] } map
    in List.fold_left add_bind StringMap.empty [ ("printInt", Int); 
                                                 ("printString", String)
                                               ]
  in

  (* Add function name to symbol table *)
  let add_func map fd = 
    let built_in_err = "function " ^ fd.fname ^ " may not be defined"
    and dup_err = "duplicate function " ^ fd.fname
    and main_err = "reserved function name: " ^ fd.fname ^ " cannot be used"
    and make_err er = raise (Failure er)
    and n = fd.fname (* Name of the function *)
    in match fd with (* No duplicate functions or redefinitions of built-ins *)
         _ when StringMap.mem n built_in_decls -> make_err built_in_err
       | _ when StringMap.mem n map -> 
                       if compare n "main" == 0
                        then  make_err main_err
                        else make_err dup_err  
       | _ ->  StringMap.add n fd map 
  in

  (* Collect all function names into one symbol table *)
  let function_decls = List.fold_left add_func built_in_decls functions
  in
  
  (* Return a function from our symbol table *)
  let find_func s = 
    try StringMap.find s function_decls
    with Not_found -> raise (Failure ("unrecognized function " ^ s))
  in
  
let check_function func =
    
    (* Make sure no formals or locals are void or duplicates *)
    check_binds "formal" func.formals;
    check_stmt_binds "local" func.body;

    (* Raise an exception if the given rvalue type cannot be assigned to
       the given lvalue type *)
    let check_assign lvaluet rvaluet err =
       if lvaluet = rvaluet then lvaluet else raise (Failure err)
    in  

    (* Build local symbol table of variables for this function *)
    let symbols = List.fold_left (fun m (ty, name) -> StringMap.add name ty m)
                  StringMap.empty (func.formals @ extract_vdecls func.body )
    in

    (* Return a variable from our local symbol table *)
    let type_of_identifier s =
      try StringMap.find s symbols
      with Not_found -> raise (Failure ("undeclared identifier " ^ s))
    in

    (* Return a semantically-checked expression, i.e., with a type *)
    let rec expr = function
         Call(fname, args) as call -> 
          let fd = find_func fname in
          let param_length = List.length fd.formals in
          if List.length args != param_length then
            raise (Failure ("expecting " ^ string_of_int param_length ^ 
                            " arguments in " ^ string_of_expr call))
          else if compare fname "main" == 0 then
            (* TODO: IF we add globals then we can remove this... thoughts? *)
            raise (Failure ("Cannot call main otherwise recurse forever"))
          else let check_call (ft, _) e = 
            let (et, e') = expr e in 
            let err = "illegal argument found " ^ string_of_typ et ^
              " expected " ^ string_of_typ ft ^ " in " ^ string_of_expr e
            in (check_assign ft et err, e')
          in 
          let args' = List.map2 check_call fd.formals args
          in (fd.typ, SCall(fname, args'))
       | Literal  l -> (Int, SLiteral l)
       | StrLit s -> (String, SStrLit s)
       | Id s       -> (type_of_identifier s, SId s)

      | BoolLit a -> raise (Failure("Boolit ERROR")) 
      | Binop (a, b, c) -> raise (Failure("Binop ERROR")) 
      | Unop (a, b) -> raise (Failure("Unop ERROR")) 
      | Assign (a, b) -> raise (Failure("Assign ERROR")) 
      | Call (fname, args) as call -> raise (Failure("Call ERROR")) 
      | Noexpr -> raise (Failure("Noexpr ERROR")) 
       | _ -> raise (Failure("Error 1: Ints only and calls are supported exressions currently.")) 
    in 

    (* Return a semantically-checked statement i.e. containing sexprs *)
    let rec check_stmt = function
        Expr e -> SExpr (expr e)
      | If(p, b1, b2) -> raise (Failure "fail if")
      | Bfs(e1, e2, e3, st) -> raise (Failure "fail for")
      | While(p, s) -> raise (Failure "fail while")
      | Return e -> raise (Failure "fail return")
        
      (* A block is correct if each statement is correct and nothing
         follows any Return statement.  Nested blocks are flattened. *)
      | Block sl -> 
          let rec check_stmt_list = function
              [Return _ as s] -> [check_stmt s]
            | Return _ :: _   -> raise (Failure "nothing may follow a return")
            | Block sl :: ss  -> check_stmt_list (sl @ ss) (* Flatten blocks *)
            | s :: ss         -> check_stmt s :: check_stmt_list ss
            | []              -> []
          in SBlock(check_stmt_list sl)
      | Binding (typ, id) -> SBinding (typ, id)
      | _ -> raise (Failure "fail ???")
  in 

  { styp = func.typ;
      sfname = func.fname;
      sformals = func.formals;
      sbody = match check_stmt (Block func.body) with
  SBlock(sl) -> sl
      | _ -> raise (Failure ("internal error: block didn't become a block?"))
    }
  
  in (List.map check_function functions)
