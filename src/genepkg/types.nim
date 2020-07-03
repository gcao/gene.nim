type
  ValueType* = enum
    Nil
    Int
  GeneValue* = ref GeneValueObj
  GeneValueObj = object
    case kind: ValueType
    of Int:
      value: int
    else: discard