import strutils, tables, dynlib

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

  Class* = ref object
    name*: string
    name_key*: int
    methods*: Table[string, Function]

  Instance* = ref object
    class*: Class
    value*: GeneValue

  Function* = ref object
    name*: string
    name_key*: int
    args*: seq[string]
    arg_keys*: seq[int]
    body*: seq[GeneValue]
    expr*: Expr # The function expression that will be the parent of body
    body_blk*: seq[Expr]

  Arguments* = ref object
    positional*: seq[GeneValue]

  GeneInternalKind* = enum
    GeneFunction
    GeneArguments
    GeneClass
    GeneNamespace
    GeneNativeProc

  Internal* = ref object
    case kind*: GeneInternalKind
    of GeneFunction:
      fn*: Function
    of GeneArguments:
      args*: Arguments
    of GeneClass:
      class*: Class
    of GeneNamespace:
      ns*: Namespace
    of GeneNativeProc:
      native_proc*: NativeProc

  ComplexSymbol* = ref object
    first*: string
    rest*: seq[string]

  GeneKind* = enum
    GeneAny
    GeneNilKind
    GeneBool
    GeneChar
    GeneInt
    GeneRatio
    GeneFloat
    GeneString
    GeneSymbol
    GeneComplexSymbol
    GeneKeyword
    GeneGene
    GeneMap
    GeneVector
    GeneCommentLine
    GeneRegex
    GeneInternal
    GeneInstance

  CommentPlacement* = enum
    Before
    After
    Inside

  Comment* = ref object
    placement*: CommentPlacement
    comment_lines*: seq[string]

  GeneValue* {.acyclic.} = ref object
    case kind*: GeneKind
    of GeneAny:
      anyVal*: pointer
    of GeneNilKind:
      discard
    of GeneBool:
      boolVal*: bool
    of GeneChar:
      character*: char
    of GeneInt:
      num*: BiggestInt
    of GeneRatio:
      rnum*: tuple[numerator, denominator: BiggestInt]
    of GeneFloat:
      fnum*: float
    of GeneString:
      str*: string
    of GeneSymbol:
      symbol*: string
    of GeneComplexSymbol:
      csymbol*: ComplexSymbol
    of GeneKeyword:
      keyword*: tuple[ns, name: string]
      is_namespaced*: bool
    of GeneGene:
      gene_op*: GeneValue
      gene_props*: Table[string, GeneValue]
      gene_data*: seq[GeneValue]
      # A gene can be normalized to match expected format
      # Example: (a = 1) => (= a 1)
      gene_normalized*: bool
    of GeneMap:
      map*: Table[string, GeneValue]
    of GeneVector:
      vec*: seq[GeneValue]
    of GeneCommentLine:
      comment*: string
    of GeneRegex:
      regex*: string
    of GeneInternal:
      internal*: Internal
    of GeneInstance:
      instance*: Instance
    # line*: int
    # column*: int
    # comments*: seq[Comment]

  GeneDocument* = ref object
    name*: string
    path*: string
    data*: seq[GeneValue]

  NativeProc* = proc(args: seq[GeneValue]): GeneValue {.nimcall.}

  ExprKind* = enum
    ExRoot
    ExLiteral
    ExSymbol
    ExComplexSymbol
    ExMap
    ExMapChild
    ExArray
    ExGene
    ExBlock
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
    ExReturn
    ExClass
    ExNew
    ExMethod
    ExInvokeMethod
    ExGetProp
    ExSetProp
    ExNamespace
    ExGlobal
    ExImport
    ExCallNative

  Expr* = ref object of RootObj
    module*: Module
    parent*: Expr
    posInParent*: int
    case kind*: ExprKind
    of ExRoot:
      root*: Expr
    of ExLiteral:
      literal*: GeneValue
    of ExSymbol:
      # symbol*: string
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
      gene_blk*: seq[Expr]
    of ExBlock:
      blk*: seq[Expr]
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
    of ExReturn:
      return_val*: Expr
    of ExClass:
      class*: GeneValue
      class_name*: GeneValue # The simple name or complex name that is associated with the class
      class_body*: seq[Expr]
    of ExNew:
      new_class*: Expr
      new_args*: seq[Expr]
    of ExMethod:
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
    of ExGlobal:
      discard
    of ExImport:
      import_module*: string
      import_mappings*: seq[string]
    of ExCallNative:
      native_name*: string
      native_index*: int
      native_args*: seq[Expr]

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

  NativeProcsType* = ref object
    procs*: seq[NativeProc]
    name_mappings*: Table[string, int]

let
  GeneNil*   = GeneValue(kind: GeneNilKind)
  GeneTrue*  = GeneValue(kind: GeneBool, bool_val: true)
  GeneFalse* = GeneValue(kind: GeneBool, bool_val: false)

var NativeProcs* = NativeProcsType()

var GeneInts: array[111, GeneValue]
for i in 0..110:
  GeneInts[i] = GeneValue(kind: GeneInt, num: i - 10)

#################### Interfaces ##################

proc new_namespace*(module: Module): Namespace

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

proc `[]`*(self: Namespace, key: int): GeneValue {.inline.} = self.members[key]

proc `[]`*(self: Namespace, key: string): GeneValue {.inline.} =
  self[self.module.get_index(key)]

proc `[]=`*(self: var Namespace, key: int, val: GeneValue) {.inline.} =
  self.members[key] = val

#################### Function ####################

proc new_fn*(name: string, args: seq[string], body: seq[GeneValue]): Function =
  return Function(name: name, args: args, body: body)

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
      return this.anyVal == that.anyVal
    of GeneNilKind:
      return that.kind == GeneNilKind
    of GeneBool:
      return this.boolVal == that.boolVal
    of GeneChar:
      return this.character == that.character
    of GeneInt:
      return this.num == that.num
    of GeneRatio:
      return this.rnum == that.rnum
    of GeneFloat:
      return this.fnum == that.fnum
    of GeneString:
      return this.str == that.str
    of GeneSymbol:
      return this.symbol == that.symbol
    of GeneComplexSymbol:
      return this.csymbol == that.csymbol
    of GeneKeyword:
      return this.keyword == that.keyword and this.is_namespaced == that.is_namespaced
    of GeneGene:
      return this.gene_op == that.gene_op and this.gene_data == that.gene_data and this.gene_props == that.gene_props
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
    of GeneInstance:
      return this.instance == that.instance

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
    result = $(node.boolVal)
  of GeneInt:
    result = $(node.num)
  of GeneString:
    result = "\"" & node.str.replace("\"", "\\\"") & "\""
  of GeneKeyword:
    if node.is_namespaced:
      result = "::" & node.keyword.name
    elif node.keyword.ns == "":
      result = ":" & node.keyword.name
    else:
      result = ":" & node.keyword.ns & "/" & node.keyword.name
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
  #   if node.gene_op.isNil:
  #     result &= "nil "
  #   else:
  #     result &= $node.gene_op & " "
  #   # result &= node.gene_data.join(" ")
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
  return GeneValue(kind: GeneInt, num: parseBiggestInt(s))

proc new_gene_int*(val: BiggestInt): GeneValue =
  # return GeneValue(kind: GeneInt, num: val)
  if val > 100 or val < -10:
    return GeneValue(kind: GeneInt, num: val)
  else:
    return GeneInts[val + 10]

proc new_gene_ratio*(nom, denom: BiggestInt): GeneValue =
  return GeneValue(kind: GeneRatio, rnum: (nom, denom))

proc new_gene_float*(s: string): GeneValue =
  return GeneValue(kind: GeneFloat, fnum: parseFloat(s))

proc new_gene_float*(val: float): GeneValue =
  return GeneValue(kind: GeneFloat, fnum: val)

proc new_gene_bool*(val: bool): GeneValue =
  case val
  of true: return GeneTrue
  of false: return GeneFalse
  # of true: return GeneValue(kind: GeneBool, boolVal: true)
  # of false: return GeneValue(kind: GeneBool, boolVal: false)

proc new_gene_bool*(s: string): GeneValue =
  let parsed: bool = parseBool(s)
  return new_gene_bool(parsed)

proc new_gene_symbol*(name: string): GeneValue =
  return GeneValue(kind: GeneSymbol, symbol: name)

proc new_gene_complex_symbol*(first: string, rest: seq[string]): GeneValue =
  return GeneValue(kind: GeneComplexSymbol, csymbol: ComplexSymbol(first: first, rest: rest))

proc new_gene_keyword*(ns, name: string): GeneValue =
  return GeneValue(kind: GeneKeyword, keyword: (ns, name))

proc new_gene_keyword*(name: string): GeneValue =
  return GeneValue(kind: GeneKeyword, keyword: ("", name))

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
    gene_op: op,
    gene_data: @data,
  )

proc new_gene_gene*(op: GeneValue, props: Table[string, GeneValue], data: varargs[GeneValue]): GeneValue =
  return GeneValue(
    kind: GeneGene,
    gene_op: op,
    gene_props: props,
    gene_data: @data,
  )

proc new_gene_internal*(value: Internal): GeneValue =
  return GeneValue(kind: GeneInternal, internal: value)

proc new_gene_internal*(fn: Function): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneFunction, fn: fn),
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

proc new_instance*(class: Class): Instance =
  return Instance(value: new_gene_gene(GeneNil), class: class)

proc new_gene_internal*(class: Class): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneClass, class: class),
  )

proc new_gene_instance*(instance: Instance): GeneValue =
  return GeneValue(
    kind: GeneInstance,
    instance: instance,
  )

proc new_gene_internal*(ns: Namespace): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneNamespace, ns: ns),
  )

### === VALS ===

let
  KeyTag*: GeneValue   = new_gene_keyword("", "tag")
  CljTag*: GeneValue   = new_gene_keyword("", "clj")
  CljsTag*: GeneValue  = new_gene_keyword("", "cljs")
  DefaultTag*: GeneValue = new_gene_keyword("", "default")

  LineKw*: GeneValue   = new_gene_keyword("gene.nim", "line")
  ColumnKw*: GeneValue   = new_gene_keyword("gene.nim", "column")
  SplicedQKw*: GeneValue = new_gene_keyword("gene.nim", "spliced?")

proc todo*() =
  raise newException(Exception, "TODO")

proc todo*(message: string) =
  raise newException(Exception, "TODO: " & message)

proc not_allowed*() =
  raise newException(Exception, "Error: should not arrive here.")

#################### GeneValue ###################

proc is_truthy*(self: GeneValue): bool =
  case self.kind:
  of GeneBool:
    return self.boolVal
  of GeneNilKind:
    return false
  else:
    return true

proc normalize*(self: GeneValue) =
  if self.gene_normalized:
    return
  self.gene_normalized = true

  var op = self.gene_op
  if op.kind == GeneSymbol:
    if op.symbol.startsWith(".@"):
      if op.symbol.endsWith("="):
        var name = op.symbol.substr(2, op.symbol.len-2)
        self.gene_op = new_gene_symbol("@=")
        self.gene_data.insert(new_gene_string_move(name), 0)
      else:
        self.gene_op = new_gene_symbol("@")
        self.gene_data = @[new_gene_string_move(op.symbol.substr(2))]
    elif op.symbol == "import" or op.symbol == "import_native":
      var names: seq[GeneValue] = @[]
      var module: GeneValue
      var expect_module = false
      for val in self.gene_data:
        if expect_module:
          module = val
        elif val.kind == GeneSymbol and val.symbol == "from":
          expect_module = true
        else:
          names.add(val)
      self.gene_props["names"] = new_gene_vec(names)
      self.gene_props["module"] = module
      return
    elif op.symbol.startsWith("for"):
      self.gene_props["init"]   = self.gene_data[0]
      self.gene_props["guard"]  = self.gene_data[1]
      self.gene_props["update"] = self.gene_data[2]
      var body: seq[GeneValue] = @[]
      for i in 3..<self.gene_data.len:
        body.add(self.gene_data[i])
      self.gene_data = body

  if self.gene_data.len == 0:
    return

  var first = self.gene_data[0]
  if first.kind == GeneSymbol:
    if first.symbol == "+=":
      self.gene_op = new_gene_symbol("=")
      var second = self.gene_data[1]
      self.gene_data[0] = op
      self.gene_data[1] = new_gene_gene(new_gene_symbol("+"), op, second)
    elif first.symbol == "=" and op.kind == GeneSymbol and op.symbol.startsWith("@"):
      # (@prop = val)
      self.gene_op = new_gene_symbol("@=")
      self.gene_data[0] = new_gene_string(op.symbol[1..^1])
    elif first.symbol in BINARY_OPS:
      self.gene_data.delete 0
      self.gene_data.insert op, 0
      self.gene_op = first
    elif first.symbol.startsWith(".@"):
      if first.symbol.endsWith("="):
        todo()
      else:
        self.gene_op = new_gene_symbol("@")
        self.gene_data[0] = new_gene_string_move(first.symbol.substr(2))
        self.gene_props["self"] = op
    elif first.symbol[0] == '.':
      self.gene_props["self"] = op
      self.gene_props["method"] = new_gene_string_move(first.symbol.substr(1))
      self.gene_data.delete 0
      self.gene_op = new_gene_symbol("$invoke_method")

#################### Document ####################

proc new_doc*(data: seq[GeneValue]): GeneDocument =
  return GeneDocument(data: data)

#################### Application #################

var APP* = Application(
  ns: new_namespace(new_module(), "global")
)

#################### Converters ##################

converter to_gene*(v: int): GeneValue                      = new_gene_int(v)
converter to_gene*(v: bool): GeneValue                     = new_gene_bool(v)
converter to_gene*(v: float): GeneValue                    = new_gene_float(v)
converter to_gene*(v: string): GeneValue                   = new_gene_string(v)
converter to_gene*(v: Table[string, GeneValue]): GeneValue = new_gene_map(v)

# Below converter causes problem with the hash function
# converter to_gene*(v: seq[GeneValue]): GeneValue           = new_gene_vec(v)

converter from_gene*(v: GeneValue): bool =
  if v.isNil:
    return false
  case v.kind:
  of GeneBool:
    return v.boolVal
  of GeneInt:
    return v.num != 0
  of GeneFloat:
    return v.fnum != 0
  of GeneString:
    return v.str.len != 0
  of GeneVector:
    return v.vec.len != 0
  else:
    true

converter from_gene*(node: GeneValue): Function =
  var first = node.gene_data[0]
  var name: string
  if first.kind == GeneSymbol:
    name = first.symbol
  elif first.kind == GeneComplexSymbol:
    name = first.csymbol.rest[^1]
  var args: seq[string] = @[]
  var a = node.gene_data[1]
  case a.kind:
  of GeneSymbol:
    args.add(a.symbol)
  of GeneVector:
    for item in a.vec:
      args.add(item.symbol)
  else:
    not_allowed()
  var body: seq[GeneValue] = @[]
  for i in 2..<node.gene_data.len:
    body.add node.gene_data[i]

  return new_fn(name, args, body)

#################### NativeProcs #################

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
