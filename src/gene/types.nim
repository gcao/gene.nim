import strutils, tables, dynlib, unicode

const BINARY_OPS* = [
  "+", "-", "*", "/",
  "=", "+=", "-=", "*=", "/=",
  "==", "!=", "<", "<=", ">", ">=",
  "&&", "||", # TODO: xor
  "&",  "|",  # TODO: xor for bit operation
]

type
  ## This is the root of a running application
  Application* = ref object
    name*: string
    ns*: Namespace
    program*: string
    args*: seq[string]
    namespaces*: Table[string, Namespace]

  Module* = ref object
    name*: string
    root_ns*: Namespace
    name_mappings*: Table[string, int]
    names*: seq[string]

  Namespace* = ref object
    module*: Module
    parent*: Namespace
    name*: string
    name_key*: int
    members*: Table[int, GeneValue]

  Scope* = ref object
    parent*: Scope
    members*: Table[int, GeneValue]
    usage*: int

  Class* = ref object
    parent*: Class
    name*: string
    name_key*: int
    methods*: Table[string, Function]

  Mixin* = ref object
    name*: string
    name_key*: int
    methods*: Table[string, Function]

  Instance* = ref object
    class*: Class
    value*: GeneValue

  Function* = ref object
    ns*: Namespace
    parent_scope*: Scope
    name*: string
    name_key*: int
    matcher*: RootMatcher
    body*: seq[GeneValue]
    expr*: Expr # The function expression that will be the parent of body
    body_blk*: seq[Expr]

  Block* = ref object
    ns*: Namespace
    parent_scope*: Scope
    args*: seq[string]
    arg_keys*: seq[int]
    body*: seq[GeneValue]
    expr*: Expr # The function expression that will be the parent of body
    body_blk*: seq[Expr]

  Macro* = ref object
    ns*: Namespace
    name*: string
    name_key*: int
    args*: seq[string]
    arg_keys*: seq[int]
    body*: seq[GeneValue]
    expr*: Expr # The function expression that will be the parent of body

  Arguments* = ref object
    positional*: seq[GeneValue]

  GeneInternalKind* = enum
    GeneFunction
    GeneMacro
    GeneBlock
    GeneReturn
    GeneArguments
    GeneClass
    GeneMixin
    GeneInstance
    GeneNamespace
    GeneNativeProc

  Internal* = ref object
    case kind*: GeneInternalKind
    of GeneFunction:
      fn*: Function
    of GeneMacro:
      mac*: Macro
    of GeneBlock:
      blk*: Block
    of GeneReturn:
      ret*: Return
    of GeneArguments:
      args*: Arguments
    of GeneClass:
      class*: Class
    of GeneMixin:
      mix*: Mixin
    of GeneInstance:
      instance*: Instance
    of GeneNamespace:
      ns*: Namespace
    of GeneNativeProc:
      native_proc*: NativeProc

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
    op*: GeneValue
    props*: Table[string, GeneValue]
    data*: seq[GeneValue]
    # A gene can be normalized to match expected format
    # Example: (a = 1) => (= a 1)
    normalized*: bool

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
    GeneMap
    GeneVector
    GeneGene
    GeneInternal
    GeneAny
    GeneCommentLine

  CommentPlacement* = enum
    Before
    After
    Inside

  Comment* = ref object
    placement*: CommentPlacement
    comment_lines*: seq[string]

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
      regex*: string
    of GeneMap:
      map*: Table[string, GeneValue]
    of GeneVector:
      vec*: seq[GeneValue]
    of GeneGene:
      gene*: Gene
    of GeneInternal:
      internal*: Internal
    of GeneAny:
      any*: pointer
    of GeneCommentLine:
      comment*: string
    # line*: int
    # column*: int
    # comments*: seq[Comment]

  GeneDocument* = ref object
    name*: string
    path*: string
    data*: seq[GeneValue]

  NativeProc* = proc(args: seq[GeneValue]): GeneValue {.nimcall.}

  ExprKind* = enum
    ExTodo
    ExNotAllowed
    ExRoot
    ExLiteral
    ExSymbol
    ExComplexSymbol
    ExMap
    ExMapChild
    ExArray
    ExGene
    ExGroup
    ExVar
    ExAssignment
    ExBinary
    ExBinImmediate
    # ExBinImmediate2
    ExUnknown
    ExIf
    # ExIfElseIf
    ExLoop
    ExBreak
    ExWhile
    ExFn
    ExMacro
    ExBlock
    ExReturn
    ExReturnRef
    ExClass
    ExMixin
    ExNew
    ExInclude
    ExMethod
    ExInvokeMethod
    ExGetProp
    ExSetProp
    ExNamespace
    ExSelf
    ExGlobal
    ExImport
    ExCallNative
    ExGetClass
    ExQuote
    ExEval
    ExCallerEval
    ExMatch

  Expr* = ref object of RootObj
    module*: Module
    parent*: Expr
    posInParent*: int
    case kind*: ExprKind
    of ExTodo:
      todo*: Expr
    of ExNotAllowed:
      not_allowed*: Expr
    of ExRoot:
      root*: Expr
    of ExLiteral:
      literal*: GeneValue
    of ExSymbol:
      symbol*: string
      symbol_key*: int
    of ExComplexSymbol:
      csymbol*: ComplexSymbol
    of ExUnknown:
      unknown*: GeneValue
    of ExArray:
      array*: seq[Expr]
    of ExMap:
      map*: seq[Expr]
    of ExMapChild:
      map_key*: string
      map_val*: Expr
    of ExGene:
      gene*: GeneValue
      gene_op*: Expr
      gene_props*: seq[Expr]
      gene_data*: seq[Expr]
    of ExGroup:
      group*: seq[Expr]
    of ExVar, ExAssignment:
      # var_name*: string
      var_key*: int
      var_val*: Expr
    of ExBinary:
      bin_op*: BinOps
      bin_first*: Expr
      bin_second*: Expr
    of ExBinImmediate:
      bini_op*: BinOps
      bini_first*: Expr
      bini_second*: GeneValue
    of ExIf:
      if_cond*: Expr
      if_then*: Expr
      if_else*: Expr
    of ExLoop:
      loop_blk*: seq[Expr]
    of ExBreak:
      break_val*: Expr
    of ExWhile:
      while_cond*: Expr
      while_blk*: seq[Expr]
    of ExFn:
      fn*: GeneValue
    of ExBlock:
      blk*: GeneValue
    of ExMacro:
      mac*: GeneValue
    of ExReturn:
      return_val*: Expr
    of ExReturnRef:
      discard
    of ExClass:
      super_class*: Expr
      class*: GeneValue
      class_name*: GeneValue # The simple name or complex name that is associated with the class
      class_body*: seq[Expr]
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
      meth_ns*: Namespace
      meth*: GeneValue
    of ExInvokeMethod:
      invoke_self*: Expr
      invoke_meth*: string
      invoke_args*: seq[Expr]
    of ExGetProp:
      get_prop_self*: Expr
      get_prop_name*: string
    of ExSetProp:
      set_prop_name*: string
      set_prop_val*: Expr
    of ExNamespace:
      ns*: GeneValue
      ns_body*: seq[Expr]
    of ExSelf, ExGlobal:
      discard
    of ExImport:
      import_module*: string
      import_mappings*: seq[string]
    of ExCallNative:
      native_name*: string
      native_index*: int
      native_args*: seq[Expr]
    of ExGetClass:
      get_class_val*: Expr
    of ExQuote:
      quote_val*: GeneValue
    of ExEval:
      eval_args*: seq[Expr]
    of ExCallerEval:
      caller_eval_args*: seq[Expr]
    of ExMatch:
      match_pattern*: GeneValue
      match_val*: Expr

  VM* = ref object
    app*: Application
    cur_frame*: Frame
    cur_module*: Module
    modules*: Table[string, Namespace]

  FrameManager* = ref object
    cache*: seq[Frame]

  ScopeManager* = ref object
    cache*: seq[Scope]

  FrameKind* = enum
    FrFunction
    FrMethod
    FrModule
    FrNamespace
    FrClass
    FrMixin
    FrEval # the code passed to (eval)
    FrBlock # like a block passed to a method in Ruby

  FrameExtra* = ref object
    case kind*: FrameKind
    of FrFunction:
      # fn_name*: string  # We may support 1-n mapping for function and names
      fn*: Function
    of FrMethod:
      class*: Class
      meth*: Function
      meth_name*: string
      # hierarchy*: CallHierarchy # A hierarchy object that tracks where the method is in class hierarchy
    else:
      discard

  Frame* = ref object
    parent*: Frame
    self*: GeneValue
    ns*: Namespace
    scope*: Scope
    extra*: FrameExtra

  Break* = ref object of CatchableError
    val*: GeneValue

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
    name*: string
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
    name*: string
    value*: GeneValue # Either value_expr or value must be given
    value_expr*: Expr # Expression for calculating default value

  MatchResult* = ref object
    message*: string
    kind*: MatchResultKind
    # If success
    fields*: seq[MatchedField]
    assign_only*: bool # If true, no new variables will be defined
    # If missing fields
    missing*: seq[string]
    # If wrong type
    expect_type*: string
    found_type*: string

  # Internal state when applying the matcher to an input
  # Limited to one level
  MatchState* = ref object
    # prop_processed*: seq[string]
    data_index*: int
  NativeProcsType* = ref object
    procs*: seq[NativeProc]
    name_mappings*: Table[string, int]

let
  GeneNil*   = GeneValue(kind: GeneNilKind)
  GeneTrue*  = GeneValue(kind: GeneBool, bool: true)
  GeneFalse* = GeneValue(kind: GeneBool, bool: false)
  GenePlaceholder* = GeneValue(kind: GenePlaceholderKind)

var NativeProcs* = NativeProcsType()

var GeneInts: array[111, GeneValue]
for i in 0..110:
  GeneInts[i] = GeneValue(kind: GeneInt, int: i - 10)

proc todo*() =
  raise newException(Exception, "TODO")

proc todo*(message: string) =
  raise newException(Exception, "TODO: " & message)

proc not_allowed*(message: string) =
  raise newException(Exception, message)

proc not_allowed*() =
  not_allowed("Error: should not arrive here.")

#################### Interfaces ##################

proc new_namespace*(module: Module): Namespace
proc new_match_matcher*(): RootMatcher
proc new_arg_matcher*(): RootMatcher
proc parse*(self: var RootMatcher, v: GeneValue)

#################### Module ######################

proc new_module*(name: string): Module =
  result = Module(
    name: name,
  )
  result.root_ns = new_namespace(result)

proc new_module*(): Module =
  result = new_module("<unknown>")

proc get_index*(self: var Module, name: string): int =
  if self.name_mappings.hasKey(name):
    return self.name_mappings[name]
  else:
    result = self.names.len
    self.names.add(name)
    self.name_mappings[name] = result

#################### Namespace ###################

proc new_namespace*(module: Module): Namespace =
  return Namespace(
    module: module,
    name: "<root>",
    members: Table[int, GeneValue](),
  )

proc new_namespace*(module: Module, name: string): Namespace =
  return Namespace(
    module: module,
    name: name,
    members: Table[int, GeneValue](),
  )

proc new_namespace*(parent: Namespace, name: string): Namespace =
  return Namespace(
    module: parent.module,
    parent: parent,
    name: name,
    members: Table[int, GeneValue](),
  )

proc hasKey*(self: Namespace, key: string): bool {.inline.} =
  return self.members.hasKey(self.module.get_index(key))

# proc def_member*(self: var Namespace, key: int, val: GeneValue) {.inline.} =
#   self.members[key] = val

proc `[]`*(self: Namespace, key: int): GeneValue {.inline.} = self.members[key]

proc `[]`*(self: Namespace, key: string): GeneValue {.inline.} =
  return self[self.module.get_index(key)]

proc `[]=`*(self: var Namespace, key: int, val: GeneValue) {.inline.} =
  self.members[key] = val

#################### Scope #######################

proc new_scope*(): Scope = Scope(
  members: Table[int, GeneValue](),
  usage: 1,
)

proc reset*(self: var Scope) {.inline.} =
  self.parent = nil
  self.members.clear()

proc hasKey*(self: Scope, key: int): bool {.inline.} =
  if self.members.hasKey(key):
    return true
  elif self.parent != nil:
    return self.parent.hasKey(key)

proc def_member*(self: var Scope, key: int, val: GeneValue) {.inline.} =
  self.members[key] = val

proc `[]`*(self: Scope, key: int): GeneValue {.inline.} =
  if self.members.hasKey(key):
    return self.members[key]
  elif self.parent != nil:
    return self.parent[key]

proc `[]=`*(self: var Scope, key: int, val: GeneValue) {.inline.} =
  if self.members.hasKey(key):
    self.members[key] = val
  elif self.parent != nil:
    self.parent[key] = val
  else:
    not_allowed()

#################### Function ####################

proc new_fn*(name: string, matcher: RootMatcher, body: seq[GeneValue]): Function =
  return Function(
    name: name,
    matcher: matcher,
    body: body,
  )

#################### Macro #######################

proc new_macro*(name: string, args: seq[string], body: seq[GeneValue]): Macro =
  return Macro(name: name, args: args, body: body)

#################### Block #######################

proc new_block*(args: seq[string], body: seq[GeneValue]): Block =
  return Block(args: args, body: body)

#################### Return ######################

proc new_return*(): Return =
  return Return()

#################### Arguments ###################

proc new_args*(): Arguments =
  return Arguments(positional: @[])

proc new_args*(args: seq[GeneValue]): Arguments =
  return Arguments(positional: args)

proc `[]`*(self: Arguments, i: int): GeneValue =
  return self.positional[i]

proc `[]=`*(self: Arguments, i: int, val: GeneValue) =
  while i >= self.positional.len:
    self.positional.add(GeneNil)
  self.positional[i] = val

#################### Class #######################

proc get_method*(self: Class, name: string): Function =
  if self.methods.hasKey(name):
    return self.methods[name]
  elif self.parent != nil:
    return self.parent.get_method(name)

#################### ComplexSymbol ###############

proc `==`*(this, that: ComplexSymbol): bool =
  return this.first == that.first and this.rest == that.rest

#################### GeneValue ###################

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
    of GeneGene:
      return this.gene.op == that.gene.op and this.gene.data == that.gene.data and this.gene.props == that.gene.props
    of GeneMap:
      return this.map == that.map
    of GeneVector:
      return this.vec == that.vec
    of GeneCommentLine:
      return this.comment == that.comment
    of GeneRegex:
      return this.regex == that.regex
    of GeneInternal:
      case this.internal.kind:
      of GeneNamespace:
        return this.internal.ns == that.internal.ns
      else:
        return this.internal == that.internal

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
  of GeneString:
    result = "\"" & node.str.replace("\"", "\\\"") & "\""
  of GeneSymbol:
    result = node.symbol
  of GeneComplexSymbol:
    if node.csymbol.first == "":
      result = "/" & node.csymbol.rest.join("/")
    else:
      result = node.csymbol.first & "/" & node.csymbol.rest.join("/")
  of GeneVector:
    result = "["
    result &= node.vec.join(" ")
    result &= "]"
  # of GeneGene:
  #   result = "("
  #   if node.gene.op.isNil:
  #     result &= "nil "
  #   else:
  #     result &= $node.gene.op & " "
  #   # result &= node.gene.data.join(" ")
  #   result &= ")"
  of GeneInternal:
    case node.internal.kind:
    of GeneFunction:
      result = "(fn $# ...)" % [node.internal.fn.name]
    else:
      result = "GeneInternal"
  else:
    result = $node.kind

## ============== NEW OBJ FACTORIES =================

proc new_gene_string*(s: string): GeneValue =
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

proc new_gene_vec*(items: seq[GeneValue]): GeneValue =
  return GeneValue(
    kind: GeneVector,
    vec: items,
  )

proc new_gene_vec*(items: varargs[GeneValue]): GeneValue = new_gene_vec(@items)

proc new_gene_map*(): GeneValue =
  return GeneValue(
    kind: GeneMap,
    map: Table[string, GeneValue](),
  )

proc new_gene_map*(map: Table[string, GeneValue]): GeneValue =
  return GeneValue(
    kind: GeneMap,
    map: map,
  )

# proc new_gene_gene_simple*(op: GeneValue): GeneValue =
#   return GeneValue(
#     kind: GeneGene,
#     gene_op: op,
#   )

proc new_gene_gene*(op: GeneValue, data: varargs[GeneValue]): GeneValue =
  return GeneValue(
    kind: GeneGene,
    gene: Gene(op: op, data: @data),
  )

proc new_gene_gene*(op: GeneValue, props: Table[string, GeneValue], data: varargs[GeneValue]): GeneValue =
  return GeneValue(
    kind: GeneGene,
    gene: Gene(op: op, props: props, data: @data),
  )

proc new_gene_internal*(value: Internal): GeneValue =
  return GeneValue(kind: GeneInternal, internal: value)

proc new_gene_internal*(fn: Function): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneFunction, fn: fn),
  )

proc new_gene_internal*(mac: Macro): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneMacro, mac: mac),
  )

proc new_gene_internal*(blk: Block): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneBlock, blk: blk),
  )

proc new_gene_internal*(ret: Return): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneReturn, ret: ret),
  )

proc new_gene_internal*(value: NativeProc): GeneValue =
  return GeneValue(kind: GeneInternal, internal: Internal(kind: GeneNativeProc, native_proc: value))

proc new_gene_arguments*(): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneArguments, args: new_args()),
  )

proc new_class*(name: string): Class =
  return Class(name: name)

proc new_mixin*(name: string): Mixin =
  return Mixin(name: name)

proc new_instance*(class: Class): Instance =
  return Instance(value: new_gene_gene(GeneNil), class: class)

proc new_gene_internal*(class: Class): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneClass, class: class),
  )

proc new_gene_internal*(mix: Mixin): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneMixin, mix: mix),
  )

proc new_gene_instance*(instance: Instance): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneInstance, instance: instance),
  )

proc new_gene_internal*(ns: Namespace): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneNamespace, ns: ns),
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

proc normalize*(self: GeneValue) =
  if self.gene.normalized:
    return
  self.gene.normalized = true

  var op = self.gene.op
  if op.kind == GeneSymbol:
    if op.symbol.startsWith(".@"):
      if op.symbol.endsWith("="):
        var name = op.symbol.substr(2, op.symbol.len-2)
        self.gene.op = new_gene_symbol("@=")
        self.gene.data.insert(new_gene_string_move(name), 0)
      else:
        self.gene.op = new_gene_symbol("@")
        self.gene.data = @[new_gene_string_move(op.symbol.substr(2))]
    elif op.symbol == "import" or op.symbol == "import_native":
      var names: seq[GeneValue] = @[]
      var module: GeneValue
      var expect_module = false
      for val in self.gene.data:
        if expect_module:
          module = val
        elif val.kind == GeneSymbol and val.symbol == "from":
          expect_module = true
        else:
          names.add(val)
      self.gene.props["names"] = new_gene_vec(names)
      self.gene.props["module"] = module
      return
    elif op.symbol == "->":
      return
    elif op.symbol.startsWith("for"):
      self.gene.props["init"]   = self.gene.data[0]
      self.gene.props["guard"]  = self.gene.data[1]
      self.gene.props["update"] = self.gene.data[2]
      var body: seq[GeneValue] = @[]
      for i in 3..<self.gene.data.len:
        body.add(self.gene.data[i])
      self.gene.data = body

  if self.gene.data.len == 0:
    return

  var first = self.gene.data[0]
  if first.kind == GeneSymbol:
    if first.symbol == "+=":
      self.gene.op = new_gene_symbol("=")
      var second = self.gene.data[1]
      self.gene.data[0] = op
      self.gene.data[1] = new_gene_gene(new_gene_symbol("+"), op, second)
    elif first.symbol == "=" and op.kind == GeneSymbol and op.symbol.startsWith("@"):
      # (@prop = val)
      self.gene.op = new_gene_symbol("@=")
      self.gene.data[0] = new_gene_string(op.symbol[1..^1])
    elif first.symbol in BINARY_OPS:
      self.gene.data.delete 0
      self.gene.data.insert op, 0
      self.gene.op = first
    elif first.symbol.startsWith(".@"):
      if first.symbol.endsWith("="):
        todo()
      else:
        self.gene.op = new_gene_symbol("@")
        self.gene.data[0] = new_gene_string_move(first.symbol.substr(2))
        self.gene.props["self"] = op
    elif first.symbol[0] == '.':
      self.gene.props["self"] = op
      self.gene.props["method"] = new_gene_string_move(first.symbol.substr(1))
      self.gene.data.delete 0
      self.gene.op = new_gene_symbol("$invoke_method")
    elif first.symbol == "->":
      self.gene.props["args"] = self.gene.op
      self.gene.op = self.gene.data[0]
      self.gene.data.delete 0

proc strip_comments*(node: GeneValue) =
  case node.kind:
  of GeneVector:
    var has_comments = false
    var vec: seq[GeneValue] = @[]
    for item in node.vec:
      if item.kind != GeneCommentLine:
        has_comments = true
        vec.add(item)
    if has_comments:
      node.vec = vec
  of GeneGene:
    var has_comments = false
    var vec: seq[GeneValue] = @[]
    for item in node.gene.data:
      if item.kind != GeneCommentLine:
        has_comments = true
        vec.add(item)
    if has_comments:
      node.gene.data = vec
  else:
    discard

#################### Document ####################

proc new_doc*(data: seq[GeneValue]): GeneDocument =
  return GeneDocument(data: data)

#################### Application #################

var GLOBAL_NS*: GeneValue
var GENE_NS*:   GeneValue
var GENEX_NS*:  GeneValue

proc new_app*(): Application =
  var module = new_module("global")
  GLOBAL_NS = new_gene_internal(new_namespace(module, "global"))
  result = Application(
    ns: GLOBAL_NS.internal.ns,
  )

var APP* = new_app()

#################### Converters ##################

converter to_gene*(v: int): GeneValue                      = new_gene_int(v)
converter to_gene*(v: bool): GeneValue                     = new_gene_bool(v)
converter to_gene*(v: float): GeneValue                    = new_gene_float(v)
converter to_gene*(v: string): GeneValue                   = new_gene_string(v)
converter to_gene*(v: char): GeneValue                     = new_gene_char(v)
converter to_gene*(v: Rune): GeneValue                     = new_gene_char(v)
converter to_gene*(v: Table[string, GeneValue]): GeneValue = new_gene_map(v)

# Below converter causes problem with the hash function
# converter to_gene*(v: seq[GeneValue]): GeneValue           = new_gene_vec(v)

converter to_bool*(v: GeneValue): bool =
  if v.isNil:
    return false
  case v.kind:
  of GeneBool:
    return v.bool
  of GeneInt:
    return v.int != 0
  of GeneFloat:
    return v.float != 0
  of GeneString:
    return v.str.len != 0
  of GeneVector:
    return v.vec.len != 0
  else:
    true

converter to_function*(node: GeneValue): Function =
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

  result = new_fn(name, matcher, body)

converter to_macro*(node: GeneValue): Macro =
  var first = node.gene.data[0]
  var name: string
  if first.kind == GeneSymbol:
    name = first.symbol
  elif first.kind == GeneComplexSymbol:
    name = first.csymbol.rest[^1]
  var args: seq[string] = @[]
  var a = node.gene.data[1]
  case a.kind:
  of GeneSymbol:
    args.add(a.symbol)
  of GeneVector:
    for item in a.vec:
      args.add(item.symbol)
  else:
    not_allowed()
  var body: seq[GeneValue] = @[]
  for i in 2..<node.gene.data.len:
    body.add node.gene.data[i]

  return new_macro(name, args, body)

converter to_block*(node: GeneValue): Block =
  var args: seq[string] = @[]
  if node.gene.props.hasKey("args"):
    var a = node.gene.props["args"]
    case a.kind:
    of GeneSymbol:
      args.add(a.symbol)
    of GeneVector:
      for item in a.vec:
        args.add(item.symbol)
    else:
      not_allowed()
  var body: seq[GeneValue] = @[]
  for i in 0..<node.gene.data.len:
    body.add node.gene.data[i]

  return new_block(args, body)

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

proc new_matched_field(name: string, value: GeneValue): MatchedField =
  result = MatchedField(
    name: name,
    value: value,
  )

proc required(self: Matcher): bool =
  return self.default_value == nil and not self.splat

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
    var m = new_matcher(self, MatchData)
    group.add(m)
    if v.symbol != "_":
      if v.symbol.endsWith("..."):
        m.name = v.symbol[0..^4]
        m.splat = true
      else:
        m.name = v.symbol
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

proc `[]`(self: GeneValue, i: int): GeneValue =
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

proc match(self: Matcher, input: GeneValue, state: MatchState, r: MatchResult) =
  case self.kind:
  of MatchData:
    var name = self.name
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
    if name != "":
      var matched_field = new_matched_field(name, value)
      matched_field.value_expr = value_expr
      r.fields.add(matched_field)
    var child_state = MatchState()
    for child in self.children:
      child.match(value, child_state, r)
  else:
    todo()

proc match*(self: RootMatcher, input: GeneValue): MatchResult =
  result = MatchResult()
  var children = self.children
  var state = MatchState()
  for child in children:
    child.match(input, state, result)

#################### NativeProcs #################

proc add*(self: var NativeProcsType, name: string, p: NativeProc): int =
  result = self.procs.len
  self.procs.add(p)
  self.name_mappings[name] = result

# This is mainly created to make the code in native_procs.nim look slightly better
# (no discard, or `()` is required)
proc add_only*(self: var NativeProcsType, name: string, p: NativeProc) =
  var index = self.procs.len
  self.procs.add(p)
  self.name_mappings[name] = index

# Remove the stored proc but leave a nil in place to not cause index changes
# to any other procs
proc remove*(self: var NativeProcsType, name: string) =
  todo()

proc get_index*(self: var NativeProcsType, name: string): int =
  return self.name_mappings[name]

proc get*(self: var NativeProcsType, index: int): NativeProc =
  return self.procs[index]

#################### Dynamic #####################

proc load_dynamic*(path:string, names: seq[string]): Table[string, NativeProc] =
  result = Table[string, NativeProc]()
  let lib = loadLib(path)
  for name in names:
    var s = name
    let p = lib.symAddr(s)
    result[s] = cast[NativeProc](p)

# This is not needed
# proc call_dynamic*(p: native_proc, args: seq[GeneValue]): GeneValue =
#   return p(args)
