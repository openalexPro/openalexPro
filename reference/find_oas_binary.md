# Find the openalex-snapshot binary

Resolves the path to the `openalex-snapshot` binary using the following
order of precedence:

1.  Explicit `oas_bin` argument

2.  Package option `getOption("openalexPro.oas_bin")`

3.  `Sys.which("openalex-snapshot")` (PATH search)

## Usage

``` r
find_oas_binary(oas_bin = NULL)
```

## Arguments

- oas_bin:

  Optional path to the binary. If `NULL`, falls back to the package
  option then PATH.

## Value

Character string: absolute path to the binary.
