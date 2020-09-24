import ./types

type
  Interpreter2* = ref object

  Evaluator* = ref object of RootObj
    parent*: Evaluator

  # # Evaluates numbers, boolean, strings etc
  # LiteralEvaluator* = ref object of Evaluator
  
  SymbolEvaluator* = ref object of Evaluator

  MapEvaluator* = ref object of Evaluator
    keys: seq[string]
    index: int

  ArrayEvaluator* = ref object of Evaluator
    size: int
    index: int

  GeneEvaluator* = ref object of Evaluator

#################### Interfaces ##################

#################### Implementations #############

method eval*(self: Evaluator, node: GeneValue): GeneValue {.base.} =
  discard


#################### Interpreter2 ################

proc new_interpreter2*(): Interpreter2 =
  return Interpreter2()

proc eval*(self: Interpreter2, code: string): GeneValue =
  discard
