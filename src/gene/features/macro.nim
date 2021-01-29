import tables

import ../map_key
import ../types
import ../translators/base as translators_base
import ../interpreter/base as interpreter_base

let MACRO_KEY* = add_key("macro")

proc new_macro*(name: string, matcher: RootMatcher, body: seq[GeneValue]): Macro =
  return Macro(
    name: name,
    matcher: matcher,
    body: body,
  )

converter new_gene_internal*(mac: Macro): GeneValue =
  return GeneValue(
    kind: GeneInternal,
    internal: Internal(kind: GeneMacro, mac: mac),
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

  GeneEvaluators[ord(GeneMacro)] = proc(self: VirtualMachine, frame: Frame, expr: Expr, `type`: GeneValue): GeneValue =
    var mac = `type`.internal.mac
    var mac_scope = new_scope()
    var new_frame = FrameMgr.get(FrFunction, mac.ns, mac_scope)
    new_frame.parent = frame

    new_frame.args = expr.gene
    self.process_args(new_frame, mac.matcher, new_frame.args)

    var blk: seq[Expr] = @[]
    for item in mac.body:
      blk.add(new_expr(mac.expr, item))
    try:
      for e in blk:
        result = self.eval(new_frame, e)
    except Return as r:
      result = r.val
    except CatchableError as e:
      if self.repl_on_error:
        result = repl_on_error(self, frame, e)
      else:
        raise
