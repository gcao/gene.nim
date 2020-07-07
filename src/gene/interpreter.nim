import sequtils

import ./types
import ./parser
import ./vm_types

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

    ## Follow condition
    Logic

    ## elif
    ElseIf

    ## else
    Else

# Interfaces
proc eval*(self: var VM, node: GeneValue): GeneValue
proc eval_gene(self: var VM, node: GeneValue): GeneValue
proc eval_if(self: var VM, nodes: seq[GeneValue]): GeneValue
proc eval_fn(self: var VM, node: GeneValue): GeneValue
proc call(self: var VM, fn: Function, args: Arguments): GeneValue
proc normalize(node: GeneValue)

proc eval_gene(self: var VM, node: GeneValue): GeneValue =
  normalize(node)
  var op = node.op
  case op.kind:
  of GeneSymbol:
    if op.symbol == "var":
      var name = $node.list[0]
      var value =
        if node.list.len > 1:
          self.eval(node.list[1])
        else:
          GeneNil
      self.cur_stack.cur_scope[name] = value
    elif op.symbol == "if":
      return self.eval_if(node.list)
    elif op.symbol == "fn":
      return self.eval_fn(node)
    elif op.symbol == "=":
      var first = node.list[0]
      var second = node.list[1]
      case first.kind:
      of GeneSymbol:
        self.cur_stack.cur_scope[first.symbol] = self.eval(second)
      else:
        todo()
    elif op.symbol == "+":
      var first = self.eval(node.list[0])
      var second = self.eval(node.list[1])
      var firstKind = first.kind
      var secondKind = second.kind
      if firstKind == GeneInt and secondKind == GeneInt:
        return new_gene_int(first.num + second.num)
      else:
        todo()
    elif op.symbol == "==":
      var first = self.eval(node.list[0])
      var second = self.eval(node.list[1])
      return new_gene_bool(first == second)
    elif op.symbol == "<=":
      var first = self.eval(node.list[0])
      var second = self.eval(node.list[1])
      var firstKind = first.kind
      var secondKind = second.kind
      if firstKind == GeneInt and secondKind == GeneInt:
        return new_gene_bool(first.num <= second.num)
      else:
        todo()
    elif op.symbol == "<":
      var first = self.eval(node.list[0])
      var second = self.eval(node.list[1])
      var firstKind = first.kind
      var secondKind = second.kind
      if firstKind == GeneInt and secondKind == GeneInt:
        return new_gene_bool(first.num < second.num)
      else:
        todo()
    else:
      var target = self.eval(op)
      if target.kind == GeneInternal and target.internal.kind == GeneFunction:
        var fn = target.internal.fn
        var this = self
        var args = node.list.map(proc(item: GeneValue): GeneValue = this.eval(item))
        return self.call(fn, new_args(args))
      else:
        todo()
  else:
    todo()

proc eval_if(self: var VM, nodes: seq[GeneValue]): GeneValue =
  var state = IfState.If
  for node in nodes:
    case state:
    of IfState.If:
      var cond = self.eval(node)
      if cond.isTruthy:
        state = IfState.Truthy
      else:
        state = IfState.Falsy
    of IfState.ElseIf:
      todo()
    of IfState.Else:
      todo()
    of IfState.Truthy:
      case node.kind:
      of GeneSymbol:
        if node.symbol == "elif" or node.symbol == "else":
          return
        else:
          result = self.eval(node)
      else:
        result = self.eval(node)
    of IfState.Falsy:
      todo()
    of IfState.Logic:
      todo()

proc eval_fn(self: var VM, node: GeneValue): GeneValue =
  var name = node.list[0].symbol
  var args: seq[string] = @[]
  var a = node.list[1]
  case a.kind:
  of GeneSymbol:
    args.add(a.symbol)
  of GeneVector:
    for item in a.vec:
      args.add(item.symbol)
  else:
    todo()
  var body: seq[GeneValue] = @[]
  for i in 2..<node.list.len:
    body.add node.list[i]

  var fn = Function(name: name, args: args, body: body)
  var internal = Internal(kind: GeneFunction, fn: fn)
  result = new_gene_internal(internal)
  self.cur_stack.cur_scope[name] = result

proc call(self: var VM, fn: Function, args: Arguments): GeneValue =
  var stack = self.cur_stack.grow()
  self.cur_stack = stack
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
  of GeneBool:
    return new_gene_bool(node.boolVal)
  of GeneSymbol:
    var name = node.symbol
    return cast[GeneValue](self.cur_stack.cur_scope[name])
  of GeneGene:
    return self.eval_gene(node)
  else:
    todo()

proc eval*(self: var VM, buffer: string): GeneValue =
  var parsed = read_all(buffer)
  for node in parsed:
    result = self.eval node

const BINARY_OPS = [
  "+", "-", "*", "/",
  "=", "+=", "-=", "*=", "/=",
  "==", "!=", "<", "<=", ">", ">=",
  "&&", "||", # TODO: xor
  "&",  "|",  # TODO: xor for bit operation
]

proc normalize(node: GeneValue) =
  if node.list.len == 0:
    return
  var first = node.list[0]
  if first.kind == GeneSymbol:
    if first.symbol in BINARY_OPS:
      var op = node.op
      node.list.delete 0
      node.list.insert op, 0
      node.op = first
