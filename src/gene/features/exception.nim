import ../map_key
import ../types
import ../translators

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