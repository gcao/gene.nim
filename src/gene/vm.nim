import tables, sequtils

import ./types

const CORE_REGISTERS* = 8

type
  VM* = ref object
    cur_stack*: Stack
    cur_block*: Block
    pos*: int

  Caller* = ref object
    stack*: Stack
    blk*: Block
    pos*: int

  Stack* {.acyclic.} = ref object
    self*: GeneValue
    cur_ns*: Namespace
    cur_scope*: Scope
    registers: array[CORE_REGISTERS, GeneValue]
    more_regs: seq[GeneValue]
    caller*: Caller

  Scope* = ref object
    parent*: Scope
    members*: Table[int, GeneValue]

  FunctionScope* = ref object
    parent*: Scope
    cache*: seq[GeneValue]
    mappings*: Table[string, int]

  StackManager* = ref object
    cache*: seq[Stack]

var StackMgr* = StackManager(cache: @[])

#################### Interfaces ##################

#################### Namespace ###################

proc `[]`*(self: Namespace, key: int): GeneValue = self.members[key]

proc `[]=`*(self: var Namespace, key: int, val: GeneValue) =
  self.members[key] = val

#################### Scope #######################

proc new_scope*(): Scope = Scope(members: Table[int, GeneValue]())

proc hasKey*(self: Scope, key: int): bool = self.members.hasKey(key)

proc `[]`*(self: Scope, key: int): GeneValue = self.members[key]

proc `[]=`*(self: var Scope, key: int, val: GeneValue) =
  self.members[key] = val

#################### Stack #######################

proc new_stack*(): Stack =
  return Stack(
    more_regs: @[],
  )

proc new_stack*(ns: Namespace): Stack =
  return Stack(
    cur_ns: ns,
    cur_scope: new_scope(),
    more_regs: @[],
  )

proc grow*(self: var Stack): Stack =
  return Stack(
    cur_ns: self.cur_ns,
    cur_scope: new_scope(),
    more_regs: @[],
  )

proc reset*(self: var Stack) =
  self.cur_ns = nil
  self.cur_scope = nil
  self.self = nil
  for i in 0..<CORE_REGISTERS:
    self.registers[i] = nil
  self.more_regs.delete(0, self.more_regs.len)
  self.caller = nil

proc default*(self: var Stack): GeneValue = self.registers[0]

proc `default=`*(self: var Stack, val: GeneValue): GeneValue =
  self.registers[0] = val

proc `[]`*(self: var Stack, i: int): GeneValue =
  if i < CORE_REGISTERS:
    return self.registers[i]
  else:
    return self.more_regs[i]

proc get*(self: var Stack, key: int): GeneValue =
  if self.cur_scope.hasKey(key):
    return self.cur_scope[key]
  else:
    return self.cur_ns[key]

proc `[]=`*(self: var Stack, i: int, val: GeneValue) =
  if i < CORE_REGISTERS:
    self.registers[i] = val
  else:
    self.more_regs[i] = val

#################### StackManager ################

proc get*(self: var StackManager): Stack =
  if self.cache.len > 0:
    return self.cache.pop()
  else:
    return new_stack()

proc free*(self: var StackManager, stack: var Stack) =
  stack.reset()
  self.cache.add(stack)

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

#################### Caller ######################

proc new_caller*(stack: Stack, blk: Block, pos: int): Caller =
  return Caller(stack: stack, blk: blk, pos: pos)
