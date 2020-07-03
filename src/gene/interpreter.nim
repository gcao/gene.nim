import types
import parser

type
  Interpreter* = ref object
    result*: GeneValue

proc eval*(self: var Interpreter, node: GeneValue): GeneValue =
  case node.kind:
  of GeneNil:
    return Nil
  else:
    discard

proc eval*(self: var Interpreter, buffer: string): GeneValue =
  var parsed = read_all(buffer)
  for node in parsed:
    self.result = self.eval node
  return self.result
