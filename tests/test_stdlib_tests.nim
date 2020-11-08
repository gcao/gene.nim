import ./helpers

test_core """

(import genex/tests/[test skip_test])

(test "A basic test"
  (assert true)
)

(skip_test "A failing test"
  (assert false)
)

(skip_test "Another failing test"
  (fail)
)

"""
