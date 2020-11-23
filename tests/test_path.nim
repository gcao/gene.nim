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
#   * Gene type: ($gtype)
#   * Gene properties ($gprops)
#   * Gene property names ($gnames)
#   * Gene property values ($gvalues)
#   * Gene data ($gdata)
#   * Descendants: how does match work for this?
#   * Predicate (_ (it -> (...)))
#   * Composite
# * Extend
# 
# GenePathResult
# * Single value
# * Array or map or gene
# 
# ($gpath 0 "test")  # target[0]["test"]
# ($gpath (range 0 3) ($gtype))  # target[0..3].type
# ($gpaths [0 "test"] [1 "another"])  # target[0]["test"] + target[1]["another"]
#
# (@ 0 "test") = (@ ^target self ($gpath 0 "test"))
# (@ 0 "test" = "value") = (@= ^target self ($gpath 0 "test") "value")
# (-@ 0 "test") = (@ ^target self ^^delete ($gpath 0 "test"))
# @test = (@ ^target self ($gpath "test"))
# @first/second = (@ ^target self ($gpath "first" "second"))
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
