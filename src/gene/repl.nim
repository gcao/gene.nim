import strutils, os, posix, noise

import ./types
import ./parser

# TODO: readline support
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
    raise_os_error(os_last_error())
  raise new_exception(KeyboardInterrupt, "Keyboard Interrupt")

# https://stackoverflow.com/questions/5762491/how-to-print-color-in-console-using-system-out-println
# https://en.wikipedia.org/wiki/ANSI_escape_code
proc error(message: string): string =
  return "\u001B[31m" & message & "\u001B[0m"

proc repl*(self: VM, frame: Frame, eval: Eval, return_value: bool): GeneValue =
  echo "Welcome to interactive Gene!"
  echo "Note: press Ctrl-D to exit."

  var noise = Noise.init()
  let prompt = Styler.init(fgGreen, "Gene> ")
  noise.set_prompt(prompt)
  var history_file = "/tmp/gene_history"
  discard noise.history_load(history_file)
  set_control_c_hook(handler)
  try:
    var input = ""
    while true:
      try:
        let ok = noise.read_line()
        if not ok:
          break

        input = input & noise.get_line()
        input = input.strip()
        case input:
        of "":
          continue
        of "help":
          echo "TODO"
          input = ""
          continue
        of "exit", "quit":
          quit(0)
        else:
          discard

        result = eval(self, frame, input)
        stdout.write_line(result)

        noise.history_add(input)

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
      except CatchableError as e:
        result = GeneNil
        input = ""
        var s = e.get_stack_trace()
        s.strip_line_end()
        echo s
        echo error("$#: $#" % [$e.name, $e.msg])
  finally:
    unset_control_c_hook()

  discard noise.history_save(history_file)
  if not return_value:
    return GeneNil
