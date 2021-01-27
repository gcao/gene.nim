import ./types
import ./interpreter/base
import ./interpreter/evaluators
import ./interpreter/native

init_evaluators()

proc init_app_and_vm*() =
  var app = new_app()
  VM = new_vm(app)

proc load_core_module*(self: VirtualMachine) =
  VM.gene_ns  = new_namespace("gene")
  VM.app.ns[GENE_KEY] = VM.gene_ns
  VM.genex_ns = new_namespace("genex")
  VM.app.ns[GENEX_KEY] = VM.genex_ns
  VM.gene_ns.internal.ns[NATIVE_KEY] = new_namespace("native")
  init_native()
  discard self.import_module(CORE_KEY, readFile(GENE_HOME & "/src/core.gene"))

proc load_gene_module*(self: VirtualMachine) =
  discard self.import_module(GENE_KEY, readFile(GENE_HOME & "/src/gene.gene"))
  GeneObjectClass    = VM.gene_ns[OBJECT_CLASS_KEY]
  GeneClassClass     = VM.gene_ns[CLASS_CLASS_KEY]
  GeneExceptionClass = VM.gene_ns[EXCEPTION_CLASS_KEY]

proc load_genex_module*(self: VirtualMachine) =
  discard self.import_module(GENEX_KEY, readFile(GENE_HOME & "/src/genex.gene"))

export base.eval

when isMainModule:
  import os, times

  if commandLineParams().len == 0:
    echo "\nUsage: interpreter <GENE FILE>\n"
    quit(0)

  init_app_and_vm()
  var module = new_module()
  var frame = FrameMgr.get(FrModule, module.root_ns, new_scope())
  let e = VM.prepare(readFile(commandLineParams()[0]))
  let start = cpuTime()
  let result = VM.eval(frame, e)
  echo "Time: " & $(cpuTime() - start)
  echo result
