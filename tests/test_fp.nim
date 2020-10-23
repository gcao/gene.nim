import unittest

import gene/types

import ./helpers

# Functional programming:
#
# * Return function as result
# * Pass function around
# * Closure
# * Iterators
# * Pure function (mark function as pure, all standard lib should be marked pure if true)
# * Continuation - is it possible?

test_interpreter "(fn f a a)", proc(r: GeneValue) =
  check r.internal.fn.name == "f"

test_interpreter "(fn f _)", proc(r: GeneValue) =
  check r.internal.fn.matcher.children.len == 0

test_interpreter "(fn f [] 1) (f)", 1
test_interpreter "(fn f a (a + 1)) (f 1)", 2

test_interpreter """
  (fn f [a = 1] a)
  (f)
""", 1

test_interpreter """
  (fn f [a = 1] a)
  (f 2)
""", 2

test_interpreter """
  (fn f [a b = a] b)
  (f 1)
""", 1

test_interpreter """
  (fn f [a b = (a + 1)] b)
  (f 1)
""", 2

test_interpreter """
  (fn f _
    (return 1)
    2
  )
  (f)
""", 1

test_interpreter """
  (fn fib n
    (if (n < 2)
      n
    else
      ((fib (n - 1)) + (fib (n - 2)))
    )
  )
  (fib 6)
""", 8

test_interpreter """
  (fn f _
    (fn g a a)
  )
  ((f) 1)
""", 1

test_interpreter """
  (fn f a
    (fn g _ a)
  )
  ((f 1))
""", 1

test_interpreter """
  (fn f _
    (var r return)
    (r 1)
    2
  )
  (f)
""", 1

# return can be assigned and will remember which function
# to return from
# Caution: "r" should only be used in nested functions/blocks inside "f"
test_interpreter """
  (fn g ret
    (ret 1)
  )
  (fn f _
    (var r return)
    (loop
      (g r)
    )
  )
  (f)
""", 1

# return can be assigned and will remember which function
# to return from
test_interpreter """
  (fn f _
    (var r return)
    (fn g _
      (r 1)
    )
    (loop
      (g)
    )
  )
  (f)
""", 1

test_interpreter """
  (fn f _ $args)
  (f 1)
""", proc(r: GeneValue) =
  check r.gene.data[0] == 1

test_interpreter """
  (fn f [a b] (a + b))
  (fn g _
    (f ...)
  )
  (g 1 2)
""", 3

test_interpreter """
  (var f
    (fnx a a)
  )
  (f 1)
""", 1

test_interpreter """
  (var f
    (fnxx 1)
  )
  (f)
""", 1

# test_interpreter """
#   (fn f _ 1)
#   (var f
#     (fnx _
#       ((f) + 1)
#     )
#   )
#   (f)
# """, 2
