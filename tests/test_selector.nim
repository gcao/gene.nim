import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

# GenePath
# * Borrow ideas from XPath/XSLT/CSS
#   * XPath: locate any node or group of nodes in a xml document
#   * XSLT: transform a xml document to another
#   * CSS: apply styles on any element or group of elements in a html document
#   * CSS Selectors: similar to XPath
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
#   * Gene type: :type
#   * Gene properties: :props
#   * Gene property names: :names
#   * Gene property values: :values
#   * Gene data: :data
#   * Descendants: :descendants - how does match work for this? self.gene.data and their descendants?
#   * Predicate (fnx it ...)
#   * Composite: [0 1 (range 3 5)]
# * Extend
# 
# GenePathResult
# * Single value
# * Array or map or gene
# 
# ($sel 0 "test")  # target[0]["test"]
# ($sel (range 0 3) ($type))  # target[0..3].type
# ($sels [0 "test"] [1 "another"])  # target[0]["test"] + target[1]["another"]
#
# (@ 0 "test") = (@ ^target self ($sel 0 "test"))
# (@ 0 "test" = "value") = (@= ^target self ($sel 0 "test") "value")
# (-@ 0 "test") = (@ ^target self ^^delete ($sel 0 "test"))
# @test = (@ ^target self ($sel "test"))
# @first/second = (@ ^target self ($sel "first" "second"))
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
  (($sel "test") {^test 1})
""", 1

test_interpreter """
  (($sel 0) [1 2])
""", 1

test_interpreter """
  (($sel 0 "test") [{^test 1}])
""", 1
