import unittest, tables

import gene/types

import ./helpers

# OOP:
#
# * Single inheritance
# * private / protected / public methods
# * method_missing - can only be defined in classes
# * Mixin: all stuff in mixin are copied to the target class/mixin

test_interpreter "(class A)", proc(r: GeneValue) =
  check r.internal.class.name == "A"

test_interpreter """
  (class A)
  (new A)
""", proc(r: GeneValue) =
  check r.instance.class.name == "A"

test_interpreter """
  (class A
    (method new []
      (@description = "Class A")
    )
  )
  (new A)
""", proc(r: GeneValue) =
  check r.instance.value.gene_props["description"] == "Class A"

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
  check r.instance.value.gene_props["description"] == "test"

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

# test_interpreter """
#   (class A
#     (method test []
#       "A.test"
#     )
#   )
#   (class B < A
#   )
#   ((new B) .test)
# """, "A.test"
