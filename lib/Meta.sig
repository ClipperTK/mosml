(* Meta -- functions for use in an interactive Moscow ML session *)

val printVal    : 'a -> 'a
val printDepth  : int ref
val printLength : int ref
val installPP   : (ppstream -> 'a -> unit) -> unit

val use         : string -> unit
val compile     : string -> unit
val load        : string -> unit
val loadOne     : string -> unit
val loaded      : unit -> string list
val loadPath    : string list ref

val quietdec    : bool ref
val verbose     : bool ref

val exnName     : exn -> string
val exnMessage  : exn -> string

val quotation   : bool ref
val valuepoly   : bool ref

val quit        : unit -> 'a
val system      : string -> int

(* 
   [printVal e] prints the value of expression e to standard output
   exactly as it would be printed at top-level, and returns the value
   of e.  Output is flushed immediately.  This function is provided as
   a simple debugging aid.  The effect of printVal is similar to that
   of `print' in Edinburgh ML or Umeaa ML.  For string arguments, the 
   effect of SML/NJ print can be achieved by the function 
   TextIO.print : string -> unit.

   [printDepth] determines the depth (in terms of nested constructors,
   records, tuples, lists, and vectors) to which values are printed by
   the top-level value printer and the function printVal.  The components
   of the value whose depth is greater than printDepth are printed as
   `#'.  The initial value of printDepth is 20. This value can be
   changed at any moment, by evaluating, for example,
        printDepth := 17;

   [printLength] determines the way in which list values are printed
   by the top-level value printer and the function printVal.  If the
   length of a list is greater than printLength, then only the first
   printLength elements are printed, and the remaining elements are
   printed as `...'.  The initial value of printLength is 200.  This
   value can be changed at any moment, by evaluating, for example,
        printLength := 500;

   [quit ()] quits Moscow ML immediately.

   [installPP pp] installs the prettyprinter pp at type ty, provided
   pp has type ppstream -> ty -> unit.  The type ty must be a nullary
   (parameter-less) type constructor representing a datatype, either
   built-in (such as bool) or user-defined.  Whenever a value of type
   ty is about to be printed by the interactive system, or function
   printVal is invoked on an argument of type ty, the pretty-printer 
   pp will be invoked to print it.  See library unit PP for more
   information.

   [use "f"] causes ML declarations to be read from file f as if they
   were entered from the console.  A file loaded by use may, in turn,
   evaluate calls to use.  For best results, use `use' only at top
   level, or at top level within a use'd file.

   [compile "U.sig"] will compile and elaborate the unit signature in
   file U.sig, producing a compiled signature file U.ui.  During
   compilation, the compiled signatures of other units will be
   accessed if they are mentioned in U.sig.

   [compile "U.sml"] will elaborate and compile the unit body in file
   U.sml, producing a bytecode file U.uo.  If there is an explicit
   signature U.sig, then file U.ui must exist, and the unit body must
   match the signature.  If there is no U.sig, then an inferred
   signature file U.ui will be produced also.  No evaluation takes
   place.  During compilation, the compiled signatures of other units
   will be accessed if they are mentioned in U.sml.

   The declared identifiers will be reported if verbose is true (see
   below); otherwise compilation will be silent.  In any case,
   compilation warnings are reported, and compilation errors abort the
   compilation and raise the exception Fail with a string argument.

   [load "U"] will load and evaluate the compiled unit body from file
   U.uo.  The resulting values are not reported, but exceptions are
   reported, and cause evaluation and loading to stop.  If U is
   already loaded, then load "U" has no effect.  If any other unit is
   mentioned by U but not yet loaded, then it will be loaded
   automatically before U.

   After loading a unit, it can be opened with `open U'.  Opening it
   at top-level will list the identifiers declared in the unit.

   When loading U, it is checked that the signatures of units
   mentioned by U agree with the signatures used when compiling U, and
   it is checked that the signature of U has not been modified since U
   was compiled; these checks are necessary for type safety.  The
   exception Fail is raised if these signature checks fail, or if the
   file containing U or a unit mentioned by U does not exist.

   [loadOne "U"] is similar to `load "U"', but raises exception Fail
   if U is already loaded or if some unit mentioned by U is not yet
   loaded.  That is, it does not automatically load any units
   mentioned by U.  It performs the same signature checks as `load'.

   [loaded ()] returns a list of the names of all compiled units that
   have been loaded so far.  The names appear in some random order.

   [loadPath] determines the load path: which directories will be
   searched for interface files (.ui files), bytecode files (.uo
   files), and source files (.sml files).  This variable affects the
   load, loadOne, and use functions.  The current directory is always
   searched first, followed by the directories in loadPath, in order.
   By default, only the standard library directory is in the list, but
   if additional directories are specified using option -I, then these
   directories are prepended to loadPath.

   [quietdec] when {\tt true}, turns off the interactive system's
   prompt and responses, except warnings and error messages.  Useful
   for writing scripts in SML.  The default value is false; can be set
   to true with the -quietdec command line option.

   [verbose] determines whether the signature inferred by a call to
   compile will be printed.  The printed signature follows the syntax
   of Moscow ML signatures, so the output of compile "U.sml" can be
   edited to subsequently create file U.sig.  The default value is
   ref false.

   [exnName exn] returns a name for the exception constructor in exn.  
   Never raises an exception itself.  The name returned may be that of
   any exception constructor aliasing with exn.  For instance,
        let exception E1; exception E2 = E1 in exnName E2 end
   may evaluate to "E1" or "E2".

   [exnMessage exn] formats and returns a message corresponding to
   exception exn.  For the exceptions defined in the SML Basis Library, 
   the message will include the argument carried by the exception.

   [quotation] determines whether quotations and antiquotations are
   permitted in declarations entered at top-level and in files
   compiled with compile.  A quotation is a piece of text surrounded
   by backquote characters `a b c` and is used to embed object
   language phrases in ML programs; see the Moscow ML Owner's Manual
   for a brief explanation of quotations.  When quotation is false,
   the backquote character is an ordinary symbol which can be used in
   ML symbolic identifiers.  When quotation is {\tt true}, the
   backquote character is illegal in symbolic identifiers, and a
   quotation `a b c` will be recognized by the parser and evaluated to
   an object of type 'a General.frag list.  The default value is ref
   false.

   [valuepoly] determines whether the type checker should use `value
   polymorphism', making no distinction between imperative ('_a) and
   applicative ('a) type variables, and generalizing type variables
   only in non-expansive expressions.  An expression is non-expansive
   if it is a variable, a special constant, a function, a tuple or 
   record of non-expansive expressions, a parenthesized or typed 
   non-expansive expression, or the application of an exception or value 
   constructor (other than ref) to a non-expansive expression.
        If valuepoly is false, then the type checker will distinguish 
   imperative and applicative type variables, generalize all applicative 
   type variables, and generalize imperative type variables only in
   non-expansive expressions.  This is the default, required by the
   1990 Definition of Standard ML, Section 4.8.

   [system "com"] causes the command com to be executed by the
   operating system.  If a non-zero integer is returned, this must
   indicate that the operating system has failed to execute the
   command.  Under MS DOS, the integer returned tends to always equal
   zero, even when the command fails.  
*)
