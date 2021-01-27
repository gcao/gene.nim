import ../types
import ./base

type
  TryParsingState = enum
    TryBody
    TryCatch
    TryCatchBody
    TryFinally

let TRY*      = new_gene_symbol("try")
let CATCH*    = new_gene_symbol("catch")
let FINALLY*  = new_gene_symbol("finally")

proc init_translators*() =
  TranslatorMgr[TRY_KEY           ] = proc(parent: Expr, val: GeneValue): Expr =
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
