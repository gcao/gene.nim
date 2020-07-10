# To run these tests, simply execute `nimble test`.

import unittest

import gene/types
import gene/compiler
import gene/vm
import gene/cpu

# Uncomment below lines to see logs
# import logging
# addHandler(newConsoleLogger())

test "Compiler / VM: 1":
  var c = new_compiler()
  var vm = new_vm()
  var module = c.compile("1")
  check vm.run(module) == new_gene_int(1)

test "Compiler / VM: (1 + 2)":
  var c = new_compiler()
  var vm = new_vm()
  var module = c.compile("(1 + 2)")
  check vm.run(module) == new_gene_int(3)

test "Compiler / VM: (if true 1)":
  var c = new_compiler()
  var vm = new_vm()
  var module = c.compile("(if true 1)")
  check vm.run(module) == new_gene_int(1)

test "Compiler / VM: (if false 1 else 2)":
  var c = new_compiler()
  var vm = new_vm()
  var module = c.compile("(if false 1 else 2)")
  check vm.run(module) == new_gene_int(2)

test "Compiler / VM: (if false 1 elif true 2 else 3)":
  var c = new_compiler()
  var vm = new_vm()
  var module = c.compile("(if false 1 elif true 2 else 3)")
  check vm.run(module) == new_gene_int(2)

test "Compiler / VM: (if false 1 elif false 2 else 3)":
  var c = new_compiler()
  var vm = new_vm()
  var module = c.compile("(if false 1 elif false 2 else 3)")
  check vm.run(module) == new_gene_int(3)