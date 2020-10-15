# import ./types

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

  Matcher* = ref object of RootObj
    name*: string
    required*: bool

  MatcherGroup* = ref object of Matcher
    children*: Matcher

  PlaceholderMatcher* = ref object of Matcher

  RootMatcher* = ref object of Matcher

##################################################

# proc new_matchers(v: GeneValue): Matchers =
#   case v.kind:
#   of GeneSymbol
