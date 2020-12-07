import gene/types

import ./helpers

# test_interpreter """
#   (fn f [sum n]
#     (if (n == 0)
#       sum
#     else
#       (f (sum + n) (n - 1))
#     )
#   )
#   (f 0 1000)
# """, 500500
