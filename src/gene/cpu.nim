import strformat, logging

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
    debug(&"{self.pos:>4} {instr}")
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
    of DefMember:
      self.pos += 1
      var name = instr.val.str
      self.cur_stack.cur_scope[name] = self.cur_stack[0]
    of GetMember:
      self.pos += 1
      var name = instr.val.str
      self.cur_stack[0] = self.cur_stack.cur_scope[name]
    of Add:
      self.pos += 1
      let first = self.cur_stack[instr.reg].num
      let second = self.cur_stack[instr.reg2].num
      self.cur_stack[0] = new_gene_int(first + second)
    of Lt:
      self.pos += 1
      let first = self.cur_stack[instr.reg].num
      let second = self.cur_stack[instr.reg2].num
      self.cur_stack[0] = new_gene_bool(first < second)
    of Jump:
      self.pos = cast[int](instr.val.num)
    of JumpIfFalse:
      if self.cur_stack[instr.reg].isTruthy:
        self.pos += 1
      else:
        self.pos = cast[int](instr.val.num)
    else:
      self.pos += 1
      todo()

  result = self.cur_stack.default
