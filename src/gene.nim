# See https://nim-lang.org/docs/nimprof.html
# Compiles with --profiler:on and a report will automatically be generated
# nimble build -d:release --profiler:on
# import nimprof
# setSamplingFrequency(1)

import times, logging, os

import gene/types
import gene/interpreter
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

proc init_vm(): VM =
  result = new_vm()
  result.load_core_module()
  result.load_gene_module()
  result.load_genex_module()

proc main() =
  var options = parse_options()
  setup_logger(options.debugging)

  var vm = init_vm()
  vm.repl_on_error = options.repl_on_error
  if options.repl:
    var frame = vm.eval_prepare()
    discard repl(vm, frame, eval_only, false)
  else:
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
