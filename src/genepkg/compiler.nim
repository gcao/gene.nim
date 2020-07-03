import sequtils

import parser
import types

type
  InstrType* = enum
    Init
    Default
  Instruction* = ref InstructionObj
  InstructionObj* = object
    case kind*: InstrType
    of Default:
      value: GeneValue
    else: discard

proc instr_init*(): Instruction = Instruction(kind: Init)

proc compile*(node: GeneNode): seq[Instruction] =
  result.add(instr_init())
  case node.kind:
    of GeneNil:
      discard
    else: discard

proc compile*(nodes: seq[GeneNode]): seq[Instruction] =
  for node in nodes:
    result = concat(result, compile(node))

proc compile*(buffer: string): seq[Instruction] =
  var nodes = read_all(buffer)
  return compile(nodes)
