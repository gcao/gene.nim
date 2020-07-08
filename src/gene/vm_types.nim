import tables

import ./types

type
  VM* = ref object
    cur_ns*: Namespace
    cur_stack*: Stack
    pos*: int

  Namespace* = ref object
    parent*: Namespace
    members*: Table[string, GeneValue]

  Stack* {.acyclic.} = ref object
    parent*: Stack
    cur_scope*: Scope
    default*: GeneValue

  Scope* = ref object
    parent*: Scope
    members*: Table[string, GeneValue]

#################### Interfaces ##################

proc new_scope*(): Scope

#################### Namespace ###################

proc new_namespace*(): Namespace = Namespace(members: Table[string, GeneValue]())

proc `[]`*(self: Namespace, key: string): GeneValue = self.members[key]

proc `[]=`*(self: var Namespace, key: string, val: GeneValue) =
  self.members[key] = val

#################### Stack #######################

proc new_stack*(): Stack = Stack(cur_scope: new_scope())

proc grow*(self: var Stack): Stack = Stack(parent: self, cur_scope: new_scope())

#################### Scope #######################

proc new_scope*(): Scope = Scope(members: Table[string, GeneValue]())

proc hasKey*(self: Scope, key: string): bool = self.members.hasKey(key)

proc `[]`*(self: Scope, key: string): GeneValue = self.members[key]

proc `[]=`*(self: var Scope, key: string, val: GeneValue) =
  self.members[key] = val

#################### VM ##########################

proc new_vm*(): VM =
  return VM(
    cur_ns: new_namespace(),
    cur_stack: new_stack(),
    pos: -1,
  )

proc `[]`*(self: VM, key: string): GeneValue =
  if self.cur_stack.cur_scope.hasKey(key):
    return self.cur_stack.cur_scope[key]
  else:
    return self.cur_ns[key]
