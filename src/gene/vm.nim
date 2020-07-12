import tables

import ./types

const CORE_REGISTERS* = 8

type
  ## This is the root of a running application
  Application* = ref object
    ns: Namespace

  VM* = ref object
    root_ns*: Namespace
    cur_stack*: Stack
    pos*: int

  Namespace* = ref object
    parent*: Namespace
    members*: Table[string, GeneValue]

  Stack* {.acyclic.} = ref object
    parent*: Stack
    cur_ns*: Namespace
    cur_scope*: Scope
    registers: array[CORE_REGISTERS, GeneValue]
    more_regs: seq[GeneValue]

  Scope* = ref object
    parent*: Scope
    members*: Table[string, GeneValue]

#################### Interfaces ##################

#################### Namespace ###################

proc new_namespace*(): Namespace = Namespace(members: Table[string, GeneValue]())

proc `[]`*(self: Namespace, key: string): GeneValue = self.members[key]

proc `[]=`*(self: var Namespace, key: string, val: GeneValue) =
  self.members[key] = val

#################### Application #######################

let APP* = Application(ns: new_namespace())

#################### Scope #######################

proc new_scope*(): Scope = Scope(members: Table[string, GeneValue]())

proc hasKey*(self: Scope, key: string): bool = self.members.hasKey(key)

proc `[]`*(self: Scope, key: string): GeneValue = self.members[key]

proc `[]=`*(self: var Scope, key: string, val: GeneValue) =
  self.members[key] = val

#################### Stack #######################

proc new_stack*(ns: Namespace): Stack =
  return Stack(
    cur_ns: ns,
    cur_scope: new_scope(),
    more_regs: @[],
  )

proc grow*(self: var Stack): Stack =
  return Stack(
    parent: self,
    cur_ns: self.cur_ns,
    cur_scope: new_scope(),
    more_regs: @[],
  )

proc default*(self: var Stack): GeneValue = self.registers[0]

proc `default=`*(self: var Stack, val: GeneValue): GeneValue =
  self.registers[0] = val

proc `[]`*(self: var Stack, i: int): GeneValue =
  if i < CORE_REGISTERS:
    return self.registers[i]
  else:
    return self.more_regs[i]

proc `[]`*(self: var Stack, name: string): GeneValue =
  if self.cur_scope.hasKey(name):
    return self.cur_scope[name]
  else:
    return self.cur_ns[name]

proc `[]=`*(self: var Stack, i: int, val: GeneValue) =
  if i < CORE_REGISTERS:
    self.registers[i] = val
  else:
    self.more_regs[i] = val

#################### VM ##########################

proc new_vm*(): VM =
  var ns = new_namespace()
  return VM(
    root_ns: ns,
    cur_stack: new_stack(ns),
    pos: -1,
  )

proc `[]`*(self: VM, key: string): GeneValue =
  if self.cur_stack.cur_scope.hasKey(key):
    return self.cur_stack.cur_scope[key]
  else:
    return self.cur_stack.cur_ns[key]
