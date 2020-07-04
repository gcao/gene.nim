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

proc new_scope*(): Scope = Scope(members: Table[string, GeneValue]())

proc new_vm*(): VM =
  result.cur_stack = Stack(cur_scope: new_scope())
  result.pos = -1
