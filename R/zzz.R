.onAttach <- function(libname, pkgname) {
  # packageStartupMessage("Thank you for using mypackage! 🚀")
  packageStartupMessage(
    "
      This package is in beta phase.

      The function definitions are likely stable in the
      release on r-universe https://openalexpro.r-universe.dev/openalexPro,
      but nothing can be assumed in the dev version on GitHub!

      As usual, the author(s) do not take any responsibility for the
      correct functioning of the package or any responsibility for
      resulting wrong statements, delays, costs, etc.
    "
  )
}
