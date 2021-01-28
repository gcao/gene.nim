import ../map_key
import ../types
import ../translators/base as translators_base
import ../interpreter/base as interpreter_base

proc new_macro*(name: string, matcher: RootMatcher, body: seq[GeneValue]): Macro =
  return Macro(
    name: name,
    matcher: matcher,
    body: body,
  )

converter to_macro(node: GeneValue): Macro =
  var first = node.gene.data[0]
  var name: string
  if first.kind == GeneSymbol:
    name = first.symbol
  elif first.kind == GeneComplexSymbol:
    name = first.csymbol.rest[^1]

  var matcher = new_arg_matcher()
  matcher.parse(node.gene.data[1])

  var body: seq[GeneValue] = @[]
  for i in 2..<node.gene.data.len:
    body.add node.gene.data[i]

  body = wrap_with_try(body)
  return new_macro(name, matcher, body)

proc init*() =
  TranslatorMgr[MACRO_KEY] = proc(parent: Expr, val: GeneValue): Expr =
    var mac: Macro = val
    result = Expr(
      kind: ExMacro,
      parent: parent,
      mac: mac,
      mac_name: val.gene.data[0],
    )
    mac.expr = result

  EvaluatorMgr[ExMacro] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    expr.mac.internal.mac.ns = frame.ns
    self.def_member(frame, expr.mac_name, expr.mac, true)
    result = expr.mac
