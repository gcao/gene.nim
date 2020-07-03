type
  GeneKind* = enum
    GeneNil
    GeneBool
    GeneChar
    GeneInt
    GeneRatio
    GeneFloat
    GeneString
    GeneSymbol
    GeneKeyword
    GeneGene
    GeneMap
    GeneVector
    GeneSet
    GeneTaggedValue
    GeneCommentLine
    GeneRegex

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
    of GeneNil:
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
      symbol*: tuple[ns, name: string]
      symbol_meta*: HMap
    of GeneKeyword:
      keyword*: tuple[ns, name: string]
      is_namespaced*: bool
    of GeneGene:
      list*: seq[GeneValue]
      list_meta*: HMap
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
    line*: int
    column*: int
    comments*: seq[Comment]

  GeneDocument* = ref object
    ## Name or path of the document
    name: string
    data: seq[GeneValue]

let Nil* = GeneValue(kind: GeneNil)

proc `==`*(this, that: GeneValue): bool =
  if this.is_nil:
    if that.is_nil: return true
    return false
  elif that.is_nil or this.kind != that.kind:
    return false
  else:
    case this.kind
    of GeneNil:
      return that.kind == GeneNil
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
    of GeneKeyword:
      return this.keyword == that.keyword and this.is_namespaced == that.is_namespaced
    of GeneGene:
      return this.list == that.list
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
