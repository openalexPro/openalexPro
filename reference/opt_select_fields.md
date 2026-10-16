# Get available select fields from OpenAlex API

Valid select fields differ between entities (e.g. \`orcid\` for
authors). The list is taken from the error message OpenAlex returns for
an invalid select field, which names exactly the fields it accepts for
that entity; error responses cost no credits. Each entity's list is
cached for the R session.

## Usage

``` r
opt_select_fields(update = FALSE, entity = "works")
```

## Arguments

- update:

  logical. If \`TRUE\` update the existing value. Default is \`FALSE\`.

- entity:

  OpenAlex entity, e.g. \`"works"\` (default), \`"authors"\`,
  \`"institutions"\`. Use the same value as \`entity\` in
  \[pro_query()\].

## Value

A character vector of available select fields. Empty if OpenAlex does
not return a list for \`entity\` (e.g. the retired \`"venues"\`).
