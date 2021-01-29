import strutils, tables, strutils
import asyncdispatch
import os

import ../map_key
import ../types
import ../parser
import ../decorator
import ../translators
import ../repl

let GENE_HOME*    = get_env("GENE_HOME", parent_dir(get_app_dir()))
let GENE_RUNTIME* = Runtime(
  home: GENE_HOME,
  name: "default",
  version: read_file(GENE_HOME & "/VERSION").strip(),
)

#################### Definitions #################

proc import_module*(self: VirtualMachine, name: MapKey, code: string): Namespace
proc def_member*(self: VirtualMachine, frame: Frame, name: MapKey, value: GeneValue, in_ns: bool)
proc def_member*(self: VirtualMachine, frame: Frame, name: GeneValue, value: GeneValue, in_ns: bool)
proc get_member*(self: VirtualMachine, frame: Frame, name: ComplexSymbol): GeneValue
proc set_member*(self: VirtualMachine, frame: Frame, name: GeneValue, value: GeneValue)
proc match*(self: VirtualMachine, frame: Frame, pattern: GeneValue, val: GeneValue, mode: MatchMode): GeneValue
proc import_from_ns*(self: VirtualMachine, frame: Frame, source: GeneValue, group: seq[ImportMatcher])
proc explode_and_add*(parent: GeneValue, value: GeneValue)

proc eval_args*(self: VirtualMachine, frame: Frame, props: seq[Expr], data: seq[Expr]): GeneValue {.inline.}

proc call_method*(self: VirtualMachine, frame: Frame, instance: GeneValue, class: Class, method_name: MapKey, args_blk: seq[Expr]): GeneValue
proc call_method*(self: VirtualMachine, frame: Frame, instance: GeneValue, class: Class, method_name: MapKey, args: GeneValue): GeneValue
proc call_fn*(self: VirtualMachine, frame: Frame, target: GeneValue, fn: Function, args: GeneValue, options: Table[FnOption, GeneValue]): GeneValue
proc call_fn*(self: VirtualMachine, target: GeneValue, fn: Function, args: GeneValue): GeneValue
proc call_block*(self: VirtualMachine, frame: Frame, target: GeneValue, blk: Block, expr: Expr): GeneValue

proc call_aspect*(self: VirtualMachine, frame: Frame, aspect: Aspect, expr: Expr): GeneValue
proc call_aspect_instance*(self: VirtualMachine, frame: Frame, instance: AspectInstance, args: GeneValue): GeneValue

#################### Implementations #############

#################### Application #################

proc new_app*(): Application =
  result = Application()
  var global = new_namespace("global")
  result.ns = global
  global[APP_KEY] = result
  global[STDIN_KEY]  = stdin
  global[STDOUT_KEY] = stdout
  global[STDERR_KEY] = stderr
  # Moved to interpreter_extras.nim
  # var cmd_args = command_line_params().map(str_to_gene)
  # global[CMD_ARGS_KEY] = cmd_args

#################### Package #####################

proc parse_deps(deps: seq[GeneValue]): Table[string, Package] =
  for dep in deps:
    var name = dep.gene.data[0].str
    var version = dep.gene.data[1]
    var location = dep.gene.props[LOCATION_KEY]
    var pkg = Package(name: name, version: version)
    pkg.dir = location.str
    result[name] = pkg

proc new_package*(dir: string): Package =
  result = Package()
  var d = absolute_path(dir)
  while d.len > 1:  # not "/"
    var package_file = d & "/package.gene"
    if file_exists(package_file):
      var doc = read_document(read_file(package_file))
      result.name = doc.props[NAME_KEY].str
      result.version = doc.props[VERSION_KEY]
      result.ns = new_namespace(VM.app.ns, "package:" & result.name)
      result.dir = d
      result.dependencies = parse_deps(doc.props[DEPS_KEY].vec)
      result.ns[CUR_PKG_KEY] = result
      return result
    else:
      d = parent_dir(d)

  result.adhoc = true
  result.ns = new_namespace(VM.app.ns, "package:<adhoc>")
  result.dir = d
  result.ns[CUR_PKG_KEY] = result

#################### Module ######################

proc new_module*(name: string): Module =
  result = Module(
    name: name,
    root_ns: new_namespace(VM.app.ns),
  )

proc new_module*(): Module =
  result = new_module("<unknown>")

#################### Selectors ###################

let NO_RESULT = new_gene_gene(new_gene_symbol("SELECTOR_NO_RESULT"))

proc search*(self: Selector, target: GeneValue, r: SelectorResult)

proc search_first(self: SelectorMatcher, target: GeneValue): GeneValue =
  case self.kind:
  of SmByIndex:
    case target.kind:
    of GeneVector:
      if self.index >= target.vec.len:
        return NO_RESULT
      else:
        return target.vec[self.index]
    of GeneGene:
      if self.index >= target.gene.data.len:
        return NO_RESULT
      else:
        return target.gene.data[self.index]
    else:
      todo()
  of SmByName:
    case target.kind:
    of GeneMap:
      if target.map.has_key(self.name):
        return target.map[self.name]
      else:
        return NO_RESULT
    of GeneGene:
      if target.gene.props.has_key(self.name):
        return target.gene.props[self.name]
      else:
        return NO_RESULT
    of GeneInternal:
      case target.internal.kind:
      of GeneInstance:
        return target.internal.instance.value.gene.props.get_or_default(self.name, GeneNil)
      else:
        todo($target.internal.kind)
    else:
      todo($target.kind)
  of SmByType:
    case target.kind:
    of GeneVector:
      for item in target.vec:
        if item.kind == GeneGene and item.gene.type == self.by_type:
          return item
    else:
      todo($target.kind)
  else:
    todo()

proc add_self_and_descendants(self: var seq[GeneValue], v: GeneValue) =
  self.add(v)
  case v.kind:
  of GeneVector:
    for child in v.vec:
      self.add_self_and_descendants(child)
  of GeneGene:
    for child in v.gene.data:
      self.add_self_and_descendants(child)
  else:
    discard

proc search(self: SelectorMatcher, target: GeneValue): seq[GeneValue] =
  case self.kind:
  of SmByIndex:
    case target.kind:
    of GeneVector:
      result.add(target.vec[self.index])
    of GeneGene:
      result.add(target.gene.data[self.index])
    else:
      todo()
  of SmByName:
    case target.kind:
    of GeneMap:
      result.add(target.map[self.name])
    else:
      todo()
  of SmByType:
    case target.kind:
    of GeneVector:
      for item in target.vec:
        if item.kind == GeneGene and item.gene.type == self.by_type:
          result.add(item)
    of GeneGene:
      for item in target.gene.data:
        if item.kind == GeneGene and item.gene.type == self.by_type:
          result.add(item)
    else:
      discard
  of SmSelfAndDescendants:
    result.add_self_and_descendants(target)
  of SmCallback:
    var args = new_gene_gene(GeneNil)
    args.gene.data.add(target)
    var v = VM.call_fn(GeneNil, self.callback.internal.fn, args)
    if v.kind == GeneGene and v.gene.type.kind == GeneSymbol:
      case v.gene.type.symbol:
      of "void":
        discard
      else:
        result.add(v)
    else:
      result.add(v)
  else:
    todo()

proc search(self: SelectorItem, target: GeneValue, r: SelectorResult) =
  case self.kind:
  of SiDefault:
    if self.is_last():
      case r.mode:
      of SrFirst:
        for m in self.matchers:
          var v = m.search_first(target)
          if v != NO_RESULT:
            r.done = true
            r.first = v
            break
      of SrAll:
        for m in self.matchers:
          r.all.add(m.search(target))
    else:
      var items: seq[GeneValue] = @[]
      for m in self.matchers:
        try:
          items.add(m.search(target))
        except SelectorNoResult:
          discard
      for child in self.children:
        for item in items:
          child.search(item, r)
  of SiSelector:
    self.selector.search(target, r)

proc search(self: Selector, target: GeneValue, r: SelectorResult) =
  case r.mode:
  of SrFirst:
    for child in self.children:
      child.search(target, r)
      if r.done:
        return
  else:
    for child in self.children:
      child.search(target, r)

proc search*(self: Selector, target: GeneValue): GeneValue =
  if self.is_singular():
    var r = SelectorResult(mode: SrFirst)
    self.search(target, r)
    if r.done:
      result = r.first
      # TODO: invoke callbacks
    else:
      raise new_exception(SelectorNoResult, "No result is found for the selector.")
  else:
    var r = SelectorResult(mode: SrAll)
    self.search(target, r)
    result = new_gene_vec(r.all)
    # TODO: invoke callbacks

proc update(self: SelectorItem, target: GeneValue, value: GeneValue): bool =
  for m in self.matchers:
    case m.kind:
    of SmByIndex:
      case target.kind:
      of GeneVector:
        if self.is_last:
          target.vec[m.index] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.vec[m.index], value)
      else:
        todo()
    of SmByName:
      case target.kind:
      of GeneMap:
        if self.is_last:
          target.map[m.name] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.map[m.name], value)
      of GeneGene:
        if self.is_last:
          target.gene.props[m.name] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.gene.props[m.name], value)
      of GeneInternal:
        case target.internal.kind:
        of GeneInstance:
          var g = target.internal.instance.value.gene
          if self.is_last:
            g.props[m.name] = value
            result = true
          else:
            for child in self.children:
              result = result or child.update(g.props[m.name], value)
        else:
          todo()
      else:
        todo($target.kind)
    else:
      todo()

proc update*(self: Selector, target: GeneValue, value: GeneValue): bool =
  for child in self.children:
    result = result or child.update(target, value)

#################### VM ##########################

proc new_vm*(app: Application): VirtualMachine =
  result = VirtualMachine(
    app: app,
  )

proc get_class*(val: GeneValue): Class =
  case val.kind:
  of GeneInternal:
    case val.internal.kind:
    of GeneApplication:
      return VM.gene_ns.internal.ns[APPLICATION_CLASS_KEY].internal.class
    of GenePackage:
      return VM.gene_ns.internal.ns[PACKAGE_CLASS_KEY].internal.class
    of GeneInstance:
      return val.internal.instance.class
    of GeneClass:
      return VM.gene_ns.internal.ns[CLASS_CLASS_KEY].internal.class
    of GeneNamespace:
      return VM.gene_ns.internal.ns[NAMESPACE_CLASS_KEY].internal.class
    of GeneFuture:
      return VM.gene_ns.internal.ns[FUTURE_CLASS_KEY].internal.class
    of GeneFile:
      return VM.gene_ns.internal.ns[FILE_CLASS_KEY].internal.class
    of GeneExceptionKind:
      var ex = val.internal.exception
      if ex is GeneException:
        var ex = cast[GeneException](ex)
        if ex.instance != nil:
          return ex.instance.internal.class
        else:
          return GeneExceptionClass.internal.class
      # elif ex is CatchableError:
      #   var nim = VM.app.ns[NIM_KEY]
      #   return nim.internal.ns[CATCHABLE_ERROR_KEY].internal.class
      else:
        return GeneExceptionClass.internal.class
    else:
      todo()
  of GeneNilKind:
    return VM.gene_ns.internal.ns[NIL_CLASS_KEY].internal.class
  of GeneBool:
    return VM.gene_ns.internal.ns[BOOL_CLASS_KEY].internal.class
  of GeneInt:
    return VM.gene_ns.internal.ns[INT_CLASS_KEY].internal.class
  of GeneChar:
    return VM.gene_ns.internal.ns[CHAR_CLASS_KEY].internal.class
  of GeneString:
    return VM.gene_ns.internal.ns[STRING_CLASS_KEY].internal.class
  of GeneSymbol:
    return VM.gene_ns.internal.ns[SYMBOL_CLASS_KEY].internal.class
  of GeneComplexSymbol:
    return VM.gene_ns.internal.ns[COMPLEX_SYMBOL_CLASS_KEY].internal.class
  of GeneVector:
    return VM.gene_ns.internal.ns[ARRAY_CLASS_KEY].internal.class
  of GeneMap:
    return VM.gene_ns.internal.ns[MAP_CLASS_KEY].internal.class
  of GeneSet:
    return VM.gene_ns.internal.ns[SET_CLASS_KEY].internal.class
  of GeneGene:
    return VM.gene_ns.internal.ns[GENE_CLASS_KEY].internal.class
  of GeneRegex:
    return VM.gene_ns.internal.ns[REGEX_CLASS_KEY].internal.class
  of GeneRange:
    return VM.gene_ns.internal.ns[RANGE_CLASS_KEY].internal.class
  of GeneDate:
    return VM.gene_ns.internal.ns[DATE_CLASS_KEY].internal.class
  of GeneDateTime:
    return VM.gene_ns.internal.ns[DATETIME_CLASS_KEY].internal.class
  of GeneTimeKind:
    return VM.gene_ns.internal.ns[TIME_CLASS_KEY].internal.class
  of GeneTimezone:
    return VM.gene_ns.internal.ns[TIMEZONE_CLASS_KEY].internal.class
  of GeneAny:
    if val.any_type == HTTP_REQUEST_KEY:
      return VM.genex_ns.internal.ns[HTTP_KEY].internal.ns[REQUEST_CLASS_KEY].internal.class
    else:
      todo()
  else:
    todo()

proc is_a*(self: GeneValue, class: Class): bool =
  var my_class = self.get_class
  while true:
    if my_class == class:
      return true
    if my_class.parent == nil:
      return false
    else:
      my_class = my_class.parent

proc wait_for_futures*(self: VirtualMachine) =
  try:
    run_forever()
  except ValueError as e:
    if e.msg == "No handles or timers registered in dispatcher.":
      discard
    else:
      raise

proc prepare*(self: VirtualMachine, code: string): Expr =
  var parsed = process_decorators(read_all(code))
  result = Expr(
    kind: ExRoot,
  )
  result.root = new_group_expr(result, parsed)

const DRAIN_MAX = 15
var drain_count = 0
proc drain() {.inline.} =
  if drain_count < DRAIN_MAX:
    drain_count += 1
  else:
    drain_count = 0
    if hasPendingOperations():
      drain(0)

proc eval*(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  if expr.evaluator != nil:
    result = expr.evaluator(self, frame, expr)
  else:
    var evaluator = EvaluatorMgr[expr.kind]
    expr.evaluator = evaluator
    result = evaluator(self, frame, expr)

  drain()
  if result == nil:
    return GeneNil
  else:
    return result

proc eval_prepare*(self: VirtualMachine): Frame =
  var module = new_module()
  return FrameMgr.get(FrModule, module.root_ns, new_scope())

proc eval_only*(self: VirtualMachine, frame: Frame, code: string): GeneValue =
  result = self.eval(frame, self.prepare(code))
  drain(0)

proc eval*(self: VirtualMachine, code: string): GeneValue =
  var module = new_module()
  var frame = FrameMgr.get(FrModule, module.root_ns, new_scope())
  result = self.eval(frame, self.prepare(code))
  drain(0)

proc init_package*(self: VirtualMachine, dir: string) =
  self.app.pkg = new_package(dir)

proc run_file*(self: VirtualMachine, file: string): GeneValue =
  var module = new_module(self.app.pkg.ns, file)
  var frame = FrameMgr.get(FrModule, module.root_ns, new_scope())
  var code = read_file(file)
  discard self.eval(frame, self.prepare(code))
  if frame.ns.has_key(MAIN_KEY):
    var main = frame[MAIN_KEY]
    if main.kind == GeneInternal and main.internal.kind == GeneFunction:
      var args = VM.app.ns[CMD_ARGS_KEY]
      var options = Table[FnOption, GeneValue]()
      result = self.call_fn(frame, GeneNil, main.internal.fn, args, options)
    else:
      raise new_exception(CatchableError, "main is not a function.")
  self.wait_for_futures()

proc import_module*(self: VirtualMachine, name: MapKey, code: string): Namespace =
  if self.modules.has_key(name):
    return self.modules[name]
  var module = new_module(name.to_s)
  var frame = FrameMgr.get(FrModule, module.root_ns, new_scope())
  self.def_member(frame, FILE_KEY, name.to_s, true)
  discard self.eval(frame, self.prepare(code))
  result = module.root_ns
  self.modules[name] = result

proc call_method*(self: VirtualMachine, frame: Frame, instance: GeneValue, class: Class, method_name: MapKey, args: GeneValue): GeneValue =
  var meth = class.get_method(method_name)
  if meth != nil:
    var options = Table[FnOption, GeneValue]()
    options[FnClass] = class
    options[FnMethod] = meth
    if meth.fn == nil:
      result = meth.fn_native(instance, args.gene.props, args.gene.data)
    else:
      result = self.call_fn(frame, instance, meth.fn, args, options)
  else:
    if method_name == NEW_KEY: # No implementation is required for `new` method
      discard
    else:
      todo("Method is missing: " & method_name.to_s)

proc call_method*(self: VirtualMachine, frame: Frame, instance: GeneValue, class: Class, method_name: MapKey, args_blk: seq[Expr]): GeneValue =
  var args = self.eval_args(frame, @[], args_blk)
  result = self.call_method(frame, instance, class, method_name, args)

proc eval_args*(self: VirtualMachine, frame: Frame, props: seq[Expr], data: seq[Expr]): GeneValue {.inline.} =
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

proc process_args*(self: VirtualMachine, frame: Frame, matcher: RootMatcher, args: GeneValue) =
  var match_result = matcher.match(args)
  case match_result.kind:
  of MatchSuccess:
    for field in match_result.fields:
      if field.value_expr != nil:
        frame.scope.def_member(field.name, self.eval(frame, field.value_expr))
      else:
        frame.scope.def_member(field.name, field.value)
  of MatchMissingFields:
    for field in match_result.missing:
      not_allowed("Argument " & field.to_s & " is missing.")
  else:
    todo()

proc repl_on_error*(self: VirtualMachine, frame: Frame, e: ref CatchableError): GeneValue =
  echo "An exception was thrown: " & e.msg
  echo "Opening debug console..."
  echo "Note: the exception can be accessed as $ex"
  var ex = error_to_gene(e)
  self.def_member(frame, CUR_EXCEPTION_KEY, ex, false)
  result = repl(self, frame, eval_only, true)

proc call_fn_internal*(
  self: VirtualMachine,
  frame: Frame,
  target: GeneValue,
  fn: Function,
  args: GeneValue,
  options: Table[FnOption, GeneValue]
): GeneValue =
  var ns: Namespace = fn.ns
  var fn_scope = new_scope()
  if fn.expr.kind == ExFn:
    fn_scope.set_parent(fn.parent_scope, fn.parent_scope_max)
  var new_frame: Frame
  if options.has_key(FnMethod):
    new_frame = FrameMgr.get(FrMethod, ns, fn_scope)
    fn_scope.def_member(CLASS_OPTION_KEY, options[FnClass])
    var meth = options[FnMethod]
    fn_scope.def_member(METHOD_OPTION_KEY, meth)
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
  except CatchableError as e:
    if self.repl_on_error:
      result = repl_on_error(self, frame, e)
    else:
      raise

proc call_fn*(
  self: VirtualMachine,
  frame: Frame,
  target: GeneValue,
  fn: Function,
  args: GeneValue,
  options: Table[FnOption, GeneValue]
): GeneValue =
  if fn.async:
    try:
      var val = self.call_fn_internal(frame, target, fn, args, options)
      if val.kind == GeneInternal and val.internal.kind == GeneFuture:
        return val
      var future = new_future[GeneValue]()
      future.complete(val)
      result = future_to_gene(future)
    except CatchableError as e:
      var future = new_future[GeneValue]()
      future.fail(e)
      result = future_to_gene(future)
  else:
    return self.call_fn_internal(frame, target, fn, args, options)

proc call_fn*(
  self: VirtualMachine,
  target: GeneValue,
  fn: Function,
  args: GeneValue,
): GeneValue =
  var ns = VM.app.ns
  var scope = new_scope()
  var frame = FrameMgr.get(FrBody, ns, scope)
  frame.args = args
  var options = Table[FnOption, GeneValue]()
  self.call_fn(frame, target, fn, args, options)

proc call_block*(self: VirtualMachine, frame: Frame, target: GeneValue, blk: Block, args: GeneValue): GeneValue =
  var blk_scope = new_scope()
  blk_scope.set_parent(blk.frame.scope, blk.parent_scope_max)
  var new_frame = blk.frame
  self.process_args(new_frame, blk.matcher, args)

  var blk2: seq[Expr] = @[]
  for item in blk.body:
    blk2.add(new_expr(blk.expr, item))
  try:
    for e in blk2:
      result = self.eval(new_frame, e)
  except Return, Break:
    raise
  except CatchableError as e:
    if self.repl_on_error:
      result = repl_on_error(self, frame, e)
    else:
      raise

proc call_block*(self: VirtualMachine, frame: Frame, target: GeneValue, blk: Block, expr: Expr): GeneValue =
  var args_blk: seq[Expr]
  case expr.kind:
  of ExGene:
    args_blk = expr.gene_data
  else:
    args_blk = @[]

  var args = new_gene_gene(GeneNil)
  for e in args_blk:
    var v = self.eval(frame, e)
    if v.kind == GeneInternal and v.internal.kind == GeneExplode:
      args.merge(v.internal.explode)
    else:
      args.gene.data.add(v)

  result = self.call_block(frame, target, blk, args)

proc call_aspect*(self: VirtualMachine, frame: Frame, aspect: Aspect, expr: Expr): GeneValue =
  var new_scope = new_scope()
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

proc call_aspect_instance*(self: VirtualMachine, frame: Frame, instance: AspectInstance, args: GeneValue): GeneValue =
  var aspect = instance.aspect
  var new_scope = new_scope()
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

proc call_target*(self: VirtualMachine, frame: Frame, target: GeneValue, args: GeneValue, expr: Expr): GeneValue =
  case target.kind:
  of GeneInternal:
    case target.internal.kind:
    of GeneFunction:
      var options = Table[FnOption, GeneValue]()
      result = self.call_fn(frame, GeneNil, target.internal.fn, args, options)
    of GeneBlock:
      result = self.call_block(frame, GeneNil, target.internal.blk, args)
    else:
      todo()
  else:
    todo()

proc def_member*(self: VirtualMachine, frame: Frame, name: MapKey, value: GeneValue, in_ns: bool) =
  if in_ns:
    frame.ns[name] = value
  else:
    frame.scope.def_member(name, value)

proc def_member*(self: VirtualMachine, frame: Frame, name: GeneValue, value: GeneValue, in_ns: bool) =
  case name.kind:
  of GeneString:
    if in_ns:
      frame.ns[name.str.to_key] = value
    else:
      frame.scope.def_member(name.str.to_key, value)
  of GeneSymbol:
    if in_ns:
      frame.ns[name.symbol.to_key] = value
    else:
      frame.scope.def_member(name.symbol.to_key, value)
  of GeneComplexSymbol:
    var ns: Namespace
    case name.csymbol.first:
    of "global":
      ns = VM.app.ns
    of "gene":
      ns = VM.gene_ns.internal.ns
    of "genex":
      ns = VM.genex_ns.internal.ns
    of "":
      ns = frame.ns
    else:
      var s = name.csymbol.first
      ns = frame[s.to_key].internal.ns
    for i in 0..<(name.csymbol.rest.len - 1):
      var name = name.csymbol.rest[i]
      ns = ns[name.to_key].internal.ns
    var base_name = name.csymbol.rest[^1]
    ns[base_name.to_key] = value
  else:
    not_allowed()

proc get_member*(self: VirtualMachine, frame: Frame, name: ComplexSymbol): GeneValue =
  if name.first == "global":
    result = VM.app.ns
  elif name.first == "gene":
    result = VM.gene_ns
  elif name.first == "genex":
    result = VM.genex_ns
  elif name.first == "":
    result = frame.ns
  else:
    result = frame[name.first.to_key]
  for name in name.rest:
    result = result.get_member(name)

proc set_member*(self: VirtualMachine, frame: Frame, name: GeneValue, value: GeneValue) =
  case name.kind:
  of GeneSymbol:
    if frame.scope.has_key(name.symbol.to_key):
      frame.scope[name.symbol.to_key] = value
    else:
      frame.ns[name.symbol.to_key] = value
  of GeneComplexSymbol:
    var ns: Namespace
    case name.csymbol.first:
    of "global":
      ns = VM.app.ns
    of "gene":
      ns = VM.gene_ns.internal.ns
    of "genex":
      ns = VM.genex_ns.internal.ns
    of "":
      ns = frame.ns
    else:
      var s = name.csymbol.first
      ns = frame[s.to_key].internal.ns
    for i in 0..<(name.csymbol.rest.len - 1):
      var name = name.csymbol.rest[i]
      ns = ns[name.to_key].internal.ns
    var base_name = name.csymbol.rest[^1]
    ns[base_name.to_key] = value
  else:
    not_allowed()

proc match*(self: VirtualMachine, frame: Frame, pattern: GeneValue, val: GeneValue, mode: MatchMode): GeneValue =
  case pattern.kind:
  of GeneSymbol:
    var name = pattern.symbol
    case mode:
    of MatchArgs:
      frame.scope.def_member(name.to_key, val.gene.data[0])
    else:
      frame.scope.def_member(name.to_key, val)
  of GeneVector:
    for i in 0..<pattern.vec.len:
      var name = pattern.vec[i].symbol
      if i < val.gene.data.len:
        frame.scope.def_member(name.to_key, val.gene.data[i])
      else:
        frame.scope.def_member(name.to_key, GeneNil)
  else:
    todo()

proc import_from_ns*(self: VirtualMachine, frame: Frame, source: GeneValue, group: seq[ImportMatcher]) =
  for m in group:
    if m.name == MUL_KEY:
      for k, v in source.internal.ns.members:
        self.def_member(frame, k, v, true)
    else:
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
