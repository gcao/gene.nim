# See https://nim-lang.org/docs/nimprof.html
# Compiles with --profiler:on and a report will automatically be generated
# nimble build -d:release --profiler:on
# import nimprof
# setSamplingFrequency(1)

import times, logging, os, streams, parsecsv

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

proc eval_includes(vm: VirtualMachine, frame: Frame, options: Options) =
  if options.include.len > 0:
    for file in options.include:
      discard vm.eval_only(frame, read_file(file))

proc main() =
  var options = parse_options()
  setup_logger(options.debugging)

  init_vm()
  VM.repl_on_error = options.repl_on_error
  if options.repl:
    var frame = VM.eval_prepare()
    VM.eval_includes(frame, options)
    discard repl(VM, frame, eval_only, false)
  elif options.eval != "":
    var frame = VM.eval_prepare()
    VM.eval_includes(frame, options)
    if options.input_mode == ImCsv:
      var code = VM.prepare(options.eval)
      var index_name = new_gene_symbol(options.index_name)
      var value_name = new_gene_symbol(options.value_name)
      var index = 0
      VM.def_member(frame, index_name, index, false)
      VM.def_member(frame, value_name, GeneNil, false)
      var parser: CsvParser
      parser.open(new_file_stream(stdin), "<STDIN>")
      while parser.read_row():
        var val = new_gene_vec()
        for item in parser.row:
          val.vec.add(item)
        VM.set_member(frame, index_name, index)
        VM.set_member(frame, value_name, val)
        var result = VM.eval(frame, code)
        if options.print_result:
          if not options.filter_result or result:
            echo result.to_s
        index += 1
    else:
      var result = VM.eval_only(frame, options.eval)
      if options.print_result:
        echo result.to_s
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
