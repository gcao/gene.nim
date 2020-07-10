import strutils

const BINARY_OPS* = [
  "+", "-", "*", "/",
  "=", "+=", "-=", "*=", "/=",
  "==", "!=", "<", "<=", ">", ">=",
  "&&", "||", # TODO: xor
  "&",  "|",  # TODO: xor for bit operation
]

type
  Function* = ref object
    name*: string
    args*: seq[string]
    body*: seq[GeneValue]

  Arguments* = ref object
    positional*: seq[GeneValue]

  GeneInternalKind* = enum
    GeneFunction
    GeneArguments

  Internal* = ref object
    case kind*: GeneInternalKind
    of GeneFunction:
      fn*: Function
    of GeneArguments:
      args*: Arguments

  GeneKind* = enum
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
    GeneTaggedValue
    GeneCommentLine
    GeneRegex
    GeneInternal

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
    of GeneNilKind:
      nil
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
      symbol_meta*: HMap
    of GeneComplexSymbol:
      csymbol*: tuple[ns, name: string]
      csymbol_meta*: HMap
    of GeneKeyword:
      keyword*: tuple[ns, name: string]
      is_namespaced*: bool
    of GeneGene:
      op*: GeneValue
      list*: seq[GeneValue]
      list_meta*: HMap
      # A gene can be normalized to match expected format
      # Example: (a = 1) => (= a 1)
      normalized*: bool
    of GeneMap:
      map*: HMap
      map_meta*: HMap
    of GeneVector:
      vec*: seq[GeneValue]
      vec_meta*: HMap
    of GeneSet:
      set_elems*: HMap
      set_meta*: HMap
    of GeneTaggedValue:
      tag*:  tuple[ns, name: string]
      value*: GeneValue
    of GeneCommentLine:
      comment*: string
    of GeneRegex:
      regex*: string
    of GeneInternal:
      internal*: Internal
    line*: int
    column*: int
    comments*: seq[Comment]

  GeneDocument* = ref object
    name*: string
    path*: string
    data*: seq[GeneValue]

#################### GeneValue ###################

proc `==`*(this, that: GeneValue): bool =
  if this.is_nil:
    if that.is_nil: return true
    return false
  elif that.is_nil or this.kind != that.kind:
    return false
  else:
    case this.kind
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
      return this.op == that.op and this.list == that.list
    of GeneMap:
      return this.map == that.map
    of GeneVector:
      return this.vec == that.vec
    of GeneSet:
      return this.set_elems == that.set_elems
    of GeneTaggedValue:
      return this.tag == that.tag and this.value == that.value
    of GeneCommentLine:
      return this.comment == that.comment
    of GeneRegex:
      return this.regex == that.regex
    of GeneInternal:
      return this.internal == that.internal

proc `$`*(node: GeneValue): string =
  case node.kind
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
    if node.csymbol.ns == "":
      result = node.csymbol.name
    else:
      result = node.csymbol.ns & "/" & node.csymbol.name
  else:
    result = $node.kind

## ============== NEW OBJ FACTORIES =================

let
  gene_nil*  = GeneValue(kind: GeneNilKind)
  gene_true*  = GeneValue(kind: GeneBool, bool_val: true)
  gene_false* = GeneValue(kind: GeneBool, bool_val: false)

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
  of true: return gene_true
  of false: return gene_false
  # of true: return GeneValue(kind: GeneBool, boolVal: true)
  # of false: return GeneValue(kind: GeneBool, boolVal: false)

proc new_gene_bool*(s: string): GeneValue =
  let parsed: bool = parseBool(s)
  return new_gene_bool(parsed)

proc new_gene_symbol*(name: string): GeneValue =
  return GeneValue(kind: GeneSymbol, symbol: name)

proc new_gene_complex_symbol*(ns, name: string): GeneValue =
  return GeneValue(kind: GeneComplexSymbol, csymbol: (ns, name))

proc new_gene_keyword*(ns, name: string): GeneValue =
  return GeneValue(kind: GeneKeyword, keyword: (ns, name))

proc new_gene_keyword*(name: string): GeneValue =
  return GeneValue(kind: GeneKeyword, keyword: ("", name))

proc new_gene_internal*(value: Internal): GeneValue =
  return GeneValue(kind: GeneInternal, internal: value)

### === VALS ===

let
  GeneNil*: GeneValue  = gene_nil
  GeneTrue*: GeneValue  = gene_true
  GeneFalse*: GeneValue = gene_false
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
  if self.list.len == 0:
    return
  var first = self.list[0]
  if first.kind == GeneSymbol:
    if first.symbol in BINARY_OPS:
      var op = self.op
      self.list.delete 0
      self.list.insert op, 0
      self.op = first

#################### Arguments ###################

proc new_args*(): Arguments =
  return Arguments(positional: @[])

proc new_args*(args: seq[GeneValue]): Arguments =
  return Arguments(positional: args)

proc `[]`*(self: Arguments, i: int): GeneValue =
  return self.positional[i]

#################### Document ###################

proc new_doc*(data: seq[GeneValue]): GeneDocument =
  return GeneDocument(data: data)
