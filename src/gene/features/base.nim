# import tables

# import ../types
# import ../translators

# type
#   FeatureKind* = enum
#     FkFeature
#     FkGroup

#   Feature* = ref object
#     name*: string
#     description*: string
#     active*: bool
#     case kind*: FeatureKind
#     of FkFeature:
#       translators*: Table[string,   Translator]
#       evaluators*:  Table[ExprKind, Evaluator]
#     of FkGroup:
#       children*: seq[Feature]
