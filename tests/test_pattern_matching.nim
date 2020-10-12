import gene/types

import ./helpers

# Pattern Matching 
#
# * Argument parsing
# * (match (…) value)
#   Match works similar to argument parsing
# * Custom matchers can be created, which takes something and
#   returns a function that takes a value and a scope object and
#   parses the value and stores as one or multiple variables

test_interpreter """
  (fn f a
    a
  )
  (f 1)
""", 1

test_interpreter """
  (fn f [a b]
    (a + b)
  )
  (f 1 2)
""", 3

test_interpreter """
  (match a 1)
  a
""", 1

test_interpreter """
  (var x (:test 1 2))
  (match [a b] x)
  (a + b)
""", 3

test_interpreter """
  (var x (:test 1))
  (match [a b] x)
  b
""", GeneNil
