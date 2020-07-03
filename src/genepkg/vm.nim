import types
import compiler

type
  VM* = ref object
    pos: uint

proc exec*(buffer: string): GeneValue =
  # compile(buffer)
  discard