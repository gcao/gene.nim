# See https://nim-lang.org/docs/nimprof.html
# Compiles with --profiler:on and a report will automatically be generated
# nimble build -d:release --profiler:on
# import nimprof

import times, parseopt, strutils

import gene/types
import gene/vm
import gene/parser
import gene/interpreter
import gene/compiler
import gene/cpu

var running_mode = RunningMode.Interpreted
var file: string

proc parseOptions() =
  for kind, key, value in getOpt():
    case kind
    of cmdArgument:
      file = key

    of cmdLongOption, cmdShortOption:
      case key
      of "mode", "m":
        if value.cmpIgnoreCase("compiled") == 0:
          running_mode = RunningMode.Compiled
      else:
        echo "Unknown option: ", key

    of cmdEnd:
      discard

proc main() =
  parseOptions()

  if file == "":
    todo("REPL Support")
  else:
    var vm = new_vm()
    if running_mode == Interpreted:
      let parsed = read_all(readFile(file))
      let start = cpuTime()
      let result = vm.eval(parsed)
      echo "Time: " & $(cpuTime() - start)
      echo result.num
    else:
      var c = new_compiler()
      var module = c.compile(readFile(file))
      let start = cpuTime()
      let result = vm.run(module)
      echo "Time: " & $(cpuTime() - start)
      echo result.num

when isMainModule:
  main()
