import parser

type
  InstrType = enum
    Init
  Instruction = object
    kind: InstrType

proc compile(code: seq[GeneNode]): seq[Instruction] =
  discard
