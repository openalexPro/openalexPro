# Validate OpenAlex credentials

Makes a minimal API request to verify that the api_key is valid.

## Usage

``` r
pro_validate_credentials(api_key = pro_api_key(), show_credentials = FALSE)
```

## Arguments

- api_key:

  API key to validate (character string) or \`NULL\`.

- show_credentials:

  shows the api_key using \`message()\`. USE WITH CAUTION!

## Value

TRUE if credentials work, FALSE otherwise
