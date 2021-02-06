import os, re, strutils, tables, unicode, hashes, sets, json, asyncdispatch, times, strformat

import ./map_key

export MapKey

const DEFAULT_ERROR_MESSAGE = "Error occurred."
const BINARY_OPS* = [
  "+", "-", "*", "/", "**",
  "=", "+=", "-=", "*=", "/=", "**=",
  "==", "!=", "<", "<=", ">", ">=",
  "&&", "||", # TODO: xor
  "&&=", "||=",
  "&",  "|",  # TODO: xor for bit operation
  "&=", "|=",
]

type
  GeneException* = object of CatchableError
    instance*: GeneValue  # instance of Gene exception class

  NotDefinedException* = object of GeneException

  # index of a name in a scope
  NameIndexScope* = distinct int

  Runtime* = ref object
    name*: string     # default/...
    home*: string     # GENE_HOME directory
    version*: string
    features*: Table[string, GeneValue]

  ## This is the root of a running application
  Application* = ref object
    name*: string         # default to base name of command
    pkg*: Package         # Entry package for the application
    ns*: Namespace
    cmd*: string
    args*: seq[string]

  Package* = ref object
    dir*: string          # Where the package assets are installed
    adhoc*: bool          # Adhoc package is created when package.gene is not found
    ns*: Namespace
    name*: string
    version*: GeneValue
    license*: GeneValue
    dependencies*: Table[string, Package]
    homepage*: string
    props*: Table[string, GeneValue]  # Additional properties
    doc*: GeneDocument    # content of package.gene

  Module* = ref object
    pkg*: Package         # Package in which the module belongs, or stdlib if not set
    name*: string
    root_ns*: Namespace

  ImportMatcherRoot* = ref object
    children*: seq[ImportMatcher]
    `from`*: GeneValue

  ImportMatcher* = ref object
    name*: MapKey
    `as`*: MapKey
    children*: seq[ImportMatcher]
    children_only*: bool # true if self should not be imported

  Namespace* = ref object
    parent*: Namespace
    stop_inheritance*: bool  # When set to true, stop looking up for members
    name*: string
    members*: Table[MapKey, GeneValue]

  Scope* = ref object
    parent*: Scope
    parent_index_max*: NameIndexScope
    members*:  seq[GeneValue]
    mappings*: Table[MapKey, seq[NameIndexScope]]

  Class* = ref object
    parent*: Class
    name*: string
    methods*: Table[MapKey, Method]
    ns*: Namespace # Class can act like a namespace

  Mixin* = ref object
    name*: string
    methods*: Table[MapKey, Method]
    # TODO: ns*: Namespace # Mixin can act like a namespace

  Method* = ref object
    class*: Class
    name*: string
    fn*: Function
    fn_native*: NativeMethod
    # public*: bool

  Instance* = ref object
    class*: Class
    value*: GeneValue

  AspectKind* = enum
    AspClass
    AspFunction

  Aspect* = ref object
    kind*: AspectKind
    ns*: Namespace
    name*: string
    matcher*: RootMatcher
    body*: seq[GeneValue]
    # active*: bool
    expr*: Expr

  AspectInstance* = ref object
    aspect*: Aspect
    target*: GeneValue
    # active*: bool
    before_advices*: seq[Advice]
    after_advices*:  seq[Advice]
    around_advices*: seq[Advice]

  # Order of execution:
  # before 1
  # before 2
  # invariant 1
  # invariant 2
  # around 1
  # around 2
  # target
  # around 2
  # around 1
  # after 1
  # after 2
  # invariant 1
  # invariant 2
  AdviceKind* = enum
    AdBefore         # run before target
    Adafter          # run after target
    AdAround         # wrap around target
    AdCatch          # catch exception
    AdEnsure         # try...finally to ensure resources are released
    AdInvariant      # code get executed before and after, false -> throws InvariantError

  AdviceOptionKind* = enum
    # applicable to before
    AoPreCondition      # false -> throw PreconditionError
    AoPreCheck          # false -> stop further execution
    AoReplaceArgs       # result will be used as new args
    # applicable to after
    AoPostCondition     # false -> throw PostConditionError
    AoResultAsFirstArg
    AoReplaceResult

  # How do we make `before` advice to return a result? by throwing a special exception?
  Advice* = ref object
    owner*: AspectInstance
    kind*: AdviceKind
    options*: OrderedTable[AdviceOptionKind, GeneValue]
    logic*: Function

  # ClassAdviceKind* = enum
  #   ClPreProcess
  #   ClPreCondition  # if false is returned, throw PreconditionError
  #   ClPostProcess
  #   ClPostCondition # if false is returned, throw PostconditionError
  #   ClAround        # wrap around the method
  #   ClInvariant     # executed before and after (not like around advices)
  #                   # if false is returned, throw InvariantError

  # ClassAdviceMatcher* = ref object
  #   `include`*: seq[string]
  #   exclude*: seq[string]
  #   include_all*: bool # exclude still applies

  # ClassAdvice* = ref object
  #   name*: string # Optional name for better debugging
  #   class*: Class
  #   target*: GeneValue
  #   logic*: Function
  #   expr*: Expr

  # # some can be replaced with options, option key should be from some enum
  # AdviceKind* = enum
  #   AdPreProcess
  #   AdProcessArgs    # args will be replaced with advice result
  #   AdPreCondition   # if false is returned, throw PreconditionError
  #   AdPostProcess
  #   AdPostCleanup    # does not affect result
  #   AdPostCondition  # if false is returned, throw PostconditionError
  #   AdCatchException # like Around advice, will catch specified exception
  #   AdAround         # wrap around the method
  #   AdInvariant      # executed before and after (not like around advices)
  #                    # if false is returned, throw InvariantError

  # PointCutKind* = enum
  #   PcMethod
  #   PcFunction

  # PointCut* = ref object
  #   case kind*: PointCutKind
  #   of PcMethod:
  #     `include`*: seq[string]
  #     # include_pattern*:
  #     exclude*: seq[string]
  #   else:
  #     discard

  Function* = ref object
    async*: bool
    ns*: Namespace
    parent_scope*: Scope
    parent_scope_max*: NameIndexScope
    name*: string
    matcher*: RootMatcher
    body*: seq[GeneValue]
    expr*: Expr # The function expression that will be the parent of body
    body_blk*: seq[Expr]

  Block* = ref object
    frame*: Frame
    parent_scope_max*: NameIndexScope
    matcher*: RootMatcher
    body*: seq[GeneValue]
    expr*: Expr # The expression that will be the parent of body
    body_blk*: seq[Expr]

  Macro* = ref object
    ns*: Namespace
    name*: string
    matcher*: RootMatcher
    body*: seq[GeneValue]
    expr*: Expr # The expression that will be the parent of body

  Enum* = ref object
    name*: string
    members*: OrderedTable[string, EnumMember]

  EnumMember* = ref object
    parent*: Enum
    name*: string
    value*: int

  # Iterator* = iterator(): tuple[k, v: GeneValue] {.closure.}
  # IteratorWrapper* = proc(args: varargs[GeneValue]): Iterator

  GeneInternalKind* = enum
    GeneApplication
    GenePackage
    GeneFunction
    GeneMacro
    GeneBlock
    GeneReturn
    GeneClass
    GeneMixin
    GeneMethod
    GeneInstance
    GeneNamespace
    GeneEnum
    GeneEnumMember
    GeneAspect
    GeneAdvice
    GeneAspectInstance
    GeneExplode
    GeneFile
    GeneExceptionKind
    GeneFuture
    GeneSelector
    GeneNativeFn
    GeneNativeMethod
    GeneExpr
    # GeneIterator
    # GeneIteratorWrapper

  Internal* = object
    case kind*: GeneInternalKind
    of GeneApplication:
      app*: Application
    of GenePackage:
      pkg*: Package
    of GeneFunction:
      fn*: Function
    of GeneMacro:
      mac*: Macro
    of GeneBlock:
      blk*: Block
    of GeneReturn:
      ret*: Return
    of GeneClass:
      class*: Class
    of GeneMixin:
      mix*: Mixin
    of GeneMethod:
      meth*: Method
    of GeneInstance:
      instance*: Instance
    of GeneNamespace:
      ns*: Namespace
    of GeneEnum:
      `enum`*: Enum
    of GeneEnumMember:
      enum_member*: EnumMember
    of GeneAspect:
      aspect*: Aspect
    of GeneAdvice:
      advice*: Advice
    of GeneAspectInstance:
      aspect_instance*: AspectInstance
    of GeneExplode:
      explode*: GeneValue
    of GeneFile:
      file*: File
    of GeneExceptionKind:
      exception*: ref CatchableError
    of GeneFuture:
      future*: Future[GeneValue]
    of GeneSelector:
      selector*: Selector
    of GeneNativeFn:
      native_fn*: NativeFn
    of GeneNativeMethod:
      native_meth*: NativeMethod
    of GeneExpr:
      expr*: Expr
    # of GeneIterator:
    #   `iterator`*: Iterator
    # of GeneIteratorWrapper:
    #   `iterator_wrapper`*: IteratorWrapper

  ComplexSymbol* = ref object
    first*: string
    rest*: seq[string]

  # applicable to numbers, characters
  Range* = ref object
    first*: GeneValue
    last*: GeneValue
    step*: GeneValue # default to 1 if first is greater than last
    # include_first*: bool # always true
    include_last*: bool # default to false

  Gene* {.acyclic.} = ref object
    `type`*: GeneValue
    props*: OrderedTable[MapKey, GeneValue]
    data*: seq[GeneValue]
    # A gene can be normalized to match expected format
    # Example: (a = 1) => (= a 1)
    normalized*: bool

  SelectorNoResult* = object of GeneException

  Selector* {.acyclic.} = ref object
    children*: seq[SelectorItem]  # Each child represents a branch
    default*: GeneValue

  SelectorItemKind* = enum
    SiDefault
    SiSelector

  SelectorItem* {.acyclic.} = ref object
    case kind*: SelectorItemKind
    of SiDefault:
      matchers*: seq[SelectorMatcher]
      children*: seq[SelectorItem]  # Each child represents a branch
    of SiSelector:
      selector*: Selector

  SelectorMatcherKind* = enum
    SmByIndex
    SmByIndexList
    SmByIndexRange
    SmByName
    SmByNameList
    SmByNamePattern
    SmSymbol
    SmByType
    SmType
    SmProps
    SmKeys
    SmValues
    SmData
    SmSelfAndDescendants
    SmDescendants
    SmCallback

  SelectorMatcher* = ref object
    root*: Selector
    case kind*: SelectorMatcherKind
    of SmByIndex:
      index*: int
    of SmByName:
      name*: MapKey
    of SmByType:
      by_type*: GeneValue
    of SmCallback:
      callback*: GeneValue
    else: discard

  SelectResultMode* = enum
    SrFirst
    SrAll

  SelectorResult* = ref object
    done*: bool
    case mode*: SelectResultMode
    of SrFirst:
      first*: GeneValue
    of SrAll:
      all*: seq[GeneValue]

  # Non-date specific time object
  GeneTime* = ref object
    hour*: int
    minute*: int
    second*: int
    timezone*: Timezone

  MyDateTime* = ref object
    date*: DateTime

  GeneKind* = enum
    GeneNilKind
    GenePlaceholderKind
    GeneBool
    GeneInt
    GeneRatio
    GeneFloat
    GeneChar
    GeneString
    GeneSymbol
    GeneComplexSymbol
    GeneRegex
    GeneRange
    # Time part should be 00:00:00 and timezone should not matter
    GeneDate
    # Date + time + timezone
    GeneDateTime
    GeneTimeKind
    GeneTimezone
    GeneMap
    GeneVector
    GeneSet
    GeneGene
    GeneStream
    GeneInternal
    GeneAny

  GeneValue* {.acyclic.} = ref object
    case kind*: GeneKind
    of GeneNilKind, GenePlaceholderKind:
      discard
    of GeneBool:
      bool*: bool
    of GeneInt:
      int*: BiggestInt
    of GeneRatio:
      ratio*: tuple[numerator, denominator: BiggestInt]
    of GeneFloat:
      float*: float
    of GeneChar:
      char*: char
      rune*: Rune
    of GeneString:
      str*: string
    of GeneSymbol:
      symbol*: string
    of GeneComplexSymbol:
      csymbol*: ComplexSymbol
    of GeneRegex:
      regex*: Regex
    of GeneRange:
      range_start*: GeneValue
      range_end*: GeneValue
      range_incl_start*: bool
      range_incl_end*: bool
    of GeneDate, GeneDateTime:
      date_internal: MyDateTime
    of GeneTimeKind:
      time*: GeneTime
    of GeneTimezone:
      timezone*: Timezone
    of GeneMap:
      map*: OrderedTable[MapKey, GeneValue]
    of GeneVector:
      vec*: seq[GeneValue]
    of GeneSet:
      set*: OrderedSet[GeneValue]
    of GeneGene:
      gene*: Gene
    of GeneStream:
      stream*: seq[GeneValue]
    of GeneInternal:
      internal*: Internal
    of GeneAny:
      any_type*: MapKey   # Optional type info
      any*: pointer
    # line*: int
    # column*: int

  GeneDocument* = ref object
    `type`: GeneValue
    props*: OrderedTable[MapKey, GeneValue]
    data*: seq[GeneValue]

  NativeFn* = proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue {.nimcall.}

  FnOption* = enum
    FnClass
    FnMethod

  NativeMethod* = proc(
    self: GeneValue,
    props: OrderedTable[MapKey, GeneValue],
    data: seq[GeneValue],
  ): GeneValue {.nimcall.}

  SymbolKind* = enum
    SkUnknown
    SkGene
    SkGenex
    SkNamespace
    SkScope

  ExprKind* = enum
    ExCustom
    ExTodo
    ExNotAllowed
    ExRoot
    ExLiteral
    ExString
    ExSymbol
    ExComplexSymbol
    ExMap
    ExMapChild
    ExArray
    ExGene
    ExEnum
    ExRange
    ExGet
    ExSet
    ExGroup
    ExDo
    ExVar
    ExAssignment
    ExNot
    ExBinary
    ExBinImmediate
    ExBinAssignment
    ExIf
    ExCase
    ExLoop
    ExBreak
    ExContinue
    ExWhile
    ExFor
    ExExplode
    ExThrow
    ExTry
    ExAwait
    ExFn
    ExArgs
    ExMacro
    ExBlock
    ExReturn
    ExReturnRef
    ExAspect
    ExAdvice
    ExClass
    ExObject
    ExMixin
    ExNew
    ExInclude
    ExMethod
    ExInvokeMethod
    ExSuper
    ExNamespace
    ExDefMember
    ExDefNsMember
    ExSelf
    ExGlobal
    ExImport
    ExIncludeFile
    ExStopInheritance
    ExCall
    ExGetClass
    ExQuote
    ExUnquote
    ExParse
    ExEval
    ExCallerEval
    ExMatch
    ExExit
    ExEnv
    ExPrint
    ExParseCmdArgs
    ExRepl
    ExAsync
    ExAsyncCallback
    ExSelector

  Expr* = ref object of RootObj
    parent*: Expr
    evaluator*: Evaluator
    case kind*: ExprKind
    of ExCustom:
      custom*: GeneValue
      custom_type*: MapKey
    of ExTodo:
      todo*: Expr
    of ExNotAllowed:
      not_allowed*: Expr
    of ExRoot:
      root*: Expr
    of ExLiteral:
      literal*: GeneValue
    of ExString:
      str*: string
    of ExSymbol:
      symbol*: MapKey
      case symbol_kind*: SymbolKind
      of SkNamespace:
        symbol_ns*: Namespace
      else:
        discard
    of ExComplexSymbol:
      csymbol*: ComplexSymbol
    of ExArray:
      array*: seq[Expr]
    of ExMap:
      map*: seq[Expr]
    of ExMapChild:
      map_key*: MapKey
      map_val*: Expr
    of ExEnum:
      `enum`*: Enum
    of ExGene:
      gene*: GeneValue
      gene_type*: Expr
      gene_props*: seq[Expr]
      gene_data*: seq[Expr]
    of ExRange:
      range_start*: Expr
      range_end*: Expr
      range_incl_start*: bool
      range_incl_end*: bool
    of ExGet:
      get_target*: Expr
      get_index*: Expr
    of ExSet:
      set_target*: Expr
      set_index*: Expr
      set_value*: Expr
    of ExGroup:
      group*: seq[Expr]
    of ExDo:
      do_props*: seq[Expr]
      do_body*: seq[Expr]
    of ExVar, ExAssignment:
      var_name*: GeneValue
      var_val*: Expr
    of ExNot:
      `not`*: Expr
    of ExBinary:
      bin_op*: BinOps
      bin_first*: Expr
      bin_second*: Expr
    of ExBinImmediate:
      bini_op*: BinOps
      bini_first*: Expr
      bini_second*: GeneValue
    of ExBinAssignment:
      bina_op*: BinOps
      bina_first*: GeneValue
      bina_second*: Expr
    of ExIf:
      if_cond*: Expr
      if_then*: Expr
      if_elifs*: seq[(Expr, Expr)]
      if_else*: Expr
    of ExCase:
      case_input*: Expr
      case_blks*: seq[Expr]   # Code blocks
      case_else*: Expr        # Else block
      case_lite_mapping*: Table[MapKey, int]  # literal -> block index
      case_more_mapping*: seq[(Expr, int)]    # non-literal -> block index
    of ExLoop:
      loop_blk*: seq[Expr]
    of ExBreak:
      break_val*: Expr
    of ExContinue:
      discard
    of ExWhile:
      while_cond*: Expr
      while_blk*: seq[Expr]
    of ExFor:
      for_vars*: GeneValue
      for_in*: Expr
      for_blk*: seq[Expr]
    of ExExplode:
      explode*: Expr
    of ExThrow:
      throw_type*: Expr
      throw_mesg*: Expr
    of ExTry:
      try_body*: seq[Expr]
      try_catches*: seq[(Expr, seq[Expr])]
      try_finally*: seq[Expr]
    of ExFn:
      fn*: GeneValue
      fn_name*: GeneValue
    of ExArgs:
      discard
    of ExBlock:
      blk*: GeneValue
    of ExMacro:
      mac*: GeneValue
      mac_name*: GeneValue
    of ExReturn:
      return_val*: Expr
    of ExReturnRef:
      discard
    of ExAspect:
      aspect*: GeneValue
    of ExAdvice:
      advice*: GeneValue
    of ExClass:
      super_class*: Expr
      class*: GeneValue
      class_name*: GeneValue # The simple name or complex name that is associated with the class
      class_body*: seq[Expr]
    of ExObject:
      obj_super_class*: Expr
      obj_name*: GeneValue # The simple name or complex name that is associated with the class
      obj_body*: seq[Expr]
    of ExMixin:
      mix*: GeneValue
      mix_name*: GeneValue
      mix_body*: seq[Expr]
    of ExNew:
      new_class*: Expr
      new_args*: seq[Expr]
    of ExInclude:
      include_args*: seq[Expr]
    of ExMethod:
      meth*: GeneValue
      meth_fn_native*: Expr
    of ExInvokeMethod:
      invoke_self*: Expr
      invoke_meth*: MapKey
      invoke_args*: seq[Expr]
    of ExSuper:
      super_args*: seq[Expr]
    of ExNamespace:
      ns*: GeneValue
      ns_name*: GeneValue # The simple name or complex name that is associated
      ns_body*: seq[Expr]
    of ExDefMember:
      def_member_name*: Expr
      def_member_value*: Expr
    of ExDefNsMember:
      def_ns_member_name*: Expr
      def_ns_member_value*: Expr
    of ExSelf, ExGlobal:
      discard
    of ExImport:
      import_matcher*: ImportMatcherRoot
      import_from*: Expr
      import_pkg*: Expr
      import_native*: bool
    of ExIncludeFile:
      include_file*: Expr
    of ExStopInheritance:
      discard
    of ExCall:
      # call_props*: OrderedTable[MapKey, Expr]
      call_target*: Expr
      call_args*: Expr
    of ExGetClass:
      get_class_val*: Expr
    of ExQuote:
      quote_val*: GeneValue
    of ExUnquote:
      unquote_val*: GeneValue
    of ExParse:
      parse*: Expr
    of ExEval:
      eval_self*: Expr
      eval_args*: seq[Expr]
    of ExCallerEval:
      caller_eval_args*: seq[Expr]
    of ExMatch:
      match_pattern*: GeneValue
      match_val*: Expr
    of ExExit:
      exit*: Expr
    of ExEnv:
      env*: Expr
      env_default*: Expr
    of ExPrint:
      print_and_return*: bool
      print_to*: Expr
      print*: seq[Expr]
    of ExParseCmdArgs:
      cmd_args_schema*: ArgMatcherRoot
      cmd_args*: Expr
    of ExRepl:
      discard
    of ExAsync:
      async*: Expr
    of ExAwait:
      await*: seq[Expr]
    of ExAsyncCallback:
      acb_success*: bool
      acb_self*: Expr
      acb_callback*: Expr
    of ExSelector:
      selector*: seq[Expr]
      parallel_mode*: bool

  VirtualMachine* = ref object
    app*: Application
    modules*: OrderedTable[MapKey, Namespace]
    repl_on_error*: bool
    gene_ns*: GeneValue
    genex_ns*: GeneValue
    object_class*: GeneValue
    class_class*: GeneValue
    exception_class*: GeneValue

  Evaluator* = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue

  EvaluatorManager* = ref object
    mappings*: Table[ExprKind, Evaluator]

  FrameKind* = enum
    FrFunction
    FrMacro
    FrMethod
    FrModule
    FrBody

  FrameExtra* = ref object
    case kind*: FrameKind
    of FrFunction:
      fn*: Function
    of FrMacro:
      mac*: Function
    of FrMethod:
      class*: Class
      meth*: Function
      meth_name*: MapKey
      # hierarchy*: CallHierarchy # A hierarchy object that tracks where the method is in class hierarchy
    else:
      discard

  Frame* = ref object
    parent*: Frame
    self*: GeneValue
    ns*: Namespace
    scope*: Scope
    args*: GeneValue # This is only available in some frames (e.g. function/macro/block)
    extra*: FrameExtra

  Break* = ref object of CatchableError
    val*: GeneValue

  Continue* = ref object of CatchableError

  Return* = ref object of CatchableError
    frame*: Frame
    val*: GeneValue

  BinOps* = enum
    BinAdd
    BinSub
    BinMul
    BinDiv
    BinEq
    BinNeq
    BinLt
    BinLe
    BinGt
    BinGe
    BinAnd
    BinOr

  MatchMode* = enum
    MatchDefault
    MatchArgs

  MatchingMode* = enum
    MatchArgParsing # (fn f [a b] ...)
    MatchExpression # (match [a b] input): a and b will be defined
    MatchAssignment # ([a b] = input): a and b must be defined first

  # Match the whole input or the first child (if running in ArgumentMode)
  # Can have name, match nothing, or have group of children
  RootMatcher* = ref object
    mode*: MatchingMode
    children*: seq[Matcher]

  MatcherKind* = enum
    MatchOp
    MatchProp
    MatchData

  Matcher* = ref object
    root*: RootMatcher
    kind*: MatcherKind
    name*: MapKey
    # match_name*: bool # Match symbol to name - useful for (myif true then ... else ...)
    default_value*: GeneValue
    default_value_expr*: Expr
    splat*: bool
    min_left*: int # Minimum number of args following this
    children*: seq[Matcher]
    # required*: bool # computed property: true if splat is false and default value is not given

  MatchResultKind* = enum
    MatchSuccess
    MatchMissingFields
    MatchWrongType # E.g. map is passed but array or gene is expected

  MatchedField* = ref object
    name*: MapKey
    value*: GeneValue # Either value_expr or value must be given
    value_expr*: Expr # Expression for calculating default value

  MatchResult* = ref object
    message*: string
    kind*: MatchResultKind
    # If success
    fields*: seq[MatchedField]
    assign_only*: bool # If true, no new variables will be defined
    # If missing fields
    missing*: seq[MapKey]
    # If wrong type
    expect_type*: string
    found_type*: string

  # Internal state when applying the matcher to an input
  # Limited to one level
  MatchState* = ref object
    # prop_processed*: seq[MapKey]
    data_index*: int

  FrameManager* = ref object
    cache*: seq[Frame]

  # Types related to command line argument parsing
  ArgumentError* = object of CatchableError

  ArgMatcherRoot* = ref object
    include_program*: bool
    options*: Table[string, ArgMatcher]
    args*: seq[ArgMatcher]
    # Extra is always returned if "-- ..." is found.

  ArgMatcherKind* = enum
    ArgOption      # options
    ArgPositional  # positional arguments

  ArgDataType* = enum
    ArgInt
    ArgBool
    ArgString

  ArgMatcher* = ref object
    case kind*: ArgMatcherKind
    of ArgOption:
      short_name*: string
      long_name*: string
      toggle*: bool          # if false, expect a value
    of ArgPositional:
      arg_name*: string
    description*: string
    required*: bool
    multiple*: bool
    data_type*: ArgDataType  # int, string, what else?
    default: GeneValue

  ArgMatchingResultKind* = enum
    AmSuccess
    AmFailure

  ArgMatchingResult* = ref object
    kind*: ArgMatchingResultKind
    program*: string
    options*: Table[string, GeneValue]
    args*: Table[string, GeneValue]
    extra*: seq[string]
    failure*: string  # if kind == AmFailure

let
  GeneNil*   = GeneValue(kind: GeneNilKind)
  GeneTrue*  = GeneValue(kind: GeneBool, bool: true)
  GeneFalse* = GeneValue(kind: GeneBool, bool: false)
  GenePlaceholder* = GeneValue(kind: GenePlaceholderKind)

  Quote*     = GeneValue(kind: GeneSymbol, symbol: "quote")
  Unquote*   = GeneValue(kind: GeneSymbol, symbol: "unquote")
  If*        = GeneValue(kind: GeneSymbol, symbol: "if")
  Then*      = GeneValue(kind: GeneSymbol, symbol: "then")
  Elif*      = GeneValue(kind: GeneSymbol, symbol: "elif")
  Else*      = GeneValue(kind: GeneSymbol, symbol: "else")
  When*      = GeneValue(kind: GeneSymbol, symbol: "when")
  Not*       = GeneValue(kind: GeneSymbol, symbol: "not")
  Equal*     = GeneValue(kind: GeneSymbol, symbol: "=")
  Try*       = GeneValue(kind: GeneSymbol, symbol: "try")
  Catch*     = GeneValue(kind: GeneSymbol, symbol: "catch")
  Finally*   = GeneValue(kind: GeneSymbol, symbol: "finally")
  Call*      = GeneValue(kind: GeneSymbol, symbol: "call")
  Do*        = GeneValue(kind: GeneSymbol, symbol: "do")

var GeneInts: array[111, GeneValue]
for i in 0..110:
  GeneInts[i] = GeneValue(kind: GeneInt, int: i - 10)

var VM*: VirtualMachine   # The current virtual machine

var GeneObjectClass*   : GeneValue
var GeneClassClass*    : GeneValue
var GeneExceptionClass*: GeneValue

var EvaluatorMgr* = EvaluatorManager()
var FrameMgr* = FrameManager()

#################### Definitions #################

converter new_gene_internal*(e: Enum): GeneValue
converter new_gene_internal*(m: EnumMember): GeneValue
converter new_gene_internal*(ns: Namespace): GeneValue

proc new_gene_int*(val: BiggestInt): GeneValue
proc new_gene_string*(s: string): GeneValue {.gcsafe.}
proc new_gene_string_move*(s: string): GeneValue
proc new_gene_vec*(items: seq[GeneValue]): GeneValue {.gcsafe.}
proc new_namespace*(): Namespace
proc new_namespace*(parent: Namespace): Namespace
proc new_match_matcher*(): RootMatcher
proc new_arg_matcher*(): RootMatcher
proc get_member*(self: GeneValue, name: string): GeneValue
proc parse*(self: var RootMatcher, v: GeneValue)

##################################################

proc todo*() =
  raise new_exception(Exception, "TODO")

proc todo*(message: string) =
  raise new_exception(Exception, "TODO: " & message)

proc not_allowed*(message: string) =
  raise new_exception(Exception, message)

proc not_allowed*() =
  not_allowed("Error: should not arrive here.")

proc new_gene_exception*(message: string, instance: GeneValue): ref Exception =
  var e = new_exception(GeneException, message)
  e.instance = instance
  return e

proc new_gene_exception*(message: string): ref Exception =
  return new_gene_exception(message, nil)

proc new_gene_exception*(instance: GeneValue): ref Exception =
  return new_gene_exception(DEFAULT_ERROR_MESSAGE, instance)

proc new_gene_exception*(): ref Exception =
  return new_gene_exception(DEFAULT_ERROR_MESSAGE, nil)

proc date*(self: GeneValue): DateTime =
  self.date_internal.date

#################### Converters ##################

converter int_to_gene*(v: int): GeneValue = new_gene_int(v)
converter int_to_gene*(v: int64): GeneValue = new_gene_int(v)
converter biggest_to_int*(v: BiggestInt): int = cast[int](v)

converter seq_to_gene*(v: seq[GeneValue]): GeneValue {.gcsafe.} = new_gene_vec(v)
converter str_to_gene*(v: string): GeneValue {.gcsafe.} = new_gene_string(v)

converter to_map*(self: OrderedTable[string, GeneValue]): OrderedTable[MapKey, GeneValue] {.inline.} =
  for k, v in self:
    result[k.to_key] = v

converter to_string_map*(self: OrderedTable[MapKey, GeneValue]): OrderedTable[string, GeneValue] {.inline.} =
  for k, v in self:
    result[k.to_s] = v

converter int_to_scope_index*(v: int): NameIndexScope = cast[NameIndexScope](v)
converter scope_index_to_int*(v: NameIndexScope): int = cast[int](v)

converter gene_to_ns*(v: GeneValue): Namespace = v.internal.ns

converter to_gene*(v: NativeFn): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(
      kind: GeneNativeFn,
      native_fn: v,
    ),
  )

converter to_gene*(v: NativeMethod): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(
      kind: GeneNativeMethod,
      native_meth: v,
    ),
  )

# converter to_gene*(v: Iterator): GeneValue =
#   return GeneValue(
#     kind: GeneInternal,
#     internal: Internal(
#       kind: GeneIterator,
#       `iterator`: v,
#     ),
#   )

# converter to_gene*(v: IteratorWrapper): GeneValue =
#   return GeneValue(
#     kind: GeneInternal,
#     internal: Internal(
#       kind: GeneIteratorWrapper,
#       `iterator_wrapper`: v,
#     ),
#   )

#################### Module ######################

proc new_module*(name: string): Module =
  result = Module(
    name: name,
    root_ns: new_namespace(VM.app.ns),
  )

proc new_module*(): Module =
  result = new_module("<unknown>")

proc new_module*(ns: Namespace, name: string): Module =
  result = Module(
    name: name,
    root_ns: new_namespace(ns),
  )

proc new_module*(ns: Namespace): Module =
  result = new_module(ns, "<unknown>")

#################### Namespace ###################

proc new_namespace*(): Namespace =
  return Namespace(
    name: "<root>",
    members: Table[MapKey, GeneValue](),
  )

proc new_namespace*(parent: Namespace): Namespace =
  return Namespace(
    parent: parent,
    name: "<root>",
    members: Table[MapKey, GeneValue](),
  )

proc new_namespace*(name: string): Namespace =
  return Namespace(
    name: name,
    members: Table[MapKey, GeneValue](),
  )

proc new_namespace*(parent: Namespace, name: string): Namespace =
  return Namespace(
    parent: parent,
    name: name,
    members: Table[MapKey, GeneValue](),
  )

proc root*(self: Namespace): Namespace =
  if self.name == "<root>":
    return self
  else:
    return self.parent.root

proc has_key*(self: Namespace, key: MapKey): bool {.inline.} =
  return self.members.has_key(key)

proc `[]`*(self: Namespace, key: MapKey): GeneValue {.inline.} =
  if self.has_key(key):
    return self.members[key]
  elif not self.stop_inheritance and self.parent != nil:
    return self.parent[key]
  else:
    raise new_exception(NotDefinedException, %key & " is not defined")

proc locate*(self: Namespace, key: MapKey): (GeneValue, Namespace) {.inline.} =
  if self.has_key(key):
    result = (self.members[key], self)
  elif not self.stop_inheritance and self.parent != nil:
    result = self.parent.locate(key)
  else:
    not_allowed()

proc `[]`*(self: Namespace, key: string): GeneValue {.inline.} =
  result = self[key.to_key]

proc `[]=`*(self: var Namespace, key: MapKey, val: GeneValue) {.inline.} =
  self.members[key] = val

proc `[]=`*(self: var Namespace, key: string, val: GeneValue) {.inline.} =
  self.members[key.to_key] = val

#################### Scope #######################

proc new_scope*(): Scope = Scope(
  members: @[],
  mappings: Table[MapKey, seq[NameIndexScope]](),
)

proc max*(self: Scope): NameIndexScope {.inline.} =
  return self.members.len

proc set_parent*(self: var Scope, parent: Scope, max: NameIndexScope) {.inline.} =
  self.parent = parent
  self.parent_index_max = max

proc reset*(self: var Scope) {.inline.} =
  self.parent = nil
  self.members.setLen(0)

proc has_key(self: Scope, key: MapKey, max: int): bool {.inline.} =
  if self.mappings.has_key(key):
    # If first >= max, all others will be >= max
    if self.mappings[key][0] < max:
      return true

  if self.parent != nil:
    return self.parent.has_key(key, self.parent_index_max)

proc has_key*(self: Scope, key: MapKey): bool {.inline.} =
  if self.mappings.has_key(key):
    return true
  elif self.parent != nil:
    return self.parent.has_key(key, self.parent_index_max)

proc def_member*(self: var Scope, key: MapKey, val: GeneValue) {.inline.} =
  var index = self.members.len
  self.members.add(val)
  if self.mappings.has_key(key):
    self.mappings[key].add(index)
  else:
    self.mappings[key] = @[cast[NameIndexScope](index)]

proc `[]`(self: Scope, key: MapKey, max: int): GeneValue {.inline.} =
  if self.mappings.has_key(key):
    var found = self.mappings[key]
    var i = found.len - 1
    while i >= 0:
      var index: int = found[i]
      if index < max:
        return self.members[index]
      i -= 1

  if self.parent != nil:
    return self.parent[key, self.parent_index_max]

proc `[]`*(self: Scope, key: MapKey): GeneValue {.inline.} =
  if self.mappings.has_key(key):
    var i: int = self.mappings[key][^1]
    return self.members[i]
  elif self.parent != nil:
    return self.parent[key, self.parent_index_max]

proc `[]=`(self: var Scope, key: MapKey, val: GeneValue, max: int) {.inline.} =
  if self.mappings.has_key(key):
    var found = self.mappings[key]
    var i = found.len - 1
    while i >= 0:
      var index: int = found[i]
      if index < max:
        self.members[i] = val
        return
      i -= 1

  if self.parent != nil:
    self.parent.`[]=`(key, val, self.parent_index_max)
  else:
    not_allowed()

proc `[]=`*(self: var Scope, key: MapKey, val: GeneValue) {.inline.} =
  if self.mappings.has_key(key):
    var i: int = self.mappings[key][^1]
    self.members[i] = val
  elif self.parent != nil:
    self.parent.`[]=`(key, val, self.parent_index_max)
  else:
    not_allowed()

#################### Frame #######################

proc new_frame*(): Frame = Frame(
  self: GeneNil,
)

proc reset*(self: var Frame) {.inline.} =
  self.self = nil
  self.ns = nil
  self.scope = nil
  self.extra = nil

proc `[]`*(self: Frame, name: MapKey): GeneValue {.inline.} =
  result = self.scope[name]
  if result == nil:
    return self.ns[name]

proc `[]`*(self: Frame, name: GeneValue): GeneValue {.inline.} =
  case name.kind:
  of GeneSymbol:
    result = self[name.symbol.to_key]
  of GeneComplexSymbol:
    var csymbol = name.csymbol
    if csymbol.first == "global":
      result = VM.app.ns
    elif csymbol.first == "gene":
      result = VM.gene_ns
    elif csymbol.first == "genex":
      result = VM.genex_ns
    elif csymbol.first == "":
      result = self.ns
    else:
      result = self[csymbol.first.to_key]
    for csymbol in csymbol.rest:
      result = result.get_member(csymbol)
  else:
    todo()

#################### Function ####################

proc new_fn*(name: string, matcher: RootMatcher, body: seq[GeneValue]): Function =
  return Function(
    name: name,
    matcher: matcher,
    body: body,
  )

#################### Macro #######################

proc new_macro*(name: string, matcher: RootMatcher, body: seq[GeneValue]): Macro =
  return Macro(
    name: name,
    matcher: matcher,
    body: body,
  )

#################### Block #######################

proc new_block*(matcher: RootMatcher,  body: seq[GeneValue]): Block =
  return Block(matcher: matcher, body: body)

#################### Return ######################

proc new_return*(): Return =
  return Return()

#################### Class #######################

proc new_class*(name: string): Class =
  return Class(
    name: name,
    ns: new_namespace(nil, name),
  )

proc get_method*(self: Class, name: MapKey): Method =
  if self.methods.has_key(name):
    return self.methods[name]
  elif self.parent != nil:
    return self.parent.get_method(name)

#################### Method ######################

proc new_method*(class: Class, name: string, fn: Function): Method =
  return Method(
    class: class,
    name: name,
    fn: fn,
  )

#################### ComplexSymbol ###############

proc all*(self: ComplexSymbol): seq[string] =
  result = @[self.first]
  for name in self.rest:
    result.add(name)

proc last*(self: ComplexSymbol): string =
  return self.rest[^1]

proc `==`*(this, that: ComplexSymbol): bool =
  return this.first == that.first and this.rest == that.rest

#################### Enum ########################

proc new_enum*(name: string): Enum =
  return Enum(name: name)

proc `[]`*(self: Enum, name: string): GeneValue =
  return new_gene_internal(self.members[name])

proc add_member*(self: var Enum, name: string, value: int) =
  self.members[name] = EnumMember(parent: self, name: name, value: value)

proc `==`*(this, that: EnumMember): bool =
  return this.parent == that.parent and this.name == that.name

#################### GeneTime ####################

proc `==`*(this, that: GeneTime): bool =
  return this.hour == that.hour and
    this.minute == that.minute and
    this.second == that.second and
    this.timezone == that.timezone

#################### GeneValue ###################

proc symbol_or_str*(self: GeneValue): string =
  case self.kind:
  of GeneSymbol:
    return self.symbol
  of GeneString:
    return self.str
  else:
    not_allowed()

proc get_member*(self: GeneValue, name: string): GeneValue =
  case self.kind:
  of GeneInternal:
    case self.internal.kind:
    of GeneNamespace:
      return self.internal.ns[name.to_key]
    of GeneClass:
      return self.internal.class.ns[name.to_key]
    of GeneEnum:
      return self.internal.enum[name]
    of GeneEnumMember:
      case name:
      of "parent":
        return self.internal.enum_member.parent
      of "name":
        return self.internal.enum_member.name
      of "value":
        return self.internal.enum_member.value
      else:
        not_allowed()
    else:
      todo()
  else:
    todo()

proc table_equals*(this, that: OrderedTable): bool =
  return this.len == 0 and that.len == 0 or
    this.len > 0 and that.len > 0 and this == that

proc `==`*(this, that: GeneValue): bool =
  if this.is_nil:
    if that.is_nil: return true
    return false
  elif that.is_nil or this.kind != that.kind:
    return false
  else:
    case this.kind
    of GeneAny:
      return this.any == that.any
    of GeneNilKind, GenePlaceholderKind:
      return true
    of GeneBool:
      return this.bool == that.bool
    of GeneChar:
      return this.char == that.char
    of GeneInt:
      return this.int == that.int
    of GeneRatio:
      return this.ratio == that.ratio
    of GeneFloat:
      return this.float == that.float
    of GeneString:
      return this.str == that.str
    of GeneSymbol:
      return this.symbol == that.symbol
    of GeneComplexSymbol:
      return this.csymbol == that.csymbol
    of GeneDate, GeneDateTime:
      return this.date == that.date
    of GeneTimeKind:
      return this.time == that.time
    of GeneTimezone:
      return this.timezone == that.timezone
    of GeneSet:
      return this.set.len == that.set.len and (this.set.len == 0 or this.set == that.set)
    of GeneGene:
      return this.gene.type == that.gene.type and
        this.gene.data == that.gene.data and
        table_equals(this.gene.props, that.gene.props)
    of GeneMap:
      return table_equals(this.map, that.map)
    of GeneVector:
      return this.vec == that.vec
    of GeneStream:
      return this.stream == that.stream
    of GeneRegex:
      return this.regex == that.regex
    of GeneRange:
      return this.range_start      == that.range_start      and
             this.range_end        == that.range_end        and
             this.range_incl_start == that.range_incl_start and
             this.range_incl_end   == that.range_incl_end
    of GeneInternal:
      case this.internal.kind:
      of GeneNamespace:
        return this.internal.ns == that.internal.ns
      else:
        todo()

proc hash*(node: GeneValue): Hash =
  var h: Hash = 0
  h = h !& hash(node.kind)
  case node.kind
  of GeneAny:
    todo()
  of GeneNilKind, GenePlaceholderKind:
    discard
  of GeneBool:
    h = h !& hash(node.bool)
  of GeneChar:
    h = h !& hash(node.char)
  of GeneInt:
    h = h !& hash(node.int)
  of GeneRatio:
    h = h !& hash(node.ratio)
  of GeneFloat:
    h = h !& hash(node.float)
  of GeneString:
    h = h !& hash(node.str)
  of GeneSymbol:
    h = h !& hash(node.symbol)
  of GeneComplexSymbol:
    h = h !& hash(node.csymbol.first & "/" & node.csymbol.rest.join("/"))
  of GeneDate, GeneDateTime:
    todo($node.internal.kind)
  of GeneTimeKind:
    todo($node.internal.kind)
  of GeneTimezone:
    todo($node.internal.kind)
  of GeneSet:
    h = h !& hash(node.set)
  of GeneGene:
    if node.gene.type != nil:
      h = h !& hash(node.gene.type)
    h = h !& hash(node.gene.data)
  of GeneMap:
    for key, val in node.map:
      h = h !& hash(key)
      h = h !& hash(val)
  of GeneVector:
    h = h !& hash(node.vec)
  of GeneStream:
    h = h !& hash(node.stream)
  of GeneRegex:
    todo()
  of GeneRange:
    h = h !& hash(node.range_start) !& hash(node.range_end)
  of GeneInternal:
    todo($node.internal.kind)
  result = !$h

proc is_literal*(self: GeneValue): bool =
  case self.kind:
  of GeneBool, GeneNilKind, GeneInt, GeneFloat, GeneRatio:
    return true
  else:
    return false

proc `$`*(node: GeneValue): string =
  if node.isNil:
    return "nil"
  case node.kind
  of GeneNilKind:
    result = "nil"
  of GeneBool:
    result = $(node.bool)
  of GeneInt:
    result = $(node.int)
  of GeneFloat:
    result = $(node.float)
  of GeneString:
    result = "\"" & node.str.replace("\"", "\\\"") & "\""
  of GeneSymbol:
    result = node.symbol
  of GeneComplexSymbol:
    if node.csymbol.first == "":
      result = "/" & node.csymbol.rest.join("/")
    else:
      result = node.csymbol.first & "/" & node.csymbol.rest.join("/")
  of GeneDate:
    result = node.date.format("yyyy-MM-dd")
  of GeneDateTime:
    result = node.date.format("yyyy-MM-dd'T'HH:mm:sszzz")
  of GeneTimeKind:
    result = &"{node.time.hour:02}:{node.time.minute:02}:{node.time.second:02}"
  of GeneVector:
    result = "["
    result &= node.vec.join(" ")
    result &= "]"
  of GeneGene:
    result = "(" & $node.gene.type
    if node.gene.props.len > 0:
      for k, v in node.gene.props:
        result &= " ^" & k.to_s & " " & $v
    if node.gene.data.len > 0:
      result &= " " & node.gene.data.join(" ")
    result &= ")"
  of GeneInternal:
    case node.internal.kind:
    of GeneFunction:
      result = "(fn $# ...)" % [node.internal.fn.name]
    of GeneMacro:
      result = "(macro $# ...)" % [node.internal.mac.name]
    of GeneNamespace:
      result = "(ns $# ...)" % [node.internal.ns.name]
    of GeneClass:
      result = "(class $# ...)" % [node.internal.class.name]
    of GeneInstance:
      result = "($# ...)" % [node.internal.instance.class.name]
    else:
      result = "GeneInternal"
  else:
    result = $node.kind

proc to_s*(self: GeneValue): string =
  return case self.kind:
    of GeneNilKind: ""
    of GeneString: self.str
    else: $self

proc `%`*(self: GeneValue): JsonNode =
  case self.kind:
  of GeneNilKind:
    return newJNull()
  of GeneBool:
    return %self.bool
  of GeneInt:
    return %self.int
  of GeneString:
    return %self.str
  of GeneVector:
    result = newJArray()
    for item in self.vec:
      result.add(%item)
  of GeneMap:
    result = newJObject()
    for k, v in self.map:
      result[k.to_s] = %v
  else:
    todo()

proc to_json*(self: GeneValue): string =
  return $(%self)

# proc to_xml*(self: GeneValue): string =
#   case self.kind:
#   of GeneGene:
#     result = "<" & $self.gene.type
#     for k, v in self.gene.props:
#       result &= k.to_s & $v
#     result &= ">"
#     for child in self.gene.data:
#       result &= child.to_xml
#     result &= "</" & $self.gene.type & ">"
#   else:
#     result = $self

proc `[]`*(self: OrderedTable[MapKey, GeneValue], key: string): GeneValue =
  self[key.to_key]

proc `[]=`*(self: var OrderedTable[MapKey, GeneValue], key: string, value: GeneValue) =
  self[key.to_key] = value

#################### AOP #########################

proc new_aspect*(name: string, matcher: RootMatcher, body: seq[GeneValue]): Aspect =
  return Aspect(
    name: name,
    matcher: matcher,
    body: body,
  )

proc new_aspect_instance*(aspect: Aspect, target: GeneValue): AspectInstance =
  return AspectInstance(
    aspect: aspect,
    target: target,
  )

proc new_advice*(kind: AdviceKind, logic: Function): Advice =
  return Advice(
    kind: kind,
    logic: logic,
  )

#################### Constructors ################

proc new_gene_any*(v: pointer): GeneValue =
  return GeneValue(kind: GeneAny, any: v)

proc new_gene_any*(v: pointer, `type`: MapKey): GeneValue =
  return GeneValue(kind: GeneAny, any: v, any_type: `type`)

proc new_gene_any*(v: pointer, `type`: string): GeneValue =
  return GeneValue(kind: GeneAny, any: v, any_type: `type`.to_key)

proc new_gene_string*(s: string): GeneValue {.gcsafe.} =
  return GeneValue(kind: GeneString, str: s)

proc new_gene_string_move*(s: string): GeneValue =
  result = GeneValue(kind: GeneString)
  shallowCopy(result.str, s)

proc new_gene_int*(s: string): GeneValue =
  return GeneValue(kind: GeneInt, int: parseBiggestInt(s))

proc new_gene_int*(val: BiggestInt): GeneValue =
  # return GeneValue(kind: GeneInt, int: val)
  if val > 100 or val < -10:
    return GeneValue(kind: GeneInt, int: val)
  else:
    return GeneInts[val + 10]

proc new_gene_ratio*(nom, denom: BiggestInt): GeneValue =
  return GeneValue(kind: GeneRatio, ratio: (nom, denom))

proc new_gene_float*(s: string): GeneValue =
  return GeneValue(kind: GeneFloat, float: parseFloat(s))

proc new_gene_float*(val: float): GeneValue =
  return GeneValue(kind: GeneFloat, float: val)

proc new_gene_bool*(val: bool): GeneValue =
  case val
  of true: return GeneTrue
  of false: return GeneFalse
  # of true: return GeneValue(kind: GeneBool, boolVal: true)
  # of false: return GeneValue(kind: GeneBool, boolVal: false)

proc new_gene_bool*(s: string): GeneValue =
  let parsed: bool = parseBool(s)
  return new_gene_bool(parsed)

proc new_gene_char*(c: char): GeneValue =
  return GeneValue(kind: GeneChar, char: c)

proc new_gene_char*(c: Rune): GeneValue =
  return GeneValue(kind: GeneChar, rune: c)

proc new_gene_symbol*(name: string): GeneValue =
  return GeneValue(kind: GeneSymbol, symbol: name)

proc new_gene_complex_symbol*(first: string, rest: seq[string]): GeneValue =
  return GeneValue(kind: GeneComplexSymbol, csymbol: ComplexSymbol(first: first, rest: rest))

proc new_gene_regex*(regex: string, flags: set[RegexFlag] = {reStudy}): GeneValue =
  return GeneValue(kind: GeneRegex, regex: re(regex, flags))

proc new_gene_range*(rstart: GeneValue, rend: GeneValue): GeneValue =
  return GeneValue(
    kind: GeneRange,
    range_start: rstart,
    range_end: rend,
    range_incl_start: true,
    range_incl_end: false,
  )

proc new_gene_date*(year, month, day: int): GeneValue =
  return GeneValue(
    kind: GeneDate,
    date_internal: MyDateTime(date: init_date_time(day, cast[Month](month), year, 0, 0, 0, utc())),
  )

proc new_gene_date*(date: DateTime): GeneValue =
  return GeneValue(
    kind: GeneDate,
    date_internal: MyDateTime(date: date),
  )

proc new_gene_datetime*(date: DateTime): GeneValue =
  return GeneValue(
    kind: GeneDateTime,
    date_internal: MyDateTime(date: date),
  )

proc new_gene_time*(hour, min, sec: int): GeneValue =
  return GeneValue(
    kind: GeneTimeKind,
    time: GeneTime(hour: hour, minute: min, second: sec, timezone: utc()),
  )

proc new_gene_vec*(items: seq[GeneValue]): GeneValue {.gcsafe.} =
  return GeneValue(
    kind: GeneVector,
    vec: items,
  )

proc new_gene_vec*(items: varargs[GeneValue]): GeneValue = new_gene_vec(@items)

proc new_gene_stream*(items: seq[GeneValue]): GeneValue =
  return GeneValue(
    kind: GeneStream,
    stream: items,
  )

proc new_gene_map*(): GeneValue =
  return GeneValue(
    kind: GeneMap,
    map: OrderedTable[MapKey, GeneValue](),
  )

converter new_gene_map*(self: OrderedTable[string, GeneValue]): GeneValue =
  return GeneValue(
    kind: GeneMap,
    map: self,
  )

proc new_gene_set*(items: varargs[GeneValue]): GeneValue =
  result = GeneValue(
    kind: GeneSet,
    set: OrderedSet[GeneValue](),
  )
  for item in items:
    result.set.incl(item)

proc new_gene_map*(map: OrderedTable[MapKey, GeneValue]): GeneValue =
  return GeneValue(
    kind: GeneMap,
    map: map,
  )

proc new_gene_gene*(): GeneValue =
  return GeneValue(
    kind: GeneGene,
    gene: Gene(type: GeneNil),
  )

# proc new_gene_gene_simple*(`type`: GeneValue): GeneValue =
#   return GeneValue(
#     kind: GeneGene,
#     gene_type: `type`,
#   )

proc new_gene_gene*(`type`: GeneValue, data: varargs[GeneValue]): GeneValue =
  return GeneValue(
    kind: GeneGene,
    gene: Gene(type: `type`, data: @data),
  )

proc new_gene_gene*(`type`: GeneValue, props: OrderedTable[MapKey, GeneValue], data: varargs[GeneValue]): GeneValue =
  return GeneValue(
    kind: GeneGene,
    gene: Gene(type: `type`, props: props, data: @data),
  )

converter new_gene_internal*(e: Enum): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneEnum, `enum`: e),
  )

converter new_gene_internal*(m: EnumMember): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneEnumMember, enum_member: m),
  )

converter new_gene_internal*(app: Application): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneApplication, app: app),
  )

converter new_gene_internal*(pkg: Package): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GenePackage, pkg: pkg),
  )

converter new_gene_internal*(fn: Function): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneFunction, fn: fn),
  )

converter new_gene_internal*(mac: Macro): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneMacro, mac: mac),
  )

converter new_gene_internal*(blk: Block): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneBlock, blk: blk),
  )

converter new_gene_internal*(ret: Return): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneReturn, ret: ret),
  )

converter new_gene_internal*(file: File): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneFile, file: file),
  )

converter new_gene_internal*(value: NativeFn): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneNativeFn, native_fn: value),
  )

proc new_mixin*(name: string): Mixin =
  return Mixin(name: name)

proc new_instance*(class: Class): Instance =
  return Instance(value: new_gene_gene(GeneNil), class: class)

converter new_gene_internal*(aspect: Aspect): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneAspect, aspect: aspect),
  )

converter new_gene_internal*(v: AspectInstance): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneAspectInstance, aspect_instance: v),
  )

converter new_gene_internal*(class: Class): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneClass, class: class),
  )

converter new_gene_internal*(mix: Mixin): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneMixin, mix: mix),
  )

converter new_gene_internal*(meth: Method): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneMethod, meth: meth),
  )

converter new_gene_instance*(instance: Instance): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneInstance, instance: instance),
  )

converter new_gene_internal*(ns: Namespace): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneNamespace, ns: ns),
  )

converter new_gene_internal*(sel: Selector): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneSelector, selector: sel),
  )

proc future_to_gene*(f: Future[GeneValue]): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneFuture, future: f),
  )

# Do not allow auto conversion between CatchableError and GeneValue
# because there are sub-classes of CatchableError that need to be
# handled differently.
proc error_to_gene*(ex: ref CatchableError): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneExceptionKind, exception: ex),
  )

proc new_gene_explode*(v: GeneValue): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneExplode, explode: v),
  )

#################### GeneValue ###################

proc is_truthy*(self: GeneValue): bool =
  case self.kind:
  of GeneBool:
    return self.bool
  of GeneNilKind:
    return false
  else:
    return true

proc merge*(self: var GeneValue, value: GeneValue) =
  case self.kind:
  of GeneGene:
    case value.kind:
    of GeneGene:
      for item in value.gene.data:
        self.gene.data.add(item)
      for k, v in value.gene.props:
        self.gene.props[k] = v
    of GeneVector:
      for item in value.vec:
        self.gene.data.add(item)
    of GeneMap:
      for k, v in value.map:
        self.gene.props[k] = v
    else:
      todo()
  of GeneVector:
    case value.kind:
    of GeneVector:
      for item in value.vec:
        self.gene.data.add(item)
    else:
      todo()
  else:
    todo()

#################### Document ####################

proc new_doc*(data: seq[GeneValue]): GeneDocument =
  return GeneDocument(data: data)

#################### Converters ##################

converter to_gene*(v: int): GeneValue                      = new_gene_int(v)
converter to_gene*(v: bool): GeneValue                     = new_gene_bool(v)
converter to_gene*(v: float): GeneValue                    = new_gene_float(v)
converter to_gene*(v: string): GeneValue                   = new_gene_string(v)
converter to_gene*(v: char): GeneValue                     = new_gene_char(v)
converter to_gene*(v: Rune): GeneValue                     = new_gene_char(v)
converter to_gene*(v: OrderedTable[MapKey, GeneValue]): GeneValue = new_gene_map(v)

# Below converter causes problem with the hash function
# converter to_gene*(v: seq[GeneValue]): GeneValue           = new_gene_vec(v)

converter to_bool*(v: GeneValue): bool =
  if v.isNil:
    return false
  case v.kind:
  of GeneNilKind:
    return false
  of GeneBool:
    return v.bool
  of GeneString:
    return v.str != ""
  else:
    return true

converter to_aspect*(node: GeneValue): Aspect =
  var first = node.gene.data[0]
  var name: string
  if first.kind == GeneSymbol:
    name = first.symbol
  elif first.kind == GeneComplexSymbol:
    name = first.csymbol.rest[^1]

  var matcher = new_arg_matcher()
  matcher.parse(node.gene.data[1])

  var body: seq[GeneValue] = @[]
  for i in 2..<node.gene.data.len:
    body.add node.gene.data[i]

  return new_aspect(name, matcher, body)

converter to_selector_matcher*(name: string): GeneValue =
  try:
    return parse_int(name)
  except ValueError:
    return name

converter to_selector_item*(name: string): SelectorItem =
  result = SelectorItem()
  try:
    var index = parse_int(name)
    result.matchers.add(SelectorMatcher(kind: SmByIndex, index: index))
  except ValueError:
    result.matchers.add(SelectorMatcher(kind: SmByName, name: name.to_key))

converter to_selector*(s: string): Selector =
  assert(s[0] == '@')
  result = Selector()
  result.children.add(to_selector_item(s[1..^1]))

converter to_selector*(s: ComplexSymbol): Selector =
  assert(s.first[0] == '@')
  result = Selector()
  var item = to_selector_item(s.first[1..^1])
  result.children.add(item)
  for part in s.rest:
    var child = to_selector_item(part)
    item.children.add(child)
    item = child

proc wrap_with_try*(body: seq[GeneValue]): seq[GeneValue] =
  var found_catch_or_finally = false
  for item in body:
    if item == Catch or item == Finally:
      found_catch_or_finally = true
  if found_catch_or_finally:
    return @[new_gene_gene(Try, body)]
  else:
    return body

converter to_function*(node: GeneValue): Function =
  case node.kind:
  of GeneInternal:
    if node.internal.kind == GeneFunction:
      return node.internal.fn
    else:
      not_allowed()
  of GeneGene:
    var first = node.gene.data[0]
    var name: string
    if first.kind == GeneSymbol:
      name = first.symbol
    elif first.kind == GeneComplexSymbol:
      name = first.csymbol.rest[^1]

    var matcher = new_arg_matcher()
    matcher.parse(node.gene.data[1])

    var body: seq[GeneValue] = @[]
    for i in 2..<node.gene.data.len:
      body.add node.gene.data[i]

    body = wrap_with_try(body)
    result = new_fn(name, matcher, body)
    result.async = node.gene.props.get_or_default(ASYNC_KEY, false)
  else:
    not_allowed()

converter to_macro*(node: GeneValue): Macro =
  var first = node.gene.data[0]
  var name: string
  if first.kind == GeneSymbol:
    name = first.symbol
  elif first.kind == GeneComplexSymbol:
    name = first.csymbol.rest[^1]

  var matcher = new_arg_matcher()
  matcher.parse(node.gene.data[1])

  var body: seq[GeneValue] = @[]
  for i in 2..<node.gene.data.len:
    body.add node.gene.data[i]

  body = wrap_with_try(body)
  return new_macro(name, matcher, body)

converter to_block*(node: GeneValue): Block =
  var matcher = new_arg_matcher()
  if node.gene.props.has_key(ARGS_KEY):
    matcher.parse(node.gene.props[ARGS_KEY])
  var body: seq[GeneValue] = @[]
  for i in 0..<node.gene.data.len:
    body.add node.gene.data[i]

  body = wrap_with_try(body)
  return new_block(matcher, body)

converter json_to_gene*(node: JsonNode): GeneValue =
  case node.kind:
  of JNull:
    return GeneNil
  of JBool:
    return node.bval
  of JInt:
    return node.num
  of JFloat:
    return node.fnum
  of JString:
    return node.str
  of JObject:
    result = new_gene_map()
    for k, v in node.fields:
      result.map[k.to_key] = v.json_to_gene
  of JArray:
    result = new_gene_vec()
    for elem in node.elems:
      result.vec.add(elem.json_to_gene)

proc get_class*(val: GeneValue): Class =
  case val.kind:
  of GeneInternal:
    case val.internal.kind:
    of GeneApplication:
      return VM.gene_ns.internal.ns[APPLICATION_CLASS_KEY].internal.class
    of GenePackage:
      return VM.gene_ns.internal.ns[PACKAGE_CLASS_KEY].internal.class
    of GeneInstance:
      return val.internal.instance.class
    of GeneClass:
      return VM.gene_ns.internal.ns[CLASS_CLASS_KEY].internal.class
    of GeneNamespace:
      return VM.gene_ns.internal.ns[NAMESPACE_CLASS_KEY].internal.class
    of GeneFuture:
      return VM.gene_ns.internal.ns[FUTURE_CLASS_KEY].internal.class
    of GeneFile:
      return VM.gene_ns.internal.ns[FILE_CLASS_KEY].internal.class
    of GeneExceptionKind:
      var ex = val.internal.exception
      if ex is GeneException:
        var ex = cast[GeneException](ex)
        if ex.instance != nil:
          return ex.instance.internal.class
        else:
          return GeneExceptionClass.internal.class
      # elif ex is CatchableError:
      #   var nim = VM.app.ns[NIM_KEY]
      #   return nim.internal.ns[CATCHABLE_ERROR_KEY].internal.class
      else:
        return GeneExceptionClass.internal.class
    else:
      todo()
  of GeneNilKind:
    return VM.gene_ns.internal.ns[NIL_CLASS_KEY].internal.class
  of GeneBool:
    return VM.gene_ns.internal.ns[BOOL_CLASS_KEY].internal.class
  of GeneInt:
    return VM.gene_ns.internal.ns[INT_CLASS_KEY].internal.class
  of GeneChar:
    return VM.gene_ns.internal.ns[CHAR_CLASS_KEY].internal.class
  of GeneString:
    return VM.gene_ns.internal.ns[STRING_CLASS_KEY].internal.class
  of GeneSymbol:
    return VM.gene_ns.internal.ns[SYMBOL_CLASS_KEY].internal.class
  of GeneComplexSymbol:
    return VM.gene_ns.internal.ns[COMPLEX_SYMBOL_CLASS_KEY].internal.class
  of GeneVector:
    return VM.gene_ns.internal.ns[ARRAY_CLASS_KEY].internal.class
  of GeneMap:
    return VM.gene_ns.internal.ns[MAP_CLASS_KEY].internal.class
  of GeneSet:
    return VM.gene_ns.internal.ns[SET_CLASS_KEY].internal.class
  of GeneGene:
    return VM.gene_ns.internal.ns[GENE_CLASS_KEY].internal.class
  of GeneRegex:
    return VM.gene_ns.internal.ns[REGEX_CLASS_KEY].internal.class
  of GeneRange:
    return VM.gene_ns.internal.ns[RANGE_CLASS_KEY].internal.class
  of GeneDate:
    return VM.gene_ns.internal.ns[DATE_CLASS_KEY].internal.class
  of GeneDateTime:
    return VM.gene_ns.internal.ns[DATETIME_CLASS_KEY].internal.class
  of GeneTimeKind:
    return VM.gene_ns.internal.ns[TIME_CLASS_KEY].internal.class
  of GeneTimezone:
    return VM.gene_ns.internal.ns[TIMEZONE_CLASS_KEY].internal.class
  of GeneAny:
    if val.any_type == HTTP_REQUEST_KEY:
      return VM.genex_ns.internal.ns[HTTP_KEY].internal.ns[REQUEST_CLASS_KEY].internal.class
    else:
      todo()
  else:
    todo()

proc is_a*(self: GeneValue, class: Class): bool =
  var my_class = self.get_class
  while true:
    if my_class == class:
      return true
    if my_class.parent == nil:
      return false
    else:
      my_class = my_class.parent

#################### Pattern Matching ############

proc new_match_matcher*(): RootMatcher =
  result = RootMatcher(
    mode: MatchExpression,
  )

proc new_arg_matcher*(): RootMatcher =
  result = RootMatcher(
    mode: MatchArgParsing,
  )

proc new_matcher(root: RootMatcher, kind: MatcherKind): Matcher =
  result = Matcher(
    root: root,
    kind: kind,
  )

proc new_matched_field(name: MapKey, value: GeneValue): MatchedField =
  result = MatchedField(
    name: name,
    value: value,
  )

proc required(self: Matcher): bool =
  return self.default_value == nil and not self.splat

proc props(self: seq[Matcher]): HashSet[MapKey] =
  for m in self:
    if m.kind == MatchProp and not m.splat:
      result.incl(m.name)

proc prop_splat(self: seq[Matcher]): MapKey =
  for m in self:
    if m.kind == MatchProp and m.splat:
      return m.name

#################### Parsing #####################

proc calc_min_left*(self: var Matcher) =
  var min_left = 0
  var i = self.children.len
  while i > 0:
    i -= 1
    var m = self.children[i]
    m.min_left = min_left
    if m.required:
      min_left += 1

proc calc_min_left*(self: var RootMatcher) =
  var min_left = 0
  var i = self.children.len
  while i > 0:
    i -= 1
    var m = self.children[i]
    m.calc_min_left
    m.min_left = min_left
    if m.required:
      min_left += 1

proc parse(self: var RootMatcher, group: var seq[Matcher], v: GeneValue) =
  case v.kind:
  of GeneSymbol:
    if v.symbol[0] == '^':
      var m = new_matcher(self, MatchProp)
      if v.symbol.ends_with("..."):
        m.name = v.symbol[1..^4].to_key
        m.splat = true
      else:
        m.name = v.symbol[1..^1].to_key
      group.add(m)
    else:
      var m = new_matcher(self, MatchData)
      group.add(m)
      if v.symbol != "_":
        if v.symbol.endsWith("..."):
          m.name = v.symbol[0..^4].to_key
          m.splat = true
        else:
          m.name = v.symbol.to_key
  of GeneVector:
    var i = 0
    while i < v.vec.len:
      var item = v.vec[i]
      i += 1
      if item.kind == GeneVector:
        var m = new_matcher(self, MatchData)
        group.add(m)
        self.parse(m.children, item)
      else:
        self.parse(group, item)
        if i < v.vec.len and v.vec[i] == new_gene_symbol("="):
          i += 1
          var last_matcher = group[^1]
          var value = v.vec[i]
          i += 1
          last_matcher.default_value = value
  else:
    todo()

proc parse*(self: var RootMatcher, v: GeneValue) =
  if v == new_gene_symbol("_"):
    return
  self.parse(self.children, v)
  self.calc_min_left

#################### Matching ####################

proc `[]`*(self: GeneValue, i: int): GeneValue =
  case self.kind:
  of GeneGene:
    return self.gene.data[i]
  of GeneVector:
    return self.vec[i]
  else:
    not_allowed()

proc `len`(self: GeneValue): int =
  if self == nil:
    return 0
  case self.kind:
  of GeneGene:
    return self.gene.data.len
  of GeneVector:
    return self.vec.len
  else:
    not_allowed()

proc match_prop_splat*(self: seq[Matcher], input: GeneValue, r: MatchResult) =
  if input == nil or self.prop_splat == EMPTY_STRING_KEY:
    return

  var map: OrderedTable[MapKey, GeneValue]
  case input.kind:
  of GeneMap:
    map = input.map
  of GeneGene:
    map = input.gene.props
  else:
    return

  var splat = OrderedTable[MapKey, GeneValue]()
  for k, v in map:
    if k notin self.props:
      splat[k] = v
  r.fields.add(new_matched_field(self.prop_splat, new_gene_map(splat)))

proc match(self: Matcher, input: GeneValue, state: MatchState, r: MatchResult) =
  case self.kind:
  of MatchData:
    var value: GeneValue
    var value_expr: Expr
    if self.splat:
      value = new_gene_vec()
      for i in state.data_index..<input.len - self.min_left:
        value.vec.add(input[i])
        state.data_index += 1
    elif self.min_left < input.len - state.data_index:
      value = input[state.data_index]
      state.data_index += 1
    else:
      if self.default_value == nil:
        r.kind = MatchMissingFields
        r.missing.add(self.name)
        return
      elif self.default_value_expr != nil:
        value_expr = self.default_value_expr
      else:
        value = self.default_value # Default value
    if self.name != EMPTY_STRING_KEY:
      var matched_field = new_matched_field(self.name, value)
      matched_field.value_expr = value_expr
      r.fields.add(matched_field)
    var child_state = MatchState()
    for child in self.children:
      child.match(value, child_state, r)
    match_prop_splat(self.children, value, r)
  of MatchProp:
    var value: GeneValue
    var value_expr: Expr
    if self.splat:
      return
    elif input.gene.props.has_key(self.name):
      value = input.gene.props[self.name]
    else:
      if self.default_value == nil:
        r.kind = MatchMissingFields
        r.missing.add(self.name)
        return
      elif self.default_value_expr != nil:
        value_expr = self.default_value_expr
      else:
        value = self.default_value # Default value
    var matched_field = new_matched_field(self.name, value)
    matched_field.value_expr = value_expr
    r.fields.add(matched_field)
  else:
    todo()

proc match*(self: RootMatcher, input: GeneValue): MatchResult =
  result = MatchResult()
  var children = self.children
  var state = MatchState()
  for child in children:
    child.match(input, state, result)
  match_prop_splat(children, input, result)

#################### Import ######################

proc parse*(self: ImportMatcherRoot, input: GeneValue, group: ptr seq[ImportMatcher]) =
  var data: seq[GeneValue]
  case input.kind:
  of GeneGene:
    data = input.gene.data
  of GeneVector:
    data = input.vec
  else:
    todo()

  var i = 0
  while i < data.len:
    var item = data[i]
    i += 1
    case item.kind:
    of GeneSymbol:
      if item.symbol == "from":
        self.from = data[i]
        i += 1
      else:
        group[].add(ImportMatcher(name: item.symbol.to_key))
    of GeneComplexSymbol:
      var names: seq[string] = @[]
      names.add(item.csymbol.first)
      for item in item.csymbol.rest:
        names.add(item)

      var matcher: ImportMatcher
      var my_group = group
      var j = 0
      while j < names.len:
        var name = names[j]
        j += 1
        if name == "": # TODO: throw error if "" is not the last
          self.parse(data[i], matcher.children.addr)
          i += 1
        else:
          matcher = ImportMatcher(name: name.to_key)
          matcher.children_only = j < names.len
          my_group[].add(matcher)
          my_group = matcher.children.addr
    else:
      todo()

proc new_import_matcher*(v: GeneValue): ImportMatcherRoot =
  result = ImportMatcherRoot()
  result.parse(v, result.children.addr)

#################### FrameManager ################

proc get*(self: var FrameManager, kind: FrameKind, ns: Namespace, scope: Scope): Frame {.inline.} =
  if self.cache.len > 0:
    result = self.cache.pop()
  else:
    result = new_frame()
  result.parent = nil
  result.ns = ns
  result.scope = scope
  result.extra = FrameExtra(kind: kind)

proc free*(self: var FrameManager, frame: var Frame) {.inline.} =
  frame.reset()
  self.cache.add(frame)

#################### EvaluatorManager ############

proc `[]`*(self: EvaluatorManager, key: ExprKind): Evaluator =
  if self.mappings.has_key(key):
    return self.mappings[key]

proc `[]=`*(self: EvaluatorManager, key: ExprKind, e: Evaluator) =
  self.mappings[key] = e

# #################### Dynamic #####################

# proc load_dynamic*(path:string, names: seq[string]): OrderedTable[MapKey, NativeFn] =
#   result = OrderedTable[MapKey, NativeFn]()
#   let lib = loadLib(path)
#   for name in names:
#     var s = name
#     let fn = lib.symAddr(s)
#     result[s.to_key] = cast[NativeFn](fn)

#################### Selector ####################

proc new_selector*(): Selector =
  result = Selector()

proc gene_to_selector_item*(v: GeneValue): SelectorItem =
  case v.kind:
  of GeneInternal:
    case v.internal.kind:
    of GeneSelector:
      result = SelectorItem(
        kind: SiSelector,
        selector: v.internal.selector,
      )
    of GeneFunction:
      result = SelectorItem()
      result.matchers.add(SelectorMatcher(kind: SmCallback, callback: v.internal.fn))
    else:
      todo($v.internal.kind)
  of GeneInt:
    result = SelectorItem()
    result.matchers.add(SelectorMatcher(kind: SmByIndex, index: v.int))
  of GeneString:
    result = SelectorItem()
    result.matchers.add(SelectorMatcher(kind: SmByName, name: v.str.to_key))
  of GeneSymbol:
    result = SelectorItem()
    result.matchers.add(SelectorMatcher(kind: SmByType, by_type: v))
  of GenePlaceholderKind:
    result = SelectorItem()
    result.matchers.add(SelectorMatcher(kind: SmSelfAndDescendants))
  of GeneVector:
    result = SelectorItem()
    for item in v.vec:
      case item.kind:
      of GeneInt:
        result.matchers.add(SelectorMatcher(kind: SmByIndex, index: item.int))
      of GeneString:
        result.matchers.add(SelectorMatcher(kind: SmByName, name: item.str.to_key))
      of GeneSymbol:
        result.matchers.add(SelectorMatcher(kind: SmByType, by_type: item))
      else:
        todo()
  else:
    todo($v.kind)

# Definition
proc is_singular*(self: Selector): bool

proc is_singular*(self: SelectorItem): bool =
  case self.kind:
  of SiDefault:
    if self.matchers.len > 1:
      return false
    if self.matchers[0].kind notin [SmByIndex, SmByName]:
      return false
    case self.children.len:
    of 0:
      return true
    of 1:
      return self.children[0].is_singular()
    else:
      return false
  of SiSelector:
    result = self.selector.is_singular()

proc is_singular*(self: Selector): bool =
  result = self.children.len == 1 and self.children[0].is_singular()

proc is_last*(self: SelectorItem): bool =
  result = self.children.len == 0

#################### Command Line Arg Parsing ####

proc new_cmd_args_matcher*(): ArgMatcherRoot =
  return ArgMatcherRoot(
    options: Table[string, ArgMatcher](),
  )

proc name*(self: ArgMatcher): string =
  case self.kind:
  of ArgOption:
    if self.long_name == "":
      return self.short_name
    else:
      return self.long_name
  of ArgPositional:
    return self.arg_name

proc default_value*(self: ArgMatcher): GeneValue =
  case self.data_type:
  of ArgInt:
    if self.default == nil:
      if self.multiple:
        return @[]
      else:
        return 0
    else:
      return self.default
  of ArgBool:
    if self.default == nil:
      if self.multiple:
        return @[]
      else:
        return false
    else:
      return self.default
  of ArgString:
    if self.default == nil:
      if self.multiple:
        return @[]
      else:
        return ""
    else:
      return self.default

proc fields*(self: ArgMatchingResult): Table[string, GeneValue] =
  for k, v in self.options:
    result[k] = v
  for k, v in self.args:
    result[k] = v

proc parse_data_type(self: var ArgMatcher, input: GeneValue) =
  var value = input.gene.props.get_or_default(TYPE_KEY, nil)
  if value == new_gene_symbol("int"):
    self.data_type = ArgInt
  elif value == new_gene_symbol("bool"):
    self.data_type = ArgBool
  else:
    self.data_type = ArgString

proc parse*(self: var ArgMatcherRoot, schema: GeneValue) =
  if schema.vec.len == 0:
    return
  if schema.vec[0] == new_gene_symbol("program"):
    self.include_program = true
  for i, item in schema.vec:
    # Check whether first item is program
    if i == 0 and item == new_gene_symbol("program"):
      self.include_program = true
      continue

    case item.gene.type.symbol:
    of "option":
      var option = ArgMatcher(kind: ArgOption)
      option.parse_data_type(item)
      option.toggle = item.gene.props.get_or_default(TOGGLE_KEY, false)
      if option.toggle:
        option.data_type = ArgBool
      else:
        option.multiple = item.gene.props.get_or_default(MULTIPLE_KEY, false)
        option.required = item.gene.props.get_or_default(REQUIRED_KEY, false)
      if item.gene.props.has_key(DEFAULT_KEY):
        option.default = item.gene.props[DEFAULT_KEY]
        option.required = false
      for item in item.gene.data:
        if item.symbol[0] == '-':
          if item.symbol.len == 2:
            option.short_name = item.symbol
          else:
            option.long_name = item.symbol
        else:
          option.description = item.str

      if option.short_name != "":
        self.options[option.short_name] = option
      if option.long_name != "":
        self.options[option.long_name] = option

    of "argument":
      var arg = ArgMatcher(kind: ArgPositional)
      arg.arg_name = item.gene.data[0].symbol
      if item.gene.props.has_key(DEFAULT_KEY):
        arg.default = item.gene.props[DEFAULT_KEY]
        arg.required = false
      arg.parse_data_type(item)
      var is_last = i == schema.vec.len - 1
      if is_last:
        arg.multiple = item.gene.props.get_or_default(MULTIPLE_KEY, false)
        arg.required = item.gene.props.get_or_default(REQUIRED_KEY, false)
      else:
        arg.required = true
      self.args.add(arg)

    else:
      not_allowed()

proc translate(self: ArgMatcher, value: string): GeneValue =
  if self.data_type == ArgInt:
    return value.parse_int
  elif self.data_type == ArgBool:
    return value.parse_bool
  else:
    return new_gene_string(value)

proc match*(self: var ArgMatcherRoot, input: seq[string]): ArgMatchingResult =
  result = ArgMatchingResult(kind: AmSuccess)
  var arg_index = 0

  var i = 0
  if self.include_program:
    result.program = input[i]
    i += 1
  var in_extra = false
  while i < input.len:
    var item = input[i]
    i += 1
    if in_extra:
      result.extra.add(item)
    elif item == "--":
      in_extra = true
      continue
    elif item[0] == '-':
      if self.options.has_key(item):
        var option = self.options[item]
        if option.toggle:
          result.options[option.name] = true
        else:
          var value = input[i]
          i += 1
          if option.multiple:
            for s in value.split(","):
              var v = option.translate(s)
              if result.options.has_key(option.name):
                result.options[option.name].vec.add(v)
              else:
                result.options[option.name] = @[v]
          else:
            result.options[option.name] = option.translate(value)
      else:
        echo "Unknown option: " & $item
    else:
      if arg_index < self.args.len:
        var arg = self.args[arg_index]
        var value = arg.translate(item)
        if arg.multiple:
          if result.args.has_key(arg.name):
            result.args[arg.name].vec.add(value)
          else:
            result.args[arg.name] = @[value]
        else:
          arg_index += 1
          result.args[arg.name] = value
      else:
        echo "Too many arguments are found. Ignoring " & $item

  # Assign values for mandatory options and arguments
  for _, v in self.options:
    if not result.options.has_key(v.name):
      if v.required:
        raise new_exception(ArgumentError, "Missing mandatory option: " & v.name)
      else:
        result.options[v.name] = v.default_value

  for v in self.args:
    if not result.args.has_key(v.name):
      if v.required:
        raise new_exception(ArgumentError, "Missing mandatory argument: " & v.name)
      else:
        result.args[v.name] = v.default_value

proc match*(self: var ArgMatcherRoot, input: string): ArgMatchingResult =
  var parts: seq[string]
  var s = strutils.strip(input, leading=true)
  if s.len > 0:
    parts = s.split(" ")
  return self.match(parts)
