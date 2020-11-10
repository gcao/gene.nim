import parseopt

import ../gene/types

type
  Options* = ref object
    debugging*: bool
    repl*: bool
    file*: string
    args*: seq[string]
    benchmark*: bool
    print_result*: bool

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
  for kind, key, value in getOpt():
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
      of "debug", "d":
        result.debugging = true
      of "benchmark", "b":
        result.benchmark = true
      of "print_result", "p":
        result.print_result = true
      of "":
        expect_args = true
      else:
        # echo "Unknown option: ", key
        discard

    of cmdEnd:
      discard