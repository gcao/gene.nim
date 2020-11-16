# See https://nim-lang.org/docs/nimprof.html
# Compiles with --profiler:on and a report will automatically be generated
# nimble build -d:release --profiler:on
# import nimprof
# setSamplingFrequency(1)

# TODO: readline support for REPL
# https://stackoverflow.com/questions/61079605/how-to-write-a-text-prompt-in-nim-that-has-readline-style-line-editing
# https://github.com/jangko/nim-noise
#
# Ctrl-C to cancel current input

import times, strutils, logging, os, posix

import gene/types
import gene/parser
import gene/interpreter
import cmdline/option_parser

# https://rosettacode.org/wiki/Handle_a_signal#Nim
type KeyboardInterrupt = object of CatchableError
proc handler() {.noconv.} =
  var nmask, omask: Sigset
  discard sigemptyset(nmask)
  discard sigemptyset(omask)
  discard sigaddset(nmask, SIGINT)
  if sigprocmask(SIG_UNBLOCK, nmask, omask) == -1:
    raiseOSError(osLastError())
  raise new_exception(KeyboardInterrupt, "Keyboard Interrupt")
set_control_chook(handler)

proc setup_logger(debugging: bool) =
  var console_logger = new_console_logger()
  add_handler(console_logger)
  console_logger.level_threshold = Level.lvlInfo
  if debugging:
    console_logger.level_threshold = Level.lvlDebug

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
  var options = parse_options()
  setup_logger(options.debugging)

  if options.repl:
    echo "Welcome to interactive Gene!"
    echo "Note: press Ctrl-D to exit."

    if options.debugging:
      echo "The logger level is set to DEBUG."

    var vm = init_vm()
    var frame = vm.eval_prepare()
    var input = ""
    while true:
      write(stdout, prompt("Gene> "))
      try:
        input = input & read_line(stdin)
        input = input.strip
        case input:
        of "":
          continue
        of "help":
          echo "TODO"
        else:
          discard

        var r = vm.eval_only(frame, input)
        write_line(stdout, r)

        # Reset input
        input = ""
      except EOFError:
        quit_with(0, true)
      except ParseError as e:
        # Incomplete expression
        if e.msg.starts_with("EOF"):
          continue
        else:
          input = ""
      except KeyboardInterrupt:
        echo()
        input = ""
      except Exception as e:
        input = ""
        var s = e.getStackTrace()
        s.strip_line_end()
        echo s
        echo error("$#: $#" % [$e.name, $e.msg])

  else:
    var vm = init_vm()
    var file = options.file
    vm.init_package(parent_dir(file))
    let start = cpu_time()
    let result = vm.run_file(file)
    if options.print_result:
      echo result
    if options.benchmark:
      echo "Time: " & $(cpu_time() - start)

when isMainModule:
  main()
