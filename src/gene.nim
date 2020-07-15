# See https://nim-lang.org/docs/nimprof.html
# Compiles with --profiler:on and a report will automatically be generated
# nimble build -d:release --profiler:on
# import nimprof
# setSamplingFrequency(1)

import times, parseopt, strutils, logging

import gene/types
import gene/vm
import gene/parser
import gene/interpreter
import gene/compiler
import gene/cpu

var file: string
var running_mode = RunningMode.Interpreted
var debugging = false

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
      of "d":
        debugging = true
      else:
        echo "Unknown option: ", key

    of cmdEnd:
      discard

proc setupLogger() =
  var consoleLogger = newConsoleLogger()
  addHandler(consoleLogger)
  consoleLogger.levelThreshold = Level.lvlInfo
  if debugging:
    consoleLogger.levelThreshold = Level.lvlDebug

proc quit_with*(errorcode: int, newline = false) =
  if newline:
    echo ""
  echo "Good bye!"
  quit(errorcode)

proc main() =
  parseOptions()
  setupLogger()

  if file == "":
    echo "Welcome to interactive Gene!"
    echo "Note: press Ctrl-D to exit."

    if debugging:
      echo "The logger level is set to DEBUG."

    var vm = new_vm()
    while true:
      write(stdout, "Gene> ")
      try:
        var s = readLine(stdin)
        case s:
        of "": continue
        else: discard

        let r = vm.eval(s)
        case r.kind:
        else:
          writeLine(stdout, r)
      except EOFError:
        quit_with(0, true)
      except Exception as e:
        var s = e.getStackTrace()
        s.stripLineEnd
        echo s
        echo "$#: $#" % [$e.name, $e.msg]
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
