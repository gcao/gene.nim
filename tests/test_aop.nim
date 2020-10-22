import gene/types

import ./helpers

# AOP(Aspect Oriented Programming):
#
# * before
# * after
# * around
#
# * Can alter arguments
# * Can alter result
# * Can skip run
# * Can trigger retry
# * ...
#
# * AOP for OOP
#   Can be applied to classes and methods
#
# * AOP for functions
#   Can be applied to existing functions (not macros and blocks)
#
# Aspects should be grouped, but how?
# * OOP:
#   on class level
#
# * Functions:
#   on scope/ns level, a new object with same name is created in
#   the ns/scope which stores a reference of the old function object
#
# Design by Contract - can be implemented with AOP
# * precondition
# * postcondition
# * invariant
#

# test_interpreter """
#   (class A
#     (method test a
#       a
#     )
#     (before "test" (fnx a
#       ($set $args 0 (a + 1)) # have to update the args object
#     ))
#   )
#   ((new A) .test 1)
# """, 2
#

# test_interpreter """
#   (fn f a a)
#   # `f` will be replaced with a new pseudo function which can invoke
#   # the original function
#   (before f (fnx a
#     ($set $args 0 (a + 1)) # have to update the args object
#   ))
#   (f 1)
# """, 2
