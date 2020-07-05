import ./types
import ./parser
import ./vm_types

proc eval*(self: var VM, node: GeneValue): GeneValue =
  case node.kind:
  of GeneNilKind:
    return GeneNil
  of GeneInt:
    return new_gene_int(node.num)
  of GeneBool:
    return new_gene_bool(node.boolVal)
  of GeneSymbol:
    var (_, name) = node.symbol
    return cast[GeneValue](self.cur_stack.cur_scope[name])
  of GeneGene:
    var op = node.op
    case op.kind:
    of GeneSymbol:
      if op.symbol == ("", "var"):
        var name = $node.list[0]
        var value = self.eval(node.list[1])
        self.cur_stack.cur_scope[name] = value
      elif op.symbol == ("", "if"):
        todo()
    else: todo()
  else: todo()

proc eval*(self: var VM, buffer: string): GeneValue =
  var parsed = read_all(buffer)
  for node in parsed:
    result = self.eval node
  return
