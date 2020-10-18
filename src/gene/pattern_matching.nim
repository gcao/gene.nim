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

  # Match the whole input or the first child (if running in ArgumentMode)
  # Can have name, match nothing, or have group of children
  RootMatcher* = ref object
    mode*: MatchingMode
    children*: seq[Matcher]

  MatcherKind* = enum
    MatchOp
    MatchProp
    MatchData

  Matcher* = ref object
    root*: RootMatcher
    kind*: MatcherKind
    name*: string
    children*: seq[Matcher]
    required*: bool

  MatchResultKind* = enum
    MatchSuccess
    MatchMissingFields
    MatchWrongType # E.g. map is passed but array or gene is expected

  MatchedField* = ref object
    name*: string
    value*: GeneValue # Either value_expr or value must be given
    value_expr*: Expr # Expression for calculating default value

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

proc new_matcher(root: RootMatcher, kind: MatcherKind): Matcher =
  result = Matcher(
    root: root,
    kind: kind,
  )

proc new_matched_field(name: string, value: GeneValue): MatchedField =
  result = MatchedField(
    name: name,
    value: value,
  )

#################### Parsing #####################

proc parse(self: var RootMatcher, group: var seq[Matcher], v: GeneValue) =
  case v.kind:
  of GeneSymbol:
    var m = new_matcher(self, MatchData)
    group.add(m)
    if v.symbol != "_":
      m.name = v.symbol
  of GeneVector:
    for item in v.vec:
      if item.kind == GeneVector:
        var m = new_matcher(self, MatchData)
        group.add(m)
        self.parse(m.children, item)
      else:
        self.parse(group, item)
  else:
    todo()

proc parse*(self: var RootMatcher, v: GeneValue) =
  self.parse(self.children, v)

#################### Matching ####################

proc match(self: Matcher, input: GeneValue, state: MatchState, r: MatchResult) =
  case self.kind:
  of MatchData:
    var name = self.name
    var value: GeneValue
    case input.kind:
    of GeneGene:
      value = input.gene.data[state.data_index]
    of GeneVector:
      value = input.vec[state.data_index]
    else:
      todo()
    if name != "":
      r.fields.add(new_matched_field(name, value))
    state.data_index += 1
    var child_state = MatchState()
    for child in self.children:
      child.match(value, child_state, r)
  else:
    todo()

proc match*(self: RootMatcher, input: GeneValue): MatchResult =
  result = MatchResult()
  var children = self.children
  var state = MatchState()
  for child in children:
    child.match(input, state, result)
