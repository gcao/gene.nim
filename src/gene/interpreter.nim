import tables, os, sequtils, strutils

import ./types
import ./parser
import ./translators
import ./native_procs

type
  FnOption = enum
    FnClass
    FnMethod

init_native_procs()

#################### Interfaces ##################

proc import_module*(self: VM, name: string, code: string): Namespace
proc load_core_module*(self: VM)
proc load_gene_module*(self: VM)
proc load_genex_module*(self: VM)
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

#################### Implementations #############

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

proc eval*(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  if expr.evaluator != nil:
    result = expr.evaluator(self, frame, expr)
  else:
    var evaluator = EvaluatorMgr[expr.kind]
    result = evaluator(self, frame, expr)

  if result == nil:
    return GeneNil
  else:
    return result

proc eval_prepare*(self: VM): Frame =
  var module = new_module()
  return FrameMgr.get(FrModule, module.root_ns, new_scope())

proc eval_only*(self: VM, frame: Frame, code: string): GeneValue =
  return self.eval(frame, self.prepare(code))

proc eval*(self: VM, code: string): GeneValue =
  var module = new_module()
  var frame = FrameMgr.get(FrModule, module.root_ns, new_scope())
  return self.eval(frame, self.prepare(code))

proc import_module*(self: VM, name: string, code: string): Namespace =
  if self.modules.has_key(name):
    return self.modules[name]
  var module = new_module(name)
  var frame = FrameMgr.get(FrModule, module.root_ns, new_scope())
  discard self.eval(frame, self.prepare(code))
  result = module.root_ns
  self.modules[name] = result

proc load_core_module*(self: VM) =
  GENE_NS  = new_namespace("gene")
  GLOBAL_NS.internal.ns["gene"] = GENE_NS
  GENEX_NS = new_namespace("genex")
  GLOBAL_NS.internal.ns["genex"] = GENEX_NS
  discard self.import_module("core", readFile("src/core.gene"))

proc load_gene_module*(self: VM) =
  discard self.import_module("gene", readFile("src/gene.gene"))
  GeneObjectClass    = GENE_NS["Object"]
  GeneClassClass     = GENE_NS["Class"]
  GeneExceptionClass = GENE_NS["Exception"]

proc load_genex_module*(self: VM) =
  discard self.import_module("genex", readFile("src/genex.gene"))

proc call_method*(self: VM, frame: Frame, instance: GeneValue, class: Class, method_name: string, args_blk: seq[Expr]): GeneValue =
  var meth = class.get_method(method_name)
  if meth != nil:
    var options = Table[FnOption, GeneValue]()
    options[FnClass] = class
    options[FnMethod] = meth
    var args = self.eval_args(frame, @[], args_blk)
    if meth.fn == nil:
      result = meth.fn_native(args.gene.data)
    else:
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

proc process_args*(self: VM, frame: Frame, matcher: RootMatcher, args: GeneValue) =
  var match_result = matcher.match(args)
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
  var ns: Namespace = fn.ns
  var fn_scope = ScopeMgr.get()
  if fn.expr.kind == ExFn:
    fn_scope.set_parent(fn.parent_scope, fn.parent_scope_max)
  var new_frame: Frame
  if options.has_key(FnMethod):
    new_frame = FrameMgr.get(FrMethod, ns, fn_scope)
    fn_scope.def_member("$class", options[FnClass])
    var meth = options[FnMethod]
    fn_scope.def_member("$method", meth)
  else:
    new_frame = FrameMgr.get(FrFunction, ns, fn_scope)
  new_frame.parent = frame
  new_frame.self = target

  new_frame.args = args
  self.process_args(new_frame, fn.matcher, new_frame.args)

  if fn.body_blk.len == 0:  # Translate on demand
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
  self.process_args(new_frame, mac.matcher, new_frame.args)

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
  blk_scope.set_parent(blk.frame.scope, blk.parent_scope_max)
  var new_frame = blk.frame
  var args_blk: seq[Expr]
  case expr.kind:
  of ExGene:
    args_blk = expr.gene_data
  else:
    todo()

  var args = new_gene_gene(GeneNil)
  for e in args_blk:
    var v = self.eval(frame, e)
    if v.kind == GeneInternal and v.internal.kind == GeneExplode:
      args.merge(v.internal.explode)
    else:
      args.gene.data.add(v)
  self.process_args(new_frame, blk.matcher, args)

  var blk2: seq[Expr] = @[]
  for item in blk.body:
    blk2.add(new_expr(blk.expr, item))
  for e in blk2:
    result = self.eval(new_frame, e)

  ScopeMgr.free(blk_scope)

proc call_aspect*(self: VM, frame: Frame, aspect: Aspect, expr: Expr): GeneValue =
  var new_scope = ScopeMgr.get()
  var new_frame = FrameMgr.get(FrBody, aspect.ns, new_scope)
  new_frame.parent = frame

  new_frame.args = new_gene_gene(GeneNil)
  for e in expr.gene_data:
    var v = self.eval(frame, e)
    if v.kind == GeneInternal and v.internal.kind == GeneExplode:
      new_frame.args.merge(v.internal.explode)
    else:
      new_frame.args.gene.data.add(v)
  self.process_args(new_frame, aspect.matcher, new_frame.args)

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
  var new_frame = FrameMgr.get(FrBody, aspect.ns, new_scope)
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
    of "":
      ns = frame.ns
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
  elif name.first == "":
    result = frame.ns
  else:
    result = frame[name.first]
  for name in name.rest:
    result = result.get_member(name)

proc set_member*(self: VM, frame: Frame, name: GeneValue, value: GeneValue) =
  case name.kind:
  of GeneSymbol:
    if frame.scope.has_key(name.symbol):
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
    of "":
      ns = frame.ns
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

EvaluatorMgr[ExTodo] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  if expr.todo != nil:
    todo(self.eval(frame, expr.todo).str)
  else:
    todo()

EvaluatorMgr[ExNotAllowed] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  if expr.not_allowed != nil:
    not_allowed(self.eval(frame, expr.not_allowed).str)
  else:
    not_allowed()

EvaluatorMgr[ExSymbol] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  case expr.symbol:
  of "gene":
    return GENE_NS
  of "genex":
    return GENEX_NS
  else:
    result = frame[expr.symbol]

EvaluatorMgr[ExDo] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
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

EvaluatorMgr[ExGroup] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  for e in expr.group:
    result = self.eval(frame, e)

EvaluatorMgr[ExArray] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  result = new_gene_vec()
  for e in expr.array:
    result.explode_and_add(self.eval(frame, e))

EvaluatorMgr[ExMap] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  result = new_gene_map()
  for e in expr.map:
    result.map[e.map_key] = self.eval(frame, e.map_val)

EvaluatorMgr[ExMapChild] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  result = self.eval(frame, expr.map_val)
  # Assign the value to map/gene should be handled by evaluation of parent expression

EvaluatorMgr[ExGet] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var target = self.eval(frame, expr.get_target)
  var index = self.eval(frame, expr.get_index)
  result = target.gene.data[index.int]

EvaluatorMgr[ExSet] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var target = self.eval(frame, expr.set_target)
  var index = self.eval(frame, expr.set_index)
  var value = self.eval(frame, expr.set_value)
  target.gene.data[index.int] = value

EvaluatorMgr[ExDefMember] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var name = self.eval(frame, expr.def_member_name).symbol_or_str
  var value = self.eval(frame, expr.def_member_value)
  frame.scope.def_member(name, value)

EvaluatorMgr[ExDefNsMember] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var name = self.eval(frame, expr.def_ns_member_name).symbol_or_str
  var value = self.eval(frame, expr.def_ns_member_value)
  frame.ns[name] = value

EvaluatorMgr[ExRange] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var range_start = self.eval(frame, expr.range_start)
  var range_end = self.eval(frame, expr.range_end)
  result = new_gene_range(range_start, range_end)

EvaluatorMgr[ExNot] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  result = not self.eval(frame, expr.not)

EvaluatorMgr[ExBinary] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
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

EvaluatorMgr[ExBinImmediate] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
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

EvaluatorMgr[ExVar] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var val = self.eval(frame, expr.var_val)
  self.def_member(frame, expr.var_name, val, false)
  result = GeneNil

EvaluatorMgr[ExAssignment] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var val = self.eval(frame, expr.var_val)
  self.set_member(frame, expr.var_name, val)
  result = GeneNil

EvaluatorMgr[ExIf] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var v = self.eval(frame, expr.if_cond)
  if v:
    result = self.eval(frame, expr.if_then)
  elif expr.if_else != nil:
    result = self.eval(frame, expr.if_else)

EvaluatorMgr[ExLoop] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  try:
    while true:
      try:
        for e in expr.loop_blk:
          discard self.eval(frame, e)
      except Continue:
        discard
  except Break as b:
    result = b.val

EvaluatorMgr[ExBreak] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var val = GeneNil
  if expr.break_val != nil:
    val = self.eval(frame, expr.break_val)
  var e: Break
  e.new
  e.val = val
  raise e

EvaluatorMgr[ExContinue] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var e: Continue
  e.new
  raise e

EvaluatorMgr[ExWhile] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  try:
    var cond = self.eval(frame, expr.while_cond)
    while cond:
      try:
        for e in expr.while_blk:
          discard self.eval(frame, e)
      except Continue:
        discard
      cond = self.eval(frame, expr.while_cond)
  except Break as b:
    result = b.val


EvaluatorMgr[ExExplode] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var val = self.eval(frame, expr.explode)
  result = new_gene_explode(val)

EvaluatorMgr[ExThrow] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  if expr.throw_type != nil:
    var class = self.eval(frame, expr.throw_type)
    if expr.throw_mesg != nil:
      var message = self.eval(frame, expr.throw_mesg)
      var instance = new_instance(class.internal.class)
      raise new_gene_exception(message.str, instance)
    elif class.kind == GeneInternal and class.internal.kind == GeneClass:
      var instance = new_instance(class.internal.class)
      raise new_gene_exception(instance)
    elif class.kind == GeneString:
      var instance = new_instance(GeneExceptionClass.internal.class)
      raise new_gene_exception(class.str, instance)
    else:
      todo()
  else:
    # Create instance of gene/Exception
    var class = GeneExceptionClass
    var instance = new_instance(class.internal.class)
    # Create nim exception of GeneException type
    raise new_gene_exception(instance)

EvaluatorMgr[ExTry] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  try:
    for e in expr.try_body:
      result = self.eval(frame, e)
  except GeneException as ex:
    self.def_member(frame, "$ex", error_to_gene(ex), false)
    var handled = false
    if expr.try_catches.len > 0:
      for catch in expr.try_catches:
        # check whether the thrown exception matches exception in catch statement
        var class = self.eval(frame, catch[0])
        if class == GenePlaceholder:
          class = GeneExceptionClass
        if ex.instance == nil:
          raise
        if ex.instance.is_a(class.internal.class):
          handled = true
          for e in catch[1]:
            result = self.eval(frame, e)
          break
    if not handled:
      raise

EvaluatorMgr[ExFn] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  expr.fn.internal.fn.ns = frame.ns
  expr.fn.internal.fn.parent_scope = frame.scope
  expr.fn.internal.fn.parent_scope_max = frame.scope.max
  self.def_member(frame, expr.fn_name, expr.fn, true)
  result = expr.fn

EvaluatorMgr[ExArgs] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  case frame.extra.kind:
  of FrFunction, FrMacro, FrMethod:
    result = frame.args
  else:
    not_allowed()

EvaluatorMgr[ExMacro] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  expr.mac.internal.mac.ns = frame.ns
  self.def_member(frame, expr.mac_name, expr.mac, true)
  result = expr.mac

EvaluatorMgr[ExBlock] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  expr.blk.internal.blk.frame = frame
  expr.blk.internal.blk.parent_scope_max = frame.scope.max
  result = expr.blk

EvaluatorMgr[ExReturn] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var val = GeneNil
  if expr.return_val != nil:
    val = self.eval(frame, expr.return_val)
  raise Return(
    frame: frame,
    val: val,
  )

EvaluatorMgr[ExReturnRef] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  result = Return(frame: frame)

EvaluatorMgr[ExAspect] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var aspect = expr.aspect.internal.aspect
  aspect.ns = frame.ns
  frame.ns[aspect.name] = expr.aspect
  result = expr.aspect

EvaluatorMgr[ExAdvice] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var instance = frame.self.internal.aspect_instance
  var advice: Advice
  var logic = self.eval(frame, new_expr(expr, expr.advice.gene.data[1]))
  case expr.advice.gene.type.symbol:
  of "before":
    advice = new_advice(AdBefore, logic.internal.fn)
    instance.before_advices.add(advice)
  of "after":
    advice = new_advice(AdAfter, logic.internal.fn)
    instance.after_advices.add(advice)
  else:
    todo()
  advice.owner = instance

EvaluatorMgr[ExUnknown] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
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

EvaluatorMgr[ExNamespace] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
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

EvaluatorMgr[ExSelf] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  return frame.self

EvaluatorMgr[ExGlobal] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  return self.app.ns

EvaluatorMgr[ExImport] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var ns: Namespace
  # If "from" is not given, import from parent of root namespace.
  if expr.import_matcher.from == "":
    ns = frame.ns.root.parent
  else:
    ns = self.modules[expr.import_matcher.from]
  self.import_from_ns(frame, ns, expr.import_matcher.children)

EvaluatorMgr[ExStopInheritance] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  frame.ns.stop_inheritance = true

EvaluatorMgr[ExClass] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  expr.class.internal.class.ns.parent = frame.ns
  var super_class: Class
  if expr.super_class == nil:
    if GENE_NS != nil and GENE_NS.internal.ns.has_key("Object"):
      super_class = GENE_NS.internal.ns["Object"].internal.class
  else:
    super_class = self.eval(frame, expr.super_class).internal.class
  expr.class.internal.class.parent = super_class
  self.def_member(frame, expr.class_name, expr.class, true)
  var ns = expr.class.internal.class.ns
  var scope = new_scope()
  var new_frame = FrameMgr.get(FrBody, ns, scope)
  new_frame.self = expr.class
  for e in expr.class_body:
    discard self.eval(new_frame, e)
  result = expr.class

EvaluatorMgr[ExMixin] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  self.def_member(frame, expr.mix_name, expr.mix, true)
  var ns = frame.ns
  var scope = new_scope()
  var new_frame = FrameMgr.get(FrBody, ns, scope)
  new_frame.self = expr.mix
  for e in expr.mix_body:
    discard self.eval(new_frame, e)
  result = expr.mix

EvaluatorMgr[ExInclude] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  # Copy methods to target class
  for e in expr.include_args:
    var mix = self.eval(frame, e)
    for name, meth in mix.internal.mix.methods:
      frame.self.internal.class.methods[name] = meth

EvaluatorMgr[ExNew] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var class = self.eval(frame, expr.new_class)
  var instance = new_instance(class.internal.class)
  result = new_gene_instance(instance)
  discard self.call_method(frame, result, class.internal.class, "new", expr.new_args)

EvaluatorMgr[ExMethod] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var meth = expr.meth
  if expr.meth_fn_native != nil:
    meth.internal.meth.fn_native = self.eval(frame, expr.meth_fn_native).internal.native_proc
  case frame.self.internal.kind:
  of GeneClass:
    meth.internal.meth.class = frame.self.internal.class
    frame.self.internal.class.methods[meth.internal.meth.name] = meth.internal.meth
  of GeneMixin:
    frame.self.internal.mix.methods[meth.internal.meth.name] = meth.internal.meth
  else:
    not_allowed()
  result = meth

EvaluatorMgr[ExInvokeMethod] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var instance = self.eval(frame, expr.invoke_self)
  var class = instance.get_class
  result = self.call_method(frame, instance, class, expr.invoke_meth, expr.invoke_args)

EvaluatorMgr[ExSuper] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var instance = frame.self
  var meth = frame.scope["$method"].internal.meth
  var class = meth.class
  result = self.call_method(frame, instance, class.parent, meth.name, expr.super_args)

EvaluatorMgr[ExGetProp] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var target = self.eval(frame, expr.get_prop_self)
  var name = expr.get_prop_name
  result = target.internal.instance.value.gene.props[name]

EvaluatorMgr[ExSetProp] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var target = frame.self
  var name = expr.set_prop_name
  result = self.eval(frame, expr.set_prop_val)
  target.internal.instance.value.gene.props[name] = result

EvaluatorMgr[ExCall] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var target = self.eval(frame, expr.call_target)
  var call_self = GeneNil
  # if expr.call_props.has_key("self"):
  #   call_self = self.eval(frame, expr.call_props["self"])
  var args: GeneValue
  if expr.call_args != nil:
    args = self.eval(frame, expr.call_args)
  else:
    args = new_gene_gene(GeneNil)
  var options = Table[FnOption, GeneValue]()
  result = self.call_fn(frame, call_self, target.internal.fn, args, options)

EvaluatorMgr[ExCallNative] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var args: seq[GeneValue] = @[]
  for item in expr.native_args:
    args.add(self.eval(frame, item))
  var p = NativeProcs.get(expr.native_index)
  result = p(args)

EvaluatorMgr[ExGetClass] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var val = self.eval(frame, expr.get_class_val)
  result = val.get_class

EvaluatorMgr[ExParse] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var s = self.eval(frame, expr.parse).str
  return read(s)

EvaluatorMgr[ExEval] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var old_self = frame.self
  try:
    if expr.eval_self != nil:
      frame.self = self.eval(frame, expr.eval_self)
    for e in expr.eval_args:
      var init_result = self.eval(frame, e)
      result = self.eval(frame, new_expr(expr, init_result))
  finally:
    frame.self = old_self

EvaluatorMgr[ExCallerEval] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var caller_frame = frame.parent
  for e in expr.caller_eval_args:
    result = self.eval(caller_frame, new_expr(expr, self.eval(frame, e)))

EvaluatorMgr[ExMatch] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  result = self.match(frame, expr.match_pattern, self.eval(frame, expr.match_val), MatchDefault)

EvaluatorMgr[ExQuote] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  result = expr.quote_val

EvaluatorMgr[ExExit] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  if expr.exit == nil:
    quit()
  else:
    var code = self.eval(frame, expr.exit)
    quit(code.int)

EvaluatorMgr[ExEnv] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var env = self.eval(frame, expr.env)
  result = get_env(env.str)
  if result.str.len == 0:
    result = self.eval(frame, expr.env_default).to_s

EvaluatorMgr[ExPrint] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  for e in expr.print:
    var v = self.eval(frame, e)
    case v.kind:
    of GeneString:
      stdout.write v.str
    else:
      stdout.write $v
  if expr.print_and_return:
    stdout.write "\n"

EvaluatorMgr[ExRoot] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  return self.eval(frame, expr.root)

EvaluatorMgr[ExLiteral] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  return expr.literal

EvaluatorMgr[ExComplexSymbol] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  return self.get_member(frame, expr.csymbol)

EvaluatorMgr[ExGene] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var target = self.eval(frame, expr.gene_type)
  case target.kind:
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
    of GeneNativeProc:
      var args = self.eval_args(frame, expr.gene_props, expr.gene_data)
      result = target.internal.native_proc(args.gene.data)
    else:
      todo()
  of GeneString:
    var str = target.str
    for item in expr.gene_data:
      str &= self.eval(frame, item).to_s
    result = new_gene_string_move(str)
  else:
    result = new_gene_gene(target)
    for e in expr.gene_props:
      result.gene.props[e.map_key] = self.eval(frame, e.map_val)
    for e in expr.gene_data:
      result.gene.data.add(self.eval(frame, e))

EvaluatorMgr[ExEnum] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var e = expr.enum
  self.def_member(frame, e.name, e, true)

EvaluatorMgr[ExFor] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
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
          try:
            frame.scope[val] = i
            for e in expr.for_blk:
              discard self.eval(frame, e)
          except Continue:
            discard
      of GeneVector:
        for i in for_in.vec:
          try:
            frame.scope[val] = i
            for e in expr.for_blk:
              discard self.eval(frame, e)
          except Continue:
            discard
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
          try:
            frame.scope[key] = k
            frame.scope[val] = v
            for e in expr.for_blk:
              discard self.eval(frame, e)
          except Continue:
            discard
      of GeneMap:
        for k, v in for_in.map:
          try:
            frame.scope[key] = k
            frame.scope[val] = v
            for e in expr.for_blk:
              discard self.eval(frame, e)
          except Continue:
            discard
      else:
        todo()
  except Break:
    discard

EvaluatorMgr[ExParseCmdArgs] = proc(self: VM, frame: Frame, expr: Expr): GeneValue {.inline.} =
  var cmd_args = self.eval(frame, expr.cmd_args)
  var r = expr.cmd_args_schema.match(cmd_args.vec.map(proc(v: GeneValue): string = v.str))
  if r.kind == AmSuccess:
    for k, v in r.fields:
      var name = k
      if k.starts_with("--"):
        name = k[2..^1]
      elif k.starts_with("-"):
        name = k[1..^1]
      self.def_member(frame, name, v, false)
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
