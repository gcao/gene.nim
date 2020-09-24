import ./types
import ./parser

type
  Interpreter2* = ref object
    evaluators*: seq[Expr]
    stack*: seq[GeneValue]

  ExprKind* = enum
    ExLiteral
    ExSymbol
    ExMap
    ExArray
    ExGene
    ExBlock
    ExUnknown

  Expr* = ref object of RootObj
    parent*: Expr
    case kind*: ExprKind
    of ExLiteral:
      literal: GeneValue
    of ExUnknown:
      unknown: GeneValue
      posInParent: int
    of ExBlock:
      blk: seq[Expr]
    else:
      discard

#################### Interfaces ##################

proc to_expr*(node: GeneValue): Expr
proc to_block*(nodes: seq[GeneValue]): Expr

#################### Implementations #############

proc new_literal_expr*(v: GeneValue): Expr =
  return Expr(kind: ExLiteral, literal: v)

proc new_literal_expr*(parent: Expr, v: GeneValue): Expr =
  return Expr(parent: parent, kind: ExLiteral, literal: v)

proc new_unknown_expr*(v: GeneValue): Expr =
  return Expr(kind: ExUnknown, unknown: v)

proc new_unknown_expr*(parent: Expr, v: GeneValue): Expr =
  return Expr(parent: parent, kind: ExUnknown, unknown: v)

proc eval*(self: Expr): GeneValue =
  case self.kind:
  of ExLiteral:
    result = self.literal
  of ExBlock:
    for e in self.blk:
      result = e.eval()
  of ExUnknown:
    var parent = self.parent
    case parent.kind:
    of ExBlock:
      var e = to_expr(self.unknown)
      parent.blk[self.posInParent] = e
      result = e.eval()
    else:
      todo()
  else:
    todo()

#################### Interpreter2 ################

proc new_interpreter2*(): Interpreter2 =
  return Interpreter2()

proc eval*(self: Interpreter2, code: string): GeneValue =
  var parsed = read_all(code)
  return to_block(parsed).eval()

proc to_expr*(node: GeneValue): Expr =
  case node.kind:
  of GeneNilKind, GeneBool, GeneInt:
    return new_literal_expr(node)
  else:
    todo()

proc to_expr*(node: GeneValue, parent: Expr): Expr =
  result = to_expr(node)
  result.parent = parent

proc to_block*(nodes: seq[GeneValue]): Expr =
  result = Expr(kind: ExBlock)
  for node in nodes:
    result.blk.add(new_unknown_expr(result, node))
