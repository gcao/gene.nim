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
    elif op.symbol == "=":
      var first = node.list[0]
      var second = node.list[1]
      case first.kind:
      of GeneSymbol:
        self.cur_stack.cur_scope[first.symbol] = self.eval(second)
      else: todo()
  else: todo()

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
  else: todo()

proc eval*(self: var VM, buffer: string): GeneValue =
  var parsed = read_all(buffer)
  for node in parsed:
    result = self.eval node
  return

proc normalize(node: GeneValue) =
  if node.list.len == 0:
    return
  var first = node.list[0]
  if first.kind == GeneSymbol:
    if first.symbol in ["=", "+", "-", "*", "/"]:
      var op = node.op
      node.list.delete 0
      node.list.insert op, 0
      node.op = first
