import tables, strutils

import ./types
import ./parser
import ./native_procs

type
  FnOption = enum
    FnClass
    FnMethod

var FrameMgr* = FrameManager()
var ScopeMgr* = ScopeManager()

init_native_procs()

#################### Interfaces ##################

proc `[]`*(self: Frame, key: int): GeneValue {.inline.}
proc new_expr*(parent: Expr, kind: ExprKind): Expr
proc get*(self: var ScopeManager): Scope {.inline.}
proc import_module*(self: VM, name: string, code: string): Namespace
proc load_core_module*(self: VM)
proc load_gene_module*(self: VM)
proc load_genex_module*(self: VM)
proc get_class*(self: VM, val: GeneValue): Class
proc get_member*(self: VM, frame: Frame, name: ComplexSymbol): GeneValue
proc set_member*(self: VM, frame: Frame, name: GeneValue, value: GeneValue, in_ns: bool)
proc match*(self: VM, frame: Frame, pattern: GeneValue, val: GeneValue, mode: MatchMode): GeneValue

proc new_expr*(parent: Expr, node: GeneValue): Expr {.inline.}
proc new_if_expr*(parent: Expr, val: GeneValue): Expr
proc new_var_expr*(parent: Expr, name: string, val: GeneValue): Expr
proc new_assignment_expr*(parent: Expr, name: string, val: GeneValue): Expr
proc new_map_key_expr*(parent: Expr, key: string, val: GeneValue): Expr
proc new_group_expr*(parent: Expr, nodes: seq[GeneValue]): Expr
proc new_loop_expr*(parent: Expr, val: GeneValue): Expr
proc new_break_expr*(parent: Expr, val: GeneValue): Expr
proc new_while_expr*(parent: Expr, val: GeneValue): Expr
proc new_explode_expr*(parent: Expr, val: GeneValue): Expr
proc new_fn_expr*(parent: Expr, val: GeneValue): Expr
proc new_macro_expr*(parent: Expr, val: GeneValue): Expr
proc new_block_expr*(parent: Expr, val: GeneValue): Expr
proc new_return_expr*(parent: Expr, val: GeneValue): Expr
proc new_aspect_expr*(parent: Expr, val: GeneValue): Expr
proc new_advice_expr*(parent: Expr, val: GeneValue): Expr
proc new_binary_expr*(parent: Expr, op: string, val: GeneValue): Expr
proc new_ns_expr*(parent: Expr, val: GeneValue): Expr
proc new_import_expr*(parent: Expr, val: GeneValue): Expr
proc new_class_expr*(parent: Expr, val: GeneValue): Expr
proc new_mixin_expr*(parent: Expr, val: GeneValue): Expr
proc new_include_expr*(parent: Expr, val: GeneValue): Expr
proc new_new_expr*(parent: Expr, val: GeneValue): Expr
proc new_method_expr*(parent: Expr, val: GeneValue): Expr
proc new_super_expr*(parent: Expr, val: GeneValue): Expr
proc new_invoke_expr*(parent: Expr, val: GeneValue): Expr
proc new_get_prop_expr*(parent: Expr, val: GeneValue): Expr
proc new_set_prop_expr*(parent: Expr, name: string, val: GeneValue): Expr
proc new_call_native_expr*(parent: Expr, val: GeneValue): Expr
proc new_eval_expr*(parent: Expr, val: GeneValue): Expr
proc new_caller_eval_expr*(parent: Expr, val: GeneValue): Expr
proc new_match_expr*(parent: Expr, val: GeneValue): Expr
proc new_quote_expr*(parent: Expr, val: GeneValue): Expr

proc call_method*(self: VM, frame: Frame, instance: GeneValue, class: Class, method_name: string, args: seq[Expr]): GeneValue
proc call_fn*(self: VM, frame: Frame, target: GeneValue, fn: Function, args_blk: seq[Expr], options: Table[FnOption, GeneValue]): GeneValue
proc call_macro*(self: VM, frame: Frame, target: GeneValue, mac: Macro, expr: Expr): GeneValue
proc call_block*(self: VM, frame: Frame, target: GeneValue, blk: Block, expr: Expr): GeneValue

#################### Frame #######################

proc new_frame*(): Frame = Frame(
  self: GeneNil,
)

proc reset*(self: var Frame) {.inline.} =
  self.self = nil
  self.ns = nil
  self.scope = nil
  self.extra = nil

proc `[]`*(self: Frame, key: int): GeneValue {.inline.} =
  if self.scope.hasKey(key):
    return self.scope[key]
  else:
    return self.ns[key]

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

proc new_literal_expr*(parent: Expr, v: GeneValue): Expr =
  return Expr(
    kind: ExLiteral,
    parent: parent,
    module: parent.module,
    literal: v,
  )

proc new_symbol_expr*(parent: Expr, s: string): Expr =
  var key = parent.module.get_index(s)
  return Expr(
    kind: ExSymbol,
    parent: parent,
    module: parent.module,
    symbol: s,
    symbol_key: key,
  )

proc new_complex_symbol_expr*(parent: Expr, node: GeneValue): Expr =
  return Expr(
    kind: ExComplexSymbol,
    parent: parent,
    module: parent.module,
    csymbol: node.csymbol,
  )

proc new_array_expr*(parent: Expr, v: GeneValue): Expr =
  result = Expr(
    kind: ExArray,
    parent: parent,
    module: parent.module,
    array: @[],
  )
  for item in v.vec:
    result.array.add(new_expr(result, item))

proc new_map_expr*(parent: Expr, v: GeneValue): Expr =
  result = Expr(
    kind: ExMap,
    parent: parent,
    module: parent.module,
    map: @[],
  )
  for key, val in v.map:
    var e = new_map_key_expr(result, key, val)
    result.map.add(e)

proc new_gene_expr*(parent: Expr, v: GeneValue): Expr =
  return Expr(
    kind: ExGene,
    parent: parent,
    module: parent.module,
    gene: v,
  )

proc new_unknown_expr*(parent: Expr, v: GeneValue): Expr =
  return Expr(
    kind: ExUnknown,
    parent: parent,
    module: parent.module,
    unknown: v,
  )

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
    result = frame[expr.symbol_key]
  of ExComplexSymbol:
    result = self.get_member(frame, expr.csymbol)
  of ExGroup:
    for e in expr.group:
      result = self.eval(frame, e)
  of ExArray:
    result = new_gene_vec()
    for e in expr.array:
      result.vec.add(self.eval(frame, e))
  of ExMap:
    result = new_gene_map()
    for e in expr.map:
      result.map[e.map_key] = self.eval(frame, e.map_val)
  of ExMapChild:
    discard
  of ExGet:
    var target = self.eval(frame, expr.get_target)
    var index = self.eval(frame, expr.get_index)
    result = target.gene.data[index.int]
  of ExSet:
    var target = self.eval(frame, expr.set_target)
    var index = self.eval(frame, expr.set_index)
    var value = self.eval(frame, expr.set_value)
    target.gene.data[index.int] = value
  of ExGene:
    var target = self.eval(frame, expr.gene_op)
    var processed = false
    case target.kind:
    of GeneSymbol:
      processed = true
      result = new_gene_gene(target)
      for e in expr.gene_props:
        result.gene.props[e.map_key] = self.eval(frame, e.map_val)
      for e in expr.gene_data:
        result.gene.data.add(self.eval(frame, e))
    of GeneInternal:
      case target.internal.kind:
      of GeneFunction:
        processed = true
        var options = Table[FnOption, GeneValue]()
        result = self.call_fn(frame, GeneNil, target.internal.fn, expr.gene_data, options)
      of GeneMacro:
        processed = true
        result = self.call_macro(frame, GeneNil, target.internal.mac, expr)
      of GeneBlock:
        processed = true
        result = self.call_block(frame, GeneNil, target.internal.blk, expr)
      of GeneReturn:
        processed = true
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
      else:
        todo()
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
    of BinEq:  result = new_gene_bool(first.int == second.int)
    of BinNeq: result = new_gene_bool(first.int != second.int)
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
    of BinEq:  result = new_gene_bool(first.int == second.int)
    of BinNeq: result = new_gene_bool(first.int != second.int)
    of BinLt:  result = new_gene_bool(first.int < second.int)
    of BinLe:  result = new_gene_bool(first.int <= second.int)
    of BinGt:  result = new_gene_bool(first.int > second.int)
    of BinGe:  result = new_gene_bool(first.int >= second.int)
    of BinAnd: result = new_gene_bool(first.bool and second.bool)
    of BinOr:  result = new_gene_bool(first.bool or second.bool)
    else: todo()
  of ExVar:
    var val = self.eval(frame, expr.var_val)
    frame.scope.def_member(expr.var_key, val)
    result = GeneNil
  of ExAssignment:
    var val = self.eval(frame, expr.var_val)
    frame.scope[expr.var_key] = val
    result = GeneNil
  of ExIf:
    var v = self.eval(frame, expr.if_cond)
    if v:
      result = self.eval(frame, expr.if_then)
    else:
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
  of ExExplode:
    var val = self.eval(frame, expr.explode)
    result = new_gene_explode(val)
  of ExFn:
    expr.fn.internal.fn.ns = frame.ns
    expr.fn.internal.fn.parent_scope = frame.scope
    frame.ns[expr.fn.internal.fn.name_key] = expr.fn
    result = expr.fn
  of ExArgs:
    case frame.extra.kind:
    of FrFunction, FrMacro, FrBlock, FrMethod:
      result = frame.args
    else:
      not_allowed()
  of ExMacro:
    expr.mac.internal.mac.ns = frame.ns
    frame.ns[expr.mac.internal.mac.name_key] = expr.mac
    result = expr.mac
  of ExBlock:
    expr.blk.internal.blk.ns = frame.ns
    expr.blk.internal.blk.parent_scope = frame.scope
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
    result = new_gene_internal(Return(frame: frame))
  of ExAspect:
    var aspect = expr.aspect.internal.aspect
    aspect.ns = frame.ns
    var key = frame.ns.module.get_index(aspect.name)
    frame.ns[key] = expr.aspect
    result = expr.aspect
  of ExAdvice:
    todo()
    # Create advice
    # Apply it immediately
  of ExUnknown:
    var parent = expr.parent
    case parent.kind:
    of ExGroup:
      var e = new_expr(parent, expr.unknown)
      parent.group[expr.posInParent] = e
      result = self.eval(frame, e)
    of ExLoop:
      var e = new_expr(parent, expr.unknown)
      parent.loop_blk[expr.posInParent] = e
      result = self.eval(frame, e)
    else:
      todo($expr.unknown)
  of ExNamespace:
    frame.ns[expr.ns.internal.ns.name_key] = expr.ns
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
    return new_gene_internal(self.app.ns)
  of ExImport:
    var ns = self.modules[expr.import_module]
    for name in expr.import_mappings:
      var key = expr.module.get_index(name)
      frame.ns.members[key] = ns[name]
  of ExClass:
    self.set_member(frame, expr.class_name, expr.class, true)
    var super_class: Class
    if expr.super_class == nil:
      if GENE_NS != nil and GENE_NS.internal.ns.hasKey("Object"):
        super_class = GENE_NS.internal.ns["Object"].internal.class
    else:
      super_class = self.eval(frame, expr.super_class).internal.class
    expr.class.internal.class.parent = super_class
    var ns = frame.ns
    var scope = new_scope()
    var new_frame = FrameMgr.get(FrClass, ns, scope)
    new_frame.self = expr.class
    for e in expr.class_body:
      discard self.eval(new_frame, e)
    result = expr.class
  of ExMixin:
    self.set_member(frame, expr.mix_name, expr.mix, true)
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
    var method_key = frame.ns.module.get_index("$method")
    var meth = frame.scope[method_key].internal.meth
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
    result = new_gene_internal(self.get_class(val))
  of ExEval:
    for e in expr.eval_args:
      result = self.eval(frame, new_expr(expr, self.eval(frame, e)))
  of ExCallerEval:
    var caller_frame = frame.parent
    for e in expr.caller_eval_args:
      result = self.eval(caller_frame, new_expr(expr, self.eval(frame, e)))
  of ExMatch:
    result = self.match(frame, expr.match_pattern, self.eval(frame, expr.match_val), MatchDefault)
  of ExQuote:
    result = expr.quote_val
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
  var root = Expr(
    kind: ExRoot,
    module: self.cur_module,
  )
  return new_group_expr(root, parsed)

proc eval*(self: VM, code: string): GeneValue =
  self.cur_module = new_module()
  var frame = FrameMgr.get(FrModule, self.cur_module.root_ns, new_scope())
  return self.eval(frame, self.prepare(code))

proc load_core_module*(self: VM) =
  discard self.import_module("gene", readFile("src/core.gene"))

proc load_gene_module*(self: VM) =
  var ns = self.import_module("gene", readFile("src/gene.gene"))
  GENE_NS = ns["gene"]

proc load_genex_module*(self: VM) =
  var ns = self.import_module("genex", readFile("src/genex.gene"))
  GENEX_NS = ns["genex"]

proc get_class*(self: VM, val: GeneValue): Class =
  case val.kind:
  of GeneInternal:
    case val.internal.kind:
    of GeneInstance:
      return val.internal.instance.class
    else:
      todo()
  of GeneString:
    return GENE_NS.internal.ns["String"].internal.class
  else:
    todo()

proc import_module*(self: VM, name: string, code: string): Namespace =
  if self.modules.hasKey(name):
    return self.modules[name]
  self.cur_module = new_module(name)
  self.cur_frame = FrameMgr.get(FrModule, self.cur_module.root_ns, new_scope())
  discard self.eval(code)
  result = self.cur_module.root_ns
  self.modules[name] = result

proc call_method*(self: VM, frame: Frame, instance: GeneValue, class: Class, method_name: string, args: seq[Expr]): GeneValue =
  var meth = class.get_method(method_name)
  if meth != nil:
    var options = Table[FnOption, GeneValue]()
    options[FnClass] = new_gene_internal(class)
    options[FnMethod] = new_gene_internal(meth)
    result = self.call_fn(frame, instance, meth.fn, args, options)
  else:
    case method_name:
    of "new": # No implementation is required for `new` method
      discard
    else:
      todo("Method is missing: " & method_name)

proc process_args*(self: VM, frame: Frame, module: var Module, matcher: RootMatcher) =
  var match_result = matcher.match(frame.args)
  if match_result.kind == MatchSuccess:
    for field in match_result.fields:
      var key = module.get_index(field.name)
      if field.value_expr != nil:
        frame.scope.def_member(key, self.eval(frame, field.value_expr))
      else:
        frame.scope.def_member(key, field.value)
  else:
    todo()

proc call_fn*(
  self: VM,
  frame: Frame,
  target: GeneValue,
  fn: Function,
  args_blk: seq[Expr],
  options: Table[FnOption, GeneValue]
): GeneValue =
  var module = fn.expr.module
  var fn_scope = ScopeMgr.get()
  var ns: Namespace
  case fn.expr.kind:
  of ExFn:
    ns = fn.ns
    fn_scope.parent = fn.parent_scope
    fn_scope.parent.usage += 1
  of ExMethod:
    ns = fn.expr.meth_ns
  else:
    todo()
  var new_frame: Frame
  if options.hasKey(FnMethod):
    new_frame = FrameMgr.get(FrMethod, ns, fn_scope)
    var class_key = module.get_index("$class")
    fn_scope.def_member(class_key, options[FnClass])
    var method_key = module.get_index("$method")
    var meth = options[FnMethod]
    fn_scope.def_member(method_key, meth)
  else:
    new_frame = FrameMgr.get(FrFunction, ns, fn_scope)
  new_frame.parent = frame
  new_frame.self = target

  new_frame.args = new_gene_gene(GeneNil)
  for e in args_blk:
    var v = self.eval(frame, e)
    if v.kind == GeneInternal and v.internal.kind == GeneExplode:
      new_frame.args.merge(v.internal.explode)
    else:
      new_frame.args.gene.data.add(v)
  self.process_args(new_frame, module, fn.matcher)

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
  var module = mac.expr.module
  self.process_args(new_frame, module, mac.matcher)

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
  blk_scope.parent = blk.parent_scope
  blk_scope.parent.usage += 1
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
  var module = blk.expr.module
  self.process_args(new_frame, module, blk.matcher)

  var blk2: seq[Expr] = @[]
  for item in blk.body:
    blk2.add(new_expr(blk.expr, item))
  for e in blk2:
    result = self.eval(new_frame, e)

  ScopeMgr.free(blk_scope)

proc get_member*(self: VM, frame: Frame, name: ComplexSymbol): GeneValue =
  if name.first == "global":
    result = GLOBAL_NS
  elif name.first == "gene":
    result = GENE_NS
  else:
    var key = frame.ns.module.get_index(name.first)
    result = frame[key]
  for name in name.rest:
    result = result.internal.ns[name]

proc set_member*(self: VM, frame: Frame, name: GeneValue, value: GeneValue, in_ns: bool) =
  case name.kind:
  of GeneSymbol:
    var key = self.cur_module.get_index(name.symbol)
    if in_ns:
      frame.ns[key] = value
    else:
      frame.scope[key] = value
  of GeneComplexSymbol:
    var ns: Namespace
    if name.csymbol.first == "global":
      ns = GLOBAL_NS.internal.ns
    elif name.csymbol.first == "gene":
      ns = GENE_NS.internal.ns
    else:
      var key = self.cur_module.get_index(name.csymbol.first)
      ns = frame[key].internal.ns
    for i in 0..<(name.csymbol.rest.len - 1):
      var name = name.csymbol.rest[i]
      ns = ns[name].internal.ns
    var base_name = name.csymbol.rest[^1]
    var key = ns.module.get_index(base_name)
    ns[key] = value
  else:
    not_allowed()

proc match*(self: VM, frame: Frame, pattern: GeneValue, val: GeneValue, mode: MatchMode): GeneValue =
  case pattern.kind:
  of GeneSymbol:
    var name = pattern.symbol
    var key = frame.ns.module.get_index(name)
    case mode:
    of MatchArgs:
      frame.scope.def_member(key, val.gene.data[0])
    else:
      frame.scope.def_member(key, val)
  of GeneVector:
    for i in 0..<pattern.vec.len:
      var name = pattern.vec[i].symbol
      var key = frame.ns.module.get_index(name)
      if i < val.gene.data.len:
        frame.scope.def_member(key, val.gene.data[i])
      else:
        frame.scope.def_member(key, GeneNil)
  else:
    todo()

##################################################

proc new_expr*(parent: Expr, kind: ExprKind): Expr =
  result = Expr(
    kind: kind,
    parent: parent,
    module: parent.module,
  )

proc new_expr*(parent: Expr, node: GeneValue): Expr {.inline.} =
  node.strip_comments
  case node.kind:
  of GeneNilKind, GeneBool, GeneInt, GeneString:
    return new_literal_expr(parent, node)
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
    else:
      if node.symbol.endsWith("..."):
        if node.symbol.len == 3: # symbol == "..."
          return new_explode_expr(parent, new_gene_symbol("$args"))
        else:
          return new_explode_expr(parent, new_gene_symbol(node.symbol[0..^4]))
      else:
        return new_symbol_expr(parent, node.symbol)
  of GeneComplexSymbol:
    return new_complex_symbol_expr(parent, node)
  of GeneVector:
    return new_array_expr(parent, node)
  of GeneMap:
    return new_map_expr(parent, node)
  of GeneGene:
    node.normalize
    case node.gene.op.kind:
    of GeneSymbol:
      case node.gene.op.symbol:
      of "var":
        var name = node.gene.data[0].symbol
        var val = GeneNil
        if node.gene.data.len > 1:
          val = node.gene.data[1]
        return new_var_expr(parent, name, val)
      of "=":
        var name = node.gene.data[0].symbol
        var val = node.gene.data[1]
        return new_assignment_expr(parent, name, val)
      of "@":
        return new_get_prop_expr(parent, node)
      of "@=":
        var name = node.gene.data[0].str
        var val = node.gene.data[1]
        return new_set_prop_expr(parent, name, val)
      of "if":
        return new_if_expr(parent, node)
      of "do":
        return new_group_expr(parent, node.gene.data)
      of "loop":
        return new_loop_expr(parent, node)
      of "break":
        return new_break_expr(parent, node)
      of "while":
        return new_while_expr(parent, node)
      of "fn":
        return new_fn_expr(parent, node)
      of "macro":
        return new_macro_expr(parent, node)
      of "return":
        return new_return_expr(parent, node)
      of "aspect":
        return new_aspect_expr(parent, node)
      of "before":
        return new_advice_expr(parent, node)
      of "ns":
        return new_ns_expr(parent, node)
      of "import":
        return new_import_expr(parent, node)
      of "class":
        return new_class_expr(parent, node)
      of "mixin":
        return new_mixin_expr(parent, node)
      of "include":
        return new_include_expr(parent, node)
      of "new":
        return new_new_expr(parent, node)
      of "method":
        return new_method_expr(parent, node)
      of "super":
        return new_super_expr(parent, node)
      of "$invoke_method":
        return new_invoke_expr(parent, node)
      of "call_native":
        return new_call_native_expr(parent, node)
      of "$get":
        result = new_expr(parent, ExGet)
        result.get_target = new_expr(result, node.gene.data[0])
        result.get_index = new_expr(result, node.gene.data[1])
        return result
      of "$set":
        result = new_expr(parent, ExSet)
        result.set_target = new_expr(result, node.gene.data[0])
        result.set_index = new_expr(result, node.gene.data[1])
        result.set_value = new_expr(result, node.gene.data[2])
        return result
      of "$get_class":
        result = new_expr(parent, ExGetClass)
        result.get_class_val = new_expr(result, node.gene.data[0])
        return result
      of "eval":
        return new_eval_expr(parent, node)
      of "caller_eval":
        return new_caller_eval_expr(parent, node)
      of "match":
        return new_match_expr(parent, node)
      of "quote":
        return new_quote_expr(parent, node)
      of "+", "-", "==", "!=", "<", "<=", ">", ">=", "&&", "||":
        return new_binary_expr(parent, node.gene.op.symbol, node)
      of "->":
        return new_block_expr(parent, node)
      of "todo":
        result = new_expr(parent, ExTodo)
        result.todo = new_expr(result, node.gene.data[0])
        return result
      of "not_allowed":
        result = new_expr(parent, ExNotAllowed)
        result.not_allowed = new_expr(result, node.gene.data[0])
        return result
      else:
        discard
    else:
      discard
    result = new_gene_expr(parent, node)
    result.gene_op = new_expr(result, node.gene.op)
    for k, v in node.gene.props:
      result.gene_props.add(new_map_key_expr(result, k, v))
    for item in node.gene.data:
      result.gene_data.add(new_expr(result, item))
  else:
    todo($node)

proc new_group_expr*(parent: Expr, nodes: seq[GeneValue]): Expr =
  result = Expr(
    kind: ExGroup,
    parent: parent,
    module: parent.module,
  )
  for node in nodes:
    result.group.add(new_unknown_expr(result, node))

proc new_loop_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExLoop,
    parent: parent,
    module: parent.module,
  )
  for node in val.gene.data:
    result.loop_blk.add(new_expr(result, node))

proc new_break_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExBreak,
    parent: parent,
    module: parent.module,
  )
  if val.gene.data.len > 0:
    result.break_val = new_expr(result, val.gene.data[0])

proc new_while_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExWhile,
    parent: parent,
    module: parent.module,
  )
  result.while_cond = new_expr(result, val.gene.data[0])
  for i in 1..<val.gene.data.len:
    var node = val.gene.data[i]
    result.while_blk.add(new_expr(result, node))

proc new_map_key_expr*(parent: Expr, key: string, val: GeneValue): Expr =
  result = Expr(
    kind: ExMapChild,
    parent: parent,
    module: parent.module,
    map_key: key,
  )
  result.map_val = new_expr(result, val)

proc new_var_expr*(parent: Expr, name: string, val: GeneValue): Expr =
  var key = parent.module.get_index(name)
  result = Expr(
    kind: ExVar,
    parent: parent,
    module: parent.module,
    # var_name: name,
    var_key: key,
  )
  result.var_val = new_expr(result, val)

proc new_assignment_expr*(parent: Expr, name: string, val: GeneValue): Expr =
  var key = parent.module.get_index(name)
  result = Expr(
    kind: ExAssignment,
    parent: parent,
    module: parent.module,
    # var_name: name,
    var_key: key,
  )
  result.var_val = new_expr(result, val)

proc new_if_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExIf,
    parent: parent,
    module: parent.module,
  )
  result.if_cond = new_expr(result, val.gene.data[0])
  result.if_then = new_expr(result, val.gene.data[1])
  if val.gene.data.len > 3:
    result.if_else = new_expr(result, val.gene.data[3])

# Create expressions for default values
proc update_matchers*(fn: Function, group: seq[Matcher]) =
  for m in group:
    if m.default_value != nil and not m.default_value.is_literal:
      m.default_value_expr = new_expr(fn.expr, m.default_value)
    fn.update_matchers(m.children)

proc new_explode_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExExplode,
    parent: parent,
    module: parent.module,
  )
  result.explode = new_expr(parent, val)

proc new_fn_expr*(parent: Expr, val: GeneValue): Expr =
  var fn: Function = val
  fn.name_key = parent.module.get_index(fn.name)
  result = Expr(
    kind: ExFn,
    parent: parent,
    module: parent.module,
    fn: new_gene_internal(fn),
  )
  fn.expr = result
  fn.update_matchers(fn.matcher.children)

proc new_macro_expr*(parent: Expr, val: GeneValue): Expr =
  var mac: Macro = val
  mac.name_key = parent.module.get_index(mac.name)
  result = Expr(
    kind: ExMacro,
    parent: parent,
    module: parent.module,
    mac: new_gene_internal(mac),
  )
  mac.expr = result

proc new_block_expr*(parent: Expr, val: GeneValue): Expr =
  var blk: Block = val
  result = Expr(
    kind: ExBlock,
    parent: parent,
    module: parent.module,
    blk: new_gene_internal(blk),
  )
  blk.expr = result

proc new_return_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExReturn,
    parent: parent,
    module: parent.module,
  )
  if val.gene.data.len > 0:
    result.return_val = new_expr(result, val.gene.data[0])

proc new_aspect_expr*(parent: Expr, val: GeneValue): Expr =
  var aspect: Aspect = val
  result = Expr(
    kind: ExAspect,
    parent: parent,
    module: parent.module,
    aspect: new_gene_internal(aspect),
  )
  # TODO: convert default values to expressions like below
  # fn.update_matchers(fn.matcher.children)

proc new_advice_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExAdvice,
    parent: parent,
    module: parent.module,
  )
  todo()

proc new_ns_expr*(parent: Expr, val: GeneValue): Expr =
  var ns = new_namespace(parent.module, val.gene.data[0].symbol)
  ns.name_key = parent.module.get_index(ns.name)
  result = Expr(
    kind: ExNamespace,
    parent: parent,
    module: parent.module,
    ns: new_gene_internal(ns),
  )
  var body: seq[Expr] = @[]
  for i in 1..<val.gene.data.len:
    body.add(new_expr(parent, val.gene.data[i]))
  result.ns_body = body

proc new_import_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExImport,
    parent: parent,
    module: parent.module,
    import_module: val.gene.props["module"].str,
  )
  for name in val.gene.props["names"].vec:
    result.import_mappings.add(name.symbol)

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
  class.name_key = parent.module.get_index(s)
  result = Expr(
    kind: ExClass,
    parent: parent,
    module: parent.module,
    class: new_gene_internal(class),
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
  mix.name_key = parent.module.get_index(s)
  result = Expr(
    kind: ExMixin,
    parent: parent,
    module: parent.module,
    mix: new_gene_internal(mix),
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
    module: parent.module,
  )
  for item in val.gene.data:
    result.include_args.add(new_expr(result, item))

proc new_new_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExNew,
    parent: parent,
    module: parent.module,
  )
  result.new_class = new_expr(parent, val.gene.data[0])
  for i in 1..<val.gene.data.len:
    result.new_args.add(new_expr(result, val.gene.data[i]))

proc new_super_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExSuper,
    parent: parent,
    module: parent.module,
  )
  for item in val.gene.data:
    result.super_args.add(new_expr(result, item))

proc new_method_expr*(parent: Expr, val: GeneValue): Expr =
  var fn: Function = val # Converter is implicitly called here
  var meth = new_method(nil, fn.name, fn)
  result = Expr(
    kind: ExMethod,
    parent: parent,
    module: parent.module,
    meth: new_gene_internal(meth),
  )
  fn.expr = result

proc new_invoke_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExInvokeMethod,
    parent: parent,
    module: parent.module,
    invoke_meth: val.gene.props["method"].str,
  )
  result.invoke_self = new_expr(result, val.gene.props["self"])
  for item in val.gene.data:
    result.invoke_args.add(new_expr(result, item))

proc new_get_prop_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExGetProp,
    parent: parent,
    module: parent.module,
    get_prop_name: val.gene.data[0].str,
  )
  result.get_prop_self = new_expr(result, val.gene.props["self"])

proc new_set_prop_expr*(parent: Expr, name: string, val: GeneValue): Expr =
  result = Expr(
    kind: ExSetProp,
    parent: parent,
    module: parent.module,
    set_prop_name: name,
  )
  result.set_prop_val = new_expr(result, val)

proc new_call_native_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExCallNative,
    parent: parent,
    module: parent.module,
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
    module: parent.module,
  )
  for i in 0..<val.gene.data.len:
    result.eval_args.add(new_expr(result, val.gene.data[i]))

proc new_caller_eval_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExCallerEval,
    parent: parent,
    module: parent.module,
  )
  for i in 0..<val.gene.data.len:
    result.caller_eval_args.add(new_expr(result, val.gene.data[i]))

proc new_match_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExMatch,
    parent: parent,
    module: parent.module,
    match_pattern: val.gene.data[0],
  )
  result.match_val = new_expr(result, val.gene.data[1])

proc new_quote_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExQuote,
    parent: parent,
    module: parent.module,
  )
  result.quote_val = val.gene.data[0]

proc new_binary_expr*(parent: Expr, op: string, val: GeneValue): Expr =
  if val.gene.data[1].is_literal:
    result = Expr(
      kind: ExBinImmediate,
      parent: parent,
      module: parent.module,
    )
    result.bini_first = new_expr(result, val.gene.data[0])
    result.bini_second = val.gene.data[1]
    case op:
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
      module: parent.module,
    )
    result.bin_first = new_expr(result, val.gene.data[0])
    result.bin_second = new_expr(result, val.gene.data[1])
    case op:
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

when isMainModule:
  import os, times

  if commandLineParams().len == 0:
    echo "\nUsage: interpreter <GENE FILE>\n"
    quit(0)
  var interpreter = new_vm()
  interpreter.cur_module = new_module()
  var frame = FrameMgr.get(FrModule, interpreter.cur_module.root_ns, new_scope())
  let e = interpreter.prepare(readFile(commandLineParams()[0]))
  let start = cpuTime()
  let result = interpreter.eval(frame, e)
  echo "Time: " & $(cpuTime() - start)
  echo result
