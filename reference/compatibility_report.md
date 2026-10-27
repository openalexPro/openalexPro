# Render and open the compatibility report

Renders the Quarto report at \`system.file("compatibility.qmd", package
= "openalexPro") and opens the resulting HTML in your default browser.

## Usage

``` r
compatibility_report(
  output_dir = "Compatibility Report",
  open = TRUE,
  quiet = FALSE
)
```

## Arguments

- output_dir:

  Directory to write the rendered HTML and the data into. Defaults to
  the flder \`./Compatibility Report\`.

- open:

  Logical; if \`TRUE\` (default) opens the rendered HTML in the system
  browser.

- quiet:

  Logical; suppress rendering output if \`TRUE\`. Default: \`FALSE\`.

## Value

Invisibly returns the path to the rendered HTML file.

## Details

This report is designed to help you validate client-API compatibility in
real time. During rendering, the report performs live requests against
the OpenAlex API and compares the responses to the package's expected
behavior. No cached data are used: every section issues fresh API calls
so that the output reflects the current state of the upstream service.
The report summarizes differences in fields, types, pagination and
response shapes to surface potential regressions from upstream changes
or local client updates.

Note: Because it depends on live API calls, rendering may take longer
and requires network access. Be mindful of API rate limits when running
the report repeatedly.
