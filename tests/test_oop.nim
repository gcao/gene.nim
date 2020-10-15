import unittest, tables

import gene/types

import ./helpers

# OOP:
#
# * Single inheritance
# * private / protected / public methods
# * method_missing - can only be defined in classes
# * Mixin: all stuff in mixin are copied to the target class/mixin
# * Properties: just a shortcut for defining .prop/.prop= methods

test_interpreter "(class A)", proc(r: GeneValue) =
  check r.internal.class.name == "A"

test_interpreter """
  (class A)
  (new A)
""", proc(r: GeneValue) =
  check r.internal.instance.class.name == "A"

test_interpreter """
  (class A
    (method new []
      (@description = "Class A")
    )
  )
  (new A)
""", proc(r: GeneValue) =
  check r.internal.instance.value.gene_props["description"] == "Class A"

test_interpreter """
  (class A
    (method new []
      (@description = "Class A")
    )
  )
  ((new A) .@description)
""", proc(r: GeneValue) =
  check r.str == "Class A"

test_interpreter """
  (class A
    (method new description
      (@description = description)
    )
  )
  (new A "test")
""", proc(r: GeneValue) =
  check r.internal.instance.value.gene_props["description"] == "test"

test_interpreter """
  (class A
    (method test []
      "test"
    )
  )
  ((new A) .test)
""", "test"

test_interpreter """
  (class A
    (method test [a b]
      (a + b)
    )
  )
  ((new A) .test 1 2)
""", 3

test_interpreter """
  (class A
    (method test []
      "A.test"
    )
  )
  (class B < A
  )
  ((new B) .test)
""", "A.test"

test_interpreter """
  (mixin M
    (method test _
      1
    )
  )
  (class A
    (include M)
  )
  ((new A) .test)
""", 1
