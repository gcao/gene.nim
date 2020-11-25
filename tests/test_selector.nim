import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

# Selector
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
# 
# SelectorResult
# * Single value
# * Array or map or gene
#
# Define styles for gene value matched by a selector (like CSS).
# This should live outside the gene value.
# Inline styles can be defined for a gene. However it is not related to selectors.
#
# Transform a gene value based on selectors and actions (like XSLT)
# Should support non-gene output, e.g. raw strings.
# Actions:
#   * Copy value matched by selector to output
#   * Call callback with value, add result to output
# 
# (@ "test")             # target["test"]
# @test                  # target["test"]
# (@ 0 "test")           # target[0]["test"]
# @0/test                # target[0]["test"]
# (@ (@ 0) "test")       # target[0]["test"]
# (@ [0 1] "test")       # target[0, 1]["test"]
# (@ (range 0 3) :type)  # target[0..3].type
# (@* [0 "test"] [1 "another"])  # target[0]["test"] + target[1]["another"]
#
# (.@ 0 "test")             # ((@ 0 "test") self)
# (.@0/test)                # ((@ 0 "test") self)
# (.@ :type)                # ((@ :type) self)
# (obj .@ 0 "test")         # ((@ 0 "test") obj)
# (.@* 0 1)                 # ((@* 0 1) self)
# (.@ 0 "test" = "value")   # (assign self (@ 0 "test") "value")
# (.@test)                  # ((@ "test") self)
# (.@first/second)          # ((@ "first" "second") self)
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
  ((~ "test") {^test 1})
""", 1

test_interpreter """
  ((~ 0) [1 2])
""", 1

test_interpreter """
  ((~ 0 "test") [{^test 1}])
""", 1

test_interpreter """
  ((~ (~ 0)) [1 2])
""", 1

test_interpreter """
  ((~ [0 1]) [1 2])
""", @[new_gene_int(1), new_gene_int(2)]

# test_interpreter """
#   ((~* 0 1) [1 2])
# """, @[new_gene_int(1), new_gene_int(2)]