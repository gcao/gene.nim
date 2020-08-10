import random, hashes

type
  Oid* = ref object
    id*: int

proc genOid*(): Oid =
  return Oid(id: rand(10000))

proc hash*(id: Oid): Hash =
  return hash(id.id)
