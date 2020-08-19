import strformat, logging, tables

import ./types
import ./interpreter
import ./vm
import ./compiler

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
      self.cur_stack[0] = instr.val
    of CreateArguments:
      self.pos += 1
      var args = instr.val
      self.cur_stack[instr.reg] = args
    of CreateNamespace:
      self.pos += 1
      var name = instr.val.str
      var ns = new_namespace(name)
      var val = new_gene_internal(ns)
      self.cur_stack.cur_ns[name] = val
      self.cur_stack[0] = val
    of Import:
      self.pos += 1
      var module = self.cur_stack[0].str
      var ns: Namespace
      if not APP.namespaces.hasKey(module):
        self.eval_module(module)
      ns = APP.namespaces[module]
      if ns == nil:
        todo("Evaluate module")
      var names = instr.val.vec
      for name in names:
        var s = name.symbol
        self.cur_stack.cur_ns[s] = ns[s]
    of CreateClass:
      self.pos += 1
      var name = instr.val.str
      var class = new_class(name)
      var val = new_gene_internal(class)
      self.cur_stack.cur_ns[name] = val
      self.cur_stack[0] = val
    of CreateMethod:
      self.pos += 1
      var fn = self.cur_stack[0].internal.fn
      var class = self.cur_stack.self.internal.class
      class.methods[fn.name] = fn
    of CreateInstance:
      self.pos += 1
      var class = self.cur_stack[0].internal.class
      var instance = new_gene_instance(new_instance(class))
      self.cur_stack[0] = instance
      if class.methods.hasKey("new"):
        var fn = class.methods["new"]
        var stack = self.cur_stack
        var caller = new_caller(stack, self.cur_block, self.pos)
        self.cur_stack = stack.grow()
        self.cur_stack.self = instance
        self.cur_stack.caller = caller
        self.cur_block = fn.body_block
        self.pos = 0
    of PropGet:
      self.pos += 1
      var name = instr.val.str
      var val = self.cur_stack.self.instance.value.gene_props[name]
      self.cur_stack[0] = val
    of PropSet:
      self.pos += 1
      var name = instr.val.str
      var val = self.cur_stack[instr.reg]
      self.cur_stack.self.instance.value.gene_props[name] = val
    of InvokeMethod:
      self.pos += 1
      var this = self.cur_stack[instr.reg]
      var name = instr.val.str
      var fn = this.instance.class.methods[name]
      var args = self.cur_stack[instr.reg2].internal.args
      # Interpret the function body
      # self.cur_stack[0] = self.call(fn, args)
      # Or
      # Run the compiled function body
      var stack = self.cur_stack
      self.cur_stack = stack.grow()
      self.cur_stack.self = this
      for i in 0..<fn.args.len:
        var arg = fn.args[i]
        var val = args[i]
        self.cur_stack.cur_scope[arg] = val

      self.cur_stack.caller = new_caller(stack, self.cur_block, self.pos)
      self.cur_block = fn.body_block
      self.pos = 0
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

    of CallBlock:
      self.pos += 1
      var blk = self.cur_stack[instr.reg].internal.blk
      var stack = self.cur_stack
      self.cur_stack = stack.grow()
      self.cur_stack.self = stack[instr.reg2]

      self.cur_stack.caller = new_caller(stack, self.cur_block, self.pos)
      self.cur_block = blk
      self.pos = 0

    of CallEnd:
      var caller = self.cur_stack.caller
      if caller.isNil:
        not_allowed()
      else:
        if not self.cur_block.no_return:
          caller.stack[0] = self.cur_stack[0]
        self.cur_stack = caller.stack
        self.cur_block = caller.blk
        self.pos = caller.pos

    of CallBlockById:
      todo()

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
