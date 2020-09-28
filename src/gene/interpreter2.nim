import tables

import ./types
import ./parser

# let IF   = new_gene_symbol("if")
# let THEN = new_gene_symbol("then")
# let ELIF = new_gene_symbol("elif")
# let ELSE = new_gene_symbol("else")

type
  VM2* = ref object
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
    members*: Table[string, GeneValue]

  Scope* = ref object
    parent*: Scope
    members*: Table[string, GeneValue]

  ExprKind* = enum
    ExLiteral
    ExSymbol
    ExMap
    ExMapChild
    ExArray
    ExGene
    ExBlock
    ExVar
    ExAssignment
    ExUnknown
    ExIf
    # ExIfElseIf
    ExLoop
    ExBreak
    ExWhile
    ExFn
    ExReturn

  Expr* = ref object of RootObj
    parent*: Expr
    posInParent*: int
    case kind*: ExprKind
    of ExLiteral:
      literal: GeneValue
    of ExSymbol:
      symbol: string
    of ExUnknown:
      unknown: GeneValue
    of ExArray:
      array: seq[Expr]
    of ExMap:
      map: seq[Expr]
    of ExMapChild:
      map_key: string
      map_val: Expr
    of ExGene:
      gene: GeneValue
      gene_blk: seq[Expr]
    of ExBlock:
      blk: seq[Expr]
    of ExVar, ExAssignment:
      var_name: string
      var_val: Expr
    of ExIf:
      if_cond: Expr
      if_then: Expr
      if_else: Expr
    of ExLoop:
      loop_blk: seq[Expr]
    of ExBreak:
      break_val: Expr
    of ExWhile:
      while_cond: Expr
      while_blk: seq[Expr]
    of ExFn:
      fn: GeneValue
      fn_body: seq[Expr]
    of ExReturn:
      return_val: Expr

  Break* = ref object of CatchableError
    val: GeneValue

  Return* = ref object of CatchableError
    val: GeneValue

  # NormalizedIf = tuple
  #   cond: GeneValue
  #   then_logic: seq[GeneValue]
  #   elif_pairs: seq[(GeneValue, seq[GeneValue])]
  #   else_logic: seq[GeneValue]

  # IfState = enum
  #   Cond
  #   ThenBlock
  #   ElseIfCond
  #   ElseIfThenBlock
  #   ElseBlock

#################### Interfaces ##################

proc `[]`*(self: VM2, key: string): GeneValue {.inline.}
proc to_expr*(node: GeneValue): Expr
proc to_expr*(parent: Expr, node: GeneValue): Expr
proc to_if_expr*(val: GeneValue): Expr
proc to_var_expr*(name: string, val: GeneValue): Expr
proc to_assignment_expr*(name: string, val: GeneValue): Expr
proc to_map_key_expr*(parent: Expr, key: string, val: GeneValue): Expr
proc to_block*(nodes: seq[GeneValue]): Expr
proc to_loop_expr*(val: GeneValue): Expr
proc to_break_expr*(val: GeneValue): Expr
proc to_while_expr*(val: GeneValue): Expr
proc to_fn_expr*(val: GeneValue): Expr
proc to_return_expr*(val: GeneValue): Expr
# proc normalize_if*(val: GeneValue): NormalizedIf

#################### Namespace ###################

proc new_namespace*(): Namespace =
  return Namespace(
    name: "<root>",
    members: Table[string, GeneValue](),
  )

proc new_namespace*(name: string): Namespace =
  return Namespace(
    name: name,
    members: Table[string, GeneValue](),
  )

proc new_namespace*(parent: Namespace, name: string): Namespace =
  return Namespace(
    parent: parent,
    name: name,
    members: Table[string, GeneValue](),
  )

proc `[]`*(self: Namespace, key: string): GeneValue {.inline.} = self.members[key]

proc `[]=`*(self: var Namespace, key: string, val: GeneValue) {.inline.} =
  self.members[key] = val

#################### Scope #######################

proc new_scope*(): Scope = Scope(members: Table[string, GeneValue]())

proc reset*(self: var Scope) =
  self.members.clear()

proc hasKey*(self: Scope, key: string): bool {.inline.} = self.members.hasKey(key)

proc `[]`*(self: Scope, key: string): GeneValue {.inline.} = self.members[key]

proc `[]=`*(self: var Scope, key: string, val: GeneValue) {.inline.} =
  self.members[key] = val

#################### Implementations #############

proc new_literal_expr*(v: GeneValue): Expr =
  return Expr(kind: ExLiteral, literal: v)

proc new_literal_expr*(parent: Expr, v: GeneValue): Expr =
  return Expr(parent: parent, kind: ExLiteral, literal: v)

proc new_symbol_expr*(s: string): Expr =
  return Expr(kind: ExSymbol, symbol: s)

proc new_array_expr*(v: GeneValue): Expr =
  result = Expr(kind: ExArray, array: @[])
  for item in v.vec:
    result.array.add(to_expr(result, item))

proc new_map_expr*(v: GeneValue): Expr =
  result = Expr(kind: ExMap, map: @[])
  for key, val in v.map:
    var e = to_map_key_expr(result, key, val)
    result.map.add(e)

proc new_gene_expr*(v: GeneValue): Expr =
  return Expr(kind: ExGene, gene: v)

proc new_unknown_expr*(v: GeneValue): Expr =
  return Expr(kind: ExUnknown, unknown: v)

proc new_unknown_expr*(parent: Expr, v: GeneValue): Expr =
  return Expr(parent: parent, kind: ExUnknown, unknown: v)

proc eval*(self: VM2, expr: Expr): GeneValue =
  case expr.kind:
  of ExLiteral:
    result = expr.literal
  of ExSymbol:
    result = self[expr.symbol]
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
      result.map[e.map_key] = self.eval(e)
  of ExMapChild:
    result = self.eval(expr.map_val)
  of ExGene:
    var gene = expr.gene
    case gene.gene_op.kind:
    of GeneSymbol:
      case gene.gene_op.symbol:
      of "+", "-", "==", "<", "<=", ">", ">=", "&&", "||":
        expr.gene_blk = @[]
        var first = gene.gene_data[0]
        var e1 = to_expr(first)
        var v1 = self.eval(e1)
        # expr.gene_blk.add(e1)
        var second = gene.gene_data[1]
        var e2 = to_expr(second)
        var v2 = self.eval(e2)
        # expr.gene_blk.add(e2)
        case gene.gene_op.symbol:
        of "+" : result = new_gene_int(v1.num + v2.num)
        of "-" : result = new_gene_int(v1.num - v2.num)
        of "==": result = new_gene_bool(v1.num == v2.num)
        of "<" : result = new_gene_bool(v1.num <  v2.num)
        of "<=": result = new_gene_bool(v1.num <= v2.num)
        of ">" : result = new_gene_bool(v1.num >  v2.num)
        of ">=": result = new_gene_bool(v1.num >= v2.num)
        of "&&": result = new_gene_bool(v1.boolVal and v2.boolVal)
        of "||": result = new_gene_bool(v1.boolVal or  v2.boolVal)
        else: todo($gene)
      else:
        var target = self[gene.gene_op.symbol]
        if target.kind == GeneInternal and target.internal.kind == GeneFunction:
          var fn = target.internal.fn
          var fn_scope = new_scope()
          var args: seq[GeneValue] = @[]
          for item in gene.gene_data:
            args.add(self.eval(to_expr(item)))
          fn_scope.parent = self.cur_frame.scope
          for i in 0..<fn.args.len:
            var arg = fn.args[i]
            var val = args[i]
            fn_scope[arg] = val
          var caller_scope = self.cur_frame.scope
          self.cur_frame.scope = fn_scope
          try:
            for item in fn.body:
              result = self.eval(to_expr(item))
          except Return as r:
            result = r.val
          self.cur_frame.scope = caller_scope
    else:
      todo($gene)
  of ExVar:
    var val = self.eval(expr.var_val)
    self.cur_frame.scope[expr.var_name] = val
    result = GeneNil
  of ExAssignment:
    var val = self.eval(expr.var_val)
    self.cur_frame.scope[expr.var_name] = val
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
    self.cur_frame.namespace[expr.fn.internal.fn.name] = expr.fn
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
      var e = to_expr(expr.unknown)
      parent.blk[expr.posInParent] = e
      result = self.eval(e)
    of ExLoop:
      var e = to_expr(expr.unknown)
      parent.loop_blk[expr.posInParent] = e
      result = self.eval(e)
    else:
      todo($expr.unknown)
  # else:
  #   todo($expr.kind)

#################### Frame #######################

proc new_frame*(): Frame =
  return Frame(
    namespace: new_namespace(),
    scope: new_scope(),
  )

#################### VM2 #########################

proc new_vm2*(): VM2 =
  return VM2(
    cur_frame: new_frame(),
  )

proc `[]`*(self: VM2, key: string): GeneValue {.inline.} =
  if self.cur_frame.scope.hasKey(key):
    return self.cur_frame.scope[key]
  else:
    return self.cur_frame.namespace[key]

proc prepare*(self: VM2, code: string): Expr =
  var parsed = read_all(code)
  return to_block(parsed)

proc eval*(self: VM2, code: string): GeneValue =
  return self.eval(self.prepare(code))

##################################################

proc to_expr*(node: GeneValue): Expr =
  case node.kind:
  of GeneNilKind, GeneBool, GeneInt:
    return new_literal_expr(node)
  of GeneSymbol:
    return new_symbol_expr(node.symbol)
  of GeneVector:
    return new_array_expr(node)
  of GeneMap:
    return new_map_expr(node)
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
        return to_var_expr(name, val)
      of "=":
        var name = node.gene_data[0].symbol
        var val = node.gene_data[1]
        return to_assignment_expr(name, val)
      of "if":
        return to_if_expr(node)
      of "do":
        return to_block(node.gene_data)
      of "loop":
        return to_loop_expr(node)
      of "break":
        return to_break_expr(node)
      of "while":
        return to_while_expr(node)
      of "fn":
        return to_fn_expr(node)
      of "return":
        return to_return_expr(node)
      else:
        return new_gene_expr(node)
    else:
      return new_gene_expr(node)
  else:
    todo($node)

proc to_expr*(parent: Expr, node: GeneValue): Expr =
  result = to_expr(node)
  result.parent = parent

proc to_block*(nodes: seq[GeneValue]): Expr =
  result = Expr(kind: ExBlock)
  for node in nodes:
    result.blk.add(new_unknown_expr(result, node))

proc to_loop_expr*(val: GeneValue): Expr =
  result = Expr(kind: ExLoop)
  for node in val.gene_data:
    result.loop_blk.add(to_expr(node))

proc to_break_expr*(val: GeneValue): Expr =
  result = Expr(kind: ExBreak)
  if val.gene_data.len > 0:
    result.break_val = to_expr(val.gene_data[0])

proc to_while_expr*(val: GeneValue): Expr =
  result = Expr(kind: ExWhile)
  result.while_cond = to_expr(val.gene_data[0])
  for i in 1..<val.gene_data.len:
    var node = val.gene_data[i]
    result.while_blk.add(to_expr(node))

proc to_map_key_expr*(parent: Expr, key: string, val: GeneValue): Expr =
  result = Expr(
    kind: ExMapChild,
    parent: parent,
    map_key: key,
  )
  result.map_val = to_expr(result, val)

proc to_var_expr*(name: string, val: GeneValue): Expr =
  result = Expr(
    kind: ExVar,
    var_name: name,
  )
  result.var_val = to_expr(result, val)

proc to_assignment_expr*(name: string, val: GeneValue): Expr =
  result = Expr(
    kind: ExAssignment,
    var_name: name,
  )
  result.var_val = to_expr(result, val)

proc to_if_expr*(val: GeneValue): Expr =
  result = Expr(
    kind: ExIf,
    if_cond: to_expr(val.gene_data[0]),
    if_then: to_expr(val.gene_data[1]),
  )
  if val.gene_data.len > 3:
    result.if_else = to_expr(val.gene_data[3])

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

proc to_fn_expr*(val: GeneValue): Expr =
  var fn: Function = val
  result = Expr(
    kind: ExFn,
    fn: new_gene_internal(fn),
  )

proc to_return_expr*(val: GeneValue): Expr =
  result = Expr(kind: ExReturn)
  if val.gene_data.len > 0:
    result.return_val = to_expr(val.gene_data[0])

when isMainModule:
  import os, times

  if commandLineParams().len == 0:
    echo "\nUsage: interpreter2 <GENE FILE>\n"
    quit(0)
  var interpreter = new_vm2()
  let e = interpreter.prepare(readFile(commandLineParams()[0]))
  let start = cpuTime()
  let result = interpreter.eval(e)
  echo "Time: " & $(cpuTime() - start)
  echo result