import tables, strutils

import ./types
import ./parser

type
  ArgMatcherRoot* = ref object
    include_program*: bool
    options*: Table[string, ArgMatcher]
    args*: seq[ArgMatcher]
    # Extra is always returned if "-- ..." is found.

  ArgMatcherKind* = enum
    ArgOption      # options
    ArgPositional  # positional arguments

  ArgMatcher* = ref object
    kind*: ArgMatcherKind
    name*: string
    short_name*: string
    description*: string
    toggle*: bool          # if false, expect a value
    required*: bool
    position*: int
    multiple*: bool
    # data_type*: ArgType  # int, string, what else?

  ArgMatchingResultKind* = enum
    AmSuccess
    AmFailure

  ArgMatchingResult* = ref object
    kind*: ArgMatchingResultKind
    program*: string
    options*: Table[string, GeneValue]
    args*: Table[string, GeneValue]
    extra*: seq[string]
    failure*: string  # if kind == AmFailure

proc new_matcher*(): ArgMatcherRoot =
  return ArgMatcherRoot(
    options: Table[string, ArgMatcher](),
  )

proc parse*(self: var ArgMatcherRoot, schema: GeneValue) =
  if schema.vec[0] == new_gene_symbol("program"):
    self.include_program = true
  for item in schema.vec:
    case item.gene.op.symbol:
    of "option":
      todo()
    of "argument":
      todo()
    else:
      todo()

proc parse*(self: var ArgMatcherRoot, schema: string) =
  self.parse(read(schema))

proc match*(self: var ArgMatcherRoot, input: seq[string]): ArgMatchingResult =
  result = ArgMatchingResult(kind: AmSuccess)

proc match*(self: var ArgMatcherRoot, input: string): ArgMatchingResult =
  return self.match(input.split(" "))
