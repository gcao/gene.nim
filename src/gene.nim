# See https://nim-lang.org/docs/nimprof.html
# Compiles with --profiler:on and a report will automatically be generated
# nimble build -d:release --profiler:on
# import nimprof
# setSamplingFrequency(1)

import times, logging, os

import gene/types
import gene/interpreter
import gene/interpreter_extras
import gene/repl
import cmdline/option_parser

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

proc init_vm() =
  init_app_and_vm()
  VM.init_extras()
  VM.load_core_module()
  VM.load_gene_module()
  VM.load_genex_module()

proc main() =
  var options = parse_options()
  setup_logger(options.debugging)

  init_vm()
  VM.repl_on_error = options.repl_on_error
  if options.repl:
    var frame = VM.eval_prepare()
    discard repl(VM, frame, eval_only, false)
  else:
    var file = options.file
    VM.init_package(parent_dir(file))
    let start = cpu_time()
    let result = VM.run_file(file)
    if options.print_result:
      echo result
    if options.benchmark:
      echo "Time: " & $(cpu_time() - start)

when isMainModule:
  main()
