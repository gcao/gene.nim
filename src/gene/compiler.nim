import sets, sequtils, tables, oids

import ./types
import ./parser
import ./vm

type
  InstrType* = enum
    Init

    # # Save Value to default register
    Default
    # Save Value to a register
    Save
    # Copy from one register to another
    Copy

    # DefMember(String)
    # DefMemberInScope(String)
    # DefMemberInNS(String)
    # GetMember(String)
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

    # Jump(i16)
    # JumpIfFalse(i16)
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

    # # Function(name, args reg, block id)
    # Function(String, Matcher, String)
    # # Create an argument object and store in a register
    # CreateArguments(u16)

    # # Call(options)
    # Call(u16, Option<u16>, HashMap<String, Rc<dyn Any>>)
    # CallEnd

  Instruction* = ref object
    case kind*: InstrType
    else:
      discard
    reg*: int       # Optional: Default register
    reg2*: int      # Optional: Second register
    val*: GeneValue # Optional: Default immediate value

  Block* = ref object
    id*: Oid
    name*: string
    instructions*: seq[Instruction]
    ## This is not needed after compilation
    reg_mgr*: RegManager

  Module* = ref object
    id*: Oid
    blocks*: Table[Oid, Block]
    default*: Block
    # TODO: support (main ...)
    # main_block* Block

  Compiler* = ref object
    module*: Module
    cur_block: Block

  RegManager* = ref object
    next*: int
    freed*: HashSet[int]

#################### Interfaces ##################

proc compile_gene*(self: var Compiler, blk: var Block, node: GeneValue)

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

proc instr_default*(val: GeneValue): Instruction =
  return Instruction(kind: Default, val: val)

proc instr_save*(reg: int, val: GeneValue): Instruction =
  return Instruction(kind: Save, reg: reg, val: val)

proc instr_copy*(reg, reg2: int): Instruction =
  return Instruction(kind: Copy, reg: reg, reg2: reg2)

#################### RegManager ###############

proc get(self: var RegManager): int =
  if self.freed.len > 0:
    return self.freed.pop
  else:
    result = self.next
    self.next += 1

proc free(self: var RegManager, reg: int) =
  self.freed.incl(reg)

#################### Block ####################

proc new_block*(): Block =
  result = Block(
    id: genOid(),
    reg_mgr: RegManager(next: 0),
  )

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
  of GeneGene:
    self.compile_gene(blk, node)
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
  self.module.set_default(blk)
  return self.module

proc compile_gene*(self: var Compiler, blk: var Block, node: GeneValue) =
  node.normalize

  case node.op.kind:
  of GeneSymbol:
    if node.op.symbol == "+":
      todo()
    else:
      todo()
  else:
    todo()
