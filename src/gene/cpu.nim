import strformat

import ./types
import ./vm
import ./compiler

#################### Interfaces ##################

proc run*(self: var VM, blk: Block): GeneValue

#################### Implementations #############

proc run*(self: var VM, module: Module): GeneValue =
  var blk = module.default
  return self.run(blk)

proc run*(self: var VM, blk: Block): GeneValue =
  var instr: Instruction
  self.pos = 0
  while self.pos < blk.instructions.len:
    instr = blk.instructions[self.pos]
    echo &"{self.pos:>4} {instr}"
    case instr.kind:
    of Default:
      self.pos += 1
      self.cur_stack[0] = instr.val
    of Save:
      self.pos += 1
      self.cur_stack[instr.reg] = instr.val
    of Copy:
      self.pos += 1
      self.cur_stack[instr.reg2] = self.cur_stack[instr.reg]
    of Add:
      self.pos += 1
      let first = self.cur_stack[instr.reg].num
      let second = self.cur_stack[instr.reg2].num
      self.cur_stack[instr.reg] = new_gene_int(first + second)
    else:
      self.pos += 1
      todo()

  result = self.cur_stack.default
