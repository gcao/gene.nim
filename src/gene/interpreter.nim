import tables, strutils, os

import ./types
import ./parser
import ./translators
import ./native_procs

type
  FnOption = enum
    FnClass
    FnMethod

  TryParsingState = enum
    TryBody
    TryCatch
    TryCatchBody
    TryFinally

var FrameMgr* = FrameManager()
var ScopeMgr* = ScopeManager()

let TRY*      = new_gene_symbol("try")
let CATCH*    = new_gene_symbol("catch")
let FINALLY*  = new_gene_symbol("finally")

init_native_procs()

#################### Interfaces ##################

proc get*(self: var ScopeManager): Scope {.inline.}
proc import_module*(self: VM, name: string, code: string): Namespace
proc load_core_module*(self: VM)
proc load_gene_module*(self: VM)
proc load_genex_module*(self: VM)
proc get_class*(self: VM, val: GeneValue): Class
proc def_member*(self: VM, frame: Frame, name: GeneValue, value: GeneValue, in_ns: bool)
proc get_member*(self: VM, frame: Frame, name: ComplexSymbol): GeneValue
proc set_member*(self: VM, frame: Frame, name: GeneValue, value: GeneValue)
proc match*(self: VM, frame: Frame, pattern: GeneValue, val: GeneValue, mode: MatchMode): GeneValue
proc import_from_ns*(self: VM, frame: Frame, source: GeneValue, group: seq[ImportMatcher])
proc explode_and_add*(parent: GeneValue, value: GeneValue)

proc eval_args*(self: VM, frame: Frame, props: seq[Expr], data: seq[Expr]): GeneValue

proc call_method*(self: VM, frame: Frame, instance: GeneValue, class: Class, method_name: string, args_blk: seq[Expr]): GeneValue
proc call_fn*(self: VM, frame: Frame, target: GeneValue, fn: Function, args: GeneValue, options: Table[FnOption, GeneValue]): GeneValue
proc call_macro*(self: VM, frame: Frame, target: GeneValue, mac: Macro, expr: Expr): GeneValue
proc call_block*(self: VM, frame: Frame, target: GeneValue, blk: Block, expr: Expr): GeneValue

proc call_aspect*(self: VM, frame: Frame, aspect: Aspect, expr: Expr): GeneValue
proc call_aspect_instance*(self: VM, frame: Frame, instance: AspectInstance, args: GeneValue): GeneValue

#################### ScopeManager ################

proc get*(self: var ScopeManager): Scope {.inline.} =
  if self.cache.len > 0:
    result = self.cache.pop()
    result.usage = 1
  else:
    return new_scope()

proc free*(self: var ScopeManager, scope: var Scope) {.inline.} =
  discard
  # scope.usage -= 1
  # if scope.usage == 0:
  #   if scope.parent != nil:
  #     self.free(scope.parent)
  #   scope.reset()
  #   self.cache.add(scope)

#################### FrameManager ################

proc get*(self: var FrameManager, kind: FrameKind, ns: Namespace, scope: Scope): Frame {.inline.} =
  if self.cache.len > 0:
    result = self.cache.pop()
  else:
    result = new_frame()
  result.parent = nil
  result.ns = ns
  result.scope = scope
  result.extra = FrameExtra(kind: kind)

proc free*(self: var FrameManager, frame: var Frame) {.inline.} =
  frame.reset()
  self.cache.add(frame)

#################### Implementations #############

proc eval*(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  case expr.kind:
  of ExTodo:
    if expr.todo != nil:
      todo(self.eval(frame, expr.todo).str)
    else:
      todo()
  of ExNotAllowed:
    if expr.not_allowed != nil:
      not_allowed(self.eval(frame, expr.not_allowed).str)
    else:
      not_allowed()
  of ExRoot:
    result = self.eval(frame, expr.root)
  of ExLiteral:
    result = expr.literal
  of ExSymbol:
    case expr.symbol:
    of "gene":
      result = GENE_NS
    of "genex":
      result = GENEX_NS
    else:
      result = frame[expr.symbol]
  of ExComplexSymbol:
    result = self.get_member(frame, expr.csymbol)
  of ExDo:
    var old_self = frame.self
    try:
      for e in expr.do_props:
        var val = self.eval(frame, e)
        case e.map_key:
        of "self":
          frame.self = val
        else:
          todo()
      for e in expr.do_body:
        result = self.eval(frame, e)
    finally:
      frame.self = old_self
  of ExGroup:
    for e in expr.group:
      result = self.eval(frame, e)
  of ExArray:
    result = new_gene_vec()
    for e in expr.array:
      result.explode_and_add(self.eval(frame, e))
  of ExMap:
    result = new_gene_map()
    for e in expr.map:
      result.map[e.map_key] = self.eval(frame, e.map_val)
  of ExMapChild:
    result = self.eval(frame, expr.map_val)
    # Assign the value to map/gene should be handled by evaluation of parent expression
  of ExGet:
    var target = self.eval(frame, expr.get_target)
    var index = self.eval(frame, expr.get_index)
    result = target.gene.data[index.int]
  of ExSet:
    var target = self.eval(frame, expr.set_target)
    var index = self.eval(frame, expr.set_index)
    var value = self.eval(frame, expr.set_value)
    target.gene.data[index.int] = value
  of ExRange:
    var range_start = self.eval(frame, expr.range_start)
    var range_end = self.eval(frame, expr.range_end)
    result = new_gene_range(range_start, range_end)
  of ExGene:
    var target = self.eval(frame, expr.gene_op)
    case target.kind:
    of GeneSymbol:
      result = new_gene_gene(target)
      for e in expr.gene_props:
        result.gene.props[e.map_key] = self.eval(frame, e.map_val)
      for e in expr.gene_data:
        result.gene.data.add(self.eval(frame, e))
    of GeneInternal:
      case target.internal.kind:
      of GeneFunction:
        var options = Table[FnOption, GeneValue]()
        var args = self.eval_args(frame, expr.gene_props, expr.gene_data)
        result = self.call_fn(frame, GeneNil, target.internal.fn, args, options)
      of GeneMacro:
        result = self.call_macro(frame, GeneNil, target.internal.mac, expr)
      of GeneBlock:
        result = self.call_block(frame, GeneNil, target.internal.blk, expr)
      of GeneReturn:
        var val = GeneNil
        if expr.gene_data.len == 0:
          discard
        elif expr.gene_data.len == 1:
          val = self.eval(frame, expr.gene_data[0])
        else:
          not_allowed()
        raise Return(
          frame: target.internal.ret.frame,
          val: val,
        )
      of GeneAspect:
        result = self.call_aspect(frame, target.internal.aspect, expr)
      of GeneAspectInstance:
        var args = self.eval_args(frame, expr.gene_props, expr.gene_data)
        result = self.call_aspect_instance(frame, target.internal.aspect_instance, args)
      else:
        todo()
    of GeneString:
      var str = target.str
      for item in expr.gene_data:
        str &= self.eval(frame, item).to_s
      result = new_gene_string_move(str)
    else:
      todo()

  of ExBinary:
    var first = self.eval(frame, expr.bin_first)
    var second = self.eval(frame, expr.bin_second)
    case expr.bin_op:
    of BinAdd: result = new_gene_int(first.int + second.int)
    of BinSub: result = new_gene_int(first.int - second.int)
    of BinMul: result = new_gene_int(first.int * second.int)
    # of BinDiv: result = new_gene_int(first.int / second.int)
    of BinEq:  result = new_gene_bool(first == second)
    of BinNeq: result = new_gene_bool(first != second)
    of BinLt:  result = new_gene_bool(first.int < second.int)
    of BinLe:  result = new_gene_bool(first.int <= second.int)
    of BinGt:  result = new_gene_bool(first.int > second.int)
    of BinGe:  result = new_gene_bool(first.int >= second.int)
    of BinAnd: result = new_gene_bool(first.bool and second.bool)
    of BinOr:  result = new_gene_bool(first.bool or second.bool)
    else: todo()
  of ExBinImmediate:
    var first = self.eval(frame, expr.bini_first)
    var second = expr.bini_second
    case expr.bini_op:
    of BinAdd: result = new_gene_int(first.int + second.int)
    of BinSub: result = new_gene_int(first.int - second.int)
    of BinMul: result = new_gene_int(first.int * second.int)
    # of BinDiv: result = new_gene_int(first.int / second.int)
    of BinEq:  result = new_gene_bool(first == second)
    of BinNeq: result = new_gene_bool(first != second)
    of BinLt:  result = new_gene_bool(first.int < second.int)
    of BinLe:  result = new_gene_bool(first.int <= second.int)
    of BinGt:  result = new_gene_bool(first.int > second.int)
    of BinGe:  result = new_gene_bool(first.int >= second.int)
    of BinAnd: result = new_gene_bool(first.bool and second.bool)
    of BinOr:  result = new_gene_bool(first.bool or second.bool)
    else: todo()
  of ExVar:
    var val = self.eval(frame, expr.var_val)
    self.def_member(frame, expr.var_name, val, false)
    result = GeneNil
  of ExAssignment:
    var val = self.eval(frame, expr.var_val)
    self.set_member(frame, expr.var_name, val)
    result = GeneNil
  of ExIf:
    var v = self.eval(frame, expr.if_cond)
    if v:
      result = self.eval(frame, expr.if_then)
    elif expr.if_else != nil:
      result = self.eval(frame, expr.if_else)
  of ExLoop:
    try:
      while true:
        for e in expr.loop_blk:
          discard self.eval(frame, e)
    except Break as b:
      result = b.val
  of ExBreak:
    var val = GeneNil
    if expr.break_val != nil:
      val = self.eval(frame, expr.break_val)
    var e: Break
    e.new
    e.val = val
    raise e
  of ExWhile:
    try:
      var cond = self.eval(frame, expr.while_cond)
      while cond:
        for e in expr.while_blk:
          discard self.eval(frame, e)
        cond = self.eval(frame, expr.while_cond)
    except Break as b:
      result = b.val
  of ExFor:
    try:
      var for_in = self.eval(frame, expr.for_in)
      var first, second: GeneValue
      case expr.for_vars.kind:
      of GeneSymbol:
        first = expr.for_vars
      of GeneVector:
        first = expr.for_vars.vec[0]
        second = expr.for_vars.vec[1]
      else:
        not_allowed()

      if second == nil:
        var val = first.symbol
        frame.scope.def_member(val, GeneNil)
        case for_in.kind:
        of GeneRange:
          for i in for_in.range_start.int..<for_in.range_end.int:
            frame.scope[val] = i
            for e in expr.for_blk:
              discard self.eval(frame, e)
        of GeneVector:
          for i in for_in.vec:
            frame.scope[val] = i
            for e in expr.for_blk:
              discard self.eval(frame, e)
        else:
          todo()
      else:
        var key = first.symbol
        var val = second.symbol
        frame.scope.def_member(key, GeneNil)
        frame.scope.def_member(val, GeneNil)
        case for_in.kind:
        of GeneVector:
          for k, v in for_in.vec:
            frame.scope[key] = k
            frame.scope[val] = v
            for e in expr.for_blk:
              discard self.eval(frame, e)
        of GeneMap:
          for k, v in for_in.map:
            frame.scope[key] = k
            frame.scope[val] = v
            for e in expr.for_blk:
              discard self.eval(frame, e)
        else:
          todo()
    except Break:
      discard
  of ExExplode:
    var val = self.eval(frame, expr.explode)
    result = new_gene_explode(val)
  of ExThrow:
    if expr.throw_type != nil:
      var typ = self.eval(frame, expr.throw_type)
      if expr.throw_mesg != nil:
        var msg = self.eval(frame, expr.throw_mesg)
        todo()
      else:
        todo()
  of ExTry:
    try:
      for e in expr.try_body:
        result = self.eval(frame, e)
    except:
      if expr.try_catches.len > 0:
        for catch in expr.try_catches:
          # TODO: check whether the thrown exception matches exception in catch statement
          for e in catch[1]:
            result = self.eval(frame, e)
  of ExFn:
    expr.fn.internal.fn.ns = frame.ns
    expr.fn.internal.fn.parent_scope = frame.scope
    expr.fn.internal.fn.parent_scope_max = frame.scope.max
    self.def_member(frame, expr.fn_name, expr.fn, true)
    frame.ns[expr.fn.internal.fn.name] = expr.fn
    result = expr.fn
  of ExArgs:
    case frame.extra.kind:
    of FrFunction, FrMacro, FrBlock, FrMethod:
      result = frame.args
    else:
      not_allowed()
  of ExMacro:
    expr.mac.internal.mac.ns = frame.ns
    frame.ns[expr.mac.internal.mac.name] = expr.mac
    result = expr.mac
  of ExBlock:
    expr.blk.internal.blk.ns = frame.ns
    expr.blk.internal.blk.parent_scope = frame.scope
    expr.blk.internal.blk.parent_scope_max = frame.scope.max
    result = expr.blk
  of ExReturn:
    var val = GeneNil
    if expr.return_val != nil:
      val = self.eval(frame, expr.return_val)
    raise Return(
      frame: frame,
      val: val,
    )
  of ExReturnRef:
    result = Return(frame: frame)
  of ExAspect:
    var aspect = expr.aspect.internal.aspect
    aspect.ns = frame.ns
    frame.ns[aspect.name] = expr.aspect
    result = expr.aspect
  of ExAdvice:
    var instance = frame.self.internal.aspect_instance
    var advice: Advice
    var logic = self.eval(frame, new_expr(expr, expr.advice.gene.data[1]))
    case expr.advice.gene.op.symbol:
    of "before":
      advice = new_advice(AdBefore, logic.internal.fn)
      instance.before_advices.add(advice)
    of "after":
      advice = new_advice(AdAfter, logic.internal.fn)
      instance.after_advices.add(advice)
    else:
      todo()
    advice.owner = instance

  of ExUnknown:
    var parent = expr.parent
    case parent.kind:
    of ExGroup:
      var e = new_expr(parent, expr.unknown)
      result = self.eval(frame, e)
    of ExLoop:
      var e = new_expr(parent, expr.unknown)
      result = self.eval(frame, e)
    else:
      todo($expr.unknown)
  of ExNamespace:
    self.def_member(frame, expr.ns_name, expr.ns, true)
    var old_self = frame.self
    var old_ns = frame.ns
    try:
      frame.self = expr.ns
      frame.ns = expr.ns.internal.ns
      for e in expr.ns_body:
        discard self.eval(frame, e)
      result = expr.ns
    finally:
      frame.self = old_self
      frame.ns = old_ns
  of ExSelf:
    return frame.self
  of ExGlobal:
    return self.app.ns
  of ExImport:
    var ns = self.modules[expr.import_matcher.from]
    self.import_from_ns(frame, ns, expr.import_matcher.children)
  of ExClass:
    expr.class.internal.class.ns.parent = frame.ns
    self.def_member(frame, expr.class_name, expr.class, true)
    var super_class: Class
    if expr.super_class == nil:
      if GENE_NS != nil and GENE_NS.internal.ns.hasKey("Object"):
        super_class = GENE_NS.internal.ns["Object"].internal.class
    else:
      super_class = self.eval(frame, expr.super_class).internal.class
    expr.class.internal.class.parent = super_class
    var ns = expr.class.internal.class.ns
    var scope = new_scope()
    var new_frame = FrameMgr.get(FrClass, ns, scope)
    new_frame.self = expr.class
    for e in expr.class_body:
      discard self.eval(new_frame, e)
    result = expr.class
  of ExMixin:
    self.def_member(frame, expr.mix_name, expr.mix, true)
    var ns = frame.ns
    var scope = new_scope()
    var new_frame = FrameMgr.get(FrMixin, ns, scope)
    new_frame.self = expr.mix
    for e in expr.mix_body:
      discard self.eval(new_frame, e)
    result = expr.mix
  of ExInclude:
    # Copy methods to target class
    for e in expr.include_args:
      var mix = self.eval(frame, e)
      for name, meth in mix.internal.mix.methods:
        frame.self.internal.class.methods[name] = meth
  of ExNew:
    var class = self.eval(frame, expr.new_class)
    var instance = new_instance(class.internal.class)
    result = new_gene_instance(instance)
    discard self.call_method(frame, result, class.internal.class, "new", expr.new_args)
  of ExMethod:
    expr.meth_ns = frame.ns
    var meth = expr.meth
    case frame.self.internal.kind:
    of GeneClass:
      meth.internal.meth.class = frame.self.internal.class
      frame.self.internal.class.methods[meth.internal.meth.name] = meth.internal.meth
    of GeneMixin:
      frame.self.internal.mix.methods[meth.internal.meth.name] = meth.internal.meth
    else:
      not_allowed()
    result = meth
  of ExInvokeMethod:
    var instance = self.eval(frame, expr.invoke_self)
    var class = self.get_class(instance)
    result = self.call_method(frame, instance, class, expr.invoke_meth, expr.invoke_args)
  of ExSuper:
    var instance = frame.self
    var meth = frame.scope["$method"].internal.meth
    var class = meth.class
    result = self.call_method(frame, instance, class.parent, meth.name, expr.super_args)
  of ExGetProp:
    var target = self.eval(frame, expr.get_prop_self)
    var name = expr.get_prop_name
    result = target.internal.instance.value.gene.props[name]
  of ExSetProp:
    var target = frame.self
    var name = expr.set_prop_name
    result = self.eval(frame, expr.set_prop_val)
    target.internal.instance.value.gene.props[name] = result
  of ExCallNative:
    var args: seq[GeneValue] = @[]
    for item in expr.native_args:
      args.add(self.eval(frame, item))
    var p = NativeProcs.get(expr.native_index)
    result = p(args)
  of ExGetClass:
    var val = self.eval(frame, expr.get_class_val)
    result = self.get_class(val)
  of ExEval:
    for e in expr.eval_args:
      var init_result = self.eval(frame, e)
      result = self.eval(frame, new_expr(expr, init_result))
  of ExCallerEval:
    var caller_frame = frame.parent
    for e in expr.caller_eval_args:
      result = self.eval(caller_frame, new_expr(expr, self.eval(frame, e)))
  of ExMatch:
    result = self.match(frame, expr.match_pattern, self.eval(frame, expr.match_val), MatchDefault)
  of ExQuote:
    result = expr.quote_val
  of ExEnv:
    var env = self.eval(frame, expr.env)
    result = get_env(env.str)
    if result.str.len == 0:
      result = self.eval(frame, expr.env_default).to_s

  of ExPrint:
    for e in expr.print:
      var v = self.eval(frame, e)
      case v.kind:
      of GeneString:
        stdout.write v.str
      else:
        stdout.write $v
    if expr.print_and_return:
      stdout.write "\n"
  # else:
  #   todo($expr.kind)

#################### VM #########################

proc new_vm*(app: Application): VM =
  result = VM(
    app: app,
  )

proc new_vm*(): VM =
  result = new_vm(APP)

proc prepare*(self: VM, code: string): Expr =
  var parsed = read_all(code)
  result = Expr(
    kind: ExRoot,
  )
  result.root = new_group_expr(result, parsed)

proc eval*(self: VM, code: string): GeneValue =
  var module = new_module()
  var frame = FrameMgr.get(FrModule, module.root_ns, new_scope())
  return self.eval(frame, self.prepare(code))

proc import_module*(self: VM, name: string, code: string): Namespace =
  if self.modules.hasKey(name):
    return self.modules[name]
  var module = new_module(name)
  var frame = FrameMgr.get(FrModule, module.root_ns, new_scope())
  discard self.eval(frame, self.prepare(code))
  result = module.root_ns
  self.modules[name] = result

proc load_core_module*(self: VM) =
  var ns = self.import_module("core", readFile("src/core.gene"))
  GENE_NS = ns["gene"]
  GENEX_NS = ns["genex"]

proc load_gene_module*(self: VM) =
  discard self.import_module("gene", readFile("src/gene.gene"))

proc load_genex_module*(self: VM) =
  discard self.import_module("genex", readFile("src/genex.gene"))

proc get_class*(self: VM, val: GeneValue): Class =
  case val.kind:
  of GeneInternal:
    case val.internal.kind:
    of GeneInstance:
      return val.internal.instance.class
    of GeneClass:
      return GENE_NS.internal.ns["Class"].internal.class
    of GeneFile:
      return GENE_NS.internal.ns["File"].internal.class
    else:
      todo()
  of GeneNilKind:
    return GENE_NS.internal.ns["Nil"].internal.class
  of GeneBool:
    return GENE_NS.internal.ns["Bool"].internal.class
  of GeneInt:
    return GENE_NS.internal.ns["Int"].internal.class
  of GeneChar:
    return GENE_NS.internal.ns["Char"].internal.class
  of GeneString:
    return GENE_NS.internal.ns["String"].internal.class
  of GeneVector:
    return GENE_NS.internal.ns["Array"].internal.class
  of GeneMap:
    return GENE_NS.internal.ns["Map"].internal.class
  else:
    todo()

proc call_method*(self: VM, frame: Frame, instance: GeneValue, class: Class, method_name: string, args_blk: seq[Expr]): GeneValue =
  var meth = class.get_method(method_name)
  if meth != nil:
    var options = Table[FnOption, GeneValue]()
    options[FnClass] = class
    options[FnMethod] = meth
    var args = self.eval_args(frame, @[], args_blk)
    result = self.call_fn(frame, instance, meth.fn, args, options)
  else:
    case method_name:
    of "new": # No implementation is required for `new` method
      discard
    else:
      todo("Method is missing: " & method_name)

proc eval_args*(self: VM, frame: Frame, props: seq[Expr], data: seq[Expr]): GeneValue =
  result = new_gene_gene(GeneNil)
  for e in props:
    var v = self.eval(frame, e)
    result.gene.props[e.map_key] = v
  for e in data:
    var v = self.eval(frame, e)
    if v.kind == GeneInternal and v.internal.kind == GeneExplode:
      result.merge(v.internal.explode)
    else:
      result.gene.data.add(v)

proc process_args*(self: VM, frame: Frame, matcher: RootMatcher) =
  var match_result = matcher.match(frame.args)
  if match_result.kind == MatchSuccess:
    for field in match_result.fields:
      if field.value_expr != nil:
        frame.scope.def_member(field.name, self.eval(frame, field.value_expr))
      else:
        frame.scope.def_member(field.name, field.value)
  else:
    todo()

proc call_fn*(
  self: VM,
  frame: Frame,
  target: GeneValue,
  fn: Function,
  args: GeneValue,
  options: Table[FnOption, GeneValue]
): GeneValue =
  var fn_scope = ScopeMgr.get()
  var ns: Namespace
  case fn.expr.kind:
  of ExFn:
    ns = fn.ns
    fn_scope.set_parent(fn.parent_scope, fn.parent_scope_max)
  of ExMethod:
    ns = fn.expr.meth_ns
  else:
    todo()
  var new_frame: Frame
  if options.hasKey(FnMethod):
    new_frame = FrameMgr.get(FrMethod, ns, fn_scope)
    fn_scope.def_member("$class", options[FnClass])
    var meth = options[FnMethod]
    fn_scope.def_member("$method", meth)
  else:
    new_frame = FrameMgr.get(FrFunction, ns, fn_scope)
  new_frame.parent = frame
  new_frame.self = target

  new_frame.args = args
  self.process_args(new_frame, fn.matcher)

  if fn.body_blk.len == 0:
    for item in fn.body:
      fn.body_blk.add(new_expr(fn.expr, item))
  try:
    for e in fn.body_blk:
      result = self.eval(new_frame, e)
  except Return as r:
    # return's frame is the same as new_frame(current function's frame)
    if r.frame == new_frame:
      result = r.val
    else:
      raise

  ScopeMgr.free(fn_scope)

proc call_macro*(self: VM, frame: Frame, target: GeneValue, mac: Macro, expr: Expr): GeneValue =
  var mac_scope = ScopeMgr.get()
  var new_frame = FrameMgr.get(FrFunction, mac.ns, mac_scope)
  new_frame.parent = frame
  new_frame.self = target

  new_frame.args = expr.gene
  self.process_args(new_frame, mac.matcher)

  var blk: seq[Expr] = @[]
  for item in mac.body:
    blk.add(new_expr(mac.expr, item))
  try:
    for e in blk:
      result = self.eval(new_frame, e)
  except Return as r:
    result = r.val

  ScopeMgr.free(mac_scope)

proc call_block*(self: VM, frame: Frame, target: GeneValue, blk: Block, expr: Expr): GeneValue =
  var blk_scope = ScopeMgr.get()
  blk_scope.set_parent(blk.parent_scope, blk.parent_scope_max)
  var new_frame = FrameMgr.get(FrBlock, blk.ns, blk_scope)
  new_frame.parent = frame
  new_frame.self = target

  var args_blk: seq[Expr]
  case expr.kind:
  of ExGene:
    args_blk = expr.gene_data
  else:
    todo()

  new_frame.args = new_gene_gene(GeneNil)
  for e in args_blk:
    var v = self.eval(frame, e)
    if v.kind == GeneInternal and v.internal.kind == GeneExplode:
      new_frame.args.merge(v.internal.explode)
    else:
      new_frame.args.gene.data.add(v)
  self.process_args(new_frame, blk.matcher)

  var blk2: seq[Expr] = @[]
  for item in blk.body:
    blk2.add(new_expr(blk.expr, item))
  for e in blk2:
    result = self.eval(new_frame, e)

  ScopeMgr.free(blk_scope)

proc call_aspect*(self: VM, frame: Frame, aspect: Aspect, expr: Expr): GeneValue =
  var new_scope = ScopeMgr.get()
  var new_frame = FrameMgr.get(FrAspect, aspect.ns, new_scope)
  new_frame.parent = frame

  new_frame.args = new_gene_gene(GeneNil)
  for e in expr.gene_data:
    var v = self.eval(frame, e)
    if v.kind == GeneInternal and v.internal.kind == GeneExplode:
      new_frame.args.merge(v.internal.explode)
    else:
      new_frame.args.gene.data.add(v)
  self.process_args(new_frame, aspect.matcher)

  var target = new_frame.args[0]
  result = new_aspect_instance(aspect, target)
  new_frame.self = result

  var blk: seq[Expr] = @[]
  for item in aspect.body:
    blk.add(new_expr(aspect.expr, item))
  try:
    for e in blk:
      discard self.eval(new_frame, e)
  except Return:
    discard

  ScopeMgr.free(new_scope)

proc call_aspect_instance*(self: VM, frame: Frame, instance: AspectInstance, args: GeneValue): GeneValue =
  var aspect = instance.aspect
  var new_scope = ScopeMgr.get()
  var new_frame = FrameMgr.get(FrAspect, aspect.ns, new_scope)
  new_frame.parent = frame
  new_frame.args = args

  # invoke before advices
  var options = Table[FnOption, GeneValue]()
  for advice in instance.before_advices:
    discard self.call_fn(new_frame, frame.self, advice.logic, new_frame.args, options)

  # invoke target
  case instance.target.internal.kind:
  of GeneFunction:
    result = self.call_fn(new_frame, frame.self, instance.target, new_frame.args, options)
  of GeneAspectInstance:
    result = self.call_aspect_instance(new_frame, instance.target.internal.aspect_instance, new_frame.args)
  else:
    todo()

  # invoke after advices
  for advice in instance.after_advices:
    discard self.call_fn(new_frame, frame.self, advice.logic, new_frame.args, options)

  ScopeMgr.free(new_scope)

proc def_member*(self: VM, frame: Frame, name: GeneValue, value: GeneValue, in_ns: bool) =
  case name.kind:
  of GeneString:
    if in_ns:
      frame.ns[name.str] = value
    else:
      frame.scope.def_member(name.str, value)
  of GeneSymbol:
    if in_ns:
      frame.ns[name.symbol] = value
    else:
      frame.scope.def_member(name.symbol, value)
  of GeneComplexSymbol:
    var ns: Namespace
    case name.csymbol.first:
    of "global":
      ns = GLOBAL_NS.internal.ns
    of "gene":
      ns = GENE_NS.internal.ns
    of "genex":
      ns = GENEX_NS.internal.ns
    else:
      var s = name.csymbol.first
      ns = frame[s].internal.ns
    for i in 0..<(name.csymbol.rest.len - 1):
      var name = name.csymbol.rest[i]
      ns = ns[name].internal.ns
    var base_name = name.csymbol.rest[^1]
    ns[base_name] = value
  else:
    not_allowed()

proc get_member*(self: VM, frame: Frame, name: ComplexSymbol): GeneValue =
  if name.first == "global":
    result = GLOBAL_NS
  elif name.first == "gene":
    result = GENE_NS
  elif name.first == "genex":
    result = GENEX_NS
  else:
    result = frame[name.first]
  for name in name.rest:
    result = result.get_member(name)

proc set_member*(self: VM, frame: Frame, name: GeneValue, value: GeneValue) =
  case name.kind:
  of GeneSymbol:
    if frame.scope.hasKey(name.symbol):
      frame.scope[name.symbol] = value
    else:
      frame.ns[name.symbol] = value
  of GeneComplexSymbol:
    var ns: Namespace
    case name.csymbol.first:
    of "global":
      ns = GLOBAL_NS.internal.ns
    of "gene":
      ns = GENE_NS.internal.ns
    of "genex":
      ns = GENEX_NS.internal.ns
    else:
      var s = name.csymbol.first
      ns = frame[s].internal.ns
    for i in 0..<(name.csymbol.rest.len - 1):
      var name = name.csymbol.rest[i]
      ns = ns[name].internal.ns
    var base_name = name.csymbol.rest[^1]
    ns[base_name] = value
  else:
    not_allowed()

proc match*(self: VM, frame: Frame, pattern: GeneValue, val: GeneValue, mode: MatchMode): GeneValue =
  case pattern.kind:
  of GeneSymbol:
    var name = pattern.symbol
    case mode:
    of MatchArgs:
      frame.scope.def_member(name, val.gene.data[0])
    else:
      frame.scope.def_member(name, val)
  of GeneVector:
    for i in 0..<pattern.vec.len:
      var name = pattern.vec[i].symbol
      if i < val.gene.data.len:
        frame.scope.def_member(name, val.gene.data[i])
      else:
        frame.scope.def_member(name, GeneNil)
  else:
    todo()

proc import_from_ns*(self: VM, frame: Frame, source: GeneValue, group: seq[ImportMatcher]) =
  for m in group:
    var value = source.internal.ns[m.name]
    if m.children_only:
      self.import_from_ns(frame, value.internal.ns, m.children)
    else:
      self.def_member(frame, m.name, value, true)

proc explode_and_add*(parent: GeneValue, value: GeneValue) =
  if value.kind == GeneInternal and value.internal.kind == GeneExplode:
    var explode = value.internal.explode
    case parent.kind:
    of GeneVector:
      case explode.kind:
      of GeneVector:
        for item in explode.vec:
          parent.vec.add(item)
      else:
        todo()
    of GeneGene:
      case explode.kind:
      of GeneVector:
        for item in explode.vec:
          parent.vec.add(item)
      else:
        todo()
    else:
      todo()
  else:
    case parent.kind:
    of GeneVector:
      parent.vec.add(value)
    of GeneGene:
      parent.gene.data.add(value)
    else:
      todo()

when isMainModule:
  import os, times

  if commandLineParams().len == 0:
    echo "\nUsage: interpreter <GENE FILE>\n"
    quit(0)
  var interpreter = new_vm()
  var module = new_module()
  var frame = FrameMgr.get(FrModule, module.root_ns, new_scope())
  let e = interpreter.prepare(readFile(commandLineParams()[0]))
  let start = cpuTime()
  let result = interpreter.eval(frame, e)
  echo "Time: " & $(cpuTime() - start)
  echo result
