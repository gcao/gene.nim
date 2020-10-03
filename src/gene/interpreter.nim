import tables

import ./types
import ./parser

type
  VM* = ref object
    cur_frame*: Frame
    exprs*: seq[Expr]

  Frame* = ref object
    self*: GeneValue
    namespace*: Namespace
    scope*: Scope
    stack*: seq[GeneValue]

  Namespace = ref object
    parent*: Namespace
    name*: string
    members*: Table[int, GeneValue]

  Scope* = ref object
    parent*: Scope
    members*: Table[int, GeneValue]

  Break* = ref object of CatchableError
    val: GeneValue

  Return* = ref object of CatchableError
    val: GeneValue

  ScopeManager = ref object
    cache*: seq[Scope]

var ScopeMgr* = ScopeManager(cache: @[])

#################### Interfaces ##################

proc `[]`*(self: VM, key: int): GeneValue {.inline.}
proc new_expr*(parent: Expr, node: GeneValue): Expr {.inline.}
proc new_if_expr*(parent: Expr, val: GeneValue): Expr
proc new_var_expr*(parent: Expr, name: string, val: GeneValue): Expr
proc new_assignment_expr*(parent: Expr, name: string, val: GeneValue): Expr
proc new_map_key_expr*(parent: Expr, key: string, val: GeneValue): Expr
proc new_block_expr*(parent: Expr, nodes: seq[GeneValue]): Expr
proc new_loop_expr*(parent: Expr, val: GeneValue): Expr
proc new_break_expr*(parent: Expr, val: GeneValue): Expr
proc new_while_expr*(parent: Expr, val: GeneValue): Expr
proc new_fn_expr*(parent: Expr, val: GeneValue): Expr
proc new_return_expr*(parent: Expr, val: GeneValue): Expr
proc new_binary_expr*(parent: Expr, op: string, val: GeneValue): Expr
proc new_class_expr*(parent: Expr, val: GeneValue): Expr
proc new_new_expr*(parent: Expr, val: GeneValue): Expr
proc new_method_expr*(parent: Expr, val: GeneValue): Expr
proc new_get_prop_expr*(parent: Expr, val: GeneValue): Expr
proc new_set_prop_expr*(parent: Expr, name: string, val: GeneValue): Expr
proc eval_method*(self: VM, instance: GeneValue, class: Class, method_name: string): GeneValue
# proc normalize_if*(val: GeneValue): NormalizedIf

#################### Module ######################

proc new_module(): Module =
  return Module(
    name: "<unknown>",
  )

proc get_index(self: var Module, name: string): int =
  if self.name_mappings.hasKey(name):
    return self.name_mappings[name]
  else:
    result = self.names.len
    self.names.add(name)
    self.name_mappings[name] = result

#################### Namespace ###################

proc new_namespace*(): Namespace =
  return Namespace(
    name: "<root>",
    members: Table[int, GeneValue](),
  )

proc new_namespace*(name: string): Namespace =
  return Namespace(
    name: name,
    members: Table[int, GeneValue](),
  )

proc new_namespace*(parent: Namespace, name: string): Namespace =
  return Namespace(
    parent: parent,
    name: name,
    members: Table[int, GeneValue](),
  )

proc `[]`*(self: Namespace, key: int): GeneValue {.inline.} = self.members[key]

proc `[]=`*(self: var Namespace, key: int, val: GeneValue) {.inline.} =
  self.members[key] = val

#################### Scope #######################

proc new_scope*(): Scope = Scope(members: Table[int, GeneValue]())

proc reset*(self: var Scope) {.inline.} =
  self.parent = nil
  self.members.clear()

proc hasKey*(self: Scope, key: int): bool {.inline.} = self.members.hasKey(key)

proc `[]`*(self: Scope, key: int): GeneValue {.inline.} = self.members[key]

proc `[]=`*(self: var Scope, key: int, val: GeneValue) {.inline.} =
  self.members[key] = val

#################### ScopeManager ################

proc get*(self: var ScopeManager): Scope {.inline.} =
  if self.cache.len > 0:
    return self.cache.pop()
  else:
    return new_scope()

proc free*(self: var ScopeManager, scope: var Scope) {.inline.} =
  scope.reset()
  self.cache.add(scope)

#################### Function ####################

converter from_gene*(node: GeneValue): Function =
  var first = node.gene_data[0]
  var name: string
  if first.kind == GeneSymbol:
    name = first.symbol
  elif first.kind == GeneComplexSymbol:
    name = first.csymbol.rest[^1]
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

  return new_fn(name, args, body)

#################### Implementations #############

proc new_literal_expr*(parent: Expr, v: GeneValue): Expr =
  return Expr(
    kind: ExLiteral,
    parent: parent,
    module: parent.module,
    literal: v,
  )

proc new_symbol_expr*(parent: Expr, s: string): Expr =
  var key = parent.module.get_index(s)
  return Expr(
    kind: ExSymbol,
    parent: parent,
    module: parent.module,
    key: key,
  )

proc new_array_expr*(parent: Expr, v: GeneValue): Expr =
  result = Expr(
    kind: ExArray,
    parent: parent,
    module: parent.module,
    array: @[],
  )
  for item in v.vec:
    result.array.add(new_expr(result, item))

proc new_map_expr*(parent: Expr, v: GeneValue): Expr =
  result = Expr(
    kind: ExMap,
    parent: parent,
    module: parent.module,
    map: @[],
  )
  for key, val in v.map:
    var e = new_map_key_expr(result, key, val)
    result.map.add(e)

proc new_gene_expr*(parent: Expr, v: GeneValue): Expr =
  return Expr(
    kind: ExGene,
    parent: parent,
    module: parent.module,
    gene: v,
  )

proc new_unknown_expr*(parent: Expr, v: GeneValue): Expr =
  return Expr(
    kind: ExUnknown,
    parent: parent,
    module: parent.module,
    unknown: v,
  )

proc eval*(self: VM, expr: Expr): GeneValue {.inline.} =
  case expr.kind:
  of ExRoot:
    result = self.eval(expr.root)
  of ExLiteral:
    result = expr.literal
  of ExSymbol:
    result = self[expr.key]
  of ExBlock:
    for e in expr.blk:
      result = self.eval(e)
  of ExArray:
    result = new_gene_vec()
    for e in expr.array:
      result.vec.add(self.eval(e))
  of ExMap:
    result = new_gene_map()
    for e in expr.map:
      result.map[e.map_key] = self.eval(e.map_val)
  of ExMapChild:
    discard
    # result = self.eval(expr.map_val)
  of ExGene:
    var target = self.eval(expr.gene_op)
    if target.kind == GeneInternal and target.internal.kind == GeneFunction:
      var fn = target.internal.fn
      var fn_scope = ScopeMgr.get()
      case expr.gene_blk.len:
      of 0:
        for i in 0..<fn.args.len:
          fn_scope[fn.arg_keys[i]] = GeneNil
      of 1:
        var arg = self.eval(expr.gene_blk[0])
        for i in 0..<fn.args.len:
          if i == 0:
            fn_scope[fn.arg_keys[0]] = arg
          else:
            fn_scope[fn.arg_keys[i]] = GeneNil
      else:
        var args: seq[GeneValue] = @[]
        for e in expr.gene_blk:
          args.add(self.eval(e))
        fn_scope.parent = self.cur_frame.scope
        for i in 0..<fn.args.len:
          fn_scope[fn.arg_keys[i]] = args[i]
      var caller_scope = self.cur_frame.scope
      self.cur_frame.scope = fn_scope
      if fn.body_blk.len == 0:
        for item in fn.body:
          fn.body_blk.add(new_expr(fn.expr, item))
      try:
        for e in fn.body_blk:
          result = self.eval(e)
      except Return as r:
        result = r.val

      ScopeMgr.free(fn_scope)
      self.cur_frame.scope = caller_scope
    else:
      todo($expr.gene)
  of ExBinary:
    var first = self.eval(expr.bin_first)
    var second = self.eval(expr.bin_second)
    case expr.bin_op:
    of BinAdd: result = new_gene_int(first.num + second.num)
    of BinSub: result = new_gene_int(first.num - second.num)
    of BinMul: result = new_gene_int(first.num * second.num)
    # of BinDiv: result = new_gene_int(first.num / second.num)
    of BinEq:  result = new_gene_bool(first.num == second.num)
    of BinNeq: result = new_gene_bool(first.num != second.num)
    of BinLt:  result = new_gene_bool(first.num < second.num)
    of BinLe:  result = new_gene_bool(first.num <= second.num)
    of BinGt:  result = new_gene_bool(first.num > second.num)
    of BinGe:  result = new_gene_bool(first.num >= second.num)
    of BinAnd: result = new_gene_bool(first.boolVal and second.boolVal)
    of BinOr:  result = new_gene_bool(first.boolVal or second.boolVal)
    else: todo()
  of ExBinImmediate:
    var first = self.eval(expr.bini_first)
    var second = expr.bini_second
    case expr.bini_op:
    of BinAdd: result = new_gene_int(first.num + second.num)
    of BinSub: result = new_gene_int(first.num - second.num)
    of BinMul: result = new_gene_int(first.num * second.num)
    # of BinDiv: result = new_gene_int(first.num / second.num)
    of BinEq:  result = new_gene_bool(first.num == second.num)
    of BinNeq: result = new_gene_bool(first.num != second.num)
    of BinLt:  result = new_gene_bool(first.num < second.num)
    of BinLe:  result = new_gene_bool(first.num <= second.num)
    of BinGt:  result = new_gene_bool(first.num > second.num)
    of BinGe:  result = new_gene_bool(first.num >= second.num)
    of BinAnd: result = new_gene_bool(first.boolVal and second.boolVal)
    of BinOr:  result = new_gene_bool(first.boolVal or second.boolVal)
    else: todo()
  of ExVar:
    var val = self.eval(expr.var_val)
    self.cur_frame.scope[expr.var_key] = val
    result = GeneNil
  of ExAssignment:
    var val = self.eval(expr.var_val)
    self.cur_frame.scope[expr.var_key] = val
    result = GeneNil
  of ExIf:
    var v = self.eval(expr.if_cond)
    if v:
      result = self.eval(expr.if_then)
    else:
      result = self.eval(expr.if_else)
  of ExLoop:
    try:
      while true:
        for e in expr.loop_blk:
          discard self.eval(e)
    except Break as b:
      result = b.val
  of ExBreak:
    var val = GeneNil
    if expr.break_val != nil:
      val = self.eval(expr.break_val)
    var e: Break
    e.new
    e.val = val
    raise e
  of ExWhile:
    try:
      var cond = self.eval(expr.while_cond)
      while cond:
        for e in expr.while_blk:
          discard self.eval(e)
        cond = self.eval(expr.while_cond)
    except Break as b:
      result = b.val
  of ExFn:
    self.cur_frame.namespace[expr.fn.internal.fn.name_key] = expr.fn
    result = expr.fn
  of ExReturn:
    var val = GeneNil
    if expr.return_val != nil:
      val = self.eval(expr.return_val)
    var e: Return
    e.new
    e.val = val
    raise e
  of ExUnknown:
    var parent = expr.parent
    case parent.kind:
    of ExBlock:
      var e = new_expr(parent, expr.unknown)
      parent.blk[expr.posInParent] = e
      result = self.eval(e)
    of ExLoop:
      var e = new_expr(parent, expr.unknown)
      parent.loop_blk[expr.posInParent] = e
      result = self.eval(e)
    else:
      todo($expr.unknown)
  of ExClass:
    self.cur_frame.namespace[expr.class.internal.class.name_key] = expr.class
    self.cur_frame.self = expr.class
    for e in expr.class_body:
      discard self.eval(e)
    result = expr.class
  of ExNew:
    var class = self.eval(expr.new_class)
    var instance = new_instance(class.internal.class)
    result = new_gene_instance(instance)
    discard self.eval_method(result, class.internal.class, "new")
  of ExMethod:
    var meth = expr.meth
    self.cur_frame.self.internal.class.methods[meth.internal.fn.name] = meth.internal.fn
    result = meth
  of ExGetProp:
    var target = self.eval(expr.get_prop_self)
    var name = expr.get_prop_name
    result = target.instance.value.gene_props[name]
  of ExSetProp:
    var target = self.cur_frame.self
    var name = expr.set_prop_name
    result = self.eval(expr.set_prop_val)
    target.instance.value.gene_props[name] = result
  # else:
  #   todo($expr.kind)

#################### Frame #######################

proc new_frame*(): Frame =
  return Frame(
    namespace: new_namespace(),
    scope: new_scope(),
  )

#################### VM #########################

proc new_vm*(): VM =
  return VM(
    cur_frame: new_frame(),
  )

proc `[]`*(self: VM, key: int): GeneValue {.inline.} =
  if self.cur_frame.scope.hasKey(key):
    return self.cur_frame.scope[key]
  else:
    return self.cur_frame.namespace[key]

proc prepare*(self: VM, code: string): Expr =
  var parsed = read_all(code)
  var root = Expr(
    kind: ExRoot,
    module: new_module(),
  )
  return new_block_expr(root, parsed)

proc eval*(self: VM, code: string): GeneValue =
  return self.eval(self.prepare(code))

proc eval_method*(self: VM, instance: GeneValue, class: Class, method_name: string): GeneValue =
  if class.methods.hasKey(method_name):
    var meth = class.methods[method_name]
    self.cur_frame.self = instance
    if meth.body_blk.len == 0:
      for item in meth.body:
        meth.body_blk.add(new_expr(meth.expr, item))
    for e in meth.body_blk:
      result = self.eval(e)

##################################################

proc new_expr*(parent: Expr, node: GeneValue): Expr {.inline.} =
  case node.kind:
  of GeneNilKind, GeneBool, GeneInt, GeneString:
    return new_literal_expr(parent, node)
  of GeneSymbol:
    return new_symbol_expr(parent, node.symbol)
  of GeneVector:
    return new_array_expr(parent, node)
  of GeneMap:
    return new_map_expr(parent, node)
  of GeneGene:
    node.normalize
    case node.gene_op.kind:
    of GeneSymbol:
      case node.gene_op.symbol:
      of "var":
        var name = node.gene_data[0].symbol
        var val = GeneNil
        if node.gene_data.len > 1:
          val = node.gene_data[1]
        return new_var_expr(parent, name, val)
      of "=":
        var name = node.gene_data[0].symbol
        var val = node.gene_data[1]
        return new_assignment_expr(parent, name, val)
      of "@":
        return new_get_prop_expr(parent, node)
      of "@=":
        var name = node.gene_data[0].str
        var val = node.gene_data[1]
        return new_set_prop_expr(parent, name, val)
      of "if":
        return new_if_expr(parent, node)
      of "do":
        return new_block_expr(parent, node.gene_data)
      of "loop":
        return new_loop_expr(parent, node)
      of "break":
        return new_break_expr(parent, node)
      of "while":
        return new_while_expr(parent, node)
      of "fn":
        return new_fn_expr(parent, node)
      of "return":
        return new_return_expr(parent, node)
      of "class":
        return new_class_expr(parent, node)
      of "new":
        return new_new_expr(parent, node)
      of "method":
        return new_method_expr(parent, node)
      of "+", "-", "==", "!=", "<", "<=", ">", ">=", "&&", "||":
        return new_binary_expr(parent, node.gene_op.symbol, node)
      else:
        discard
    else:
      discard
    result = new_gene_expr(parent, node)
    result.gene_op = new_expr(result, node.gene_op)
    for item in node.gene_data:
      result.gene_blk.add(new_expr(result, item))
  else:
    todo($node)

proc new_block_expr*(parent: Expr, nodes: seq[GeneValue]): Expr =
  result = Expr(
    kind: ExBlock,
    parent: parent,
    module: parent.module,
  )
  for node in nodes:
    result.blk.add(new_unknown_expr(result, node))

proc new_loop_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExLoop,
    parent: parent,
    module: parent.module,
  )
  for node in val.gene_data:
    result.loop_blk.add(new_expr(result, node))

proc new_break_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExBreak,
    parent: parent,
    module: parent.module,
  )
  if val.gene_data.len > 0:
    result.break_val = new_expr(result, val.gene_data[0])

proc new_while_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExWhile,
    parent: parent,
    module: parent.module,
  )
  result.while_cond = new_expr(result, val.gene_data[0])
  for i in 1..<val.gene_data.len:
    var node = val.gene_data[i]
    result.while_blk.add(new_expr(result, node))

proc new_map_key_expr*(parent: Expr, key: string, val: GeneValue): Expr =
  result = Expr(
    kind: ExMapChild,
    parent: parent,
    module: parent.module,
    map_key: key,
  )
  result.map_val = new_expr(result, val)

proc new_var_expr*(parent: Expr, name: string, val: GeneValue): Expr =
  var key = parent.module.get_index(name)
  result = Expr(
    kind: ExVar,
    parent: parent,
    module: parent.module,
    # var_name: name,
    var_key: key,
  )
  result.var_val = new_expr(result, val)

proc new_assignment_expr*(parent: Expr, name: string, val: GeneValue): Expr =
  var key = parent.module.get_index(name)
  result = Expr(
    kind: ExAssignment,
    parent: parent,
    module: parent.module,
    # var_name: name,
    var_key: key,
  )
  result.var_val = new_expr(result, val)

proc new_if_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExIf,
    parent: parent,
    module: parent.module,
  )
  result.if_cond = new_expr(result, val.gene_data[0])
  result.if_then = new_expr(result, val.gene_data[1])
  if val.gene_data.len > 3:
    result.if_else = new_expr(result, val.gene_data[3])

# proc normalize_if*(val: GeneValue): NormalizedIf =
#   var cond: GeneValue = val.gene_data[0]
#   result.cond = cond
#   var then_logic: seq[GeneValue] = @[]
#   result.then_logic = then_logic
#   var elif_pairs: seq[(GeneValue, seq[GeneValue])] = @[]
#   result.elif_pairs = elif_pairs
#   var else_logic: seq[GeneValue] = @[]
#   result.else_logic = else_logic

#   var state = ThenBlock
#   for i in 1..<val.gene_data.len:
#     var item = val.gene_data[i]
#     case state:
#     of ThenBlock:
#       if item == ELSE:
#         state = ElseBlock
#       elif item == ELIF:
#         state = ElseIfCond
#       else:
#         then_logic.add(item)
#     of ElseIfCond:
#       if item in @[ELSE, ELIF, THEN]:
#         not_allowed()
#       else:
#         state = ElseIfThenBlock
#         elif_pairs.add((item, @[]))
#     of ElseIfThenBlock:
#       if item == ELSE:
#         state = ElseBlock
#       elif item == ELIF:
#         state = ElseIfCond
#       else:
#         elif_pairs[^1][1].add(item)
#     else:
#       not_allowed()

proc new_fn_expr*(parent: Expr, val: GeneValue): Expr =
  var fn: Function = val
  fn.name_key = parent.module.get_index(fn.name)
  for name in fn.args:
    fn.arg_keys.add(parent.module.get_index(name))
  result = Expr(
    kind: ExFn,
    parent: parent,
    module: parent.module,
    fn: new_gene_internal(fn),
  )
  fn.expr = result

proc new_return_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExReturn,
    parent: parent,
    module: parent.module,
  )
  if val.gene_data.len > 0:
    result.return_val = new_expr(result, val.gene_data[0])

proc new_class_expr*(parent: Expr, val: GeneValue): Expr =
  var class = new_class(val.gene_data[0].symbol)
  result = Expr(
    kind: ExClass,
    parent: parent,
    module: parent.module,
    class: new_gene_internal(class),
  )
  var body: seq[Expr] = @[]
  for i in 1..<val.gene_data.len:
    body.add(new_expr(parent, val.gene_data[i]))
  result.class_body = body

proc new_new_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExNew,
    parent: parent,
    module: parent.module,
  )
  result.new_class = new_expr(parent, val.gene_data[0])

proc new_method_expr*(parent: Expr, val: GeneValue): Expr =
  var fn: Function = val # Converter is implicitly called here
  for name in fn.args:
    fn.arg_keys.add(parent.module.get_index(name))
  result = Expr(
    kind: ExMethod,
    parent: parent,
    module: parent.module,
    meth: new_gene_internal(fn),
  )
  fn.expr = result

proc new_get_prop_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExGetProp,
    parent: parent,
    module: parent.module,
    get_prop_name: val.gene_data[0].str,
  )
  result.get_prop_self = new_expr(result, val.gene_props["self"])

proc new_set_prop_expr*(parent: Expr, name: string, val: GeneValue): Expr =
  result = Expr(
    kind: ExSetProp,
    parent: parent,
    module: parent.module,
    set_prop_name: name,
  )
  result.set_prop_val = new_expr(result, val)

proc new_binary_expr*(parent: Expr, op: string, val: GeneValue): Expr =
  if val.gene_data[1].is_literal:
    result = Expr(
      kind: ExBinImmediate,
      parent: parent,
      module: parent.module,
    )
    result.bini_first = new_expr(result, val.gene_data[0])
    result.bini_second = val.gene_data[1]
    case op:
    of "+":  result.bini_op = BinAdd
    of "-":  result.bini_op = BinSub
    of "*":  result.bini_op = BinMul
    of "/":  result.bini_op = BinDiv
    of "==": result.bini_op = BinEq
    of "!=": result.bini_op = BinNeq
    of "<":  result.bini_op = BinLt
    of "<=": result.bini_op = BinLe
    of ">":  result.bini_op = BinGt
    of ">=": result.bini_op = BinGe
    of "&&": result.bini_op = BinAnd
    of "||": result.bini_op = BinOr
    else: not_allowed()
  else:
    result = Expr(
      kind: ExBinary,
      parent: parent,
      module: parent.module,
    )
    result.bin_first = new_expr(result, val.gene_data[0])
    result.bin_second = new_expr(result, val.gene_data[1])
    case op:
    of "+":  result.bin_op = BinAdd
    of "-":  result.bin_op = BinSub
    of "*":  result.bin_op = BinMul
    of "/":  result.bin_op = BinDiv
    of "==": result.bin_op = BinEq
    of "!=": result.bin_op = BinNeq
    of "<":  result.bin_op = BinLt
    of "<=": result.bin_op = BinLe
    of ">":  result.bin_op = BinGt
    of ">=": result.bin_op = BinGe
    of "&&": result.bin_op = BinAnd
    of "||": result.bin_op = BinOr
    else: not_allowed()

when isMainModule:
  import os, times

  if commandLineParams().len == 0:
    echo "\nUsage: interpreter2 <GENE FILE>\n"
    quit(0)
  var interpreter = new_vm()
  let e = interpreter.prepare(readFile(commandLineParams()[0]))
  let start = cpuTime()
  let result = interpreter.eval(e)
  echo "Time: " & $(cpuTime() - start)
  echo result
