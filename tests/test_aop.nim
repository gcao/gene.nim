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
# (aspect A _
#   ^extend (do
#     (method new _ ...)  # an aspect can be instantiated like class
#     (method x   _ ...)  # x is defined on the aspect, not on the target class
#   )
#
#   (before (fnx ...))
# )
# (fn f)
#
# (var a (A f ...))
# ^^^ == vvv
# (var a (new A))
# (a f ...)
#
# (a .disable)
# (a .detach)   # unwrap, unapply, ... which is the best name for this?
#

# (claspect B [target meth]
#   ^extend (do
#     (method new _ ...)  # an aspect can be instantiated like class
#     (method x   _ ...)  # x is defined on the aspect, not on the target class
#   )
#
#   (method m)  # m is defined on the target class
#
#   (before meth (fnx ...))
# )
# (class C)
#
# (var b (B C "test"))
# ^^^ == vvv
# (var b (new B))
# (b C "test")
#

# test_interpreter """
#   # claspect: define aspects that are applicable to classes
#   (claspect A [target m] # target is required, m is the matcher for arguments passed in when applied
#     (before m (fnx a
#       ($set $args 0 (a + 1)) # have to update the args object
#     ))
#   )
#   (class C
#     (method test a
#       a
#     )
#   )
#   (var applied (A C "test")) # save the reference to disable later
#   ((new C) .test 1)
# """, 2

# test_interpreter """
#   # aspect: define aspects that are applicable to functions
#   (aspect A [target arg]
#     (before target (fnx a
#       ($set $args 0 (a + arg)) # have to update the args object
#     ))
#   )
#   (fn f a
#     a
#   )
#   (var f (A f 2)) # re-define f in current scope
#   (f 1)
#   # (f .unwrap) # return the function that was wrapped
# """, 3

# test_interpreter """
#   # aspect: define aspects that are applicable to functions
#   (aspect A [target arg]
#     (before target (fnx a
#       ($set $args 0 (a + arg)) # have to update the args object
#     ))
#   )
#   (fn f a
#     a
#   )
#   (var f (A f 2)) # re-define f in current scope
#   (var f (A f 3)) # re-define f in current scope
#   (f 1)
# """, 6

# test_interpreter """
#   # aspect: define aspects that are applicable to functions
#   (aspect A [target arg]
#     (after target (fnx a
#       # TODO
#     ))
#   )
#   (fn f a
#     a
#   )
#   (var f (A f 2)) # re-define f in current scope
#   (f 1)
# """, 3

test_interpreter """
  (var /a 0)  # `a` is defined as a ns member so it's available inside the aspect
  (claspect A [target meth]
    (before meth (fnx _
      (a += 1)
    ))
  )
  (class C
    (method test _)
  )

  (A C "test")
  ((new C) .test)

  a
""", 1

test_core """
  (var /a "")  # `a` is defined as a ns member so it's available inside the aspect
  (claspect A [target meth]
    (before meth (fnx _
      (a .append "before")
    ))
    (after meth (fnx _
      (a .append "after")
    ))
  )
  (class C
    (method test _
      (a .append "test")
    )
  )

  (A C "test")
  ((new C) .test)

  a
""", "beforetestafter"

# test_core """
#   (var /a "")
#   (claspect A [target meth]
#     (around meth (fnx _
#       (a .append "before")
#       ($invoke_with_args)
#       (a .append "after")
#     ))
#   )
#   (class C
#     (method test _
#       (a .append "test")
#     )
#   )

#   (A C "test")
#   ((new C) .test)

#   a
# """, "beforetestafter"
