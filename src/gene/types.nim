import strutils, oids, sets, tables

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

    DefMember
    # DefMemberInScope(String)
    # DefMemberInNS(String)
    GetMember
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
    # reg - default
    Sub
    Mul
    Div
    Pow
    Mod
    Eq
    Neq
    Lt
    Le
    Gt
    Ge
    And
    Or
    Not
    # BitAnd
    # BitOr
    # BitXor

    # Function(fn)
    CreateFunction
    # Arguments(reg): create an arguments object and store in register <reg>
    CreateArguments

    CreateNamespace # name

    CreateClass # name

    # Call(target reg, args reg)
    Call
    CallEnd

    ## Call a block by id
    CallBlockById

  Instruction* = ref object
    kind*: InstrType
    reg*: int       # Optional: Default register
    reg2*: int      # Optional: Second register
    val*: GeneValue # Optional: Default immediate value

  Block* = ref object
    id*: Oid
    name*: string
    instructions*: seq[Instruction]
    ## This is not needed after compilation
    reg_mgr*: RegManager

  RegManager* = ref object
    next*: int
    freed*: HashSet[int]

  Namespace* = ref object
    parent*: Namespace
    name*: string
    members*: Table[string, GeneValue]
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

  Arguments* = ref object
    positional*: seq[GeneValue]

  GeneInternalKind* = enum
    GeneFunction
    GeneArguments
    GeneClass
    GeneNamespace

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

  GeneValue* {.acyclic.} = ref object
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
    line*: int
    column*: int
    comments*: seq[Comment]

  GeneDocument* = ref object
    name*: string
    path*: string
    data*: seq[GeneValue]

let
  GeneNil*   = GeneValue(kind: GeneNilKind)
  GeneTrue*  = GeneValue(kind: GeneBool, bool_val: true)
  GeneFalse* = GeneValue(kind: GeneBool, bool_val: false)

var APP*: Application

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
      return this.val == that.val
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
      return this.gene_op == that.gene_op and this.gene_data == that.gene_data
    of GeneMap:
      return this.map == that.map
    of GeneVector:
      return this.vec == that.vec
    of GeneSet:
      return this.set_elems == that.set_elems
    of GeneCommentLine:
      return this.comment == that.comment
    of GeneRegex:
      return this.regex == that.regex
    of GeneInternal:
      return this.internal == that.internal
    of GeneInstance:
      return this.instance == that.instance

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
  of GeneInternal:
    case node.internal.kind:
    of GeneFunction:
      result = "(fn $# ...)" % [node.internal.fn.name]
    else:
      result = "GeneInternal"
  else:
    result = $node.kind

## ============== NEW OBJ FACTORIES =================

proc new_gene_string_move*(s: string): GeneValue =
  result = GeneValue(kind: GeneString)
  shallowCopy(result.str, s)

proc new_gene_int*(s: string): GeneValue =
  return GeneValue(kind: GeneInt, num: parseBiggestInt(s))

proc new_gene_int*(val: int): GeneValue =
  return GeneValue(kind: GeneInt, num: val)

proc new_gene_int*(val: BiggestInt): GeneValue =
  return GeneValue(kind: GeneInt, num: val)

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

proc new_gene_arguments*(): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneArguments, args: new_args()),
  )

proc new_class*(name: string): Class =
  return Class(name: name)

proc new_instance*(class: Class): Instance =
  return Instance(value: new_gene_gene(GeneNil), class: class)

proc new_namespace*(): Namespace =
  return Namespace(
    name: "<root>",
    members: Table[string, GeneValue](),
  )

proc new_namespace*(name: string): Namespace =
  return Namespace(
    name: name,
    members: Table[string, GeneValue](),
  )

proc new_namespace*(parent: Namespace, name: string): Namespace =
  return Namespace(
    parent: parent,
    name: name,
    members: Table[string, GeneValue](),
  )

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
    if op.symbol == "import":
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

  if self.gene_data.len == 0:
    return

  var first = self.gene_data[0]
  if first.kind == GeneSymbol:
    if first.symbol in BINARY_OPS:
      self.gene_data.delete 0
      self.gene_data.insert op, 0
      self.gene_op = first
    elif first.symbol[0] == '.':
      self.gene_props["self"] = op
      self.gene_props["method"] = new_gene_string_move(first.symbol.substr(1))
      self.gene_data.delete 0
      self.gene_op = new_gene_symbol("$invoke_method")

#################### Document ###################

proc new_doc*(data: seq[GeneValue]): GeneDocument =
  return GeneDocument(data: data)

#################### Application #######################

APP = Application(
  ns: new_namespace("global")
)
