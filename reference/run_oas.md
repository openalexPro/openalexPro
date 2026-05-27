# Run an openalex-snapshot subcommand

Calls `openalex-snapshot` with the given argument vector via
[`system2()`](https://rdrr.io/r/base/system2.html) and aborts with an
informative error if the process exits with a non-zero status code.

## Usage

``` r
run_oas(args, oas_bin = NULL, error_call = rlang::caller_env())
```

## Arguments

- args:

  Character vector of arguments (subcommand first, then flags).

- oas_bin:

  Optional path to the binary; passed to \[find_oas_binary()\].

- error_call:

  The call environment for error messages.

## Value

Invisibly returns `0L` on success.
