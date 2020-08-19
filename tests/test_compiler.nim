# To run these tests, simply execute `nimble test` or `nim c -r tests/test_compiler.nim`

import unittest, tables

import gene/types
import gene/vm
import gene/compiler
import gene/interpreter
import gene/cpu

import ./helpers

test_compiler "1", 1

test_compiler "(1 + 2)", 3
test_compiler "(1 - 2)", -1

test_compiler "(1 < 2)", true

test_compiler "(if true 1)", 1
test_compiler "(if false 1 else 2)", 2
test_compiler "(if false 1 elif true 2 else 3)", 2
test_compiler "(if false 1 elif false 2 else 3)", 3

test_compiler "(var a 1) a", 1

test_compiler "(fn f [] 1)", proc(r: GeneValue) =
  check r.internal.fn.name == "f"
test_compiler "(fn f [] 1) (f)", 1
test_compiler "(fn f a (a + 1)) (f 1)", 2
test_compiler """
  (fn fib n
    (if (n < 2)
      n
    else
      ((fib (n - 1)) + (fib (n - 2)))
    )
  )
  (fib 6)
""", 8

test_compiler """
  (ns n)
""", proc(r: GeneValue) =
  check r.internal.ns.name == "n"

test_compiler """
  (ns n)
  n
""", proc(r: GeneValue) =
  check r.internal.ns.name == "n"

test "Compiler / VM: Import":
  var c = new_compiler()
  var vm = new_vm()
  vm.eval_module "file1", """
    (fn f a a)
  """
  var module = c.compile """
    (import f from "file1")
    f
  """
  var result = vm.run(module)
  check result.internal.fn.name == "f"

test_compiler """
  (class A)
""", proc(r: GeneValue) =
  check r.internal.class.name == "A"

test_compiler """
  (class A)
  A
""", proc(r: GeneValue) =
  check r.internal.class.name == "A"

test_compiler """
  (class A)
  (new A)
""", proc(r: GeneValue) =
  check r.instance.class.name == "A"

test_compiler """
  (class A
    (method new []
      (.@description= "Class A")
    )
  )
  (new A)
""", proc(r: GeneValue) =
  check r.instance.value.gene_props["description"] == "Class A"
