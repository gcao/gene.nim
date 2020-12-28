import gene/types

import ./helpers

# case...when...else statement
# `when` accepts integers, strings, chars, symbols, enum values,
#        regular expressions, ranges, classes, and any expressions etc
# Code blocks are stored in a seq
# A mapping is created from when-values to blocks
# If when-value is a literal, a static mapping is used
# If when-value must be evaluated, depending on the result type, it'll
#   use appropriate logic to determine whether it matches.
# Regular expressions, ranges, classes are handled in special logic
# Literal / constant value has higher priority than expressions
#
# Case statement should be optimized as much as possible, but still maintain
#   the flexibility and power.
#
# (case input
# when 1
#   ...
# when [2 3]
#   ...
# else
#   ...
# )

test_interpreter """
  (case 2
  when 1
    _
    100
  when 2
    _
    200
  else
    _
    300
  )
""", 200

test_interpreter """
  (case 3
  when 1
    _
    100
  when 2
    _
    200
  else
    _
    300
  )
""", 300