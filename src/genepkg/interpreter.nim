import types

type
  Interpreter* = ref object

proc interpret*(self: var Interpreter, buffer: string): GeneValue =
  return Nil
