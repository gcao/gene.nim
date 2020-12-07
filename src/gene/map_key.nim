import tables, hashes

type
  MapKey* = distinct int

var Keys*: seq[string] = @[]
var KeyMapping* = Table[string, MapKey]()

converter to_key*(i: int): MapKey {.inline.} =
  result = cast[MapKey](i)

proc add_key*(s: string): MapKey {.inline.} =
  Keys.add(s)
  result = Keys.len
  KeyMapping[s] = result

converter to_key*(s: string): MapKey {.inline.} =
  if KeyMapping.has_key(s):
    result = KeyMapping[s]
  else:
    result = add_key(s) 

converter key_to_s*(self: MapKey): string {.inline.} =
  result = Keys[cast[int](self)]

converter to_strings*(self: seq[MapKey]): seq[string] {.inline.} =
  for k in self:
    result.add(k)

converter to_keys*(self: seq[string]): seq[MapKey] {.inline.} =
  for item in self:
    result.add(item)

proc `==`*(this, that: MapKey): bool {.inline.} =
  result = cast[int](this) == cast[int](that)

proc hash*(self: MapKey): Hash {.inline.} =
  result = cast[int](self)

# Add "" as the first
let EMPTY_STRING_KEY* = add_key("")
let ROOT_NS_KEY* = add_key("<root>")
