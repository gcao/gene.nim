import tables

import ./types
import ./parser

type
  VM2* = ref object
    cur_frame*: Frame
    exprs*: seq[Expr]

  Frame* = ref object
    self*: GeneValue
    namespace*: Namespace
    scope*: Scope
    stack*: seq[GeneValue]

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

#################### Interfaces ##################

proc to_expr*(node: GeneValue): Expr
proc to_expr*(parent: Expr, node: GeneValue): Expr
proc to_if_expr*(val: GeneValue): Expr
proc to_var_expr*(name: string, val: GeneValue): Expr
proc to_assignment_expr*(name: string, val: GeneValue): Expr
proc to_map_key_expr*(parent: Expr, key: string, val: GeneValue): Expr
proc to_block*(nodes: seq[GeneValue]): Expr

#################### Namespace ###################

proc `[]`*(self: Namespace, key: int): GeneValue {.inline.} = self.members[key]

proc `[]=`*(self: var Namespace, key: int, val: GeneValue) {.inline.} =
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
    result = self.cur_frame.scope[expr.symbol]
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
        todo($gene)
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
  of ExUnknown:
    var parent = expr.parent
    case parent.kind:
    of ExBlock:
      var e = to_expr(expr.unknown)
      parent.blk[expr.posInParent] = e
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

proc eval*(self: VM2, code: string): GeneValue =
  var parsed = read_all(code)
  return self.eval(to_block(parsed))

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
