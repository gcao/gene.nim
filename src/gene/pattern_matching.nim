import ./types

type
  # # Pattern matching
  # MatcherKind* = enum
  #   MatchRoot
  #   MatchPlaceholder # _
  #   MatchOne
  #   MatchMany
  #   MatchExact # exact symbol as marker

  # Matcher* = ref object
  #   name*: string
  #   required*: bool
  #   case kind*: MatcherKind
  #   of MatchOne:
  #     one_default*: GeneValue # Expression for default value
  #   of MatchExact:
  #     exact*: string
  #   else:
  #     discard

  MatchingMode* = enum
    MatchArgParsing # (fn f [a b] ...)
    MatchExpression # (match [a b] input): a and b will be defined
    MatchAssignment # ([a b] = input): a and b must be defined first

  RootMatcherKind* = enum
    RootNone # is only useful for argument parsing
    RootWithName
    RootChildren

  # Match the whole input or the first child (if running in ArgumentMode)
  # Can have name, match nothing, or have group of children
  RootMatcher* = ref object
    mode*: MatchingMode
    kind*: RootMatcherKind
    name*: string
    default*: GeneValue
    children*: seq[Matcher]

  MatcherKind* = enum
    MatchOp
    MatchProp
    MatchData

  Matcher* = ref object
    root*: RootMatcher
    kind*: MatcherKind
    name*: string

  MatchResultKind* = enum
    MatchSuccess
    MatchMissingFields
    MatchWrongType # E.g. map is passed but array or gene is expected

  MatchedField* = ref object
    name*: string
    value*: GeneValue # Either value_expr or value must be given
    value_expr*: Expr

  MatchResult* = ref object
    message*: string
    kind*: MatchResultKind
    # If success
    fields*: seq[MatchedField]
    assign_only*: bool # If true, no new variables will be defined
    # If missing fields
    missing*: seq[string]
    # If wrong type
    expect_type*: string
    found_type*: string

  # Internal state when applying the matcher to an input
  # Limited to one level
  MatchState = ref object
    prop_processed*: seq[string]
    data_index*: int

##################################################

proc new_arg_matcher*(): RootMatcher =
  result = RootMatcher(
    mode: MatchArgParsing,
  )

proc new_matcher*(root: RootMatcher, kind: MatcherKind): Matcher =
  result = Matcher(
    root: root,
    kind: kind,
  )

proc new_matched_field*(name: string, value: GeneValue): MatchedField =
  result = MatchedField(
    name: name,
    value: value,
  )

proc parse*(self: var RootMatcher, parent: Matcher, v: GeneValue) =
  if parent == nil:
    # On top level
    case v.kind:
    of GeneSymbol:
      if v.symbol == "_":
        self.kind = RootNone
      else:
        var m = new_matcher(self, MatchData)
        m.name = v.symbol
        self.children.add(m)
    of GeneVector:
      for item in v.vec:
        case item.kind:
        of GeneSymbol:
          if item.symbol == "_":
            var m = new_matcher(self, MatchData)
            self.children.add(m)
          else:
            var m = new_matcher(self, MatchData)
            m.name = item.symbol
            self.children.add(m)
        else:
          todo()
    else:
      todo()
  else:
    # On child levels
    todo()

proc parse*(self: var RootMatcher, v: GeneValue) =
  self.parse(nil, v)

proc match*(self: Matcher, input: GeneValue, state: MatchState, r: MatchResult) =
  case self.kind:
  of MatchData:
    var name = self.name
    var value = input.gene.data[state.data_index]
    if name != "":
      r.fields.add(new_matched_field(name, value))
    state.data_index += 1
  else:
    todo()

proc match*(self: RootMatcher, input: GeneValue): MatchResult =
  result = MatchResult()
  var children = self.children
  var state = MatchState()
  for child in children:
    child.match(input, state, result)
