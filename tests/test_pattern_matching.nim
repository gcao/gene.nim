import gene/types

import ./helpers

# Pattern Matching 
#
# * Argument parsing
# * (match pattern input)
#   Match works similar to argument parsing
# * Custom matchers can be created, which takes something and
#   returns a function that takes an input and a scope object and
#   parses the input and stores as one or multiple variables
# * Every standard type should have an adapter to allow pattern matching
#   to access its data easily
#

# Mode: argument, match, ...
# When matching arguments, root level name will match first item in the input
# While (match name) will match the whole input
#
# Root level
# (match name input)
# (match _ input)
#
# Child level
# (match [a? b] input) # "a" is optional, if input contains only one item, it'll be
#                      # assigned to "b"
# (match [a... b] input) # "a" will match 0 to many items, the last item is assigned to "b"
# (match [a = 1 b] input) # "a" is optional and has default value of 1
#
# Grandchild level
# (match [a b [c]] input) # "c" will match a grandchild
#
# Match properties
# (match [^a] input)  # "a" will match input's property "a"
# (match [^a!] input) # "a" will match input's property "a" and is required
# (match [^a: var_a] input) # "var_a" will match input's property "a"
# (match [^a: var_a = 1] input) # "var_a" will match input's property "a", and has default
#                               # value of 1
#
# Q: How do we match gene_op?
# A: Use "*" to signify it. like "^" to signify properties. It does not support optional,
#    default values etc
#    [*op] will assign gene_op to "op"
#    [*: [...]] "*:" or "*name:" will signify that next item matches gene_op's internal structure
#

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

# test_interpreter """
#   (match
#     [:if cond :then logic1... :else logic2...]
#     :[if true then
#       (do A)
#       (do B)
#     else
#       (do C)
#       (do D)
#     ]
#   )
#   cond
# """, true
