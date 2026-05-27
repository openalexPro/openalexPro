# Retrieve the OpenAlex Pro API key

Retrieves the OpenAlex Pro API key from one of several locations,
checked in the following order:

## Usage

``` r
pro_api_key()
```

## Value

A character string containing the API key, or `NULL` if no key could be
found.

## Details

1.  The R option `openalexPro$api_key`

2.  The environment variable `openalexPro.api_key`

3.  The system keyring via the keyring package (only if the package
    keyring is installed)

If no API key is found, `NULL` or an empty string may be returned,
depending on the environment variable state.

## See also

[`options`](https://rdrr.io/r/base/options.html),
[`Sys.getenv`](https://rdrr.io/r/base/Sys.getenv.html)

## Examples

``` r
if (FALSE) { # \dontrun{
pro_api_key()

options(openalexPro = list(api_key = "my-key"))
pro_api_key()
} # }
```
