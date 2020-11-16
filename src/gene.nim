# See https://nim-lang.org/docs/nimprof.html
# Compiles with --profiler:on and a report will automatically be generated
# nimble build -d:release --profiler:on
# import nimprof
# setSamplingFrequency(1)

# TODO: readline support for REPL
# https://stackoverflow.com/questions/61079605/how-to-write-a-text-prompt-in-nim-that-has-readline-style-line-editing
# https://github.com/jangko/nim-noise
#
# TODO:
# Ctrl-C to cancel current line
# Ctrl-C Ctrl-C to exit

import times, strutils, logging, os

import gene/types
import gene/parser
import gene/interpreter
import cmdline/option_parser

# https://rosettacode.org/wiki/Handle_a_signal#Nim
type KeyboardInterrupt = object of CatchableError
proc handler() {.noconv.} =
  raise newException(KeyboardInterrupt, "Keyboard Interrupt")
setControlCHook(handler)

proc setupLogger(debugging: bool) =
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

# https://stackoverflow.com/questions/5762491/how-to-print-color-in-console-using-system-out-println
# https://en.wikipedia.org/wiki/ANSI_escape_code
proc error(message: string): string =
  return "\u001B[31m" & message & "\u001B[0m"

proc prompt(message: string): string =
  return "\u001B[36m" & message & "\u001B[0m"

proc init_vm(): VM =
  result = new_vm()
  result.load_core_module()
  result.load_gene_module()
  result.load_genex_module()

proc main() =
  var options = parseOptions()
  setupLogger(options.debugging)

  if options.repl:
    echo "Welcome to interactive Gene!"
    echo "Note: press Ctrl-D to exit."

    if options.debugging:
      echo "The logger level is set to DEBUG."

    var vm = init_vm()
    var frame = vm.eval_prepare()
    var input = ""
    var ctrl_c_caught = false
    while true:
      write(stdout, prompt("Gene> "))
      try:
        input = input & readLine(stdin)
        input = input.strip
        ctrl_c_caught = false
        case input:
        of "":
          continue
        of "help":
          echo "TODO"
        else:
          discard

        var r = vm.eval_only(frame, input)
        writeLine(stdout, r)

        # Reset input
        input = ""
      except EOFError:
        quit_with(0, true)
      except ParseError as e:
        # Incomplete expression
        if e.msg.startsWith("EOF"):
          continue
        else:
          input = ""
      except KeyboardInterrupt:
        if ctrl_c_caught:
          quit_with(1, true)
        else:
          ctrl_c_caught = true
          echo "\n"
          input = ""
      except Exception as e:
        input = ""
        var s = e.getStackTrace()
        s.stripLineEnd
        echo s
        echo error("$#: $#" % [$e.name, $e.msg])

  else:
    var vm = init_vm()
    var file = options.file
    vm.init_package(parentDir(file))
    let start = cpuTime()
    let result = vm.run_file(file)
    if options.print_result:
      echo result
    if options.benchmark:
      echo "Time: " & $(cpuTime() - start)

when isMainModule:
  main()
