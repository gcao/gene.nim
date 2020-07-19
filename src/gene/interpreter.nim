import sequtils, tables

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
proc eval_fn*(self: var VM, node: GeneValue): GeneValue
proc call*(self: var VM, fn: Function, args: Arguments): GeneValue

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
    elif op.symbol == "if":
      return self.eval_if(node.gene_data)
    elif op.symbol == "fn":
      return self.eval_fn(node)
    elif op.symbol == "=":
      var first = node.gene_data[0]
      var second = node.gene_data[1]
      case first.kind:
      of GeneSymbol:
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
    return cast[GeneValue](self[name])
  of GeneGene:
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
