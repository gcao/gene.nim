import types
import parser

type
  Interpreter* = ref object
    result*: GeneValue

proc eval*(self: var Interpreter, node: GeneValue): GeneValue =
  case node.kind:
  of GeneNilKind:
    return GeneNil
  of GeneInt:
    return new_gene_int(node.num)
  else:
    discard

proc eval*(self: var Interpreter, buffer: string): GeneValue =
  var parsed = read_all(buffer)
  for node in parsed:
    self.result = self.eval node
  return self.result
