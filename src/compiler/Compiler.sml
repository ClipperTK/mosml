(* Compiler.sml *)

open List Obj BasicIO Nonstdio Fnlib Mixture Const Globals Location Units;
open Types Smlperv Asynt Parser Ovlres Infixres Elab Sigmtch;
open Tr_env Front Back Pr_zam Emit_phr;

(* Lexer of stream *)

fun createLexerStream (is : BasicIO.instream) =
  Lexing.createLexer (fn buff => fn n => Nonstdio.buff_input is buff 0 n)
;

(* Parsing functions *)

fun parsePhrase parsingFun lexingFun lexbuf =
  let fun skip() =
    (case lexingFun lexbuf of
        EOF => ()
      | SEMICOLON => ()
      | _ => skip())
    handle LexicalError(_,_,_) =>
      skip()
  in
    parsingFun lexingFun lexbuf
    handle
        Parsing.ParseError f =>
           let val pos1 = Lexing.getLexemeStart lexbuf
               val pos2 = Lexing.getLexemeEnd lexbuf
           in
             Lexer.resetLexerState();
             if f (Obj.repr EOF) orelse
                f (Obj.repr SEMICOLON)
             then () else skip();
             msgIBlock 0;
             errLocation (Loc(pos1, pos2));
             errPrompt "Syntax error.";
             msgEOL();
             msgEBlock();
             raise Toplevel
           end
       | LexicalError(msg, pos1, pos2) =>
           (msgIBlock 0;
            if pos1 >= 0 andalso pos2 >= 0 then
              errLocation (Loc(pos1, pos2))
            else ();
            errPrompt "Lexical error: "; msgString msg;
            msgString "."; msgEOL();
            msgEBlock();
            skip();
            raise Toplevel)
       | Toplevel =>
           (skip ();
            raise Toplevel)
  end
;

fun parsePhraseAndClear parsingFun lexingFun lexbuf =
  let val phr =
    parsePhrase parsingFun lexingFun lexbuf
    handle x => (Lexer.resetLexerState(); Parsing.clearParser(); raise x)
  in
    Lexer.resetLexerState();
    Parsing.clearParser();
    phr
  end;

val parseToplevelPhrase =
  parsePhraseAndClear Parser.ToplevelPhrase Lexer.Token
;

val parseStructFile =
  parsePhraseAndClear Parser.StructFile Lexer.Token
;

val parseSigFile =
  parsePhraseAndClear Parser.SigFile Lexer.Token
;

fun isInTable key tbl =
  (Hasht.find tbl key; true)
  handle Subscript => false
;

fun filter p xs =
  rev(foldL (fn x => fn acc => if p x then x::acc else acc) [] xs)
;

fun filterExcRenList excRenList uVarEnv =
  filter (fn ({qual, id = [id]}, _) => isInTable id uVarEnv) excRenList
;

fun filterValRenList valRenList uModEnv uFunEnv uVarEnv =
    filter (fn (id, stamp) => 
	    case unmangle id of
		 ValId vid => isInTable vid uVarEnv
	      |  ModId mid => isInTable mid uModEnv
	      |  FunId fid => isInTable fid uFunEnv)
    valRenList
;

fun cleanEnvAcc [] acc = acc
  | cleanEnvAcc ((k, v) :: rest) acc =
      if exists (fn (k', _) => k = k') acc then
        cleanEnvAcc rest acc
      else
        cleanEnvAcc rest ((k, v) :: acc)
;

fun cleanEnv env =
  cleanEnvAcc (foldEnv (fn a => fn x => fn acc => (a,x)::acc) [] env) []
;


(* Reporting the results of compiling a phrase *)

val verbose = ref false;



fun reportFixityResult (id, status) =
(
  (case status of
       NONFIXst =>
         msgString "nonfix "
     | INFIXst i =>
         (msgString "infix ";
          msgInt i; msgString " ")
     | INFIXRst i =>
         (msgString "infixr ";
          msgInt i; msgString " "));
  msgString id
);


fun reportEquOfType equ =
  msgString
    (case equ of
         FALSEequ => ""
       | TRUEequ => "eq"
       | REFequ => "prim_EQ")
;

fun reportLhsOfTypeResult (tyname : TyName) =
  let val arity = case (#tnKind (!(#info tyname))) of 
                    ARITYkind arity => arity
                  | _ => fatalError "reportLhsOfTypeResult"
      val vs = newTypeVars arity
      val lhs = type_con (map TypeOfTypeVar vs) tyname
  in printType lhs end
;

fun reportTypeResult tyname = 
    (msgString "toplevel reportTypeResult disabled";
    msgFlush())

local
    fun prTopEnv prInfo env firstLine =
	foldEnv (fn k => fn v => fn firstLine => 
		(msgIBlock 0;
		 prInfo k v;	
                 msgEOL();
                 msgEBlock();       
		 false)) firstLine env;
   fun prVal {qualid,info=(sch,status)} = ()
in
fun report_comp_results iBas (Env as EXISTS(T,(ME,FE,GE,VE,TE))) =
  let
     val _ = checkClosedExEnvironment Env; 
     val _ = collectTopVars Env;
     val firstLine = 
	 case T of 
	     [] => true 
	   |   _ =>  (msgIBlock 0;
		      msgPrompt "New type names: ";
		      prTyNameSet T ",";
		      msgEOL();
		      msgEBlock();
		      false)
     val firstLine = 
	 prTopEnv (fn id => fn status => reportFixityResult (id,status)) iBas firstLine;
     val firstLine = 
	 prTopEnv prModInfo ME firstLine;
     val firstLine = 
	 prTopEnv prFunInfo FE firstLine;
     val firstLine = 
	 prTopEnv prSigInfo GE firstLine;
     val firstLine = 
	 prTopEnv prTyInfo TE firstLine;
     val firstLine =
         prTopEnv (prVarInfo prVal) VE firstLine 
  in
      ()
  end
end;

(* To write the signature of the unit currently compiled *)
(* The same value has to be written twice, because it's unclear *)
(* how to `open` a file in "read/write" mode in a Caml Light program. *)

fun writeCompiledSignature filename_ui =
  let val sigStamp = ref dummySigStamp
      val sigLen = ref 0
  in
    let val os = open_out_bin filename_ui in
      (output_value os (!currentSig);
       sigLen := pos_out os;
       close_out os)
      handle x =>
        (close_out os;
         remove_file filename_ui;
         raise x)
    end;
    let val is = open_in_bin filename_ui in
      let val sigImage = input(is, !sigLen) 
	  prim_val md5sum_ : string -> string = 1 "md5sum"
      in
        if size sigImage < !sigLen then raise Size else ();
        close_in is;
        remove_file filename_ui;
        sigStamp := md5sum_ sigImage
      end
      handle x =>
        (close_in is;
         remove_file filename_ui;
         raise x)
    end;
    let val os = open_out_bin filename_ui in
      (output(os, !sigStamp);
       output_value os (!currentSig);
       close_out os)
      handle x =>
        (close_out os;
         remove_file filename_ui;
         raise x)
    end;
    !sigStamp
  end;

(* Checks and error messages for compiling units *)

fun checkUnitId msg (locid as (loc, id)) uname =
    if id <> uname then
	(msgIBlock 0;
	 errLocation loc;
	 errPrompt "Error: "; msgString msg; 
	 msgString " name and file name are incompatible";
	 msgEOL();
	 msgEBlock();
	 raise Toplevel)
    else ();

(* Check that there is a .ui file in the load_path: *)

fun checkExists filename_ui filename_sig filename_sml =
    (find_in_path filename_ui; ()) 
    handle Fail _ =>
	(msgIBlock 0;
	 errPrompt "File "; msgString filename_sig;
	 msgString " must be compiled before ";
	 msgString filename_sml; msgEOL();
	 msgEBlock();
	 raise Toplevel)

fun checkNotExists filename_sig filename_sml =
    if file_exists filename_sig then
	(msgIBlock 0;
	 errPrompt "File "; msgString filename_sig;
	 msgString " exists, but there is no signature constraint in ";
	 msgString filename_sml; msgEOL();
	 msgEBlock();
	 raise Toplevel)
    else ();

(* Compiling a signature *)

(* cvr: TODO this could be optimized by using checkNoRebindings,
   and just calling the update functions instead of extendXXX, which
   are then made redundant *)
fun compileSpecPhrase spec =
  let 
      val LAMBDA(T, S) = elabToplevelSpec spec
  in
    updateCurrentStaticT T;  
    extendCurrentStaticS S;
    let val S' = normStr S  (* cvr: we norm S so that calculated (sub)fields
			       are correct *)
    in
	extendCurrentStaticME (MEofStr S');  
	extendCurrentStaticFE (FEofStr S');  
	extendCurrentStaticVE (VEofStr S');  
	extendCurrentStaticTE (TEofStr S')
    end;
    if !verbose then
      ((* report_comp_results iBas cBas VE TE; *) (*cvr: TODO*)
       msgFlush())
    else ()
  end
;

fun compileSignature uname filename =
  let
      val source_name = filename ^ ".sig"
      val target_name = filename ^ ".ui"
      (* val () = (msgIBlock 0;
                   msgString "[compiling file \""; msgString source_name;
                   msgString "\"]"; msgEOL(); msgEBlock();) *)
      val restorePrState = savePrState()
      val () = resetTypePrinter()
      val () = startCompilingUnit uname
      val () = initInitialEnvironments()
      val is = open_in_bin source_name
      val () = remove_file target_name;
      val lexbuf = createLexerStream is
      fun compileSig (AnonSig specs) = 
	  app compileSpecPhrase specs
	| compileSig (NamedSig{locsigid, specs}) = 
	  (checkUnitId "signature" locsigid uname;
	   app compileSpecPhrase specs)
  in
       input_name   := source_name;
       input_stream := is;
       input_lexbuf := lexbuf;
       extendCurrentStaticS (STRstr(NILenv,NILenv,NILenv,NILenv)); 
         (* cvr: need the above  to distinguish
	         an empty sig file 
                 from a non-existent one *)
       (compileSig (parseSigFile lexbuf);
        ignore (rectifySignature ());
        ignore (writeCompiledSignature target_name);
        close_in is;
        restorePrState())
       handle x => (close_in is;restorePrState();raise x)
  end
;

(* Compiling an implementation *)

(* This is written in tail-recursive form to ensure *)
(* that the intermediate results will be discarded. *)

fun updateCurrentCompState ((iBas, cBas, ExEnv as EXISTS(T,(ME,FE,GE,VE, TE))), RE) =
(
  updateCurrentInfixBasis iBas;
  updateCurrentStaticT T;
  updateCurrentStaticME ME;
  updateCurrentStaticFE FE;
  updateCurrentStaticGE GE;
  updateCurrentStaticVE VE;
  updateCurrentStaticTE TE;
  updateCurrentRenEnv RE;
  if !verbose then
    (report_comp_results iBas ExEnv;
     msgFlush())
  else ()
);

fun compLamPhrase os state (RE, lams) =
(
  app
    (fn (is_pure, lam) =>
       ((* msgIBlock 0; printLam lam; msgEOL(); msgEBlock(); *)
       emit_phrase os
         let val zam = compileLambda is_pure lam in
           (* printZamPhrase zam; msgFlush(); *) 
           zam
         end))
    lams;
    updateCurrentCompState (state, RE)
);

fun compResolvedDecPhrase os (iBas, cBas, dec) =
  let val ExEnv = elabToplevelDec dec in
    resolveOvlDec dec;
    commit_free_typevar_names (); (* cvr: will never be rolled-back *)
    compLamPhrase os (iBas, cBas, ExEnv) (translateToplevelDec dec)
  end
;

fun compileImplPhrase os dec =
  let val (iBas,resdec) = resolveToplevelDec dec in
      compResolvedDecPhrase os (iBas,NILenv,resdec)
  end
;



fun compileAndEmit uname filename specSig_opt decs =
  let
    val filename_ui  = filename ^ ".ui"
    val filename_uo  = filename ^ ".uo"
    (* val () = (msgIBlock 0;
                 msgString "[compiling file \""; msgString filename_sml;
                 msgString "\"]"; msgEOL(); msgEBlock()) *)
    val restorePrState = savePrState(); (* cvr: *)
    val () = resetTypePrinter();
    val () = startCompilingUnit uname
    val () = initInitialEnvironments()
    val os = open_out_bin filename_uo
  in
    ( start_emit_phrase os;
      app (compileImplPhrase os) decs;
      let val (excRenList, valRenList) = rectifySignature() in
          (case specSig_opt of
               NONE =>
                (checkClosedCSig (!currentSig);  
                 let val sigStamp = writeCompiledSignature filename_ui in
                   end_emit_phrase
                     excRenList valRenList
                     sigStamp (#uMentions (!currentSig))
                     os
                 end)
             | SOME specSig =>
                 let val {uVarEnv,uModEnv,uFunEnv,uStamp, ...} = specSig 
                     val valRenList = matchSignature os valRenList (!currentSig) specSig;
		 in
                   end_emit_phrase
                     (filterExcRenList excRenList uVarEnv)
                     (filterValRenList valRenList uModEnv uFunEnv uVarEnv)
                     (getOption (!uStamp)) (#uMentions (!currentSig))
                     os
                 end);
          close_out os;
          restorePrState()
        end
    )
    handle x => (close_out os; remove_file filename_uo;restorePrState();raise x)
  end;

fun compileUnitBody uname filename =
  let val filename_sig = filename ^ ".sig"
      val filename_ui  = filename ^ ".ui"
      val filename_sml = filename ^ ".sml"
      val is = open_in_bin filename_sml
      val lexbuf = createLexerStream is
      fun compileStruct (AnonStruct decs) = 
	  if file_exists filename_sig then
	      (hasSpecifiedSignature := true;
	       checkExists filename_ui filename_sig filename_sml;
	       compileAndEmit uname filename (SOME (readSig uname)) decs)
	  else 
	      (hasSpecifiedSignature := false;
	       remove_file filename_ui;
	       compileAndEmit uname filename NONE decs)
	| compileStruct (NamedStruct{locstrid, locsigid = NONE, decs}) =
	  (checkUnitId "structure" locstrid uname;
	   checkNotExists filename_sig filename_sml;
	   hasSpecifiedSignature := false;
	   remove_file filename_ui;
	   compileAndEmit uname filename NONE decs)
	| compileStruct (NamedStruct _) = fatalError "compileUnitBody"
	| compileStruct (Abstraction{locstrid, locsigid, decs}) =
	  (checkUnitId "structure" locstrid uname;
	   checkUnitId "signature" locsigid uname;
	   checkExists filename_ui filename_sig filename_sml;
	   hasSpecifiedSignature := true;
	   compileAndEmit uname filename (SOME (readSig uname)) decs)
  in
      input_name := filename_sml;
      input_stream := is;
      input_lexbuf := lexbuf;
      (compileStruct (parseStructFile lexbuf))
       handle x => (close_in is; raise x)	  
  end;
