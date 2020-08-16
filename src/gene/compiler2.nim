import ./types
import ./parser

type
  Compiler2* = ref object
    module*: Module
    cur_block: Block

  BlockItemKind* = enum
    InstructionKind
    BlockKind

  BlockItem* = ref object
    case kind*: BlockItemKind
    of InstructionKind:
      instr*: Instruction
    of BlockKind:
      blk*: PseudoBlock

  PseudoBlock* = ref object
    parent*: PseudoBlock
    prev*: PseudoBlock
    next*: PseudoBlock
    children*: seq[BlockItem]

#################### PseudoBlock #################

proc new_pseudo_block*(): PseudoBlock =
  return PseudoBlock()

proc add*(self: var PseudoBlock, instr: Instruction) =
  self.children.add(BlockItem(kind: InstructionKind, instr: instr))

proc add(blk: var Block, blk2: PseudoBlock) =
  for item in blk2.children:
    case item.kind:
    of InstructionKind:
      blk.add(item.instr)
    of BlockKind:
      blk.add(item.blk)

converter to_block*(v: PseudoBlock): Block =
  result = new_block()
  for item in v.children:
    case item.kind:
    of InstructionKind:
      result.add(item.instr)
    of BlockKind:
      result.add(item.blk)

##################################################

proc new_compiler2*(): Compiler2 =
  return Compiler2()

proc compile_gene*(self: var Compiler2, blk: var PseudoBlock, node: GeneValue) =
  node.normalize
  todo()

proc compile*(self: var Compiler2, blk: var PseudoBlock, node: GeneValue) =
  case node.kind:
  of GeneNilKind, GeneInt, GeneFloat, GeneRatio, GeneBool, GeneChar, GeneString:
    blk.add(instr_default(node))
  of GeneSymbol:
    blk.add(instr_get_member(node.symbol))
  of GeneGene:
    self.compile_gene(blk, node)
  else:
    todo($node)

proc compile*(self: var Compiler2, doc: GeneDocument): PseudoBlock =
  result = new_pseudo_block()
  for node in doc.data:
    self.compile(result, node)

proc compile*(self: var Compiler2, buffer: string): Module =
  var doc = read_document(buffer)
  self.module = new_module()
  var blk = self.compile(doc)
  self.module.set_default(blk)
  return self.module
