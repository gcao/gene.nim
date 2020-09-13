import os, sequtils, tables, hashes

import ./types
import ./parser
import ./vm

type
  IfState = enum
    ## Initial state
    If

    # TODO: is this a good idea - "if not, elif not"?
    # ## Can be used in front of condition
    # Not

    ## Can follow if and else if
    Truthy

    ## Can follow if and else if
    Falsy

    ## elif
    ElseIf

    ## else
    Else

#################### Interfaces ##################

proc eval*(self: var VM, node: GeneValue): GeneValue
proc eval_gene*(self: var VM, node: GeneValue): GeneValue
proc eval_if*(self: var VM, nodes: seq[GeneValue]): GeneValue
proc eval_do*(self: var VM, node: GeneValue): GeneValue
proc eval_loop*(self: var VM, node: GeneValue): GeneValue
proc eval_for*(self: var VM, node: GeneValue): GeneValue
proc eval_break*(self: var VM, node: GeneValue): GeneValue
proc eval_fn*(self: var VM, node: GeneValue): GeneValue
proc eval_return*(self: var VM, node: GeneValue): GeneValue
proc eval_ns*(self: var VM, node: GeneValue): GeneValue
proc eval_class*(self: var VM, node: GeneValue): GeneValue
proc eval_method*(self: var VM, node: GeneValue): GeneValue
proc eval_invoke_method(self: var VM, node: GeneValue): GeneValue
proc eval_new*(self: var VM, node: GeneValue): GeneValue
proc eval_at*(self: var VM, node: GeneValue): GeneValue
proc eval_argv*(self: var VM, node: GeneValue): GeneValue
proc eval_import*(self: var VM, node: GeneValue): GeneValue
proc eval_call_native*(self: var VM, node: GeneValue): GeneValue
proc call*(self: var VM, fn: Function, args: Arguments): GeneValue
proc call_method*(self: var VM, instance: GeneValue, fn: Function, args: Arguments): GeneValue
proc eval_module*(self: var VM, name: string)

#################### Implementations #############

proc eval_gene(self: var VM, node: GeneValue): GeneValue =
  node.normalize
  var op = node.d.gene_op
  case op.d.kind:
  of GeneSymbol:
    if op.d.symbol == "var":
      var name = $node.d.gene_data[0]
      var value =
        if node.d.gene_data.len > 1:
          self.eval(node.d.gene_data[1])
        else:
          GeneNil
      let key = cast[Hash](name.hash)
      self.cur_stack.cur_scope[key] = value
    elif op.d.symbol == "@":
      return self.eval_at(node)
    elif op.d.symbol == "if":
      return self.eval_if(node.d.gene_data)
    elif op.d.symbol == "do":
      return self.eval_do(node)
    elif op.d.symbol == "loop":
      return self.eval_loop(node)
    elif op.d.symbol == "for":
      return self.eval_for(node)
    elif op.d.symbol == "break":
      return self.eval_break(node)
    elif op.d.symbol == "fn":
      return self.eval_fn(node)
    elif op.d.symbol == "return":
      return self.eval_return(node)
    elif op.d.symbol == "ns":
      return self.eval_ns(node)
    elif op.d.symbol == "import":
      return self.eval_import(node)
    elif op.d.symbol == "class":
      return self.eval_class(node)
    elif op.d.symbol == "method":
      return self.eval_method(node)
    elif op.d.symbol == "new":
      return self.eval_new(node)
    elif op.d.symbol == "$invoke_method":
      return self.eval_invoke_method(node)
    elif op.d.symbol == "$ARGV":
      return self.eval_argv(node)
    elif op.d.symbol == "$call_native":
      return self.eval_call_native(node)
    elif op.d.symbol == "=":
      var first = node.d.gene_data[0]
      var second = node.d.gene_data[1]
      case first.d.kind:
      of GeneSymbol:
        var symbol = first.d.symbol
        if symbol[0] == '@':
          var cur_self = self.cur_stack.self
          case cur_self.d.kind:
          of GeneInstance:
            cur_self.d.instance.value.d.gene_props[symbol.substr(1)] = self.eval(second)
          else:
            todo()
        else:
          let key = cast[Hash](first.d.symbol.hash) 
          self.cur_stack.cur_scope[key] = self.eval(second)
      else:
        todo($node)
    elif op.d.symbol == "+":
      var first = self.eval(node.d.gene_data[0])
      var second = self.eval(node.d.gene_data[1])
      var firstKind = first.d.kind
      var secondKind = second.d.kind
      if firstKind == GeneInt and secondKind == GeneInt:
        return new_gene_int(first.d.num + second.d.num)
      else:
        todo($node)
    elif op.d.symbol == "-":
      var first = self.eval(node.d.gene_data[0])
      var second = self.eval(node.d.gene_data[1])
      var firstKind = first.d.kind
      var secondKind = second.d.kind
      if firstKind == GeneInt and secondKind == GeneInt:
        return new_gene_int(first.d.num - second.d.num)
      else:
        todo($node)
    elif op.d.symbol == "==":
      var first = self.eval(node.d.gene_data[0])
      var second = self.eval(node.d.gene_data[1])
      return new_gene_bool(first == second)
    elif op.d.symbol == "<=":
      var first = self.eval(node.d.gene_data[0])
      var second = self.eval(node.d.gene_data[1])
      var firstKind = first.d.kind
      var secondKind = second.d.kind
      if firstKind == GeneInt and secondKind == GeneInt:
        return new_gene_bool(first.d.num <= second.d.num)
      else:
        todo($node)
    elif op.d.symbol == "<":
      var first = self.eval(node.d.gene_data[0])
      var second = self.eval(node.d.gene_data[1])
      var firstKind = first.d.kind
      var secondKind = second.d.kind
      if firstKind == GeneInt and secondKind == GeneInt:
        return new_gene_bool(first.d.num < second.d.num)
      else:
        todo($node)
    elif op.d.symbol == "&&":
      var first = self.eval(node.d.gene_data[0])
      var second = self.eval(node.d.gene_data[1])
      return new_gene_bool(first.is_truthy and second.is_truthy)
    elif op.d.symbol == "||":
      var first = self.eval(node.d.gene_data[0])
      var second = self.eval(node.d.gene_data[1])
      return new_gene_bool(first.is_truthy or second.is_truthy)
    else:
      var target = self.eval(op)
      if target.d.kind == GeneInternal and target.d.internal.kind == GeneFunction:
        var fn = target.d.internal.fn
        var this = self
        var args = node.d.gene_data.map(proc(item: GeneValue): GeneValue = this.eval(item))
        return self.call(fn, new_args(args))
      else:
        todo($node)
  else:
    todo($node)

proc eval_if(self: var VM, nodes: seq[GeneValue]): GeneValue =
  var state = IfState.If
  for node in nodes:
    case state:
    of IfState.If, IfState.ElseIf:
      var cond = self.eval(node)
      if cond.isTruthy:
        state = IfState.Truthy
      else:
        state = IfState.Falsy
    of IfState.Else:
      result = self.eval(node)
    of IfState.Truthy:
      case node.d.kind:
      of GeneSymbol:
        if node.d.symbol == "elif" or node.d.symbol == "else":
          break
        else:
          result = self.eval(node)
      else:
        result = self.eval(node)
    of IfState.Falsy:
      if node.d.kind == GeneSymbol:
        if node.d.symbol == "elif":
          state = IfState.ElseIf
        elif node.d.symbol == "else":
          state = IfState.Else

proc eval_do(self: var VM, node: GeneValue): GeneValue =
  for child in node.d.gene_data:
    result = self.eval(child)

proc eval_loop(self: var VM, node: GeneValue): GeneValue =
  var i = 0
  var len = node.d.gene_data.len
  while true:
    var child = node.d.gene_data[i]
    var r = self.eval(child)
    if not r.d.isNil and r.d.kind == GeneInternal and r.d.internal.kind == GeneBreak:
      result = r.d.internal.break_val
      break
    i = (i + 1) mod len

proc eval_for(self: var VM, node: GeneValue): GeneValue =
  discard self.eval(node.d.gene_props["init"])
  while self.eval(node.d.gene_props["guard"]):
    for child in node.d.gene_data:
      var r = self.eval(child)
      if not r.d.isNil and r.d.internal.kind == GeneBreak:
        return
    discard self.eval(node.d.gene_props["update"])

proc eval_break(self: var VM, node: GeneValue): GeneValue =
  if node.d.gene_data.len > 0:
    var v = self.eval(node.d.gene_data[0])
    return new_gene_internal(Internal(kind: GeneBreak, break_val: v))
  else:
    return new_gene_internal(Internal(kind: GeneBreak))

proc eval_fn(self: var VM, node: GeneValue): GeneValue =
  var name = node.d.gene_data[0].d.symbol
  var args: seq[string] = @[]
  var a = node.d.gene_data[1]
  case a.d.kind:
  of GeneSymbol:
    args.add(a.d.symbol)
  of GeneVector:
    for item in a.d.vec:
      args.add(item.d.symbol)
  else:
    not_allowed()
  var body: seq[GeneValue] = @[]
  for i in 2..<node.d.gene_data.len:
    body.add node.d.gene_data[i]

  var fn = Function(name: name, args: args, body: body)
  var internal = Internal(kind: GeneFunction, fn: fn)
  result = new_gene_internal(internal)
  let key = cast[Hash](name.hash)
  self.cur_stack.cur_ns[key] = result

proc eval_return(self: var VM, node: GeneValue): GeneValue =
  var val = self.eval(node.d.gene_data[0])
  return new_gene_internal(Internal(kind: GeneReturn, return_val: val))

proc eval_ns*(self: var VM, node: GeneValue): GeneValue =
  var name = node.d.gene_data[0].d.symbol
  var ns = new_namespace(name)
  result = new_gene_internal(ns)
  let key = cast[Hash](name.hash)
  self.cur_stack.cur_ns[key] = result

  var stack = self.cur_stack
  self.cur_stack = stack.grow()
  self.cur_stack.self = result
  self.cur_stack.cur_ns = ns
  for i in 1..<node.d.gene_data.len:
    var child = node.d.gene_data[i]
    discard self.eval child

  self.cur_stack = stack

proc eval_class*(self: var VM, node: GeneValue): GeneValue =
  var name: string
  var ns: Namespace
  var first = node.d.gene_data[0]
  case first.d.kind:
  of GeneSymbol:
    name = first.d.symbol
    ns = self.cur_stack.cur_ns
  of GeneComplexSymbol:
    var nsName = first.d.csymbol.first
    var rest = first.d.csymbol.rest
    name = rest[^1]
    if nsName == "global":
      ns = APP.ns
    else:
      let key = cast[Hash](nsName.hash)
      ns = self.cur_stack.cur_ns[key].d.internal.ns
    for i in 0..<rest.len - 1:
      let key = cast[Hash](rest[i].hash)
      ns = ns[key].d.internal.ns
  else:
    not_allowed()

  var class = Class(name: name)
  var internal = Internal(kind: GeneClass, class: class)
  result = new_gene_internal(internal)
  let key = cast[Hash](name.hash)
  ns[key] = result

  var stack = self.cur_stack
  self.cur_stack = stack.grow()
  self.cur_stack.self = result
  for i in 1..<node.d.gene_data.len:
    var child = node.d.gene_data[i]
    discard self.eval child

  self.cur_stack = stack

proc eval_method(self: var VM, node: GeneValue): GeneValue =
  var name = node.d.gene_data[0].d.symbol
  var args: seq[string] = @[]
  var a = node.d.gene_data[1]
  case a.d.kind:
  of GeneSymbol:
    args.add(a.d.symbol)
  of GeneVector:
    for item in a.d.vec:
      args.add(item.d.symbol)
  else:
    not_allowed()
  var body: seq[GeneValue] = @[]
  for i in 2..<node.d.gene_data.len:
    body.add node.d.gene_data[i]

  var fn = Function(name: name, args: args, body: body)
  var internal = Internal(kind: GeneFunction, fn: fn)
  result = new_gene_internal(internal)
  self.cur_stack.self.d.internal.class.methods[name] = fn

proc eval_invoke_method(self: var VM, node: GeneValue): GeneValue =
  var instance = self.eval(node.d.gene_props["self"])
  var class: Class
  case instance.d.kind:
  of GeneInstance:
    class = instance.d.instance.class
  of GeneString:
    let key = cast[Hash]("String".hash)
    class = APP.ns[key].d.internal.class
  else:
    todo()
  var meth = class.methods[node.d.gene_props["method"].d.str]
  var this = self
  var args = node.d.gene_data.map(proc(item: GeneValue): GeneValue = this.eval(item))
  return self.call_method(instance, meth, new_args(args))

proc eval_new*(self: var VM, node: GeneValue): GeneValue =
  var class = self.eval(node.d.gene_data[0]).d.internal.class
  var instance = new_instance(class)
  result = new_gene_instance(instance)

  if class.methods.hasKey("new"):
    var new_method = class.methods["new"]
    var args: seq[GeneValue] = @[]
    for i in 1..<node.d.gene_data.len:
      args.add(self.eval(node.d.gene_data[i]))
    discard self.call_method(result, new_method, new_args(args))

proc eval_at*(self: var VM, node: GeneValue): GeneValue =
  var target =
    if node.d.gene_props["self"].d.isNil:
      self.cur_stack.self
    else:
      self.eval(node.d.gene_props["self"])
  var name = node.d.gene_data[0].d.str
  case target.d.kind:
  of GeneInstance:
    return target.d.instance.value.d.gene_props[name]
  of GeneGene:
    return target.d.gene_props[name]
  else:
    not_allowed()

proc eval_argv*(self: var VM, node: GeneValue): GeneValue =
  # todo("map() does not work with arc GC algorithm")
  if node.d.gene_data.len == 1:
    if node.d.gene_data[0] == new_gene_int(0):
      return new_gene_string_move(getAppFilename())
    else:
      var argv = commandLineParams().map(proc(s: string): GeneValue = new_gene_string_move(s))
      return argv[node.d.gene_data[0].d.num - 1]

  var argv = commandLineParams().map(proc(s: string): GeneValue = new_gene_string_move(s))
  argv.insert(new_gene_string_move(getAppFilename()))
  return new_gene_vec(argv)

proc eval_import*(self: var VM, node: GeneValue): GeneValue =
  var module = node.d.gene_props["module"].d.str
  var ns: Namespace
  if not APP.namespaces.hasKey(module):
    self.eval_module(module)
  ns = APP.namespaces[module]
  if ns == nil:
    todo("Evaluate module")
  for name in node.d.gene_props["names"].d.vec:
    var s = name.d.symbol
    let key = cast[Hash](s.hash)
    self.cur_stack.cur_ns[key] = ns[key]
  return GeneNil

proc eval_call_native*(self: var VM, node: GeneValue): GeneValue =
  var name = node.d.gene_data[0].d.str
  case name:
  of "str_len":
    var arg0 = self.eval(node.d.gene_data[1]).d.str
    return new_gene_int(len(arg0))
  else:
    todo()

proc call*(self: var VM, fn: Function, args: Arguments): GeneValue =
  var stack = self.cur_stack
  self.cur_stack = stack.grow()
  for i in 0..<fn.args.len:
    var arg = fn.args[i]
    var val = args[i]
    let key = cast[Hash](arg.hash)
    self.cur_stack.cur_scope[key] = val

  try:
    for node in fn.body:
      result = self.eval node

  finally:
    self.cur_stack = stack

proc call_method*(self: var VM, instance: GeneValue, fn: Function, args: Arguments): GeneValue =
  var stack = self.cur_stack
  self.cur_stack = stack.grow()
  self.cur_stack.self = instance
  for i in 0..<fn.args.len:
    var arg = fn.args[i]
    var val = args[i]
    let key = cast[Hash](arg.hash)
    self.cur_stack.cur_scope[key] = val

  try:
    for node in fn.body:
      result = self.eval node

  finally:
    self.cur_stack = stack

proc eval*(self: var VM, node: GeneValue): GeneValue =
  case node.d.kind:
  of GeneNilKind:
    return GeneNil
  of GeneInt:
    return new_gene_int(node.d.num)
  of GeneString:
    return new_gene_string_move(node.d.str)
  of GeneBool:
    return new_gene_bool(node.d.boolVal)
  of GeneSymbol:
    var name = node.d.symbol
    case name:
    of "global":
      return new_gene_internal(APP.ns)
    of "self":
      return self.cur_stack.self
    else:
      let key = cast[Hash](name.hash)
      return self[key]
  of GeneComplexSymbol:
    var sym = node.d.csymbol
    if sym.first == "":
      result = new_gene_internal(self.cur_stack.cur_ns)
    elif sym.first == "global":
      result = new_gene_internal(APP.ns)
    else:
      let key = cast[Hash](sym.first.hash)
      result = self[key]
    for name in sym.rest:
      let key = cast[Hash](name.hash)
      result = result.d.internal.ns[key]
    return result
  of GeneGene:
    node.normalize
    return self.eval_gene(node)
  of GeneVector:
    # return new_gene_vec(node.d.vec.mapIt(self.eval(it)))
    var vec: seq[GeneValue] = @[]
    for child in node.d.vec:
      vec.add(self.eval(child))
    return new_gene_vec(vec)
  of GeneMap:
    var map = Table[string, GeneValue]()
    for key in node.d.map.keys:
      map[key] = self.eval(node.d.map[key])
    return new_gene_map(map)
  else:
    todo($node)

proc eval*(self: var VM, nodes: seq[GeneValue]): GeneValue =
  for node in nodes:
    result = self.eval node

proc eval*(self: var VM, buffer: string): GeneValue =
  var parsed = read_all(buffer)
  for node in parsed:
    result = self.eval node

proc eval_module*(self: var VM, name: string, buffer: string) =
  var stack = self.cur_stack.grow()
  self.cur_stack = stack
  stack.cur_ns = new_namespace()
  stack.cur_ns.name = name
  APP.namespaces[name] = stack.cur_ns

  var parsed = read_all(buffer)
  for node in parsed:
    discard self.eval node

proc eval_module*(self: var VM, name: string) =
  self.eval_module(name, readFile(name))
