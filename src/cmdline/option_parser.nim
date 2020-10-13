import parseopt

import ../gene/types

type
  Options* = ref object
    debugging*: bool
    repl*: bool
    file*: string
    args*: seq[string]

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
      of "":
        expect_args = true
      else:
        echo "Unknown option: ", key

    of cmdEnd:
      discard