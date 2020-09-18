import strutils, oids, sets, tables, dynlib

proc todo*() =
  raise newException(Exception, "TODO")

proc todo*(message: string) =
  raise newException(Exception, "TODO: " & message)

proc not_allowed*() =
  raise newException(Exception, "Error: should not arrive here.")

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

  RunningMode* = enum
    Interpreted
    Compiled
    # Mixed

  InstrType* = enum
    Init

    # # Save Value to default register
    Default
    # Save Value to a register
    Save
    # Copy from one register to another
    Copy

    Print
    Println

    DefMember
    DefNsMember
    GetMember
    GetNestedNsMember
    # GetMemberInScope(String)
    # GetMemberInNS(String)
    # SetMember(String)
    # SetMemberInScope(String)
    # SetMemberInNS(String)

    # GetItem(target reg, index)
    # GetItem(u16, usize)
    # GetItemDynamic(target reg, index reg)
    # GetItemDynamic(String, String)
    # SetItem(target reg, index, value reg)
    SetItem
    # SetItem(u16, usize)
    # SetItemDynamic(target reg, index reg, value reg)
    # SetItemDynamic(String, String, String)

    # GetProp(target reg, name)
    # GetProp(String, String)
    # GetPropDynamic(target reg, name reg)
    # GetPropDynamic(String, String)
    # SetProp(target reg, name, value reg)
    # SetProp(u16, String)
    # SetPropDynamic(target reg, name reg, value reg)
    # SetPropDynamic(String, String, String)

    Jump
    JumpIfFalse
    # Below are pseudo instructions that should be replaced with other jump instructions
    # before sent to the VM to execute.
    # JumpToElse
    # JumpToNextStatement

    # Break
    # LoopStart
    # LoopEnd

    # reg + default
    Add
    AddI
    # reg - default
    Sub
    SubI
    Mul
    Div
    Pow
    Mod
    Eq
    EqI
    Neq
    Lt
    LtI
    Le
    Gt
    Ge
    And
    Or
    Not
    # BitAnd
    # BitOr
    # BitXor

    Global
    Self

    # Function(fn)
    CreateFunction
    # Arguments(reg): create an arguments object and store in register <reg>
    CreateArguments

    CreateNamespace # name
    Import # names
    ImportNative # names

    CreateClass # name
    # self: class
    # reg: function object
    CreateMethod
    CreateInstance # name

    # reg: self
    # val: name
    # reg2: args
    InvokeMethod

    # (@ "name")
    # val: "name"
    PropGet
    # (@= "name" value)
    # val: "name"
    # reg: value
    PropSet

    # Call(target reg, args reg)
    Call
    CallEnd

    # name: native proc name
    # reg: args
    CallNative

    InvokeNative

    # reg: target block
    # reg2: optional self
    CallBlock

  Instruction* = ref object
    kind*: InstrType
    reg*: int       # Optional: Default register
    reg2*: int      # Optional: Second register
    val*: GeneValue # Optional: Default immediate value

  Block* = ref object
    id*: Oid
    name*: string
    instructions*: seq[Instruction]
    ## No need to return value to caller, applicable to class/namespace block etc
    no_return*: bool
    ## This is not needed after compilation
    reg_mgr*: RegManager
    scope_mgr*: ScopeManager

  RegManager* = ref object
    next*: int
    freed*: HashSet[int]

  MemberKind* = enum
    ScopeMember
    NamespaceMember
    ArgumentMember # similar to scope member

  Member* = ref object
    kind*: MemberKind
    name*: string
    usage*: int
    inherited*: bool # Inherited in a function or code evaluated during execution

  ScopeManager* = ref object
    parent*: ScopeManager
    inherit_scope*: bool
    # key: internal name = name, name%1, ...
    # val: member object
    members*: Table[string, Member]
    # key: name
    # val: stack of internal names used as key in self.members
    reused_members*: Table[string, seq[string]]

  Namespace* = ref object
    parent*: Namespace
    name*: string
    members*: Table[int, GeneValue]
    # cache*: Table[string, GeneValue]

  Module* = ref object
    id*: Oid
    blocks*: Table[Oid, Block]
    default*: Block
    # TODO: support (main ...)
    # main_block* Block

  Class* = ref object
    name*: string
    methods*: Table[string, Function]

  Instance* = ref object
    class*: Class
    value*: GeneValue

  Function* = ref object
    name*: string
    args*: seq[string]
    body*: seq[GeneValue]
    body_block*: Block
    ## No need to return value to caller, applicable to class constructor etc
    no_return*: bool

  Arguments* = ref object
    positional*: seq[GeneValue]

  GeneInternalKind* = enum
    GeneFunction
    GeneArguments
    GeneBlock
    GeneClass
    GeneNamespace
    GeneReturn
    GeneBreak
    GeneNativeProc

  Internal* = ref object
    case kind*: GeneInternalKind
    of GeneFunction:
      fn*: Function
    of GeneArguments:
      args*: Arguments
    of GeneBlock:
      blk*: Block
    of GeneClass:
      class*: Class
    of GeneNamespace:
      ns*: Namespace
    of GeneReturn:
      return_val*: GeneValue
    of GeneBreak:
      break_val*: GeneValue
    of GeneNativeProc:
      native_proc*: native_proc

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
    GeneSet
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

  HMapEntry* = ref HMapEntryObj
  HMapEntryObj = tuple[key: GeneValue, value: GeneValue]

  HMap* = ref HMapObj
  HMapObj* = object
    count*: int
    buckets*: seq[seq[HMapEntry]]

  GeneValue* = object
    d*: GeneValueInternal

  GeneValueInternal* = ptr object
    refCount: uint
    case kind*: GeneKind
    of GeneAny:
      val: pointer
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
      # map*: HMap
      map*: Table[string, GeneValue]
    of GeneVector:
      vec*: seq[GeneValue]
    of GeneSet:
      set_elems*: HMap
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

  native_proc* = proc(args: seq[GeneValue]): GeneValue {.nimcall.}

var GeneValueCache: seq[GeneValueInternal] = @[]

proc `$`*(node: GeneValue): string

proc `=destroy`*(x: var GeneValue) {.inline.} =
  if x.d == nil:
    return
  if x.d.refCount == 0:
    # We have the last reference
    x.d[].wasMoved
    GeneValueCache.add(x.d)
  else:
    x.d.refCount -= 1
  x.d = nil

# proc `=sink`*(dst: var GeneValue, src: GeneValue) {.inline.} =
#   if dst.d != nil:
#     `=destroy`(dst)
#   if src.d != nil:
#     dst.d = src.d

proc `=`*(dst: var GeneValue, src: GeneValue) {.inline.} =
  if src.d == dst.d:
    return
  `=destroy`(dst)
  if src.d == nil:
    dst.d = nil
  else:
    src.d.refCount += 1
    dst.d = src.d

let GeneValueSize = sizeof(typeof(default(GeneValueInternal)[]))

proc new_gene*(kind: GeneKind): GeneValue =
  var internal: GeneValueInternal
  if GeneValueCache.len > 0:
    internal = GeneValueCache.pop()
  else:
    internal = cast[GeneValueInternal](alloc0(GeneValueSize))
  var offset = GeneValueInternal.offsetOf(kind)
  cast[ptr GeneKind](cast[uint](internal) + offset.uint)[] = kind
  internal.refCount = 1
  return GeneValue(d: internal)

# var
#   GeneNil*   = GeneValue(kind: GeneNilKind)
#   GeneTrue*  = GeneValue(kind: GeneBool, bool_val: true)
#   GeneFalse* = GeneValue(kind: GeneBool, bool_val: false)
var GeneNil*   = new_gene(GeneNilKind)
var GeneTrue*  = new_gene(GeneBool)
GeneTrue.d.bool_val = true
var GeneFalse* = new_gene(GeneBool)
GeneFalse.d.bool_val = false

var APP*: Application

# var GeneInts: array[111, GeneValue]
# for i in 0..110:
#   GeneInts[i] = GeneValue(kind: GeneInt, num: i - 10)

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

# proc clone*(self: GeneValue): GeneValue =
#   result = new_gene(self.d.kind)
#   case self.d.kind:
#   of GeneInt:
#     result.d.num = self.d.num
#   else:
#     todo()

proc `==`*(this, that: GeneValue): bool =
  if this.d.is_nil:
    if that.d.is_nil: return true
    return false
  elif that.d.is_nil or this.d.kind != that.d.kind:
    return false
  else:
    case this.d.kind
    of GeneNilKind:
      return that.d.kind == GeneNilKind
    of GeneBool:
      return this.d.boolVal == that.d.boolVal
    of GeneChar:
      return this.d.character == that.d.character
    of GeneInt:
      return this.d.num == that.d.num
    of GeneRatio:
      return this.d.rnum == that.d.rnum
    of GeneFloat:
      return this.d.fnum == that.d.fnum
    of GeneString:
      return this.d.str == that.d.str
    of GeneSymbol:
      return this.d.symbol == that.d.symbol
    of GeneComplexSymbol:
      return this.d.csymbol == that.d.csymbol
    of GeneKeyword:
      return this.d.keyword == that.d.keyword and this.d.is_namespaced == that.d.is_namespaced
    of GeneGene:
      return this.d.gene_op == that.d.gene_op and this.d.gene_data == that.d.gene_data
    of GeneMap:
      return this.d.map == that.d.map
    of GeneVector:
      return this.d.vec == that.d.vec
    of GeneSet:
      return this.d.set_elems == that.d.set_elems
    of GeneCommentLine:
      return this.d.comment == that.d.comment
    of GeneRegex:
      return this.d.regex == that.d.regex
    of GeneInternal:
      return this.d.internal == that.d.internal
    of GeneInstance:
      return this.d.instance == that.d.instance
    else:
      todo()

proc is_literal*(self: GeneValue): bool =
  case self.d.kind:
  of GeneBool, GeneNilKind, GeneInt, GeneFloat, GeneRatio:
    return true
  else:
    return false

proc `$`*(node: GeneValue): string =
  if node.d == nil:
    return "nil"
  case node.d.kind
  of GeneNilKind:
    result = "nil"
  of GeneBool:
    result = $(node.d.boolVal)
  of GeneInt:
    result = $(node.d.num)
  of GeneString:
    result = "TODO"
    # result = "\"" & node.d.str.replace("\"", "\\\"") & "\""
  of GeneKeyword:
    if node.d.is_namespaced:
      result = "::" & node.d.keyword.name
    elif node.d.keyword.ns == "":
      result = ":" & node.d.keyword.name
    else:
      result = ":" & node.d.keyword.ns & "/" & node.d.keyword.name
  of GeneSymbol:
    result = node.d.symbol
  of GeneComplexSymbol:
    if node.d.csymbol.first == "":
      result = "/" & node.d.csymbol.rest.join("/")
    else:
      result = node.d.csymbol.first & "/" & node.d.csymbol.rest.join("/")
  of GeneVector:
    result = "["
    result &= node.d.vec.join(" ")
    result &= "]"
  # of GeneGene:
  #   result = "("
  #   if node.gene_op == nil:
  #     result &= "nil "
  #   else:
  #     result &= $node.gene_op & " "
  #   # result &= node.gene_data.join(" ")
  #   result &= ")"
  of GeneInternal:
    case node.d.internal.kind:
    of GeneFunction:
      result = "(fn $# ...)" % [node.d.internal.fn.name]
    else:
      result = "GeneInternal"
  else:
    result = $node.d.kind

## ============== NEW OBJ FACTORIES =================

proc new_gene_string*(s: string): GeneValue =
  # return GeneValue(kind: GeneString, str: s)
  result = new_gene(GeneString)
  result.d.str = s

proc new_gene_string_move*(s: string): GeneValue =
  # result = GeneValue(kind: GeneString)
  result = new_gene(GeneString)
  shallowCopy(result.d.str, s)

proc new_gene_int*(s: string): GeneValue =
  # return GeneValue(kind: GeneInt, num: parseBiggestInt(s))
  result = new_gene(GeneInt)
  result.d.num = parseBiggestInt(s)

proc new_gene_int*(val: int): GeneValue =
  # return GeneValue(kind: GeneInt, num: val)
  result = new_gene(GeneInt)
  result.d.num = val
  # if val > 100 or val < -10:
  #   return GeneValue(kind: GeneInt, num: val)
  # else:
  #   return GeneInts[val + 10]

proc new_gene_int*(val: BiggestInt): GeneValue =
  # return GeneValue(kind: GeneInt, num: val)
  result = new_gene(GeneInt)
  result.d.num = val

proc new_gene_ratio*(nom, denom: BiggestInt): GeneValue =
  # return GeneValue(kind: GeneRatio, rnum: (nom, denom))
  result = new_gene(GeneRatio)
  result.d.rnum = (nom, denom)

proc new_gene_float*(s: string): GeneValue =
  # return GeneValue(kind: GeneFloat, fnum: parseFloat(s))
  result = new_gene(GeneFloat)
  result.d.fnum = parseFloat(s)

proc new_gene_float*(val: float): GeneValue =
  # return GeneValue(kind: GeneFloat, fnum: val)
  result = new_gene(GeneFloat)
  result.d.fnum = val

proc new_gene_bool*(val: bool): GeneValue =
  case val
  of true: return GeneTrue
  of false: return GeneFalse
  # of true: return GeneValue(kind: GeneBool, boolVal: true)
  # of false: return GeneValue(kind: GeneBool, boolVal: false)

proc new_gene_bool*(s: string): GeneValue =
  let parsed: bool = parseBool(s)
  # return new_gene_bool(parsed)
  result = new_gene(GeneBool)
  result.d.boolVal = parsed

proc new_gene_symbol*(name: string): GeneValue =
  # return GeneValue(kind: GeneSymbol, symbol: name)
  result = new_gene(GeneSymbol)
  result.d.symbol = name

proc new_gene_complex_symbol*(first: string, rest: seq[string]): GeneValue =
  # return GeneValue(kind: GeneComplexSymbol, csymbol: ComplexSymbol(first: first, rest: rest))
  result = new_gene(GeneComplexSymbol)
  result.d.csymbol = ComplexSymbol(first: first, rest: rest)

proc new_gene_keyword*(ns, name: string): GeneValue =
  # return GeneValue(kind: GeneKeyword, keyword: (ns, name))
  result = new_gene(GeneKeyword)
  result.d.keyword = (ns, name)

proc new_gene_keyword*(name: string): GeneValue =
  # return GeneValue(kind: GeneKeyword, keyword: ("", name))
  result = new_gene(GeneKeyword)
  result.d.keyword = ("", name)

proc new_gene_vec*(items: seq[GeneValue]): GeneValue =
  # return GeneValue(kind: GeneVector, vec: items)
  result = new_gene(GeneVector)
  result.d.vec = items

proc new_gene_vec*(items: varargs[GeneValue]): GeneValue = new_gene_vec(@items)

proc new_gene_map*(map: Table[string, GeneValue]): GeneValue =
  # return GeneValue(kind: GeneMap, map: map)
  result = new_gene(GeneMap)
  result.d.map = map

# proc new_gene_gene_simple*(op: GeneValue): GeneValue =
#   return GeneValue(
#     kind: GeneGene,
#     gene_op: op,
#   )

proc new_gene_gene*(op: GeneValue, data: varargs[GeneValue]): GeneValue =
  # return GeneValue(
  #   kind: GeneGene,
  #   gene_op: op,
  #   gene_data: @data,
  # )
  result = new_gene(GeneGene)
  result.d.gene_op = op
  result.d.gene_data = @data

proc new_gene_gene*(op: GeneValue, props: Table[string, GeneValue], data: varargs[GeneValue]): GeneValue =
  # return GeneValue(
  #   kind: GeneGene,
  #   gene_op: op,
  #   gene_props: props,
  #   gene_data: @data,
  # )
  result = new_gene(GeneGene)
  result.d.gene_op = op
  result.d.gene_props = props
  result.d.gene_data = @data

proc new_gene_internal*(value: Internal): GeneValue =
  # return GeneValue(kind: GeneInternal, internal: value)
  result = new_gene(GeneInternal)
  result.d.internal = value

proc new_gene_internal*(fn: Function): GeneValue =
  # return GeneValue(
  #   kind: GeneInternal,
  #   internal: Internal(kind: GeneFunction, fn: fn),
  # )
  result = new_gene(GeneInternal)
  result.d.internal = Internal(kind: GeneFunction, fn: fn)

proc new_gene_internal*(value: native_proc): GeneValue =
  # return GeneValue(kind: GeneInternal, internal: Internal(kind: GeneNativeProc, native_proc: value))
  result = new_gene(GeneInternal)
  result.d.internal = Internal(kind: GeneNativeProc, native_proc: value)

proc new_gene_arguments*(): GeneValue =
  # return GeneValue(
  #   kind: GeneInternal,
  #   internal: Internal(kind: GeneArguments, args: new_args()),
  # )
  result = new_gene(GeneInternal)
  result.d.internal = Internal(kind: GeneArguments, args: new_args())

proc new_class*(name: string): Class =
  return Class(name: name)

proc new_instance*(class: Class): Instance =
  return Instance(value: new_gene_gene(GeneNil), class: class)

proc new_namespace*(): Namespace =
  return Namespace(
    name: "<root>",
    members: Table[int, GeneValue](),
  )

proc new_namespace*(name: string): Namespace =
  return Namespace(
    name: name,
    members: Table[int, GeneValue](),
  )

proc new_namespace*(parent: Namespace, name: string): Namespace =
  return Namespace(
    parent: parent,
    name: name,
    members: Table[int, GeneValue](),
  )

proc new_gene_internal*(class: Class): GeneValue =
  # return GeneValue(
  #   kind: GeneInternal,
  #   internal: Internal(kind: GeneClass, class: class),
  # )
  result = new_gene(GeneInternal)
  result.d.internal = Internal(kind: GeneClass, class: class)

proc new_gene_instance*(instance: Instance): GeneValue =
  # return GeneValue(
  #   kind: GeneInstance,
  #   instance: instance,
  # )
  result = new_gene(GeneInstance)
  result.d.instance = instance

proc new_gene_internal*(ns: Namespace): GeneValue =
  # return GeneValue(
  #   kind: GeneInternal,
  #   internal: Internal(kind: GeneNamespace, ns: ns),
  # )
  result = new_gene(GeneInternal)
  result.d.internal = Internal(kind: GeneNamespace, ns: ns)

### === VALS ===

let
  KeyTag*: GeneValue   = new_gene_keyword("", "tag")
  CljTag*: GeneValue   = new_gene_keyword("", "clj")
  CljsTag*: GeneValue  = new_gene_keyword("", "cljs")
  DefaultTag*: GeneValue = new_gene_keyword("", "default")

  LineKw*: GeneValue   = new_gene_keyword("gene.nim", "line")
  ColumnKw*: GeneValue   = new_gene_keyword("gene.nim", "column")
  SplicedQKw*: GeneValue = new_gene_keyword("gene.nim", "spliced?")

#################### GeneValue ###################

proc is_truthy*(self: GeneValue): bool =
  case self.d.kind:
  of GeneBool:
    return self.d.boolVal
  of GeneNilKind:
    return false
  else:
    return true

proc normalize*(self: GeneValue) =
  if self.d.gene_normalized:
    return
  self.d.gene_normalized = true

  var op = self.d.gene_op
  if op.d.kind == GeneSymbol:
    if op.d.symbol.startsWith(".@"):
      if op.d.symbol.endsWith("="):
        var name = op.d.symbol.substr(2, op.d.symbol.len-2)
        self.d.gene_op = new_gene_symbol("@=")
        self.d.gene_data.insert(new_gene_string_move(name), 0)
      else:
        self.d.gene_op = new_gene_symbol("@")
        self.d.gene_data = @[new_gene_string_move(op.d.symbol.substr(2))]
    elif op.d.symbol == "import" or op.d.symbol == "import_native":
      var names: seq[GeneValue] = @[]
      var module: GeneValue
      var expect_module = false
      for val in self.d.gene_data:
        if expect_module:
          module = val
        elif val.d.kind == GeneSymbol and val.d.symbol == "from":
          expect_module = true
        else:
          names.add(val)
      self.d.gene_props["names"] = new_gene_vec(names)
      self.d.gene_props["module"] = module
      return
    elif op.d.symbol.startsWith("for"):
      self.d.gene_props["init"]   = self.d.gene_data[0]
      self.d.gene_props["guard"]  = self.d.gene_data[1]
      self.d.gene_props["update"] = self.d.gene_data[2]
      var body: seq[GeneValue] = @[]
      for i in 3..<self.d.gene_data.len:
        body.add(self.d.gene_data[i])
      self.d.gene_data = body

  if self.d.gene_data.len == 0:
    return

  var first = self.d.gene_data[0]
  if first.d.kind == GeneSymbol:
    if first.d.symbol == "+=":
      self.d.gene_op = new_gene_symbol("=")
      var second = self.d.gene_data[1]
      self.d.gene_data[0] = op
      self.d.gene_data[1] = new_gene_gene(new_gene_symbol("+"), op, second)
    elif first.d.symbol in BINARY_OPS:
      self.d.gene_data.delete 0
      self.d.gene_data.insert op, 0
      self.d.gene_op = first
    elif first.d.symbol.startsWith(".@"):
      if first.d.symbol.endsWith("="):
        todo()
      else:
        self.d.gene_op = new_gene_symbol("@")
        self.d.gene_data[0] = new_gene_string_move(first.d.symbol.substr(2))
        self.d.gene_props["self"] = op
    elif first.d.symbol[0] == '.':
      self.d.gene_props["self"] = op
      self.d.gene_props["method"] = new_gene_string_move(first.d.symbol.substr(1))
      self.d.gene_data.delete 0
      self.d.gene_op = new_gene_symbol("$invoke_method")

#################### Document ####################

proc new_doc*(data: seq[GeneValue]): GeneDocument =
  return GeneDocument(data: data)

#################### Application #################

APP = Application(
  ns: new_namespace("global")
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
  if v.d == nil:
    return false
  case v.d.kind:
  of GeneBool:
    return v.d.boolVal
  of GeneInt:
    return v.d.num != 0
  of GeneFloat:
    return v.d.fnum != 0
  of GeneString:
    return v.d.str.len != 0
  of GeneVector:
    return v.d.vec.len != 0
  else:
    true

#################### Dynamic #####################

proc load_dynamic*(path:string, names: seq[string]): Table[string, native_proc] =
  result = Table[string, native_proc]()
  let lib = loadLib(path)
  for name in names:
    var s = name
    let p = lib.symAddr(s)
    result[s] = cast[native_proc](p)

# This is not needed
# proc call_dynamic*(p: native_proc, args: seq[GeneValue]): GeneValue =
#   return p(args)
