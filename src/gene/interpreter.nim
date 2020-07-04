import types
import parser
import vm_types

proc eval*(self: var VM, node: GeneValue): GeneValue =
  case node.kind:
  of GeneNilKind:
    return GeneNil
  of GeneInt:
    return new_gene_int(node.num)
  else:
    discard

proc eval*(self: var VM, buffer: string): GeneValue =
  var parsed = read_all(buffer)
  for node in parsed:
    result = self.eval node
  return
