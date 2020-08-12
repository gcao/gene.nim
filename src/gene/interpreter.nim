import os, sequtils, tables

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
  var op = node.gene_op
  case op.kind:
  of GeneSymbol:
    if op.symbol == "var":
      var name = $node.gene_data[0]
      var value =
        if node.gene_data.len > 1:
          self.eval(node.gene_data[1])
        else:
          GeneNil
      self.cur_stack.cur_scope[name] = value
    elif op.symbol == "@":
      return self.eval_at(node)
    elif op.symbol == "if":
      return self.eval_if(node.gene_data)
    elif op.symbol == "do":
      return self.eval_do(node)
    elif op.symbol == "loop":
      return self.eval_loop(node)
    elif op.symbol == "for":
      return self.eval_for(node)
    elif op.symbol == "break":
      return self.eval_break(node)
    elif op.symbol == "fn":
      return self.eval_fn(node)
    elif op.symbol == "return":
      return self.eval_return(node)
    elif op.symbol == "ns":
      return self.eval_ns(node)
    elif op.symbol == "import":
      return self.eval_import(node)
    elif op.symbol == "class":
      return self.eval_class(node)
    elif op.symbol == "method":
      return self.eval_method(node)
    elif op.symbol == "new":
      return self.eval_new(node)
    elif op.symbol == "$invoke_method":
      return self.eval_invoke_method(node)
    elif op.symbol == "$ARGV":
      return self.eval_argv(node)
    elif op.symbol == "$call_native":
      return self.eval_call_native(node)
    elif op.symbol == "=":
      var first = node.gene_data[0]
      var second = node.gene_data[1]
      case first.kind:
      of GeneSymbol:
        var symbol = first.symbol
        if symbol[0] == '@':
          var cur_self = self.cur_stack.self
          case cur_self.kind:
          of GeneInstance:
            cur_self.instance.value.gene_props[symbol.substr(1)] = self.eval(second)
          else:
            todo()
        else:
          self.cur_stack.cur_scope[first.symbol] = self.eval(second)
      else:
        todo($node)
    elif op.symbol == "+":
      var first = self.eval(node.gene_data[0])
      var second = self.eval(node.gene_data[1])
      var firstKind = first.kind
      var secondKind = second.kind
      if firstKind == GeneInt and secondKind == GeneInt:
        return new_gene_int(first.num + second.num)
      else:
        todo($node)
    elif op.symbol == "-":
      var first = self.eval(node.gene_data[0])
      var second = self.eval(node.gene_data[1])
      var firstKind = first.kind
      var secondKind = second.kind
      if firstKind == GeneInt and secondKind == GeneInt:
        return new_gene_int(first.num - second.num)
      else:
        todo($node)
    elif op.symbol == "==":
      var first = self.eval(node.gene_data[0])
      var second = self.eval(node.gene_data[1])
      return new_gene_bool(first == second)
    elif op.symbol == "<=":
      var first = self.eval(node.gene_data[0])
      var second = self.eval(node.gene_data[1])
      var firstKind = first.kind
      var secondKind = second.kind
      if firstKind == GeneInt and secondKind == GeneInt:
        return new_gene_bool(first.num <= second.num)
      else:
        todo($node)
    elif op.symbol == "<":
      var first = self.eval(node.gene_data[0])
      var second = self.eval(node.gene_data[1])
      var firstKind = first.kind
      var secondKind = second.kind
      if firstKind == GeneInt and secondKind == GeneInt:
        return new_gene_bool(first.num < second.num)
      else:
        todo($node)
    elif op.symbol == "&&":
      var first = self.eval(node.gene_data[0])
      var second = self.eval(node.gene_data[1])
      return new_gene_bool(first.is_truthy and second.is_truthy)
    elif op.symbol == "||":
      var first = self.eval(node.gene_data[0])
      var second = self.eval(node.gene_data[1])
      return new_gene_bool(first.is_truthy or second.is_truthy)
    else:
      var target = self.eval(op)
      if target.kind == GeneInternal and target.internal.kind == GeneFunction:
        var fn = target.internal.fn
        var this = self
        var args = node.gene_data.map(proc(item: GeneValue): GeneValue = this.eval(item))
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
      case node.kind:
      of GeneSymbol:
        if node.symbol == "elif" or node.symbol == "else":
          break
        else:
          result = self.eval(node)
      else:
        result = self.eval(node)
    of IfState.Falsy:
      if node.kind == GeneSymbol:
        if node.symbol == "elif":
          state = IfState.ElseIf
        elif node.symbol == "else":
          state = IfState.Else

proc eval_do(self: var VM, node: GeneValue): GeneValue =
  for child in node.gene_data:
    result = self.eval(child)

proc eval_loop(self: var VM, node: GeneValue): GeneValue =
  var i = 0
  var len = node.gene_data.len
  while true:
    var child = node.gene_data[i]
    var r = self.eval(child)
    if not r.isNil and r.kind == GeneInternal and r.internal.kind == GeneBreak:
      result = r.internal.break_val
      break
    i = (i + 1) mod len

proc eval_for(self: var VM, node: GeneValue): GeneValue =
  discard self.eval(node.gene_props["init"])
  while self.eval(node.gene_props["guard"]):
    for child in node.gene_data:
      var r = self.eval(child)
      if not r.isNil and r.internal.kind == GeneBreak:
        return
    discard self.eval(node.gene_props["update"])

proc eval_break(self: var VM, node: GeneValue): GeneValue =
  if node.gene_data.len > 0:
    var v = self.eval(node.gene_data[0])
    return new_gene_internal(Internal(kind: GeneBreak, break_val: v))
  else:
    return new_gene_internal(Internal(kind: GeneBreak))

proc eval_fn(self: var VM, node: GeneValue): GeneValue =
  var name = node.gene_data[0].symbol
  var args: seq[string] = @[]
  var a = node.gene_data[1]
  case a.kind:
  of GeneSymbol:
    args.add(a.symbol)
  of GeneVector:
    for item in a.vec:
      args.add(item.symbol)
  else:
    not_allowed()
  var body: seq[GeneValue] = @[]
  for i in 2..<node.gene_data.len:
    body.add node.gene_data[i]

  var fn = Function(name: name, args: args, body: body)
  var internal = Internal(kind: GeneFunction, fn: fn)
  result = new_gene_internal(internal)
  self.cur_stack.cur_ns[name] = result

proc eval_return(self: var VM, node: GeneValue): GeneValue =
  var val = self.eval(node.gene_data[0])
  return new_gene_internal(Internal(kind: GeneReturn, return_val: val))

proc eval_ns*(self: var VM, node: GeneValue): GeneValue =
  var name = node.gene_data[0].symbol
  var ns = new_namespace(name)
  result = new_gene_internal(ns)
  self.cur_stack.cur_ns[name] = result

  var stack = self.cur_stack
  self.cur_stack = stack.grow()
  self.cur_stack.self = result
  self.cur_stack.cur_ns = ns
  for i in 1..<node.gene_data.len:
    var child = node.gene_data[i]
    discard self.eval child

  self.cur_stack = stack

proc eval_class*(self: var VM, node: GeneValue): GeneValue =
  var name: string
  var ns: Namespace
  var first = node.gene_data[0]
  case first.kind:
  of GeneSymbol:
    name = first.symbol
    ns = self.cur_stack.cur_ns
  of GeneComplexSymbol:
    var nsName = first.csymbol.first
    var rest = first.csymbol.rest
    name = rest[^1]
    if nsName == "global":
      ns = APP.ns
    else:
      ns = self.cur_stack.cur_ns[nsName].internal.ns
    for i in 0..<rest.len - 1:
      ns = ns[rest[i]].internal.ns
  else:
    not_allowed()

  var class = Class(name: name)
  var internal = Internal(kind: GeneClass, class: class)
  result = new_gene_internal(internal)
  ns[name] = result

  var stack = self.cur_stack
  self.cur_stack = stack.grow()
  self.cur_stack.self = result
  for i in 1..<node.gene_data.len:
    var child = node.gene_data[i]
    discard self.eval child

  self.cur_stack = stack

proc eval_method(self: var VM, node: GeneValue): GeneValue =
  var name = node.gene_data[0].symbol
  var args: seq[string] = @[]
  var a = node.gene_data[1]
  case a.kind:
  of GeneSymbol:
    args.add(a.symbol)
  of GeneVector:
    for item in a.vec:
      args.add(item.symbol)
  else:
    not_allowed()
  var body: seq[GeneValue] = @[]
  for i in 2..<node.gene_data.len:
    body.add node.gene_data[i]

  var fn = Function(name: name, args: args, body: body)
  var internal = Internal(kind: GeneFunction, fn: fn)
  result = new_gene_internal(internal)
  self.cur_stack.self.internal.class.methods[name] = fn

proc eval_invoke_method(self: var VM, node: GeneValue): GeneValue =
  var instance = self.eval(node.gene_props["self"])
  var class: Class
  case instance.kind:
  of GeneInstance:
    class = instance.instance.class
  of GeneString:
    class = APP.ns["String"].internal.class
  else:
    todo()
  var meth = class.methods[node.gene_props["method"].str]
  var this = self
  var args = node.gene_data.map(proc(item: GeneValue): GeneValue = this.eval(item))
  return self.call_method(instance, meth, new_args(args))

proc eval_new*(self: var VM, node: GeneValue): GeneValue =
  var class = self.eval(node.gene_data[0]).internal.class
  var instance = new_instance(class)
  result = new_gene_instance(instance)

  if class.methods.hasKey("new"):
    var new_method = class.methods["new"]
    var args: seq[GeneValue] = @[]
    for i in 1..<node.gene_data.len:
      args.add(self.eval(node.gene_data[i]))
    discard self.call_method(result, new_method, new_args(args))

proc eval_at*(self: var VM, node: GeneValue): GeneValue =
  var target =
    if node.gene_props["self"].isNil:
      self.cur_stack.self
    else:
      self.eval(node.gene_props["self"])
  var name = node.gene_data[0].str
  case target.kind:
  of GeneInstance:
    return target.instance.value.gene_props[name]
  of GeneGene:
    return target.gene_props[name]
  else:
    not_allowed()

proc eval_argv*(self: var VM, node: GeneValue): GeneValue =
  if node.gene_data.len == 1:
    if node.gene_data[0] == new_gene_int(0):
      return new_gene_string_move(getAppFilename())
    else:
      var argv = commandLineParams().map(proc(s: string): GeneValue = new_gene_string_move(s))
      return argv[node.gene_data[0].num - 1]

  var argv = commandLineParams().map(proc(s: string): GeneValue = new_gene_string_move(s))
  argv.insert(new_gene_string_move(getAppFilename()))
  return new_gene_vec(argv)

proc eval_import*(self: var VM, node: GeneValue): GeneValue =
  var module = node.gene_props["module"].str
  var ns: Namespace
  if not APP.namespaces.hasKey(module):
    self.eval_module(module)
  ns = APP.namespaces[module]
  if ns == nil:
    todo("Evaluate module")
  for name in node.gene_props["names"].vec:
    var s = name.symbol
    self.cur_stack.cur_ns[s] = ns[s]
  return GeneNil

proc eval_call_native*(self: var VM, node: GeneValue): GeneValue =
  var name = node.gene_data[0].str
  case name:
  of "str_len":
    var arg0 = self.eval(node.gene_data[1]).str
    return new_gene_int(len(arg0))
  else:
    todo()

proc call*(self: var VM, fn: Function, args: Arguments): GeneValue =
  var stack = self.cur_stack
  self.cur_stack = stack.grow()
  for i in 0..<fn.args.len:
    var arg = fn.args[i]
    var val = args[i]
    self.cur_stack.cur_scope[arg] = val

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
    self.cur_stack.cur_scope[arg] = val

  try:
    for node in fn.body:
      result = self.eval node

  finally:
    self.cur_stack = stack

proc eval*(self: var VM, node: GeneValue): GeneValue =
  case node.kind:
  of GeneNilKind:
    return GeneNil
  of GeneInt:
    return new_gene_int(node.num)
  of GeneString:
    return new_gene_string_move(node.str)
  of GeneBool:
    return new_gene_bool(node.boolVal)
  of GeneSymbol:
    var name = node.symbol
    case name:
    of "global":
      return new_gene_internal(APP.ns)
    of "self":
      return self.cur_stack.self
    else:
      return self[name]
  of GeneComplexSymbol:
    var sym = node.csymbol
    if sym.first == "":
      result = new_gene_internal(self.cur_stack.cur_ns)
    elif sym.first == "global":
      result = new_gene_internal(APP.ns)
    else:
      result = self[sym.first]
    for name in sym.rest:
      result = result.internal.ns[name]
    return result
  of GeneGene:
    node.normalize
    return self.eval_gene(node)
  of GeneVector:
    return new_gene_vec(node.vec.mapIt(self.eval(it)))
  of GeneMap:
    var map = Table[string, GeneValue]()
    for key in node.map.keys:
      map[key] = self.eval(node.map[key])
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
