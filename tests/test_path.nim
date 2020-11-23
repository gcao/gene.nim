import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

# GenePath
# * Borrow ideas from XPath
# * Mode:
#   * Match first
#   * Match all
# * Flags:
#   * error_on_no_match: Throw error if none is matched
# * Types
#   * Index: 0,1,..-2,-1
#   * Index list
#   * Index range: 0..2
#   * Property name
#   * Property name list
#   * Property name pattern: /^test/
#   * Gene type: ($type)
#   * Gene properties ($props)
#   * Gene property names ($names)
#   * Gene property values ($values)
#   * Gene data ($data)
#   * Descendants: how does match work for this?
#   * Predicate (_ (it -> (...)))
#   * Composite
# * Extend
# 
# GenePathResult
# * Single value
# * Array or map or gene
# 
# ($path 0 "test")  # target[0]["test"]
# ($path (range 0 3) ($type))  # target[0..3].type
# ($paths [0 "test"] [1 "another"])  # target[0]["test"] + target[1]["another"]
#
# (@ 0 "test") = (@ ^target self ($path 0 "test"))
# (@ 0 "test" = "value") = (@= ^target self ($path 0 "test") "value")
# (-@ 0 "test") = (@ ^target self ^^delete ($path 0 "test"))
# @test = (@ ^target self ($path "test"))
# @first/second = (@ ^target self ($path "first" "second"))
#
# * Traversal
# * Assign
# * Remove

test_interpreter """
  ({^a "A"} .@ "a")
""", "A"

test_interpreter """
  ((_ ^a "A") .@ "a")
""", "A"

# test_interpreter """
#   ([1 2] .@ 0)
# """, 1

test_interpreter """
  (($path "test") {^test 1})
""", 1
