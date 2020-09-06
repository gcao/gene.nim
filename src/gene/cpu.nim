# import strformat, logging
import tables, hashes, sequtils

import ./types
import ./interpreter
import ./vm
import ./compiler

#################### Interfaces ##################

#################### Implementations #############

proc run*(self: var VM, module: Module): GeneValue =
  var cur_block = module.default
  var pos = 0
  var instr: Instruction
  while pos < cur_block.instructions.len:
    instr = cur_block.instructions[pos]
    # debug(&"{pos:>4} {instr}")
    case instr.kind:
    of Default:
      pos += 1
      self.cur_stack[0] = instr.val
    of Save:
      pos += 1
      self.cur_stack[instr.reg] = instr.val
    of Copy:
      pos += 1
      self.cur_stack[instr.reg2] = self.cur_stack[instr.reg]
    of Print, Println:
      pos += 1
      let val = self.cur_stack[instr.reg]
      case val.kind:
      of GeneNilKind:
        discard
      of GeneString:
        stdout.write(val.str)
      else:
        stdout.write($val)
      if instr.kind == Println:
        stdout.write("\n")
    of Global:
      pos += 1
      self.cur_stack[0] = new_gene_internal(APP.ns)
    of Self:
      pos += 1
      self.cur_stack[0] = self.cur_stack.self
    of DefMember:
      pos += 1
      let key = instr.reg
      self.cur_stack.cur_scope[key] = self.cur_stack[0]
    of DefNsMember:
      pos += 1
      let name = instr.val
      case name.kind:
      of GeneSymbol:
        var key = name.symbol.hash
        self.cur_stack.cur_ns[key] = self.cur_stack[0]
      of GeneComplexSymbol:
        var csymbol = name.csymbol
        var ns: Namespace
        case csymbol.first:
        of "global":
          ns = APP.ns
        else:
          ns = self.cur_stack.cur_ns
          var key = csymbol.first.hash
          ns = ns[key].internal.ns
        for i in 0..<csymbol.rest.len - 1:
          var key = csymbol.rest[i].hash
          ns = ns[key].internal.ns
        var key = csymbol.rest[^1].hash
        ns[key] = self.cur_stack[0]
      else:
        not_allowed()
    of GetMember:
      pos += 1
      var key = instr.reg
      self.cur_stack[0] = self.cur_stack.get(key)
    of GetNestedNsMember:
      pos += 1
      var name = instr.val.csymbol
      var ns: Namespace
      case name.first:
      of "global":
        ns = APP.ns
      else:
        var key = name.first.hash
        ns = self.cur_stack.cur_ns[key].internal.ns
      for i in 0..<name.rest.len - 1:
        var s = name.rest[i]
        var key = s.hash
        ns = ns[key].internal.ns
      var key = name.rest[^1].hash
      self.cur_stack[0] = ns[key]
    of Add:
      pos += 1
      let first = self.cur_stack[instr.reg].num
      let second = self.cur_stack[instr.reg2].num
      self.cur_stack[0] = new_gene_int(first + second)
    of AddI:
      pos += 1
      let first = self.cur_stack[instr.reg].num
      let second = instr.val.num
      self.cur_stack[0] = new_gene_int(first + second)
    of Sub:
      pos += 1
      let first = self.cur_stack[instr.reg].num
      let second = self.cur_stack[instr.reg2].num
      self.cur_stack[0] = new_gene_int(first - second)
    of SubI:
      pos += 1
      let first = self.cur_stack[instr.reg].num
      let second = instr.val.num
      self.cur_stack[0] = new_gene_int(first - second)
    of Lt:
      pos += 1
      let first = self.cur_stack[instr.reg].num
      let second = self.cur_stack[instr.reg2].num
      self.cur_stack[0] = new_gene_bool(first < second)
    of LtI:
      pos += 1
      let first = self.cur_stack[instr.reg].num
      let second = instr.val.num
      self.cur_stack[0] = new_gene_bool(first < second)
    of Jump:
      pos = cast[int](instr.val.num)
    of JumpIfFalse:
      if self.cur_stack[instr.reg].isTruthy:
        pos += 1
      else:
        pos = cast[int](instr.val.num)
    of CreateFunction:
      pos += 1
      var fn = instr.val
      let key = cast[Hash](fn.internal.fn.name.hash)
      self.cur_stack.cur_ns[key] = fn
      self.cur_stack[0] = instr.val
    of CreateArguments:
      pos += 1
      var args = instr.val
      self.cur_stack[instr.reg] = args
    of CreateNamespace:
      pos += 1
      var name = instr.val.str
      var ns = new_namespace(name)
      var val = new_gene_internal(ns)
      let key = cast[Hash](name.hash)
      self.cur_stack.cur_ns[key] = val
      self.cur_stack[0] = val
    of Import:
      pos += 1
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
        let key = cast[Hash](s.hash)
        self.cur_stack.cur_ns[key] = ns[key]
    of ImportNative:
      pos += 1
      var module = self.cur_stack[0].str
      var names = instr.val.vec.map(proc(v: GeneValue): string = v.symbol)
      var mappings = load_dynamic(module, names)
      for name in names:
        let key = cast[Hash](name.hash)
        self.cur_stack.cur_ns[key] = new_gene_internal(mappings[name])
    of CreateClass:
      pos += 1
      var name = instr.val.str
      var class = new_class(name)
      var val = new_gene_internal(class)
      let key = cast[Hash](name.hash)
      self.cur_stack.cur_ns[key] = val
      self.cur_stack[0] = val
    of CreateMethod:
      pos += 1
      var fn = self.cur_stack[0].internal.fn
      var class = self.cur_stack.self.internal.class
      class.methods[fn.name] = fn
    of CreateInstance:
      pos += 1
      var class = self.cur_stack[0].internal.class
      var instance = new_gene_instance(new_instance(class))
      self.cur_stack[0] = instance
      if class.methods.hasKey("new"):
        var fn = class.methods["new"]
        var stack = self.cur_stack
        var args = self.cur_stack[instr.reg].internal.args
        self.cur_stack = StackMgr.get
        self.cur_stack.cur_ns = stack.cur_ns
        self.cur_stack.cur_scope = ScopeMgr.get()
        self.cur_stack.self = instance
        self.cur_stack.caller_stack = stack
        self.cur_stack.caller_blk = cur_block
        self.cur_stack.caller_pos = pos
        for i in 0..<fn.args.len:
          var arg = fn.args[i]
          var val = args[i]
          let key = cast[Hash](arg.hash)
          self.cur_stack.cur_scope[key] = val
        cur_block = fn.body_block
        pos = 0
    of PropGet:
      pos += 1
      var name = instr.val.str
      var this = self.cur_stack[0]
      var val = this.instance.value.gene_props[name]
      self.cur_stack[0] = val
    of PropSet:
      pos += 1
      var name = instr.val.str
      var val = self.cur_stack[instr.reg]
      self.cur_stack.self.instance.value.gene_props[name] = val

    of InvokeMethod:
      pos += 1
      var this = self.cur_stack[instr.reg]
      var name = instr.val.str
      var fn = this.instance.class.methods[name]
      var args = self.cur_stack[instr.reg2].internal.args
      var stack = self.cur_stack
      var cur_stack = StackMgr.get
      cur_stack.self = this
      cur_stack.cur_ns = stack.cur_ns
      cur_stack.cur_scope = ScopeMgr.get()
      for i in 0..<fn.args.len:
        var arg = fn.args[i]
        var val = args[i]
        let key = cast[Hash](arg.hash)
        cur_stack.cur_scope[key] = val
      cur_stack.caller_stack = stack
      cur_stack.caller_blk = cur_block
      cur_stack.caller_pos = pos
      self.cur_stack = cur_stack
      cur_block = fn.body_block
      pos = 0

    of Call:
      pos += 1
      var stack = self.cur_stack
      var fn = stack[0].internal.fn
      var args = stack[instr.reg].internal.args
      var cur_stack = StackMgr.get()
      cur_stack.cur_ns = stack.cur_ns
      cur_stack.cur_scope = ScopeMgr.get()
      for i in 0..<fn.args.len:
        var arg = fn.args[i]
        var val = args[i]
        let key = cast[Hash](arg.hash)
        cur_stack.cur_scope[key] = val
      cur_stack.caller_stack = stack
      cur_stack.caller_blk = cur_block
      cur_stack.caller_pos = pos
      self.cur_stack = cur_stack
      cur_block = fn.body_block
      pos = 0

    of CallNative:
      pos += 1
      var name = instr.val.str
      case name:
      of "str_len":
        var args = self.cur_stack[instr.reg].internal.args
        var str = args[0].str
        self.cur_stack[0] = new_gene_int(str.len)
      else:
        todo(name)

    of InvokeNative:
      pos += 1
      var target = self.cur_stack[instr.reg].internal.native_proc
      var args = self.cur_stack[instr.reg2].internal.args
      self.cur_stack[0] = target(args.positional)

    of CallBlock:
      pos += 1
      var stack = self.cur_stack
      var cur_stack = StackMgr.get
      cur_stack.cur_ns = stack.cur_ns
      cur_stack.cur_scope = ScopeMgr.get()
      cur_stack.self = stack[instr.reg2]
      cur_stack.caller_stack = stack
      cur_stack.caller_blk = cur_block
      cur_stack.caller_pos = pos
      self.cur_stack = cur_stack
      cur_block = stack[instr.reg].internal.blk
      pos = 0

    of CallEnd:
      var stack = self.cur_stack
      self.cur_stack = stack.caller_stack
      if not cur_block.no_return:
        self.cur_stack[0] = stack[0]
      cur_block = stack.caller_blk
      pos = stack.caller_pos
      ScopeMgr.free(stack.cur_scope)
      StackMgr.free(stack)

    of SetItem:
      pos += 1
      var val = self.cur_stack[instr.reg]
      var index = instr.val.num
      if val.kind == GeneInternal and val.internal.kind == GeneArguments:
        val.internal.args[cast[int](index)] = self.cur_stack[0]
      else:
        todo($instr)
    else:
      # pos += 1
      todo($instr)

  result = self.cur_stack.default
