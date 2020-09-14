import strformat, logging
import sets, tables, oids, strutils, hashes

import ./types
import ./parser

# placeholders for jump* instructions
const ELSE_POS = -1
const NEXT_POS = -2

type
  Compiler* = ref object
    module*: Module
    cur_block: Block

  IfState = enum
    ## Initial state
    If

    ## Can follow if and else if
    Truthy

    ## Can follow if and else if
    Falsy

    ## elif
    ElseIf

    ## else
    Else

#################### Interfaces ##################

proc compile_symbol*(self: var Compiler, blk: var Block, name: string)
proc compile_complex_symbol*(self: var Compiler, blk: var Block, name: GeneValue)
proc compile_gene*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_print*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_if*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_fn*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_fn_body*(self: var Compiler, fn: Function): Block
proc compile_var*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_ns*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_import*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_import_native*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_class*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_method*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_new*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_body*(self: var Compiler, body: seq[GeneValue]): Block
proc compile_invoke*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_call*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_call_native*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_invoke_native*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_binary*(self: var Compiler, blk: var Block, first: GeneValue, op: string, second: GeneValue)
proc compile_prop_get*(self: var Compiler, blk: var Block, name: string)
proc compile_prop_get*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_prop_set*(self: var Compiler, blk: var Block, name: string, val: GeneValue)

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

proc instr_print*(reg: int): Instruction =
  return Instruction(kind: Print, reg: reg)

proc instr_println*(reg: int): Instruction =
  return Instruction(kind: Println, reg: reg)

proc instr_global*(): Instruction =
  return Instruction(kind: Global)

proc instr_self*(): Instruction =
  return Instruction(kind: Self)

proc instr_def_member*(name: string): Instruction =
  return Instruction(kind: DefMember, val: new_gene_string_move(name))

proc instr_def_member*(v: int): Instruction =
  return Instruction(kind: DefMember, reg: v)

proc instr_def_ns_member*(name: GeneValue): Instruction =
  return Instruction(kind: DefNsMember, val: name)

proc instr_get_member*(v: int, name: string): Instruction =
  return Instruction(kind: GetMember, reg: v, val: new_gene_string_move(name))

proc instr_get_nested_ns_member*(name: GeneValue): Instruction =
  return Instruction(kind: GetNestedNsMember, val: name)

proc instr_set_item*(reg: int, index: int): Instruction =
  return Instruction(kind: SetItem, reg: reg, val: new_gene_int(index))

proc instr_prop_get*(reg: int, name: string): Instruction =
  return Instruction(kind: PropGet, reg: reg, val: new_gene_string_move(name))

proc instr_prop_set*(name: string, reg: int): Instruction =
  return Instruction(kind: PropSet, reg: reg, val: new_gene_string_move(name))

proc instr_add*(reg, reg2: int): Instruction =
  return Instruction(kind: Add, reg: reg, reg2: reg2)

proc instr_addi*(reg: int, val: GeneValue): Instruction =
  return Instruction(kind: AddI, reg: reg, val: val)

proc instr_sub*(reg, reg2: int): Instruction =
  return Instruction(kind: Sub, reg: reg, reg2: reg2)

proc instr_subi*(reg: int, val: GeneValue): Instruction =
  return Instruction(kind: SubI, reg: reg, val: val)

proc instr_lt*(reg, reg2: int): Instruction =
  return Instruction(kind: Lt, reg: reg, reg2: reg2)

proc instr_lti*(reg: int, val: GeneValue): Instruction =
  return Instruction(kind: LtI, reg: reg, val: val)

proc instr_jump*(pos: int): Instruction =
  return Instruction(kind: Jump, val: new_gene_int(pos))

proc instr_jump_if_false*(pos: int): Instruction =
  return Instruction(kind: JumpIfFalse, val: new_gene_int(pos))

proc instr_function*(fn: Function): Instruction =
  return Instruction(kind: CreateFunction, val: new_gene_internal(fn))

proc instr_arguments*(reg: int): Instruction =
  return Instruction(kind: CreateArguments, reg: reg)

proc instr_ns*(name: string): Instruction =
  return Instruction(kind: CreateNamespace, val: new_gene_string_move(name))

proc instr_import*(names: seq[GeneValue]): Instruction =
  return Instruction(kind: Import, val: new_gene_vec(names))

proc instr_import_native*(names: seq[GeneValue]): Instruction =
  return Instruction(kind: ImportNative, val: new_gene_vec(names))

proc instr_class*(name: string): Instruction =
  return Instruction(kind: CreateClass, val: new_gene_string_move(name))

proc instr_method*(reg: int): Instruction =
  return Instruction(kind: CreateMethod, reg: reg)

proc instr_new*(reg: int): Instruction =
  return Instruction(kind: CreateInstance, reg: reg)

proc instr_invoke*(reg, reg2: int, val: GeneValue): Instruction =
  return Instruction(kind: InvokeMethod, reg: reg, reg2: reg2, val: val)

proc instr_call*(reg: int): Instruction =
  return Instruction(kind: Call, reg: reg)

proc instr_call_native*(name: string, reg: int): Instruction =
  return Instruction(kind: CallNative, reg: reg, val: new_gene_string_move(name))

proc instr_invoke_native*(reg, reg2: int): Instruction =
  return Instruction(kind: InvokeNative, reg: reg, reg2: reg2)

proc instr_call_block*(reg, reg2: int): Instruction =
  return Instruction(kind: CallBlock, reg: reg, reg2: reg2)

proc instr_call_end*(): Instruction =
  return Instruction(kind: CallEnd)

proc `$`*(instr: Instruction): string =
  case instr.kind
  of Default, Jump, JumpIfFalse, Import:
    return "$# $#" % [$instr.kind, $instr.val]
  of GetMember:
    return "$# $#" % [$instr.kind, $instr.val.d.str]
  of Call, CreateArguments:
    return "$# $#" % [$instr.kind, "R" & $instr.reg]
  of Save, SetItem:
    return "$# $# $#" % [$instr.kind, "R" & $instr.reg, $instr.val]
  of Copy, Add, Lt:
    return "$# $# $#" % [$instr.kind, "R" & $instr.reg, "R" & $instr.reg2]
  of CreateFunction:
    return "$# $#" % [$instr.kind, $instr.val.d.internal.fn.name]
  else:
    return $instr.kind

#################### RegManager ##################

proc get(self: var RegManager): int =
  if self.freed.len > 0:
    return self.freed.pop
  else:
    result = self.next
    self.next += 1

proc free(self: var RegManager, reg: int) =
  self.freed.incl(reg)

#################### ScopeManager ################

proc new_scope_manager*(): ScopeManager =
  result = ScopeManager(
    members: Table[string, Member](),
  )

proc get_available_name(self: ScopeManager, name: string): string =
  if self.members.hasKey(name):
    var i = 1
    while true:
      var s = name & "%" & $i
      if not self.members.hasKey(s):
        return s
      i += 1
  else:
    return name

proc `[]`*(self: ScopeManager, name: string): Member =
  if self.reused_members.hasKey(name):
    var names = self.reused_members[name]
    var name = names[^1]
    return self.members[name]
  elif self.parent != nil:
    return self.parent[name]

proc def_member*(self: var ScopeManager, member: Member) =
  if not self.reused_members.hasKey(member.name):
    self.reused_members[member.name] = @[]
  var names = self.reused_members[member.name]
  var name = self.get_available_name(member.name)
  names.add(name)
  self.members[name] = member

# When a member goes out of scope
proc undef_member*(self: var ScopeManager, name: string) =
  var reused = self.reused_members[name]
  discard reused.pop()
  if reused.len == 0:
    self.reused_members.del(name)

#################### Block #######################

proc new_block*(name: string): Block =
  result = Block(
    id: genOid(),
    name: name,
    reg_mgr: RegManager(next: 1),
    scope_mgr: new_scope_manager(),
  )

proc add(self: var Block, instr: Instruction) =
  self.instructions.add(instr)

proc `$`*(self: Block): string =
  result = ""
  for i in 0..<self.instructions.len:
    var instr = self.instructions[i]
    result &= &"{self.name:>20} {i:>4} {instr}\n"

#################### Module ####################

proc new_module*(): Module =
  result = Module()

proc set_default*(self: var Module, blk: Block) =
  self.default = blk
  # TODO: does not work with arc GC algorithm
  self.blocks[blk.id] = blk

#################### Compiler ####################

proc new_compiler*(): Compiler =
  result = Compiler()

proc compile*(self: var Compiler, blk: var Block, node: GeneValue) =
  case node.d.kind:
  of GeneNilKind, GeneInt, GeneFloat, GeneRatio, GeneBool, GeneChar, GeneString:
    blk.add(instr_default(node))
  of GeneSymbol:
    self.compile_symbol(blk, node.d.symbol)
  of GeneComplexSymbol:
    self.compile_complex_symbol(blk, node)
  of GeneGene:
    self.compile_gene(blk, node)
  else:
    todo($node)

proc compile*(self: var Compiler, doc: GeneDocument): Block =
  result = new_block("<root>")
  for node in doc.data:
    self.compile(result, node)
  debug("\n" & $result)

proc compile*(self: var Compiler, buffer: string): Module =
  var doc = read_document(buffer)
  self.module = new_module()
  var blk = self.compile(doc)
  self.module.set_default(blk)
  return self.module

proc compile_symbol*(self: var Compiler, blk: var Block, name: string) =
  if name.startsWith("@"):
    var name = name.substr(1)
    self.compile_prop_get(blk, name)
  elif name == "self":
    blk.add(instr_self())
  elif name == "global":
    blk.add(instr_global())
  else:
    blk.add(instr_get_member(cast[int](name.hash), name))

proc compile_complex_symbol*(self: var Compiler, blk: var Block, name: GeneValue) =
  blk.add(instr_get_nested_ns_member(name))

proc compile_fn_body*(self: var Compiler, fn: Function): Block =
  result = new_block(fn.name)
  for node in fn.body:
    self.compile(result, node)
  result.instructions.add(instr_call_end())
  debug("\n" & $result)

proc compile_body*(self: var Compiler, body: seq[GeneValue]): Block =
  result = new_block("<unknown>")
  for node in body:
    self.compile(result, node)
  result.instructions.add(instr_call_end())
  debug("\n" & $result)

proc compile_gene*(self: var Compiler, blk: var Block, node: GeneValue) =
  node.normalize

  case node.d.gene_op.d.kind:
  of GeneSymbol:
    case node.d.gene_op.d.symbol:
    of "+", "-", "<":
      var first = node.d.gene_data[0]
      var second = node.d.gene_data[1]
      self.compile_binary(blk, first, node.d.gene_op.d.symbol, second)
    of "@":
      self.compile_prop_get(blk, node)
    of "@=":
      var name = node.d.gene_data[0].d.str
      self.compile_prop_set(blk, name, node.d.gene_data[1])
    of "print", "println":
      self.compile_print(blk, node)
    of "if":
      self.compile_if(blk, node)
    of "fn":
      self.compile_fn(blk, node)
    of "var":
      self.compile_var(blk, node)
    of "ns":
      self.compile_ns(blk, node)
    of "import":
      self.compile_import(blk, node)
    of "import_native":
      self.compile_import_native(blk, node)
    of "class":
      self.compile_class(blk, node)
    of "method":
      self.compile_method(blk, node)
    of "new":
      self.compile_new(blk, node)
    of "$invoke_method":
      self.compile_invoke(blk, node)
    of "$call_native":
      self.compile_call_native(blk, node)
    of "$invoke_native":
      self.compile_invoke_native(blk, node)
    else:
      self.compile_call(blk, node)
  else:
    self.compile_call(blk, node)

proc compile_print*(self: var Compiler, blk: var Block, node: GeneValue) =
  for i in 0..<node.d.gene_data.len - 1:
    var child = node.d.gene_data[i]
    self.compile(blk, child)
    blk.add(instr_print(0))
  var last = node.d.gene_data[^1]
  if last.d != nil:
    self.compile(blk, last)
    if node.d.gene_op.d.symbol == "println":
      blk.add(instr_println(0))
    else:
      blk.add(instr_print(0))

proc compile_if*(self: var Compiler, blk: var Block, node: GeneValue) =
  node.normalize

  var start_pos = blk.instructions.len

  var last_jump_if_false: Instruction
  var jump_next: seq[Instruction]

  var state = IfState.If
  for node in node.d.gene_data:
    case state:
    of IfState.If, IfState.ElseIf:
      # node is conditon
      self.compile(blk, node)
      last_jump_if_false = instr_jump_if_false(ELSE_POS)
      blk.add(last_jump_if_false)
      state = IfState.Truthy

    of IfState.Else:
      self.compile(blk, node)

    of IfState.Truthy:
      if node.d.kind == GeneSymbol:
        if node.d.symbol == "elif":
          state = IfState.ElseIf
        elif node.d.symbol == "else":
          state = IfState.Else

        if node.d.symbol in ["elif", "else"]:
          var instr = instr_jump(NEXT_POS)
          blk.add(instr)
          jump_next.add(instr)

          if last_jump_if_false != nil:
            last_jump_if_false.val = new_gene_int(blk.instructions.len)
            last_jump_if_false = nil

          continue

      self.compile(blk, node)

    else:
      not_allowed()

    var next_pos = blk.instructions.len
    for i in start_pos..<next_pos:
      var instr = blk.instructions[i]
      if instr.kind == Jump and instr.val == new_gene_int(NEXT_POS):
        instr.val.d.num = next_pos

proc compile_var*(self: var Compiler, blk: var Block, node: GeneValue) =
  if node.d.gene_data.len > 1:
    self.compile(blk, node.d.gene_data[1])
  else:
    blk.add(instr_default(GeneNil))
  var name = node.d.gene_data[0].d.symbol
  # var member = Member(kind: ScopeMember, name: name)
  # blk.scope_mgr.def_member(member)
  # blk.add(instr_def_member(name))
  blk.add(instr_def_member(name.hash))

proc compile_fn*(self: var Compiler, blk: var Block, node: GeneValue) =
  var first = node.d.gene_data[0]
  var name: string
  if first.d.kind == GeneSymbol:
    name = first.d.symbol
  elif first.d.kind == GeneComplexSymbol:

    name = first.d.csymbol.rest[^1]
  var args: seq[string] = @[]
  var a = node.d.gene_data[1]
  case a.d.kind:
  of GeneSymbol:
    args.add(a.d.symbol)
  of GeneVector:
    for item in a.d.vec:
      args.add(item.d.symbol)
  else:
    not_allowed()
  var body: seq[GeneValue] = @[]
  for i in 2..<node.d.gene_data.len:
    body.add node.d.gene_data[i]

  var fn = new_fn(name, args, body)
  var body_block = self.compile_fn_body(fn)
  fn.body_block = body_block
  blk.add(instr_function(fn))
  # blk.add(instr_def_ns_member(first))

proc compile_ns*(self: var Compiler, blk: var Block, node: GeneValue) =
  var name = node.d.gene_data[0].d.symbol
  var body: seq[GeneValue] = @[]
  for i in 1..<node.d.gene_data.len:
    body.add node.d.gene_data[i]

  blk.add(instr_ns(name))
  # var body_block = self.compile_body(body)
  # self.module.blocks[body_block.id] = body_block
  # blk.add(instr_call(body_block.id))

proc compile_import*(self: var Compiler, blk: var Block, node: GeneValue) =
  blk.add(instr_default(node.d.gene_props["module"]))
  blk.add(instr_import(node.d.gene_props["names"].d.vec))

proc compile_import_native*(self: var Compiler, blk: var Block, node: GeneValue) =
  blk.add(instr_default(node.d.gene_props["module"]))
  blk.add(instr_import_native(node.d.gene_props["names"].d.vec))

proc compile_class*(self: var Compiler, blk: var Block, node: GeneValue) =
  var name = node.d.gene_data[0].d.symbol
  var body: seq[GeneValue] = @[]
  for i in 1..<node.d.gene_data.len:
    body.add node.d.gene_data[i]

  blk.add(instr_class(name))
  var reg = blk.reg_mgr.get
  blk.add(instr_copy(0, reg))
  var body_block = self.compile_body(body)
  self.module.blocks[body_block.id] = body_block
  blk.add(instr_default(new_gene_internal(Internal(kind: GeneBlock, blk: body_block))))
  blk.add(instr_call_block(0, reg))
  blk.add(instr_copy(reg, 0))

proc compile_method*(self: var Compiler, blk: var Block, node: GeneValue) =
  var name = node.d.gene_data[0].d.symbol
  var args: seq[string] = @[]
  var a = node.d.gene_data[1]
  case a.d.kind:
  of GeneSymbol:
    args.add(a.d.symbol)
  of GeneVector:
    for item in a.d.vec:
      args.add(item.d.symbol)
  else:
    not_allowed()
  var body: seq[GeneValue] = @[]
  for i in 2..<node.d.gene_data.len:
    body.add node.d.gene_data[i]

  var fn = new_fn(name, args, body)
  var body_block = self.compile_fn_body(fn)
  if name == "new":
    body_block.no_return = true
  fn.body_block = body_block
  blk.add(instr_function(fn))
  blk.add(instr_method(0))

proc compile_new*(self: var Compiler, blk: var Block, node: GeneValue) =
  self.compile(blk, node.d.gene_data[0])
  var target_reg = blk.reg_mgr.get
  blk.add(instr_copy(0, target_reg))
  var args_reg = blk.reg_mgr.get
  blk.add(instr_arguments(args_reg))
  for i in 1..<node.d.gene_data.len:
    var child = node.d.gene_data[i]
    self.compile(blk, child)
    blk.add(instr_set_item(args_reg, i - 1))
  blk.add(instr_copy(target_reg, 0))
  blk.add(instr_new(args_reg))
  blk.reg_mgr.free(target_reg)
  blk.reg_mgr.free(args_reg)

proc compile_invoke*(self: var Compiler, blk: var Block, node: GeneValue) =
  self.compile(blk, node.d.gene_props["self"])
  var target_reg = blk.reg_mgr.get
  blk.add(instr_copy(0, target_reg))
  var args_reg = blk.reg_mgr.get
  blk.add(instr_arguments(args_reg))
  for i in 0..<node.d.gene_data.len:
    var child = node.d.gene_data[i]
    self.compile(blk, child)
    blk.add(instr_set_item(args_reg, i))
  blk.add(instr_copy(target_reg, 0))
  var name = node.d.gene_props["method"]
  blk.add(instr_invoke(target_reg, args_reg, name))
  blk.reg_mgr.free(target_reg)
  blk.reg_mgr.free(args_reg)

proc compile_call*(self: var Compiler, blk: var Block, node: GeneValue) =
  self.compile(blk, node.d.gene_op)
  var target_reg = blk.reg_mgr.get
  blk.add(instr_copy(0, target_reg))
  var args_reg = blk.reg_mgr.get
  blk.add(instr_arguments(args_reg))
  for i in 0..<node.d.gene_data.len:
    var child = node.d.gene_data[i]
    self.compile(blk, child)
    blk.add(instr_set_item(args_reg, i))
  blk.add(instr_copy(target_reg, 0))
  blk.add(instr_call(args_reg))
  blk.reg_mgr.free(target_reg)
  blk.reg_mgr.free(args_reg)

proc compile_call_native*(self: var Compiler, blk: var Block, node: GeneValue) =
  var name = node.d.gene_data[0]
  var args_reg = blk.reg_mgr.get
  blk.add(instr_arguments(args_reg))
  for i in 1..<node.d.gene_data.len:
    var child = node.d.gene_data[i]
    self.compile(blk, child)
    blk.add(instr_set_item(args_reg, i - 1))
  blk.add(instr_call_native(name.d.str, args_reg))
  blk.reg_mgr.free(args_reg)

proc compile_invoke_native*(self: var Compiler, blk: var Block, node: GeneValue) =
  var args_reg = blk.reg_mgr.get
  blk.add(instr_arguments(args_reg))
  for i in 1..<node.d.gene_data.len:
    var child = node.d.gene_data[i]
    self.compile(blk, child)
    blk.add(instr_set_item(args_reg, i - 1))
  self.compile(blk, node.d.gene_data[0])
  blk.add(instr_invoke_native(0, args_reg))
  blk.reg_mgr.free(args_reg)

proc compile_binary*(self: var Compiler, blk: var Block, first: GeneValue, op: string, second: GeneValue) =
  # if first.kind == GeneInt and second.kind == GeneInt:
  #   blk.add(instr_default(new_gene_int(first.num + second.num)))
  # elif second.kind == GeneInt:
  #   # TODO: Use AddI
  #   todo()
  # elif first.kind == GeneInt:
  #   # TODO: compile second and use AddI
  #   todo()
  # else:
  #   self.compile(blk, first)
  #   var reg = blk.reg_mgr.get
  #   blk.add(instr_copy(0, reg))
  #   self.compile(blk, second)
  #   blk.add(instr_add(0, reg))
  #   blk.reg_mgr.free(reg)

  let fst_literal = first.is_literal
  let snd_literal = second.is_literal
  case op:
  of "+":
    if fst_literal and snd_literal:
      blk.add(instr_default(new_gene_int(first.d.num + second.d.num)))
    elif fst_literal:
      self.compile(blk, second)
      blk.add(instr_addi(0, first))
    elif snd_literal:
      self.compile(blk, first)
      blk.add(instr_addi(0, second))
    else:
      self.compile(blk, first)
      var reg = blk.reg_mgr.get
      blk.add(instr_copy(0, reg))
      self.compile(blk, second)
      blk.add(instr_add(reg, 0))
      blk.reg_mgr.free(reg)
  of "-":
    if fst_literal and snd_literal:
      blk.add(instr_default(new_gene_int(first.d.num - second.d.num)))
    elif fst_literal:
      todo()
    elif snd_literal:
      self.compile(blk, first)
      blk.add(instr_subi(0, second))
    else:
      self.compile(blk, first)
      var reg = blk.reg_mgr.get
      blk.add(instr_copy(0, reg))
      self.compile(blk, second)
      blk.add(instr_sub(reg, 0))
      blk.reg_mgr.free(reg)
  of "<":
    if fst_literal and snd_literal:
      blk.add(instr_default(new_gene_bool(first.d.num < second.d.num)))
    elif fst_literal:
      todo()
    elif snd_literal:
      self.compile(blk, first)
      blk.add(instr_lti(0, second))
    else:
      self.compile(blk, first)
      var reg = blk.reg_mgr.get
      blk.add(instr_copy(0, reg))
      self.compile(blk, second)
      blk.add(instr_lt(reg, 0))
      blk.reg_mgr.free(reg)
  else:
    todo($op)

proc compile_prop_get*(self: var Compiler, blk: var Block, name: string) =
  self.compile(blk, new_gene_symbol("self"))
  blk.add(instr_prop_get(0, name))

proc compile_prop_get*(self: var Compiler, blk: var Block, node: GeneValue) =
  self.compile(blk, node.d.gene_props["self"])
  var name = node.d.gene_data[0].d.str
  blk.add(instr_prop_get(0, name))

proc compile_prop_set*(self: var Compiler, blk: var Block, name: string, val: GeneValue) =
  self.compile(blk, val)
  blk.add(instr_prop_set(name, 0))
