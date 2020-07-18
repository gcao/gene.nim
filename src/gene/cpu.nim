import strformat, logging

import ./types
import ./vm
import ./compiler
import ./interpreter

#################### Interfaces ##################

#################### Implementations #############

proc run*(self: var VM, module: Module): GeneValue =
  self.cur_block = module.default

  var instr: Instruction
  self.pos = 0
  while self.pos < self.cur_block.instructions.len:
    instr = self.cur_block.instructions[self.pos]
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
      self.cur_stack[0] = self.cur_stack[name]
    of Add:
      self.pos += 1
      let first = self.cur_stack[instr.reg].num
      let second = self.cur_stack[instr.reg2].num
      self.cur_stack[0] = new_gene_int(first + second)
    of Sub:
      self.pos += 1
      let first = self.cur_stack[instr.reg].num
      let second = self.cur_stack[instr.reg2].num
      self.cur_stack[0] = new_gene_int(first - second)
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
    of CreateFunction:
      self.pos += 1
      var fn = instr.val
      self.cur_stack.cur_ns[fn.internal.fn.name] = fn
    of CreateArguments:
      self.pos += 1
      var args = instr.val
      self.cur_stack[instr.reg] = args
    of Call:
      self.pos += 1
      var fn = self.cur_stack[0].internal.fn
      var args = self.cur_stack[instr.reg].internal.args
      # Interpret the function body
      # self.cur_stack[0] = self.call(fn, args)
      # Or
      # Run the compiled function body
      var stack = self.cur_stack
      self.cur_stack = stack.grow()
      for i in 0..<fn.args.len:
        var arg = fn.args[i]
        var val = args[i]
        self.cur_stack.cur_scope[arg] = val

      self.cur_stack.caller = new_caller(stack, self.cur_block, self.pos)
      self.cur_block = fn.body_block
      self.pos = 0

    of CallEnd:
      var caller = self.cur_stack.caller
      if caller.isNil:
        not_allowed()
      else:
        caller.stack[0] = self.cur_stack[0]
        self.cur_stack = caller.stack
        self.cur_block = caller.blk
        self.pos = caller.pos
    of SetItem:
      self.pos += 1
      var val = self.cur_stack[instr.reg]
      var index = instr.val.num
      if val.kind == GeneInternal and val.internal.kind == GeneArguments:
        val.internal.args[cast[int](index)] = self.cur_stack[0]
      else:
        todo($instr)
    else:
      self.pos += 1
      todo($instr)

  result = self.cur_stack.default
