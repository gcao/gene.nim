import strutils, sequtils, tables
import asyncdispatch
import dynlib
import os

import ../map_key
import ../types
import ../parser
import ../dynlib_mapping
import ../translators
import ../repl
import ./base

proc init_evaluators*() =
  EvaluatorMgr[ExTodo] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    if expr.todo != nil:
      todo(self.eval(frame, expr.todo).str)
    else:
      todo()

  EvaluatorMgr[ExNotAllowed] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    if expr.not_allowed != nil:
      not_allowed(self.eval(frame, expr.not_allowed).str)
    else:
      not_allowed()

  EvaluatorMgr[ExSymbol] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    case expr.symbol_kind:
    of SkUnknown:
      var e = expr
      if expr.symbol == GENE_KEY:
        e.symbol_kind = SkGene
        return VM.gene_ns
      elif expr.symbol == GENEX_KEY:
        e.symbol_kind = SkGenex
        return VM.genex_ns
      else:
        result = frame.scope[expr.symbol]
        if result != nil:
          e.symbol_kind = SkScope
        else:
          var pair = frame.ns.locate(expr.symbol)
          e.symbol_kind = SkNamespace
          e.symbol_ns = pair[1]
          result = pair[0]
    of SkGene:
      result = VM.gene_ns
    of SkGenex:
      result = VM.genex_ns
    of SkNamespace:
      result = expr.symbol_ns[expr.symbol]
    of SkScope:
      result = frame.scope[expr.symbol]

  EvaluatorMgr[ExDo] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var old_self = frame.self
    try:
      for e in expr.do_props:
        var val = self.eval(frame, e)
        if e.map_key == SELF_KEY:
          frame.self = val
        else:
          todo()
      for e in expr.do_body:
        result = self.eval(frame, e)
        if result.kind == GeneInternal and result.internal.kind == GeneExplode:
          for item in result.internal.explode.vec:
            result = self.eval(frame, new_expr(e, item))
    finally:
      frame.self = old_self

  EvaluatorMgr[ExGroup] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    for e in expr.group:
      result = self.eval(frame, e)

  EvaluatorMgr[ExArray] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    result = new_gene_vec()
    for e in expr.array:
      result.explode_and_add(self.eval(frame, e))

  EvaluatorMgr[ExMap] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    result = new_gene_map()
    for e in expr.map:
      result.map[e.map_key] = self.eval(frame, e.map_val)

  EvaluatorMgr[ExMapChild] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    result = self.eval(frame, expr.map_val)
    # Assign the value to map/gene should be handled by evaluation of parent expression

  EvaluatorMgr[ExGet] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var target = self.eval(frame, expr.get_target)
    var index = self.eval(frame, expr.get_index)
    result = target.gene.data[index.int]

  EvaluatorMgr[ExSet] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var target = self.eval(frame, expr.set_target)
    var index = self.eval(frame, expr.set_index)
    var value = self.eval(frame, expr.set_value)
    if index.kind == GeneInternal and index.internal.kind == GeneSelector:
      var success = index.internal.selector.update(target, value)
      if not success:
        todo("Update by selector failed.")
    else:
      target.gene.data[index.int] = value

  EvaluatorMgr[ExDefMember] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var name = self.eval(frame, expr.def_member_name).symbol_or_str
    var value = self.eval(frame, expr.def_member_value)
    frame.scope.def_member(name.to_key, value)

  EvaluatorMgr[ExDefNsMember] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var name = self.eval(frame, expr.def_ns_member_name).symbol_or_str
    var value = self.eval(frame, expr.def_ns_member_value)
    frame.ns[name.to_key] = value

  EvaluatorMgr[ExRange] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var range_start = self.eval(frame, expr.range_start)
    var range_end = self.eval(frame, expr.range_end)
    result = new_gene_range(range_start, range_end)

  EvaluatorMgr[ExNot] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    result = not self.eval(frame, expr.not)

  proc bin_add(self: VirtualMachine, frame: Frame, first, second: GeneValue): GeneValue {.inline.} =
    case first.kind:
    of GeneInt:
      case second.kind:
      of GeneInt:
        result = new_gene_int(first.int + second.int)
      else:
        todo()
    else:
      var class = first.get_class()
      var args = new_gene_gene(GeneNil)
      args.gene.data.add(second)
      result = self.call_method(frame, first, class, ADD_KEY, args)

  proc bin_sub(self: VirtualMachine, frame: Frame, first, second: GeneValue): GeneValue {.inline.} =
    case first.kind:
    of GeneInt:
      case second.kind:
      of GeneInt:
        result = new_gene_int(first.int - second.int)
      else:
        todo()
    else:
      var class = first.get_class()
      var args = new_gene_gene(GeneNil)
      args.gene.data.add(second)
      result = self.call_method(frame, first, class, SUB_KEY, args)

  EvaluatorMgr[ExBinary] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var first = self.eval(frame, expr.bin_first)
    var second = self.eval(frame, expr.bin_second)
    case expr.bin_op:
    of BinAdd: result = bin_add(self, frame, first, second)
    of BinSub: result = bin_sub(self, frame, first, second)
    of BinMul: result = new_gene_int(first.int * second.int)
    of BinDiv: result = new_gene_float(first.int / second.int)
    of BinEq:  result = new_gene_bool(first == second)
    of BinNeq: result = new_gene_bool(first != second)
    of BinLt:  result = new_gene_bool(first.int < second.int)
    of BinLe:  result = new_gene_bool(first.int <= second.int)
    of BinGt:  result = new_gene_bool(first.int > second.int)
    of BinGe:  result = new_gene_bool(first.int >= second.int)
    of BinAnd: result = new_gene_bool(first.bool and second.bool)
    of BinOr:  result = new_gene_bool(first.bool or second.bool)

  EvaluatorMgr[ExBinImmediate] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var first = self.eval(frame, expr.bini_first)
    var second = expr.bini_second
    case expr.bini_op:
    of BinAdd: result = new_gene_int(first.int + second.int)
    of BinSub: result = new_gene_int(first.int - second.int)
    of BinMul: result = new_gene_int(first.int * second.int)
    of BinDiv: result = new_gene_float(first.int / second.int)
    of BinEq:  result = new_gene_bool(first == second)
    of BinNeq: result = new_gene_bool(first != second)
    of BinLt:  result = new_gene_bool(first.int < second.int)
    of BinLe:  result = new_gene_bool(first.int <= second.int)
    of BinGt:  result = new_gene_bool(first.int > second.int)
    of BinGe:  result = new_gene_bool(first.int >= second.int)
    of BinAnd: result = new_gene_bool(first.bool and second.bool)
    of BinOr:  result = new_gene_bool(first.bool or second.bool)

  EvaluatorMgr[ExBinAssignment] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var first = frame[expr.bina_first]
    var second = self.eval(frame, expr.bina_second)
    case expr.bina_op:
    of BinAdd: result = bin_add(self, frame, first, second)
    of BinSub: result = bin_sub(self, frame, first, second)
    of BinMul: result = new_gene_int(first.int * second.int)
    of BinDiv: result = new_gene_float(first.int / second.int)
    else: todo()
    self.set_member(frame, expr.bina_first, result)

  EvaluatorMgr[ExVar] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var val = self.eval(frame, expr.var_val)
    self.def_member(frame, expr.var_name, val, false)
    result = GeneNil

  EvaluatorMgr[ExAssignment] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    result = self.eval(frame, expr.var_val)
    self.set_member(frame, expr.var_name, result)

  EvaluatorMgr[ExIf] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var v = self.eval(frame, expr.if_cond)
    if v:
      result = self.eval(frame, expr.if_then)
    elif expr.if_elifs.len > 0:
      for pair in expr.if_elifs:
        if self.eval(frame, pair[0]):
          return self.eval(frame, pair[1])
    elif expr.if_else != nil:
      result = self.eval(frame, expr.if_else)

  EvaluatorMgr[ExLoop] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    try:
      while true:
        try:
          for e in expr.loop_blk:
            discard self.eval(frame, e)
        except Continue:
          discard
    except Break as b:
      result = b.val

  EvaluatorMgr[ExBreak] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var val = GeneNil
    if expr.break_val != nil:
      val = self.eval(frame, expr.break_val)
    var e: Break
    e.new
    e.val = val
    raise e

  EvaluatorMgr[ExContinue] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var e: Continue
    e.new
    raise e

  EvaluatorMgr[ExWhile] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
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


  EvaluatorMgr[ExExplode] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var val = self.eval(frame, expr.explode)
    result = new_gene_explode(val)

  EvaluatorMgr[ExThrow] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    if expr.throw_type != nil:
      var class = self.eval(frame, expr.throw_type)
      if expr.throw_mesg != nil:
        var message = self.eval(frame, expr.throw_mesg)
        var instance = new_instance(class.internal.class)
        raise new_gene_exception(message.str, instance)
      elif class.kind == GeneInternal and class.internal.kind == GeneClass:
        var instance = new_instance(class.internal.class)
        raise new_gene_exception(instance)
      elif class.kind == GeneInternal and class.internal.kind == GeneExceptionKind:
        raise class.internal.exception
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

  EvaluatorMgr[ExTry] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    try:
      for e in expr.try_body:
        result = self.eval(frame, e)
    except GeneException as ex:
      self.def_member(frame, CUR_EXCEPTION_KEY, error_to_gene(ex), false)
      var handled = false
      if expr.try_catches.len > 0:
        for catch in expr.try_catches:
          # check whether the thrown exception matches exception in catch statement
          var class = self.eval(frame, catch[0])
          if class == GenePlaceholder:
            # class = GeneExceptionClass
            handled = true
            for e in catch[1]:
              result = self.eval(frame, e)
            break
          if ex.instance == nil:
            raise
          if ex.instance.is_a(class.internal.class):
            handled = true
            for e in catch[1]:
              result = self.eval(frame, e)
            break
      for e in expr.try_finally:
        try:
          discard self.eval(frame, e)
        except Return, Break:
          discard
      if not handled:
        raise

  EvaluatorMgr[ExAwait] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    if expr.await.len == 1:
      var r = self.eval(frame, expr.await[0])
      if r.kind == GeneInternal and r.internal.kind == GeneFuture:
        result = wait_for(r.internal.future)
      else:
        todo()
    else:
      result = new_gene_vec()
      for item in expr.await:
        var r = self.eval(frame, item)
        if r.kind == GeneInternal and r.internal.kind == GeneFuture:
          result.vec.add(wait_for(r.internal.future))
        else:
          todo()

  EvaluatorMgr[ExFn] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    expr.fn.internal.fn.ns = frame.ns
    expr.fn.internal.fn.parent_scope = frame.scope
    expr.fn.internal.fn.parent_scope_max = frame.scope.max
    self.def_member(frame, expr.fn_name, expr.fn, true)
    result = expr.fn

  EvaluatorMgr[ExArgs] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    case frame.extra.kind:
    of FrFunction, FrMacro, FrMethod:
      result = frame.args
    else:
      not_allowed()

  EvaluatorMgr[ExBlock] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    expr.blk.internal.blk.frame = frame
    expr.blk.internal.blk.parent_scope_max = frame.scope.max
    result = expr.blk

  EvaluatorMgr[ExReturn] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var val = GeneNil
    if expr.return_val != nil:
      val = self.eval(frame, expr.return_val)
    raise Return(
      frame: frame,
      val: val,
    )

  EvaluatorMgr[ExReturnRef] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    result = Return(frame: frame)

  EvaluatorMgr[ExAspect] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var aspect = expr.aspect.internal.aspect
    aspect.ns = frame.ns
    frame.ns[aspect.name.to_key] = expr.aspect
    result = expr.aspect

  EvaluatorMgr[ExAdvice] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
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

  EvaluatorMgr[ExNamespace] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    expr.ns.internal.ns.parent = frame.ns
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

  EvaluatorMgr[ExSelf] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    return frame.self

  EvaluatorMgr[ExGlobal] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    return self.app.ns

  EvaluatorMgr[ExImport] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var ns: Namespace
    var dir = ""
    if frame.ns.has_key(PKG_KEY):
      var pkg = frame.ns[PKG_KEY].internal.pkg
      dir = pkg.dir & "/"
    # TODO: load import_pkg on demand
    # Set dir to import_pkg's root directory

    var `from` = expr.import_from
    if expr.import_native:
      var path = self.eval(frame, `from`).str
      let lib = load_dynlib(dir & path)
      if lib == nil:
        todo()
      else:
        for m in expr.import_matcher.children:
          var v = lib.sym_addr(m.name.to_s)
          if v == nil:
            todo()
          else:
            self.def_member(frame, m.name, new_gene_internal(cast[NativeFn](v)), true)
    else:
      # If "from" is not given, import from parent of root namespace.
      if `from` == nil:
        ns = frame.ns.root.parent
      else:
        var `from` = self.eval(frame, `from`).str
        if self.modules.has_key(`from`.to_key):
          ns = self.modules[`from`.to_key]
        else:
          var code = read_file(dir & `from` & ".gene")
          ns = self.import_module(`from`.to_key, code)
          self.modules[`from`.to_key] = ns
      self.import_from_ns(frame, ns, expr.import_matcher.children)

  EvaluatorMgr[ExIncludeFile] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var file = self.eval(frame, expr.include_file).str
    result = self.eval_only(frame, read_file(file))

  EvaluatorMgr[ExStopInheritance] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    frame.ns.stop_inheritance = true

  EvaluatorMgr[ExClass] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    expr.class.internal.class.ns.parent = frame.ns
    var super_class: Class
    if expr.super_class == nil:
      if VM.gene_ns != nil and VM.gene_ns.internal.ns.has_key(OBJECT_CLASS_KEY):
        super_class = VM.gene_ns.internal.ns[OBJECT_CLASS_KEY].internal.class
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

  EvaluatorMgr[ExObject] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var name = expr.obj_name
    var s: string
    case name.kind:
    of GeneSymbol:
      s = name.symbol
    of GeneComplexSymbol:
      s = name.csymbol.rest[^1]
    else:
      not_allowed()
    var class = new_class(s & "Class")
    class.ns.parent = frame.ns
    var super_class: Class
    if expr.obj_super_class == nil:
      if VM.gene_ns != nil and VM.gene_ns.internal.ns.has_key(OBJECT_CLASS_KEY):
        super_class = VM.gene_ns.internal.ns[OBJECT_CLASS_KEY].internal.class
    else:
      super_class = self.eval(frame, expr.obj_super_class).internal.class
    class.parent = super_class
    var ns = class.ns
    var scope = new_scope()
    var new_frame = FrameMgr.get(FrBody, ns, scope)
    new_frame.self = class
    for e in expr.obj_body:
      discard self.eval(new_frame, e)
    var instance = new_instance(class)
    result = new_gene_instance(instance)
    self.def_member(frame, name, result, true)
    discard self.call_method(frame, result, class, NEW_KEY, new_gene_gene())

  EvaluatorMgr[ExMixin] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    self.def_member(frame, expr.mix_name, expr.mix, true)
    var ns = frame.ns
    var scope = new_scope()
    var new_frame = FrameMgr.get(FrBody, ns, scope)
    new_frame.self = expr.mix
    for e in expr.mix_body:
      discard self.eval(new_frame, e)
    result = expr.mix

  EvaluatorMgr[ExInclude] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    # Copy methods to target class
    for e in expr.include_args:
      var mix = self.eval(frame, e)
      for name, meth in mix.internal.mix.methods:
        frame.self.internal.class.methods[name] = meth

  EvaluatorMgr[ExNew] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var class = self.eval(frame, expr.new_class)
    var instance = new_instance(class.internal.class)
    result = new_gene_instance(instance)
    discard self.call_method(frame, result, class.internal.class, NEW_KEY, expr.new_args)

  EvaluatorMgr[ExMethod] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var meth = expr.meth
    if expr.meth_fn_native != nil:
      meth.internal.meth.fn_native = self.eval(frame, expr.meth_fn_native).internal.native_meth
    case frame.self.internal.kind:
    of GeneClass:
      meth.internal.meth.class = frame.self.internal.class
      frame.self.internal.class.methods[meth.internal.meth.name.to_key] = meth.internal.meth
    of GeneMixin:
      frame.self.internal.mix.methods[meth.internal.meth.name.to_key] = meth.internal.meth
    else:
      not_allowed()
    result = meth

  EvaluatorMgr[ExInvokeMethod] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var instance = self.eval(frame, expr.invoke_self)
    var class = instance.get_class
    result = self.call_method(frame, instance, class, expr.invoke_meth, expr.invoke_args)

  EvaluatorMgr[ExSuper] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var instance = frame.self
    var meth = frame.scope[METHOD_OPTION_KEY].internal.meth
    var class = meth.class
    result = self.call_method(frame, instance, class.parent, meth.name.to_key, expr.super_args)

  EvaluatorMgr[ExCall] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var target = self.eval(frame, expr.call_target)
    var call_self = GeneNil
    # if expr.call_props.has_key("self"):
    #   call_self = self.eval(frame, expr.call_props[SELF_KEY])
    var args: GeneValue
    if expr.call_args != nil:
      args = self.eval(frame, expr.call_args)
    else:
      args = new_gene_gene(GeneNil)
    var options = Table[FnOption, GeneValue]()
    result = self.call_fn(frame, call_self, target.internal.fn, args, options)

  EvaluatorMgr[ExGetClass] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var val = self.eval(frame, expr.get_class_val)
    result = val.get_class

  EvaluatorMgr[ExParse] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var s = self.eval(frame, expr.parse).str
    return new_gene_stream(read_all(s))

  EvaluatorMgr[ExEval] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var old_self = frame.self
    try:
      if expr.eval_self != nil:
        frame.self = self.eval(frame, expr.eval_self)
      for e in expr.eval_args:
        var init_result = self.eval(frame, e)
        result = self.eval(frame, new_expr(expr, init_result))
    finally:
      frame.self = old_self

  EvaluatorMgr[ExCallerEval] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var caller_frame = frame.parent
    for e in expr.caller_eval_args:
      result = self.eval(caller_frame, new_expr(expr, self.eval(frame, e)))
      if result.kind == GeneInternal and result.internal.kind == GeneExplode:
        for item in result.internal.explode.vec:
          result = self.eval(caller_frame, new_expr(expr, item))

  EvaluatorMgr[ExMatch] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    result = self.match(frame, expr.match_pattern, self.eval(frame, expr.match_val), MatchDefault)

  proc unquote(self: VirtualMachine, frame: Frame, expr: Expr, val: GeneValue): GeneValue {.inline.}
  proc unquote(self: VirtualMachine, frame: Frame, expr: Expr, val: seq[GeneValue]): seq[GeneValue] =
    for item in val:
      var r = self.unquote(frame, expr, item)
      if item.kind == GeneGene and item.gene.type == Unquote and item.gene.props.get_or_default(DISCARD_KEY, false):
        discard
      else:
        result.add(r)

  proc unquote(self: VirtualMachine, frame: Frame, expr: Expr, val: GeneValue): GeneValue =
    case val.kind:
    of GeneVector:
      result = new_gene_vec()
      result.vec = self.unquote(frame, expr, val.vec)
    of GeneMap:
      result = new_gene_map()
      for k, v in val.map:
        result.map[k]= self.unquote(frame, expr, v)
    of GeneGene:
      if val.gene.type == Unquote:
        var e = new_expr(expr, val.gene.data[0])
        result = self.eval(frame, e)
      else:
        result = new_gene_gene(self.unquote(frame, expr, val.gene.type))
        for k, v in val.gene.props:
          result.gene.props[k]= self.unquote(frame, expr, v)
        result.gene.data = self.unquote(frame, expr, val.gene.data)
    of GeneSet:
      todo()
    of GeneSymbol:
      return val
    of GeneComplexSymbol:
      return val
    else:
      return val

  EvaluatorMgr[ExQuote] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var val = expr.quote_val
    result = self.unquote(frame, expr, val)

  EvaluatorMgr[ExExit] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    if expr.exit == nil:
      quit()
    else:
      var code = self.eval(frame, expr.exit)
      quit(code.int)

  EvaluatorMgr[ExEnv] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var env = self.eval(frame, expr.env)
    result = get_env(env.str)
    if result.str.len == 0:
      result = self.eval(frame, expr.env_default).to_s

  EvaluatorMgr[ExPrint] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var print_to = stdout
    if expr.print_to != nil:
      print_to = self.eval(frame, expr.print_to).internal.file
    for e in expr.print:
      var v = self.eval(frame, e)
      case v.kind:
      of GeneString:
        print_to.write v.str
      else:
        print_to.write $v
    if expr.print_and_return:
      print_to.write "\n"

  EvaluatorMgr[ExRoot] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    return self.eval(frame, expr.root)

  EvaluatorMgr[ExLiteral] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    return expr.literal

  EvaluatorMgr[ExString] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    return new_gene_string(expr.str)

  EvaluatorMgr[ExComplexSymbol] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    return self.get_member(frame, expr.csymbol)

  EvaluatorMgr[ExGene] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var target = self.eval(frame, expr.gene_type)
    case target.kind:
    of GeneInternal:
      let key = ord(target.internal.kind)
      if GeneEvaluators.has_key(key):
        return GeneEvaluators[key](self, frame, expr, target)

      case target.internal.kind:
      of GeneFunction:
        var options = Table[FnOption, GeneValue]()
        var args = self.eval_args(frame, expr.gene_props, expr.gene_data)
        result = self.call_fn(frame, GeneNil, target.internal.fn, args, options)
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
      of GeneNativeFn:
        var args = self.eval_args(frame, expr.gene_props, expr.gene_data)
        result = target.internal.native_fn(args.gene.props, args.gene.data)
      of GeneSelector:
        var val = self.eval(frame, expr.gene_data[0])
        var selector = target.internal.selector
        try:
          result = selector.search(val)
        except SelectorNoResult:
          var default_expr: Expr
          for e in expr.gene_props:
            if e.map_key == DEFAULT_KEY:
              default_expr = e.map_val
              break
          if default_expr != nil:
            result = self.eval(frame, default_expr)
          else:
            raise

      # of GeneIteratorWrapper:
      #   var p = target.internal.iterator_wrapper
      #   var args = self.eval_args(frame, expr.gene_props, expr.gene_data)
      #   result = p(args.gene.data)
      else:
        todo($target.internal.kind)
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

  EvaluatorMgr[ExEnum] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var e = expr.enum
    self.def_member(frame, e.name, e, true)

  EvaluatorMgr[ExFor] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
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
        var val = first.symbol.to_key
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
        # of GeneInternal:
        #   case for_in.internal.kind:
        #   of GeneIterator:
        #     for _, v in for_in.internal.iterator():
        #       try:
        #         frame.scope[val] = v
        #         for e in expr.for_blk:
        #           discard self.eval(frame, e)
        #       except Continue:
        #         discard
        #   else:
        #     todo($for_in.internal.kind)
        else:
          todo($for_in.kind)
      else:
        var key = first.symbol.to_key
        var val = second.symbol.to_key
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
              frame.scope[key] = k.to_s
              frame.scope[val] = v
              for e in expr.for_blk:
                discard self.eval(frame, e)
            except Continue:
              discard
        else:
          todo()
    except Break:
      discard

  EvaluatorMgr[ExParseCmdArgs] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
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

  EvaluatorMgr[ExRepl] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    return repl(self, frame, eval_only, true)

  EvaluatorMgr[ExAsync] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    try:
      var val = self.eval(frame, expr.async)
      if val.kind == GeneInternal and val.internal.kind == GeneFuture:
        return val
      var future = new_future[GeneValue]()
      future.complete(val)
      result = future_to_gene(future)
    except CatchableError as e:
      var future = new_future[GeneValue]()
      future.fail(e)
      result = future_to_gene(future)

  EvaluatorMgr[ExAsyncCallback] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    # Register callback to future
    var acb_self = self.eval(frame, expr.acb_self).internal.future
    var acb_callback = self.eval(frame, expr.acb_callback)
    if acb_self.finished:
      if expr.acb_success and not acb_self.failed:
        discard self.call_target(frame, acb_callback, @[acb_self.read()], expr)
      elif not expr.acb_success and acb_self.failed:
        # TODO: handle exceptions that are not CatchableError
        var ex = error_to_gene(cast[ref CatchableError](acb_self.read_error()))
        discard self.call_target(frame, acb_callback, @[ex], expr)
    else:
      acb_self.add_callback proc() {.gcsafe.} =
        if expr.acb_success and not acb_self.failed:
          discard self.call_target(frame, acb_callback, @[acb_self.read()], expr)
        elif not expr.acb_success and acb_self.failed:
          # TODO: handle exceptions that are not CatchableError
          var ex = error_to_gene(cast[ref CatchableError](acb_self.read_error()))
          discard self.call_target(frame, acb_callback, @[ex], expr)

  EvaluatorMgr[ExSelector] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var selector = new_selector()
    if expr.parallel_mode:
      for item in expr.selector:
        var v = self.eval(frame, item)
        selector.children.add(gene_to_selector_item(v))
    else:
      var first = self.eval(frame, expr.selector[0])
      var selector_item = gene_to_selector_item(first)
      selector.children.add(selector_item)
      for i in 1..<expr.selector.len:
        var item = self.eval(frame, expr.selector[i])
        var new_selector_item = gene_to_selector_item(item)
        selector_item.children.add(new_selector_item)
        selector_item = new_selector_item
    result = selector

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

  EvaluatorMgr[ExCase] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
    var input = self.eval(frame, expr.case_input)
    for pair in expr.case_more_mapping:
      var pattern = self.eval(frame, pair[0])
      if input.case_equals(pattern):
        return self.eval(frame, expr.case_blks[pair[1]])
    result = self.eval(frame, expr.case_else)
