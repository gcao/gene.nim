import ../map_key
import ../types
import ../translators
import ../interpreter/base

type
  CaseState = enum
    CsInput, CsWhen, CsWhenLogic, CsElse

let CASE_KEY*                 = add_key("case")
let WHEN_KEY*                 = add_key("when")

proc case_equals(input: GeneValue, pattern: GeneValue): bool =
  case input.kind:
  of GeneInt:
    case pattern.kind:
    of GeneInt:
      result = input.int == pattern.int
    of GeneRange:
      result = input.int >= pattern.range_start.int and input.int < pattern.range_end.int
    else:
      not_allowed($pattern.kind)
  else:
    result = input == pattern

proc init*() =
  TranslatorMgr[CASE_KEY] = proc(parent: Expr, node: GeneValue): Expr =
    # Create a variable because result can not be accessed from closure.
    var expr = new_expr(parent, ExCase)
    expr.case_input = new_expr(result, node.gene.data[0])

    var state = CsInput
    var cond: GeneValue
    var logic: seq[GeneValue]

    proc update_mapping(cond: GeneValue, logic: seq[GeneValue]) =
      var index = expr.case_blks.len
      expr.case_blks.add(new_group_expr(expr, logic))
      if cond.kind == GeneVector:
        for item in cond.vec:
          expr.case_more_mapping.add((new_expr(expr, item), index))
      else:
        expr.case_more_mapping.add((new_expr(expr, cond), index))

    proc handler(input: GeneValue) =
      case state:
      of CsInput:
        if input == When:
          state = CsWhen
        else:
          not_allowed()
      of CsWhen:
        state = CsWhenLogic
        cond = input
        logic = @[]
      of CsWhenLogic:
        if input == nil:
          update_mapping(cond, logic)
        elif input == When:
          state = CsWhen
          update_mapping(cond, logic)
        elif input == Else:
          state = CsElse
          update_mapping(cond, logic)
          logic = @[]
        else:
          logic.add(input)
      of CsElse:
        if input == nil:
          expr.case_else = new_group_expr(expr, logic)
        else:
          logic.add(input)

    var i = 1
    while i < node.gene.data.len:
      handler(node.gene.data[i])
      i += 1
    handler(nil)

    result = expr

  EvaluatorMgr[ExCase] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var input = self.eval(frame, expr.case_input)
    for pair in expr.case_more_mapping:
      var pattern = self.eval(frame, pair[0])
      if input.case_equals(pattern):
        return self.eval(frame, expr.case_blks[pair[1]])
    result = self.eval(frame, expr.case_else)
