import sequtils, tables, oids

import ./types
import ./parser

type
  InstrType* = enum
    Init
    Default

  Instruction* = ref object
    case kind*: InstrType
    of Default:
      value*: GeneValue
    else: discard

  Block* = ref object
    id*: Oid
    name*: string
    instructions*: seq[Instruction]

  Module* = ref object
    id*: Oid
    blocks*: Table[Oid, Block]
    default*: Block
    # TODO: support (main ...)
    # main_block* Block

  Compiler* = ref object
    module*: Module
    cur_block: Block

#################### Interfaces ##################

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

proc instr_default*(value: GeneValue): Instruction = Instruction(kind: Default, value: value)

#################### Block ####################

proc new_block*(): Block =
  result = Block(id: genOid())

proc add(self: var Block, instr: Instruction) =
  self.instructions.add(instr)

#################### Module ####################

proc new_module*(): Module =
  result = Module()

proc set_default*(self: var Module, blk: Block) =
  self.default = blk
  self.blocks[blk.id] = blk

#################### Compiler ####################

proc new_compiler*(): Compiler =
  result = Compiler()

proc compile*(self: var Compiler, blk: var Block, node: GeneValue) =
  case node.kind:
  of GeneNilKind, GeneInt, GeneFloat, GeneRatio, GeneBool, GeneChar, GeneString:
    blk.add(instr_default(node))
  else:
    todo()

proc compile*(self: var Compiler, doc: GeneDocument): Block =
  result = new_block()
  for node in doc.data:
    self.compile(result, node)

proc compile*(self: var Compiler, buffer: string): Module =
  var doc = read_document(buffer)
  self.module = new_module()
  var blk = self.compile(doc)
  self.module.setDefault(blk)
  return self.module
