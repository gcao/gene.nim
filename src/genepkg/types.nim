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
  elif that.is_nil:
    return false
  elif this.kind != that.kind:
    return false
  else:
    case this.kind
    of GeneNil:
      return true
    else:
      return false
