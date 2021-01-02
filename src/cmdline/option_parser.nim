import parseopt, os

import ../gene/types

type
  InputMode* = enum
    ImDefault
    ImLine
    ImGene
    ImCsv

  Options* = ref object
    debugging*: bool
    repl*: bool
    repl_on_error*: bool
    file*: string
    args*: seq[string]
    benchmark*: bool
    print_result*: bool
    eval*: string
    input_mode*: InputMode
    skip_first*: bool

let shortNoVal = {'d'}
let longNoVal = @[
  "debug",
  "benchmark",
  "print-result", "pr",
  "repl-on-error",
  "csv",
]

# When running like
# <PROGRAM> --debug test.gene 1 2 3
# test.gene is invoked with 1, 2, 3 as argument
#
# When running like
# <PROGRAM> --debug -- 1 2 3
# 1, 2, 3 are passed as argument to REPL
proc parseOptions*(): Options =
  result = Options(
    repl: true,
  )
  var expect_args = false
  for kind, key, value in getOpt(commandLineParams(), shortNoVal, longNoVal):
    case kind
    of cmdArgument:
      if expect_args:
        result.args.add(key)
      else:
        expect_args = true
        result.repl = false
        result.file = key

    of cmdLongOption, cmdShortOption:
      if expect_args:
        result.args.add(key)
        result.args.add(value)
      case key
      of "eval", "e":
        result.repl = false
        result.eval = value
      of "debug", "d":
        result.debugging = true
      of "benchmark":
        result.benchmark = true
      of "print-result", "pr":
        result.print_result = true
      of "input-mode", "im":
        case value:
        of "csv":
          result.input_mode = ImCsv
        else:
          raise new_exception(ArgumentError, "Invalid input-mode: " & value)
      of "csv":
        result.input_mode = ImCsv
      of "repl-on-error":
        result.repl_on_error = true
      of "":
        expect_args = true
      else:
        # echo "Unknown option: ", key
        discard

    of cmdEnd:
      discard
