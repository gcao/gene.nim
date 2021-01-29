import ../map_key
import ../types
import ../translators
import ../interpreter/base

type
  TryParsingState = enum
    TryBody
    TryCatch
    TryCatchBody
    TryFinally

let TRY_KEY*   = add_key("try")
let THROW_KEY* = add_key("throw")

let TRY*     = new_gene_symbol("try")
let CATCH*   = new_gene_symbol("catch")
let FINALLY* = new_gene_symbol("finally")

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

proc init*() =
  TranslatorMgr[THROW_KEY         ] = new_throw_expr
  TranslatorMgr[TRY_KEY           ] = new_try_expr

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
