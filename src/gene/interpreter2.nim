import tables

import ./types
import ./parser

type
  VM2* = ref object
    cur_frame*: Frame
    exprs*: seq[Expr]

  Frame* = ref object
    self*: GeneValue
    stack*: seq[GeneValue]

  ExprKind* = enum
    ExLiteral
    ExSymbol
    ExMap
    ExMapChild
    ExArray
    ExGene
    ExBlock
    ExUnknown

  Expr* = ref object of RootObj
    parent*: Expr
    posInParent*: int
    case kind*: ExprKind
    of ExLiteral:
      literal: GeneValue
    of ExUnknown:
      unknown: GeneValue
    of ExArray:
      array: seq[Expr]
    of ExMap:
      map: seq[Expr]
    of ExMapChild:
      mapKey: string
      mapVal: Expr
    of ExGene:
      gene: GeneValue
      gene_blk: seq[Expr]
    of ExBlock:
      blk: seq[Expr]
    else:
      discard

#################### Interfaces ##################

proc to_expr*(node: GeneValue): Expr
proc to_expr*(parent: Expr, node: GeneValue): Expr
proc to_map_key_expr*(parent: Expr, key: string, val: GeneValue): Expr
proc to_block*(nodes: seq[GeneValue]): Expr

#################### Implementations #############

proc new_literal_expr*(v: GeneValue): Expr =
  return Expr(kind: ExLiteral, literal: v)

proc new_literal_expr*(parent: Expr, v: GeneValue): Expr =
  return Expr(parent: parent, kind: ExLiteral, literal: v)

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
      result.map[e.mapKey] = self.eval(e)
  of ExMapChild:
    result = self.eval(expr.mapVal)
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
        else: todo()
      else:
        todo()
    else:
      todo()
  of ExUnknown:
    var parent = expr.parent
    case parent.kind:
    of ExBlock:
      var e = to_expr(expr.unknown)
      parent.blk[expr.posInParent] = e
      result = self.eval(e)
    else:
      todo()
  else:
    todo()

#################### VM2 #########################

proc new_vm2*(): VM2 =
  return VM2()

proc eval*(self: VM2, code: string): GeneValue =
  var parsed = read_all(code)
  return self.eval(to_block(parsed))

proc to_expr*(node: GeneValue): Expr =
  case node.kind:
  of GeneNilKind, GeneBool, GeneInt:
    return new_literal_expr(node)
  of GeneVector:
    return new_array_expr(node)
  of GeneMap:
    return new_map_expr(node)
  of GeneGene:
    node.normalize
    return new_gene_expr(node)
  else:
    todo()

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
    mapKey: key,
  )
  result.mapVal = to_expr(parent, val)
