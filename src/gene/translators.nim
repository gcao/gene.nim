import tables, strutils

import ./types
import ./normalizers
import ./decorator

type
  Translator* = proc(parent: Expr, val: GeneValue): Expr

  TranslatorManager* = ref object
    mappings*: Table[string, Translator]

  TryParsingState = enum
    TryBody
    TryCatch
    TryCatchBody
    TryFinally

var TranslatorMgr* = TranslatorManager()
var CustomTranslators*: seq[Translator]

let TRY*      = new_gene_symbol("try")
let CATCH*    = new_gene_symbol("catch")
let FINALLY*  = new_gene_symbol("finally")

#################### Definitions #################

proc new_expr*(parent: Expr, kind: ExprKind): Expr
proc new_expr*(parent: Expr, node: GeneValue): Expr
proc new_group_expr*(parent: Expr, nodes: seq[GeneValue]): Expr

#################### TranslatorManager ###########

proc `[]`*(self: TranslatorManager, name: string): Translator =
  if self.mappings.has_key(name):
    return self.mappings[name]

proc `[]=`*(self: TranslatorManager, name: string, t: Translator) =
  self.mappings[name] = t

#################### Translators #################

proc add_custom_translator*(t: Translator) =
  CustomTranslators.add(t)

proc new_unknown_expr*(parent: Expr, v: GeneValue): Expr =
  return Expr(
    kind: ExUnknown,
    parent: parent,
    unknown: v,
  )

proc new_literal_expr*(parent: Expr, v: GeneValue): Expr =
  return Expr(
    kind: ExLiteral,
    parent: parent,
    literal: v,
  )

proc new_symbol_expr*(parent: Expr, s: string): Expr =
  return Expr(
    kind: ExSymbol,
    parent: parent,
    symbol: s,
  )

proc new_complex_symbol_expr*(parent: Expr, node: GeneValue): Expr =
  return Expr(
    kind: ExComplexSymbol,
    parent: parent,
    csymbol: node.csymbol,
  )

proc new_array_expr*(parent: Expr, v: GeneValue): Expr =
  result = Expr(
    kind: ExArray,
    parent: parent,
    array: @[],
  )
  for item in v.vec:
    result.array.add(new_expr(result, item))

proc new_map_key_expr*(parent: Expr, key: string, val: GeneValue): Expr =
  result = Expr(
    kind: ExMapChild,
    parent: parent,
    map_key: key,
  )
  result.map_val = new_expr(result, val)

proc new_map_expr*(parent: Expr, v: GeneValue): Expr =
  result = Expr(
    kind: ExMap,
    parent: parent,
    map: @[],
  )
  for key, val in v.map:
    var e = new_map_key_expr(result, key, val)
    result.map.add(e)

proc new_gene_expr*(parent: Expr, v: GeneValue): Expr =
  return Expr(
    kind: ExGene,
    parent: parent,
    gene: v,
  )

proc new_range_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExRange,
    parent: parent,
  )
  result.range_start = new_expr(result, val.gene.data[0])
  result.range_end = new_expr(result, val.gene.data[1])
  result.range_incl_start = true
  result.range_incl_end = false

proc new_var_expr*(parent: Expr, node: GeneValue): Expr =
  var name = node.gene.data[0]
  var val = GeneNil
  if node.gene.data.len > 1:
    val = node.gene.data[1]
  result = Expr(
    kind: ExVar,
    parent: parent,
    var_name: name,
  )
  result.var_val = new_expr(result, val)

proc new_assignment_expr*(parent: Expr, node: GeneValue): Expr =
  var name = node.gene.data[0]
  var val = node.gene.data[1]
  result = Expr(
    kind: ExAssignment,
    parent: parent,
    var_name: name,
  )
  result.var_val = new_expr(result, val)

proc new_if_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExIf,
    parent: parent,
  )
  result.if_cond = new_expr(result, val.gene.props["cond"])
  result.if_then = new_group_expr(result, val.gene.props["then"].vec)
  result.if_else = new_group_expr(result, val.gene.props["else"].vec)

proc new_do_expr*(parent: Expr, node: GeneValue): Expr =
  result = Expr(
    kind: ExDo,
    parent: parent,
  )
  for k, v in node.gene.props:
    result.do_props.add(new_map_key_expr(result, k, v))
  var data = node.gene.data
  data = wrap_with_try(data)
  for item in data:
    result.do_body.add(new_expr(result, item))

proc new_group_expr*(parent: Expr, nodes: seq[GeneValue]): Expr =
  result = Expr(
    kind: ExGroup,
    parent: parent,
  )
  for node in nodes:
    result.group.add(new_unknown_expr(result, node))

proc new_loop_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExLoop,
    parent: parent,
  )
  for node in val.gene.data:
    result.loop_blk.add(new_expr(result, node))

proc new_break_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExBreak,
    parent: parent,
  )
  if val.gene.data.len > 0:
    result.break_val = new_expr(result, val.gene.data[0])

proc new_while_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExWhile,
    parent: parent,
  )
  result.while_cond = new_expr(result, val.gene.data[0])
  for i in 1..<val.gene.data.len:
    var node = val.gene.data[i]
    result.while_blk.add(new_expr(result, node))

proc new_for_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExFor,
    parent: parent,
  )
  result.for_vars = val.gene.data[0]
  result.for_in = new_expr(result, val.gene.data[2])
  for i in 3..<val.gene.data.len:
    var node = val.gene.data[i]
    result.for_blk.add(new_expr(result, node))

proc new_explode_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExExplode,
    parent: parent,
  )
  result.explode = new_expr(parent, val)

proc new_throw_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExThrow,
    parent: parent,
  )
  if val.gene.data.len > 0:
    result.throw_type = new_expr(result, val.gene.data[0])
  if val.gene.data.len > 1:
    result.throw_mesg = new_expr(result, val.gene.data[1])

proc new_try_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExTry,
    parent: parent,
  )
  var state = TryBody
  var catch_exception: Expr
  var catch_body: seq[Expr] = @[]
  for item in val.gene.data:
    case state:
    of TryBody:
      if item == CATCH:
        state = TryCatch
      elif item == FINALLY:
        state = TryFinally
      else:
        result.try_body.add(new_expr(result, item))
    of TryCatch:
      if item == CATCH:
        not_allowed()
      elif item == FINALLY:
        not_allowed()
      else:
        state = TryCatchBody
        catch_exception = new_expr(result, item)
    of TryCatchBody:
      if item == CATCH:
        state = TryCatch
        result.try_catches.add((catch_exception, catch_body))
        catch_exception = nil
        catch_body = @[]
      elif item == FINALLY:
        state = TryFinally
      else:
        catch_body.add(new_expr(result, item))
    of TryFinally:
      result.try_finally.add(new_expr(result, item))
  if state in [TryCatch, TryCatchBody]:
    result.try_catches.add((catch_exception, catch_body))
  elif state == TryFinally:
    if catch_exception != nil:
      result.try_catches.add((catch_exception, catch_body))

# Create expressions for default values
proc update_matchers*(fn: Function, group: seq[Matcher]) =
  for m in group:
    if m.default_value != nil and not m.default_value.is_literal:
      m.default_value_expr = new_expr(fn.expr, m.default_value)
    fn.update_matchers(m.children)

proc new_fn_expr*(parent: Expr, val: GeneValue): Expr =
  var fn: Function = val
  result = Expr(
    kind: ExFn,
    parent: parent,
    fn: fn,
    fn_name: val.gene.data[0],
  )
  fn.expr = result
  fn.update_matchers(fn.matcher.children)

proc new_macro_expr*(parent: Expr, val: GeneValue): Expr =
  var mac: Macro = val
  result = Expr(
    kind: ExMacro,
    parent: parent,
    mac: mac,
    mac_name: val.gene.data[0],
  )
  mac.expr = result

proc new_block_expr*(parent: Expr, val: GeneValue): Expr =
  var blk: Block = val
  result = Expr(
    kind: ExBlock,
    parent: parent,
    blk: blk,
  )
  blk.expr = result

proc new_return_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExReturn,
    parent: parent,
  )
  if val.gene.data.len > 0:
    result.return_val = new_expr(result, val.gene.data[0])

proc new_aspect_expr*(parent: Expr, val: GeneValue): Expr =
  var aspect: Aspect = val
  result = Expr(
    kind: ExAspect,
    parent: parent,
    aspect: aspect,
  )
  aspect.expr = result
  # TODO: convert default values to expressions like below
  # fn.update_matchers(fn.matcher.children)

proc new_advice_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExAdvice,
    parent: parent,
  )
  result.advice = val

proc new_ns_expr*(parent: Expr, val: GeneValue): Expr =
  var name = val.gene.data[0]
  var s: string
  case name.kind:
  of GeneSymbol:
    s = name.symbol
  of GeneComplexSymbol:
    s = name.csymbol.rest[^1]
  else:
    not_allowed()
  var ns = new_namespace(s)
  result = Expr(
    kind: ExNamespace,
    parent: parent,
    ns: ns,
    ns_name: name,
  )
  var body: seq[Expr] = @[]
  for i in 1..<val.gene.data.len:
    body.add(new_expr(parent, val.gene.data[i]))
  result.ns_body = body

proc new_import_expr*(parent: Expr, val: GeneValue): Expr =
  var matcher = new_import_matcher(val)
  result = Expr(
    kind: ExImport,
    parent: parent,
    import_matcher: matcher,
    import_native: val.gene.type.symbol == "import_native",
  )
  if matcher.from != nil:
    result.import_from = new_expr(result, matcher.from)
  if val.gene.props.has_key("pkg"):
    result.import_pkg = new_expr(result, val.gene.props["pkg"])

proc new_class_expr*(parent: Expr, val: GeneValue): Expr =
  var name = val.gene.data[0]
  var s: string
  case name.kind:
  of GeneSymbol:
    s = name.symbol
  of GeneComplexSymbol:
    s = name.csymbol.rest[^1]
  else:
    not_allowed()
  var class = new_class(s)
  result = Expr(
    kind: ExClass,
    parent: parent,
    class: class,
    class_name: name,
  )
  var body_start = 1
  if val.gene.data.len > 2 and val.gene.data[1] == new_gene_symbol("<"):
    body_start = 3
    result.super_class = new_expr(result, val.gene.data[2])
  var body: seq[Expr] = @[]
  for i in body_start..<val.gene.data.len:
    body.add(new_expr(parent, val.gene.data[i]))
  result.class_body = body

proc new_mixin_expr*(parent: Expr, val: GeneValue): Expr =
  var name = val.gene.data[0]
  var s: string
  case name.kind:
  of GeneSymbol:
    s = name.symbol
  of GeneComplexSymbol:
    s = name.csymbol.rest[^1]
  else:
    not_allowed()
  var mix = new_mixin(s)
  result = Expr(
    kind: ExMixin,
    parent: parent,
    mix: mix,
    mix_name: name,
  )
  var body: seq[Expr] = @[]
  for i in 1..<val.gene.data.len:
    body.add(new_expr(parent, val.gene.data[i]))
  result.mix_body = body

proc new_include_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExInclude,
    parent: parent,
  )
  for item in val.gene.data:
    result.include_args.add(new_expr(result, item))

proc new_new_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExNew,
    parent: parent,
  )
  result.new_class = new_expr(parent, val.gene.data[0])
  for i in 1..<val.gene.data.len:
    result.new_args.add(new_expr(result, val.gene.data[i]))

proc new_super_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExSuper,
    parent: parent,
  )
  for item in val.gene.data:
    result.super_args.add(new_expr(result, item))

proc new_method_expr*(parent: Expr, val: GeneValue): Expr =
  if val.gene.type.symbol == "native_method":
    var meth = Method(
      name: val.gene.data[0].symbol
    )
    result = Expr(
      kind: ExMethod,
      parent: parent,
      meth: meth,
    )
    result.meth_fn_native = new_expr(result, val.gene.data[1])
  else:
    var fn: Function = val # Converter is implicitly called here
    var meth = new_method(nil, fn.name, fn)
    result = Expr(
      kind: ExMethod,
      parent: parent,
      meth: meth,
    )
    fn.expr = result

proc new_invoke_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExInvokeMethod,
    parent: parent,
    invoke_meth: val.gene.props["method"].str,
  )
  result.invoke_self = new_expr(result, val.gene.props["self"])
  for item in val.gene.data:
    result.invoke_args.add(new_expr(result, item))

proc new_call_native_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExCallNative,
    parent: parent,
  )
  var name = val.gene.data[0].str
  var index = NativeProcs.get_index(name)
  result.native_name = name
  result.native_index = index
  for i in 1..<val.gene.data.len:
    result.native_args.add(new_expr(result, val.gene.data[i]))

proc new_eval_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExEval,
    parent: parent,
  )
  if val.gene.props.has_key("self"):
    result.eval_self = new_expr(result, val.gene.props["self"])
  for i in 0..<val.gene.data.len:
    result.eval_args.add(new_expr(result, val.gene.data[i]))

proc new_caller_eval_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExCallerEval,
    parent: parent,
  )
  for i in 0..<val.gene.data.len:
    result.caller_eval_args.add(new_expr(result, val.gene.data[i]))

proc new_match_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExMatch,
    parent: parent,
    match_pattern: val.gene.data[0],
  )
  result.match_val = new_expr(result, val.gene.data[1])

proc new_quote_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExQuote,
    parent: parent,
  )
  result.quote_val = val.gene.data[0]

proc new_env_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExEnv,
    parent: parent,
  )
  result.env = new_expr(result, val.gene.data[0])
  if val.gene.data.len > 1:
    result.env_default = new_expr(result, val.gene.data[1])

proc new_print_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExPrint,
    parent: parent,
    print_and_return: val.gene.type.symbol == "println",
  )
  if val.gene.props.get_or_default("stderr", false):
    result.print_to = new_expr(result, new_gene_symbol("stderr"))
  for item in val.gene.data:
    result.print.add(new_expr(result, item))

proc new_not_expr*(parent: Expr, val: GeneValue): Expr =
  result = new_expr(parent, ExNot)
  result.not = new_expr(result, val.gene.data[0])

proc new_binary_expr*(parent: Expr, `type`: string, val: GeneValue): Expr =
  if val.gene.data[1].is_literal:
    result = Expr(
      kind: ExBinImmediate,
      parent: parent,
    )
    result.bini_first = new_expr(result, val.gene.data[0])
    result.bini_second = val.gene.data[1]
    case `type`:
    of "+":  result.bini_op = BinAdd
    of "-":  result.bini_op = BinSub
    of "*":  result.bini_op = BinMul
    of "/":  result.bini_op = BinDiv
    of "==": result.bini_op = BinEq
    of "!=": result.bini_op = BinNeq
    of "<":  result.bini_op = BinLt
    of "<=": result.bini_op = BinLe
    of ">":  result.bini_op = BinGt
    of ">=": result.bini_op = BinGe
    of "&&": result.bini_op = BinAnd
    of "||": result.bini_op = BinOr
    else: not_allowed()
  else:
    result = Expr(
      kind: ExBinary,
      parent: parent,
    )
    result.bin_first = new_expr(result, val.gene.data[0])
    result.bin_second = new_expr(result, val.gene.data[1])
    case type:
    of "+":  result.bin_op = BinAdd
    of "-":  result.bin_op = BinSub
    of "*":  result.bin_op = BinMul
    of "/":  result.bin_op = BinDiv
    of "==": result.bin_op = BinEq
    of "!=": result.bin_op = BinNeq
    of "<":  result.bin_op = BinLt
    of "<=": result.bin_op = BinLe
    of ">":  result.bin_op = BinGt
    of ">=": result.bin_op = BinGe
    of "&&": result.bin_op = BinAnd
    of "||": result.bin_op = BinOr
    else: not_allowed()

proc new_expr*(parent: Expr, kind: ExprKind): Expr =
  result = Expr(
    kind: kind,
    parent: parent,
  )

proc new_expr*(parent: Expr, node: GeneValue): Expr =
  case node.kind:
  of GeneNilKind, GeneBool, GeneInt:
    return new_literal_expr(parent, node)
  of GeneString:
    result = new_expr(parent, ExString)
    result.str = node.str
  of GeneSymbol:
    case node.symbol:
    of "global":
      return new_expr(parent, ExGlobal)
    of "$args":
      return new_expr(parent, ExArgs)
    of "self":
      return new_expr(parent, ExSelf)
    of "return":
      return new_expr(parent, ExReturnRef)
    of "_":
      return new_literal_expr(parent, GenePlaceholder)
    elif node.symbol.endsWith("..."):
      if node.symbol.len == 3: # symbol == "..."
        return new_explode_expr(parent, new_gene_symbol("$args"))
      else:
        return new_explode_expr(parent, new_gene_symbol(node.symbol[0..^4]))
    elif node.symbol.startsWith("@"):
      result = new_expr(parent, ExLiteral)
      result.literal = to_selector(node.symbol)
      return result
    else:
      return new_symbol_expr(parent, node.symbol)
  of GeneComplexSymbol:
    if node.csymbol.first.startsWith("@"):
      result = new_expr(parent, ExLiteral)
      result.literal = to_selector(node.csymbol)
      return result
    else:
      return new_complex_symbol_expr(parent, node)
  of GeneVector:
    node.process_decorators()
    return new_array_expr(parent, node)
  of GeneStream:
    return new_group_expr(parent, node.stream)
  of GeneMap:
    return new_map_expr(parent, node)
  of GeneGene:
    node.normalize()
    if node.gene.type.kind == GeneSymbol:
      if node.gene.type.symbol in ["+", "-", "==", "!=", "<", "<=", ">", ">=", "&&", "||"]:
        return new_binary_expr(parent, node.gene.type.symbol, node)
      elif node.gene.type.symbol == "...":
        return new_explode_expr(parent, node.gene.data[0])
      var translator = TranslatorMgr[node.gene.type.symbol]
      if translator != nil:
        return translator(parent, node)
      for t in CustomTranslators:
        result = t(parent, node)
        if result != nil:
          return result
    # Process decorators like +f, (+g 1)
    node.process_decorators()
    result = new_gene_expr(parent, node)
    result.gene_type = new_expr(result, node.gene.type)
    for k, v in node.gene.props:
      result.gene_props.add(new_map_key_expr(result, k, v))
    for item in node.gene.data:
      result.gene_data.add(new_expr(result, item))
  else:
    return new_literal_expr(parent, node)

TranslatorMgr["enum"          ] = proc(parent: Expr, node: GeneValue): Expr =
  var e = new_enum(node.gene.data[0].symbol_or_str)
  var i = 1
  var value = 0
  while i < node.gene.data.len:
    var name = node.gene.data[i].symbol
    i += 1
    if i < node.gene.data.len and node.gene.data[i] == Equal:
      i += 1
      value = node.gene.data[i].int
      i += 1
    e.add_member(name, value)
    value += 1
  result = new_expr(parent, ExEnum)
  result.enum = e

TranslatorMgr["range"         ] = new_range_expr
TranslatorMgr["do"            ] = new_do_expr
TranslatorMgr["loop"          ] = new_loop_expr
TranslatorMgr["while"         ] = new_while_expr
TranslatorMgr["for"           ] = new_for_expr
TranslatorMgr["break"         ] = new_break_expr
TranslatorMgr["continue"      ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExContinue)
TranslatorMgr["if"            ] = new_if_expr
TranslatorMgr["not"           ] = new_not_expr
TranslatorMgr["var"           ] = new_var_expr
TranslatorMgr["throw"         ] = new_throw_expr
TranslatorMgr["try"           ] = new_try_expr
TranslatorMgr["fn"            ] = new_fn_expr
TranslatorMgr["macro"         ] = new_macro_expr
TranslatorMgr["return"        ] = new_return_expr
TranslatorMgr["aspect"        ] = new_aspect_expr
TranslatorMgr["before"        ] = new_advice_expr
TranslatorMgr["after"         ] = new_advice_expr
TranslatorMgr["ns"            ] = new_ns_expr
TranslatorMgr["import"        ] = new_import_expr
TranslatorMgr["import_native" ] = new_import_expr
TranslatorMgr["$stop_inheritance"] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExStopInheritance)
TranslatorMgr["class"         ] = new_class_expr
TranslatorMgr["method"        ] = new_method_expr
TranslatorMgr["native_method" ] = new_method_expr
TranslatorMgr["new"           ] = new_new_expr
TranslatorMgr["super"         ] = new_super_expr
TranslatorMgr["$invoke_method"] = new_invoke_expr
TranslatorMgr["mixin"         ] = new_mixin_expr
TranslatorMgr["include"       ] = new_include_expr
TranslatorMgr["call_native"   ] = new_call_native_expr
TranslatorMgr["$parse"        ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExParse)
  result.parse = new_expr(parent, node.gene.data[0])
TranslatorMgr["eval"          ] = new_eval_expr
TranslatorMgr["caller_eval"   ] = new_caller_eval_expr
TranslatorMgr["match"         ] = new_match_expr
TranslatorMgr["quote"         ] = new_quote_expr
TranslatorMgr["unquote"       ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExExit)
  result.unquote_val = node.gene.data[0]
# TranslatorMgr["..."           ] = new_explode_expr
TranslatorMgr["env"           ] = new_env_expr
TranslatorMgr["exit"          ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExExit)
  if node.gene.data.len > 0:
    result.exit = new_expr(parent, node.gene.data[0])
TranslatorMgr["print"         ] = new_print_expr
TranslatorMgr["println"       ] = new_print_expr
TranslatorMgr["="             ] = new_assignment_expr

TranslatorMgr["call"          ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExCall)
  # for k, v in node.gene.props:
  #   result.call_props[k] = new_expr(parent, v)
  result.call_target = new_expr(result, node.gene.data[0])
  if node.gene.data.len > 2:
    not_allowed("Syntax error: too many parameters are passed to (call).")
  elif node.gene.data.len > 1:
    result.call_args = new_expr(result, node.gene.data[1])

TranslatorMgr["$get"          ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExGet)
  result.get_target = new_expr(result, node.gene.data[0])
  result.get_index = new_expr(result, node.gene.data[1])

TranslatorMgr["$set"          ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExGet)
  result = new_expr(parent, ExSet)
  result.set_target = new_expr(result, node.gene.data[0])
  result.set_index = new_expr(result, node.gene.data[1])
  result.set_value = new_expr(result, node.gene.data[2])

TranslatorMgr["$def_member"   ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExDefMember)
  result.def_member_name = new_expr(result, node.gene.data[0])
  result.def_member_value = new_expr(result, node.gene.data[1])

TranslatorMgr["$def_ns_member"] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExDefNsMember)
  result.def_ns_member_name = new_expr(result, node.gene.data[0])
  result.def_ns_member_value = new_expr(result, node.gene.data[1])

TranslatorMgr["$get_class"    ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExGetClass)
  result.get_class_val = new_expr(result, node.gene.data[0])

TranslatorMgr["->"            ] = proc(parent: Expr, node: GeneValue): Expr =
  return new_block_expr(parent, node)

TranslatorMgr["todo"          ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExTodo)
  result.todo = new_expr(result, node.gene.data[0])

TranslatorMgr["not_allowed"   ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExNotAllowed)
  if node.gene.data.len > 0:
    result.not_allowed = new_expr(result, node.gene.data[0])

TranslatorMgr["$parse_cmd_args"] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExParseCmdArgs)
  var m = new_cmd_args_matcher()
  m.parse(node.gene.data[0])
  result.cmd_args_schema = m
  result.cmd_args = new_expr(result, node.gene.data[1])

TranslatorMgr["repl"] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExRepl)

TranslatorMgr["async"] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExAsync)
  result.async = new_expr(result, node.gene.data[0])

TranslatorMgr["await"] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExAwait)
  result.await = @[]
  for item in node.gene.data:
    result.await.add(new_expr(result, item))

TranslatorMgr["$on_future_success"] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExAsyncCallback)
  result.acb_success = true
  result.acb_self = new_expr(result, node.gene.data[0])
  result.acb_callback = new_expr(result, node.gene.data[1])

TranslatorMgr["$on_future_failure"] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExAsyncCallback)
  result.acb_success = false
  result.acb_self = new_expr(result, node.gene.data[0])
  result.acb_callback = new_expr(result, node.gene.data[1])

TranslatorMgr["@"] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExSelector)
  for item in node.gene.data:
    result.selector.add(new_expr(result, item))

TranslatorMgr["@*"] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExSelector)
  result.parallel_mode = true
  for item in node.gene.data:
    result.selector.add(new_expr(result, item))
