import strutils

{.push dynlib exportc.}

proc upcase*(s: string): string =
  return s.to_upper()

{.pop.}
