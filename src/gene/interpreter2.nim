import ./types
import ./parser
import ./translator2

proc prepare*(self: VirtualMachine, code: string): GeneValue =
  var parsed = read_all(code)
  translate(parsed)

proc eval*(self: VirtualMachine, frame: Frame, expr: GeneValue): GeneValue =
  case expr.kind:
  of GeneWithType:
    todo()
  else:
    result = expr   # TODO: return a copy

proc eval*(self: VirtualMachine, code: string): GeneValue =
  var module = new_module()
  var frame = FrameMgr.get(FrModule, module.root_ns, new_scope())
  self.eval(frame, self.prepare(code))
