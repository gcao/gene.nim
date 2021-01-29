import tables
import dynlib

import ../map_key
import ../types
import ../dynlib_mapping
import ../translators
import ../interpreter/base

let IMPORT_KEY*               = add_key("import")
let IMPORT_NATIVE_KEY*        = add_key("import_native")
let FROM_KEY*                 = add_key("from")
let NAMES_KEY*                = add_key("names")
let MODULE_KEY*               = add_key("module")

proc parse*(self: ImportMatcherRoot, input: GeneValue, group: ptr seq[ImportMatcher]) =
  var data: seq[GeneValue]
  case input.kind:
  of GeneGene:
    data = input.gene.data
  of GeneVector:
    data = input.vec
  else:
    todo()

  var i = 0
  while i < data.len:
    var item = data[i]
    i += 1
    case item.kind:
    of GeneSymbol:
      if item.symbol == "from":
        self.from = data[i]
        i += 1
      else:
        group[].add(ImportMatcher(name: item.symbol.to_key))
    of GeneComplexSymbol:
      var names: seq[string] = @[]
      names.add(item.csymbol.first)
      for item in item.csymbol.rest:
        names.add(item)

      var matcher: ImportMatcher
      var my_group = group
      var j = 0
      while j < names.len:
        var name = names[j]
        j += 1
        if name == "": # TODO: throw error if "" is not the last
          self.parse(data[i], matcher.children.addr)
          i += 1
        else:
          matcher = ImportMatcher(name: name.to_key)
          matcher.children_only = j < names.len
          my_group[].add(matcher)
          my_group = matcher.children.addr
    else:
      todo()

proc new_import_matcher*(v: GeneValue): ImportMatcherRoot =
  result = ImportMatcherRoot()
  result.parse(v, result.children.addr)

proc normalize(self: GeneValue) =
  var names: seq[GeneValue] = @[]
  var module: GeneValue
  var expect_module = false
  for val in self.gene.data:
    if expect_module:
      module = val
    elif val.kind == GeneSymbol and val.symbol == "from":
      expect_module = true
    else:
      names.add(val)
  self.gene.props[NAMES_KEY] = new_gene_vec(names)
  self.gene.props[MODULE_KEY] = module

proc new_import_expr(parent: Expr, val: GeneValue): Expr =
  val.normalize()
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
