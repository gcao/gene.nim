import tables, strutils

import ./types

type
  ArgMatcherRoot* = ref object
    options*: Table[string, ArgMatcher]
    pri_args*: seq[ArgMatcher]
    sec_args*: seq[ArgMatcher]

  ArgMatcherKind* = enum
    ArgOption      # Options
    ArgPrimary     # positional arguments
    ArgSecondary   # positional arguments following "--"

  ArgMatcher* = ref object
    kind*: ArgMatcherKind
    name*: string
    short_name*: string
    description*: string
    required*: bool
    position*: int
    multiple*: bool
    # data_type*: ArgType  # int, string, what else?

  ArgMatchingResultKind* = enum
    AmSuccess
    AmFailure

  ArgMatchingResult* = ref object
    case kind*: ArgMatchingResultKind
    of AmSuccess:
      program*: string
      options*: Table[string, GeneValue]
      pri_args*: seq[string]
      sec_args*: seq[string]
    of AmFailure:
      failure*: string

proc new_matcher*(): ArgMatcherRoot =
  return ArgMatcherRoot(
    options: Table[string, ArgMatcher](),
  )

proc add_toggle*(self: var ArgMatcherRoot;
  short_name: string = "";
  name: string = "";
  required: bool = false
) =
  discard

proc match*(self: var ArgMatcherRoot, input: seq[string]): ArgMatchingResult =
  result = ArgMatchingResult(kind: AmSuccess)

proc match*(self: var ArgMatcherRoot, input: string): ArgMatchingResult =
  return self.match(input.split(" "))
