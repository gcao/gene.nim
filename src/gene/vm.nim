import tables, sequtils

import ./types

const CORE_REGISTERS* = 8

type
  VM* = ref object
    cur_stack*: Stack
    cur_block*: Block
    pos*: int

  Stack* {.acyclic.} = ref object
    self*: GeneValue
    cur_ns*: Namespace
    cur_scope*: Scope
    registers: array[CORE_REGISTERS, GeneValue]
    more_regs: seq[GeneValue]
    caller_stack*: Stack
    caller_blk*: Block
    caller_pos*: int

  Scope* = ref object
    parent*: Scope
    members*: Table[int, GeneValue]

  FunctionScope* = ref object
    parent*: Scope
    cache*: seq[GeneValue]
    mappings*: Table[string, int]

  StackManager* = ref object
    cache*: seq[Stack]

  ScopeManager = ref object
    cache*: seq[Scope]

var StackMgr* = StackManager(cache: @[])
var ScopeMgr* = ScopeManager(cache: @[])

#################### Interfaces ##################

proc get*(self: var ScopeManager): Scope {.inline.}

#################### Namespace ###################

proc `[]`*(self: Namespace, key: int): GeneValue {.inline.} = self.members[key]

proc `[]=`*(self: var Namespace, key: int, val: GeneValue) {.inline.} =
  self.members[key] = val

#################### Scope #######################

proc new_scope*(): Scope = Scope(members: Table[int, GeneValue]())

proc reset*(self: var Scope) =
  self.members.clear()

proc hasKey*(self: Scope, key: int): bool {.inline.} = self.members.hasKey(key)

proc `[]`*(self: Scope, key: int): GeneValue {.inline.} = self.members[key]

proc `[]=`*(self: var Scope, key: int, val: GeneValue) {.inline.} =
  self.members[key] = val

#################### Stack #######################

proc new_stack*(): Stack =
  return Stack(
    more_regs: @[],
  )

proc new_stack*(ns: Namespace): Stack =
  return Stack(
    cur_ns: ns,
    cur_scope: ScopeMgr.get(),
    more_regs: @[],
  )

proc grow*(self: var Stack): Stack =
  return Stack(
    cur_ns: self.cur_ns,
    cur_scope: ScopeMgr.get(),
    more_regs: @[],
  )

proc reset*(self: var Stack) =
  self.self = nil
  self.cur_ns = nil
  self.cur_scope = nil
  for i in 0..<CORE_REGISTERS:
    self.registers[i] = nil
  self.more_regs.delete(0, self.more_regs.len)
  self.caller_stack = nil
  self.caller_blk = nil
  self.caller_pos = 0

proc default*(self: var Stack): GeneValue {.inline.} = self.registers[0]

proc `default=`*(self: var Stack, val: GeneValue): GeneValue {.inline.} =
  self.registers[0] = val

proc `[]`*(self: var Stack, i: int): GeneValue {.inline.} =
  if i < CORE_REGISTERS:
    return self.registers[i]
  else:
    return self.more_regs[i]

proc get*(self: var Stack, key: int): GeneValue {.inline.} =
  if self.cur_scope.hasKey(key):
    return self.cur_scope[key]
  else:
    return self.cur_ns[key]

proc `[]=`*(self: var Stack, i: int, val: GeneValue) {.inline.} =
  if i < CORE_REGISTERS:
    self.registers[i] = val
  else:
    self.more_regs[i] = val

#################### StackManager ################

proc get*(self: var StackManager): Stack {.inline.} =
  if self.cache.len > 0:
    return self.cache.pop()
  else:
    return new_stack()

proc free*(self: var StackManager, stack: var Stack) {.inline.} =
  stack.reset()
  self.cache.add(stack)

#################### ScopeManager ################

proc get*(self: var ScopeManager): Scope {.inline.} =
  if self.cache.len > 0:
    return self.cache.pop()
  else:
    return new_scope()

proc free*(self: var ScopeManager, scope: var Scope) {.inline.} =
  scope.reset()
  self.cache.add(scope)

#################### VM ##########################

proc new_vm*(): VM =
  var stack = StackMgr.get()
  stack.cur_ns = new_namespace()
  stack.cur_scope = new_scope()
  return VM(
    cur_stack: stack,
    pos: -1,
  )

proc `[]`*(self: VM, key: int): GeneValue =
  if self.cur_stack.cur_scope.hasKey(key):
    return self.cur_stack.cur_scope[key]
  else:
    return self.cur_stack.cur_ns[key]
