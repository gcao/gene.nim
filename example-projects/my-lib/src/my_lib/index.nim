# import strutils
# import gene/types

# {.push dynlib exportc.}

# proc upcase(args: seq[GeneValue]): GeneValue =
#   return args[0].to_upper()

# {.pop.}

# Add to package namespace
