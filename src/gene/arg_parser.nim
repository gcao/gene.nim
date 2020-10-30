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

  ArgDataType* = enum
    ArgInt
    ArgBool
    ArgString

  ArgMatcher* = ref object
    case kind*: ArgMatcherKind
    of ArgOption:
      short_name*: string
      long_name*: string
      toggle*: bool          # if false, expect a value
    of ArgPositional:
      arg_name*: string
    description*: string
    required*: bool
    multiple*: bool
    data_type*: ArgDataType  # int, string, what else?
    # default*: GeneValue

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

proc name*(self: ArgMatcher): string =
  case self.kind:
  of ArgOption:
    if self.long_name == "":
      return self.short_name
    else:
      return self.long_name
  of ArgPositional:
    return self.arg_name

proc parse_data_type(self: var ArgMatcher, input: GeneValue) =
  var value = input.gene.props.get_or_default("type", nil)
  if value == new_gene_symbol("int"):
    self.data_type = ArgInt
  elif value == new_gene_symbol("bool"):
    self.data_type = ArgBool
  else:
    self.data_type = ArgString

proc parse*(self: var ArgMatcherRoot, schema: GeneValue) =
  if schema.vec[0] == new_gene_symbol("program"):
    self.include_program = true
  for i, item in schema.vec:
    # Check whether first item is program
    if i == 0 and item == new_gene_symbol("program"):
      self.include_program = true
      continue

    case item.gene.op.symbol:
    of "option":
      var option = ArgMatcher(kind: ArgOption)
      option.parse_data_type(item)
      option.toggle = item.gene.props.get_or_default("toggle", false)
      if option.toggle:
        option.data_type = ArgBool
      else:
        option.multiple = item.gene.props.get_or_default("multiple", false)
        option.required = item.gene.props.get_or_default("required", false)
      for item in item.gene.data:
        if item.symbol[0] == '-':
          if item.symbol.len == 2:
            option.short_name = item.symbol
          else:
            option.long_name = item.symbol
        else:
          option.description = item.str

      if option.short_name != "":
        self.options[option.short_name] = option
      if option.long_name != "":
        self.options[option.long_name] = option

    of "argument":
      var arg = ArgMatcher(kind: ArgPositional)
      arg.arg_name = item.gene.data[0].symbol
      arg.parse_data_type(item)
      var is_last = i == schema.vec.len - 1
      if is_last:
        arg.multiple = item.gene.props.get_or_default("multiple", false)
        arg.required = item.gene.props.get_or_default("required", false)
      else:
        arg.required = true
      self.args.add(arg)

    else:
      not_allowed()

proc parse*(self: var ArgMatcherRoot, schema: string) =
  self.parse(read(schema))

proc translate(self: ArgMatcher, value: string): GeneValue =
  if self.data_type == ArgInt:
    return value.parse_int
  elif self.data_type == ArgBool:
    return value.parse_bool
  else:
    return new_gene_string(value)

proc match*(self: var ArgMatcherRoot, input: seq[string]): ArgMatchingResult =
  result = ArgMatchingResult(kind: AmSuccess)
  var arg_index = 0

  var i = 0
  if self.include_program:
    result.program = input[i]
    i += 1
  while i < input.len:
    var item = input[i]
    i += 1
    if item[0] == '-':
      if self.options.hasKey(item):
        var option = self.options[item]
        if option.toggle:
          result.options[option.name] = true
        else:
          var value = input[i]
          i += 1
          if option.multiple:
            for s in value.split(","):
              var v = option.translate(s)
              if result.options.hasKey(option.name):
                result.options[option.name].vec.add(v)
              else:
                result.options[option.name] = @[v]
          else:
            result.options[option.name] = option.translate(value)
      else:
        echo "Unknown option: " & $item
    else:
      if arg_index < self.args.len:
        var arg = self.args[arg_index]
        var name = arg.name
        var value = arg.translate(item)
        if arg.multiple:
          if result.args.hasKey(name):
            result.args[name].vec.add(value)
          else:
            result.args[name] = @[value]
        else:
          arg_index += 1
          result.args[name] = value
      else:
        echo "Too many arguments are found. Ignoring " & $item

proc match*(self: var ArgMatcherRoot, input: string): ArgMatchingResult =
  return self.match(input.strip(leading=true).split(" "))
