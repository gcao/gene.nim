import unittest

import gene/types

import ./helpers

# Decorator
#
# * Can be applied to array item, Gene data item
# * It's applied when expressions are created
# * Simple decorator: +pub
# * Complex decorator: (+add 2)
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
