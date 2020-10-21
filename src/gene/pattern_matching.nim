import ./types, strutils

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
    default_value*: GeneValue
    splat*: bool
    min_left*: int # Minimum number of args following this
    children*: seq[Matcher]
    # required*: bool # computed property: true if splat is false and default value is not given

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
    # prop_processed*: seq[string]
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

proc required(self: Matcher): bool =
  return self.default_value == nil and not self.splat

#################### Parsing #####################

# proc calc_min_left*(self: var Matcher) =
#   var min_left = 0
#   for i in (self.children.len - 1)..0:
#     var m = self.children[i]
#     m.min_left = min_left
#     if m.required:
#       min_left += 1

proc calc_min_left*(self: var RootMatcher) =
  var min_left = 0
  var i = self.children.len
  while i > 0:
    i -= 1
    var m = self.children[i]
    # m.calc_min_left
    m.min_left = min_left
    if m.required:
      min_left += 1

proc parse(self: var RootMatcher, group: var seq[Matcher], v: GeneValue) =
  case v.kind:
  of GeneSymbol:
    var m = new_matcher(self, MatchData)
    group.add(m)
    if v.symbol != "_":
      if v.symbol.endsWith("..."):
        m.name = v.symbol[0..^4]
        m.splat = true
      else:
        m.name = v.symbol
  of GeneVector:
    var i = 0
    while i < v.vec.len:
      var item = v.vec[i]
      i += 1
      if item.kind == GeneVector:
        var m = new_matcher(self, MatchData)
        group.add(m)
        self.parse(m.children, item)
      else:
        self.parse(group, item)
        if i < v.vec.len and v.vec[i] == new_gene_symbol("="):
          i += 1
          var last_matcher = group[^1]
          var value = v.vec[i]
          i += 1
          last_matcher.default_value = value
  else:
    todo()

proc parse*(self: var RootMatcher, v: GeneValue) =
  self.parse(self.children, v)
  self.calc_min_left

#################### Matching ####################

proc `[]`(self: GeneValue, i: int): GeneValue =
  case self.kind:
  of GeneGene:
    return self.gene.data[i]
  of GeneVector:
    return self.vec[i]
  else:
    not_allowed()

proc `len`(self: GeneValue): int =
  if self == nil:
    return 0
  case self.kind:
  of GeneGene:
    return self.gene.data.len
  of GeneVector:
    return self.vec.len
  else:
    not_allowed()

proc match(self: Matcher, input: GeneValue, state: MatchState, r: MatchResult) =
  case self.kind:
  of MatchData:
    var name = self.name
    var value: GeneValue
    if self.splat:
      value = new_gene_vec()
      for i in state.data_index..<input.len - self.min_left:
        value.vec.add(input[i])
        state.data_index += 1
    elif self.min_left < input.len - state.data_index:
      value = input[state.data_index]
      state.data_index += 1
    else:
      if self.default_value == nil:
        r.kind = MatchMissingFields
        return
      else:
        value = self.default_value # Default value
    if name != "":
      r.fields.add(new_matched_field(name, value))
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
