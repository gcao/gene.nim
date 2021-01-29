import ./map_key
import ./types

let EX_GROUP = add_key("group")

converter to_key*(i: MapKey): int {.inline.} = cast[int](i)

proc translate*(stmt: GeneValue): GeneValue =
  case stmt.kind:
  of GeneNilKind, GeneInt, GeneString:
    result = stmt
  of GeneByType:
    # TODO: check whether its type is a symbol of "#Expr"
    todo()
  else:
    todo()

proc translate*(stmts: seq[GeneValue]): GeneValue =
  case stmts.len:
  of 0:
    result = GeneNil
  of 1:
    result = translate(stmts[0])
  else:
    result = new_gene_by_key(EX_GROUP)
