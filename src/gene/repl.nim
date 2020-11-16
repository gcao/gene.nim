import strutils, os, posix

import ./types
import ./parser

# TODO: readline support for REPL
# https://stackoverflow.com/questions/61079605/how-to-write-a-text-prompt-in-nim-that-has-readline-style-line-editing
# https://github.com/jangko/nim-noise
#
# Ctrl-C to cancel current input

type
  KeyboardInterrupt = object of CatchableError

  Eval = proc(self: VM, frame: Frame, code: string): GeneValue

# https://rosettacode.org/wiki/Handle_a_signal#Nim
proc handler() {.noconv.} =
  var nmask, omask: Sigset
  discard sigemptyset(nmask)
  discard sigemptyset(omask)
  discard sigaddset(nmask, SIGINT)
  if sigprocmask(SIG_UNBLOCK, nmask, omask) == -1:
    raiseOSError(osLastError())
  raise new_exception(KeyboardInterrupt, "Keyboard Interrupt")

proc prompt(message: string): string =
  return "\u001B[36m" & message & "\u001B[0m"

# https://stackoverflow.com/questions/5762491/how-to-print-color-in-console-using-system-out-println
# https://en.wikipedia.org/wiki/ANSI_escape_code
proc error(message: string): string =
  return "\u001B[31m" & message & "\u001B[0m"

proc repl*(self: VM, frame: Frame, eval: Eval) =
  echo "Welcome to interactive Gene!"
  echo "Note: press Ctrl-D to exit."

  set_control_c_hook(handler)
  var input = ""
  while true:
    stdout.write(prompt("Gene> "))
    try:
      input = input & stdin.read_line()
      input = input.strip()
      case input:
      of "":
        continue
      of "help":
        echo "TODO"
        input = ""
        continue
      else:
        discard

      var r = eval(self, frame, input)
      stdout.write_line(r)

      # Reset input
      input = ""
    except EOFError:
      break
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
      var s = e.get_stack_trace()
      s.strip_line_end()
      echo s
      echo error("$#: $#" % [$e.name, $e.msg])

  unset_control_c_hook()
