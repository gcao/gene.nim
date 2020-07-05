import sequtils, tables

import ./types
import ./parser

type
  InstrType* = enum
    Init
    Default
  Instruction* = ref object
    case kind*: InstrType
    of Default:
      value: GeneValue
    else: discard

  Block* = ref object
    id*: string
    name*: string
    instructions*: seq[Instruction]

  Module* = ref object
    id*: string
    blocks*: Table[string, Block]
    default*: Block

  Compiler* = ref object
    module*: Module
    cur_block: Block

#################### Instruction #################

proc `==`*(this, that: Instruction): bool =
  if this.is_nil:
    if that.is_nil: return true
    return false
  elif that.is_nil:
    return false
  elif this.kind != that.kind:
    return false
  else:
    case this.kind
    of Init:
      return true
    else:
      return false

proc instr_init*(): Instruction = Instruction(kind: Init)

#################### Compiler ####################

proc compile*(self: var Compiler, node: GeneValue): seq[Instruction] =
  result.add(instr_init())
  case node.kind:
    else: todo()

proc compile*(self: var Compiler, nodes: seq[GeneValue]): seq[Instruction] =
  for node in nodes:
    result = concat(result, self.compile(node))

proc compile*(self: var Compiler, buffer: string): seq[Instruction] =
  var nodes = read_all(buffer)
  return self.compile(nodes)
