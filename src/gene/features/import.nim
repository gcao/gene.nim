import tables
import dynlib

import ../map_key
import ../types
import ../dynlib_mapping
import ../translators/base as translators_base
import ../interpreter/base as interpreter_base

let IMPORT_KEY*               = add_key("import")
let IMPORT_NATIVE_KEY*        = add_key("import_native")
let FROM_KEY*                 = add_key("from")

proc new_import_expr(parent: Expr, val: GeneValue): Expr =
  var matcher = new_import_matcher(val)
  result = Expr(
    kind: ExImport,
    parent: parent,
    import_matcher: matcher,
    import_native: val.gene.type.symbol == "import_native",
  )
  if matcher.from != nil:
    result.import_from = new_expr(result, matcher.from)
  if val.gene.props.has_key(PKG_KEY):
    result.import_pkg = new_expr(result, val.gene.props[PKG_KEY])

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

proc init*() =
  TranslatorMgr[IMPORT_KEY        ] = new_import_expr
  TranslatorMgr[IMPORT_NATIVE_KEY ] = new_import_expr

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
