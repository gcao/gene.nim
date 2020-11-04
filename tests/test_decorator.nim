import unittest

import gene/types

import ./helpers

# Decorator
#
# * Can be applied to array item, Gene data item
# * It's applied when expressions are created
# * Simple decorator: +pub x        -> (call ^^decorator pub x)
# * Complex decorator: (+add 2) x   -> (call ^^decorator (add 2) x)
#

# test_interpreter """
#   (fn f target
#     (target)
#   )
#   (fn g _
#     1
#   )
#   [+f g]
# """, 1
