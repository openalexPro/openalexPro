# Get available filter names from OpenAlex API

Valid filter names differ between entities (e.g. \`country_code\` is a
filter for institutions but not for works). The list is taken from the
error message OpenAlex returns for an invalid filter, which names
exactly the filters it accepts for that entity; error responses cost no
credits. Each entity's list is cached for the R session.

## Usage

``` r
opt_filter_names(update = FALSE, entity = "works")
```

## Arguments

- update:

  logical. If \`TRUE\` update the existing value. Default is \`FALSE\`.

- entity:

  OpenAlex entity, e.g. \`"works"\` (default), \`"authors"\`,
  \`"institutions"\`. Use the same value as \`entity\` in
  \[pro_query()\].

## Value

A character vector of available filter names. Empty if OpenAlex does not
return a list for \`entity\` (e.g. the retired \`"venues"\`).
