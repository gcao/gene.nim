import sets, tables, strutils

import ../wrappers/oids

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

proc compile_gene*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_if*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_fn*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_fn_body*(self: var Compiler, fn: Function): Block
proc compile_var*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_ns*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_import*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_class*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_new*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_body*(self: var Compiler, body: seq[GeneValue]): Block
proc compile_call*(self: var Compiler, blk: var Block, node: GeneValue)
proc compile_binary*(self: var Compiler, blk: var Block, first: GeneValue, op: string, second: GeneValue)


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

proc instr_def_member*(name: string): Instruction =
  return Instruction(kind: DefMember, val: new_gene_string_move(name))

proc instr_get_member*(name: string): Instruction =
  return Instruction(kind: GetMember, val: new_gene_string_move(name))

proc instr_set_item*(reg: int, index: int): Instruction =
  return Instruction(kind: SetItem, reg: reg, val: new_gene_int(index))

proc instr_add*(reg, reg2: int): Instruction =
  return Instruction(kind: Add, reg: reg, reg2: reg2)

proc instr_sub*(reg, reg2: int): Instruction =
  return Instruction(kind: Sub, reg: reg, reg2: reg2)

proc instr_lt*(reg, reg2: int): Instruction =
  return Instruction(kind: Lt, reg: reg, reg2: reg2)

proc instr_jump*(pos: int): Instruction =
  return Instruction(kind: Jump, val: new_gene_int(pos))

proc instr_jump_if_false*(pos: int): Instruction =
  return Instruction(kind: JumpIfFalse, val: new_gene_int(pos))

proc instr_function*(fn: Function): Instruction =
  return Instruction(kind: CreateFunction, val: new_gene_internal(fn))

proc instr_arguments*(reg: int): Instruction =
  return Instruction(kind: CreateArguments, reg: reg, val: new_gene_arguments())

proc instr_ns*(name: string): Instruction =
  return Instruction(kind: CreateNamespace, val: new_gene_string_move(name))

proc instr_import*(names: seq[GeneValue]): Instruction =
  return Instruction(kind: Import, val: new_gene_vec(names))

proc instr_class*(name: string): Instruction =
  return Instruction(kind: CreateClass, val: new_gene_string_move(name))

proc instr_new*(): Instruction =
  return Instruction(kind: CreateInstance)

proc instr_call*(reg: int): Instruction =
  return Instruction(kind: Call, reg: reg)

proc instr_call_end*(): Instruction =
  return Instruction(kind: CallEnd)

proc `$`*(instr: Instruction): string =
  case instr.kind
  of Default, Jump, JumpIfFalse, Import:
    return "$# $#" % [$instr.kind, $instr.val]
  of GetMember:
    return "$# $#" % [$instr.kind, $instr.val.str]
  of Call:
    return "$# $#" % [$instr.kind, "R" & $instr.reg]
  of Save, SetItem:
    return "$# $# $#" % [$instr.kind, "R" & $instr.reg, $instr.val]
  of Copy, Add, Lt:
    return "$# $# $#" % [$instr.kind, "R" & $instr.reg, "R" & $instr.reg2]
  of CreateFunction:
    return "$# $#" % [$instr.kind, $instr.val.internal.fn.name]
  else:
    return $instr.kind

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
    reg_mgr: RegManager(next: 1),
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
  of GeneSymbol:
    blk.add(instr_get_member(node.symbol))
  of GeneGene:
    self.compile_gene(blk, node)
  else:
    todo($node)

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

proc compile_fn_body*(self: var Compiler, fn: Function): Block =
  result = new_block()
  for node in fn.body:
    self.compile(result, node)
  result.instructions.add(instr_call_end())

proc compile_body*(self: var Compiler, body: seq[GeneValue]): Block =
  result = new_block()
  for node in body:
    self.compile(result, node)
  result.instructions.add(instr_call_end())

proc compile_gene*(self: var Compiler, blk: var Block, node: GeneValue) =
  node.normalize

  case node.gene_op.kind:
  of GeneSymbol:
    case node.gene_op.symbol:
    of "+", "-", "<":
      var first = node.gene_data[0]
      var second = node.gene_data[1]
      self.compile_binary(blk, first, node.gene_op.symbol, second)
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
    of "class":
      self.compile_class(blk, node)
    of "new":
      self.compile_new(blk, node)
    else:
      self.compile_call(blk, node)
  else:
    self.compile_call(blk, node)

proc compile_if*(self: var Compiler, blk: var Block, node: GeneValue) =
  node.normalize

  var start_pos = blk.instructions.len

  var last_jump_if_false: Instruction
  var jump_next: seq[Instruction]

  var state = IfState.If
  for node in node.gene_data:
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
      if node.kind == GeneSymbol:
        if node.symbol == "elif":
          state = IfState.ElseIf
        elif node.symbol == "else":
          state = IfState.Else

        if node.symbol in ["elif", "else"]:
          var instr = instr_jump(NEXT_POS)
          blk.add(instr)
          jump_next.add(instr)

          if not last_jump_if_false.isNil:
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
        instr.val.num = next_pos

proc compile_var*(self: var Compiler, blk: var Block, node: GeneValue) =
  if node.gene_data.len > 1:
    self.compile(blk, node.gene_data[1])
  else:
    blk.add(instr_default(GeneNil))
  blk.add(instr_def_member(node.gene_data[0].symbol))

proc compile_fn*(self: var Compiler, blk: var Block, node: GeneValue) =
  var name = node.gene_data[0].symbol
  var args: seq[string] = @[]
  var a = node.gene_data[1]
  case a.kind:
  of GeneSymbol:
    args.add(a.symbol)
  of GeneVector:
    for item in a.vec:
      args.add(item.symbol)
  else:
    not_allowed()
  var body: seq[GeneValue] = @[]
  for i in 2..<node.gene_data.len:
    body.add node.gene_data[i]

  var fn = new_fn(name, args, body)
  var body_block = self.compile_fn_body(fn)
  fn.body_block = body_block
  blk.add(instr_function(fn))

proc compile_ns*(self: var Compiler, blk: var Block, node: GeneValue) =
  var name = node.gene_data[0].symbol
  var body: seq[GeneValue] = @[]
  for i in 1..<node.gene_data.len:
    body.add node.gene_data[i]

  blk.add(instr_ns(name))
  # var body_block = self.compile_body(body)
  # self.module.blocks[body_block.id] = body_block
  # blk.add(instr_call(body_block.id))

proc compile_import*(self: var Compiler, blk: var Block, node: GeneValue) =
  blk.add(instr_default(node.gene_props["module"]))
  blk.add(instr_import(node.gene_props["names"].vec))

proc compile_class*(self: var Compiler, blk: var Block, node: GeneValue) =
  var name = node.gene_data[0].symbol
  var body: seq[GeneValue] = @[]
  for i in 1..<node.gene_data.len:
    body.add node.gene_data[i]

  blk.add(instr_class(name))
  # var body_block = self.compile_body(body)
  # self.module.blocks[body_block.id] = body_block
  # blk.add(instr_call(body_block.id))

proc compile_new*(self: var Compiler, blk: var Block, node: GeneValue) =
  self.compile(blk, node.gene_data[0])
  blk.add(instr_new())

proc compile_call*(self: var Compiler, blk: var Block, node: GeneValue) =
  self.compile(blk, node.gene_op)
  var target_reg = blk.reg_mgr.get
  blk.add(instr_copy(0, target_reg))
  var args_reg = blk.reg_mgr.get
  blk.add(instr_arguments(args_reg))
  for i in 0..<node.gene_data.len:
    var child = node.gene_data[i]
    self.compile(blk, child)
    blk.add(instr_set_item(args_reg, i))
  blk.add(instr_copy(target_reg, 0))
  blk.add(instr_call(args_reg))
  blk.reg_mgr.free(target_reg)
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

  self.compile(blk, first)
  var reg = blk.reg_mgr.get
  blk.add(instr_copy(0, reg))
  self.compile(blk, second)
  case op:
  of "+": blk.add(instr_add(reg, 0))
  of "-": blk.add(instr_sub(reg, 0))
  of "<": blk.add(instr_lt(reg, 0))
  else:
    todo($op)
  blk.reg_mgr.free(reg)
