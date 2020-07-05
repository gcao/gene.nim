import tables

import types

type
  VM* = ref object
    cur_stack*: Stack
    pos*: int

  Stack* {.acyclic.} = ref object
    parent*: Stack
    cur_scope*: Scope
    default*: GeneValue

  Scope* = ref object
    members*: Table[string, GeneValue]

#################### Scope #######################

proc new_scope*(): Scope = Scope(members: Table[string, GeneValue]())

proc `[]`*(scope: Scope, key: string): GeneValue = scope.members[key]

proc `[]=`*(scope: Scope, key: string, val: GeneValue) =
  scope.members[key] = val

#################### VM ##########################

proc new_vm*(): VM =
  return VM(
    cur_stack: Stack(cur_scope: new_scope()),
    pos: -1,
  )
