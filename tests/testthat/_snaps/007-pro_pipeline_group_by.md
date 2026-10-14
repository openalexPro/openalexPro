# pro_request_jsonl_parquet `biodiversity` and group by type

    Code
      nrow(results_openalexPro)
    Output
      [1] 21
    Code
      sort(names(results_openalexPro))
    Output
      [1] "citation"         "count"            "key"              "key_display_name"
      [5] "page"            
    Code
      results_openalexPro <- dplyr::collect(dplyr::arrange(dplyr::mutate(
        results_openalexPro, citation = NULL, page = NULL), key))
      print(results_openalexPro)
    Output
      # A tibble: 21 x 3
         key                                            key_display_name     count
         <chr>                                          <chr>                <int>
       1 https://openalex.org/types/article             article             118010
       2 https://openalex.org/types/book                book                  2685
       3 https://openalex.org/types/book-chapter        book-chapter          6355
       4 https://openalex.org/types/book-review         book-review           1079
       5 https://openalex.org/types/conference-abstract conference-abstract    255
       6 https://openalex.org/types/conference-paper    conference-paper      2648
       7 https://openalex.org/types/dataset             dataset                123
       8 https://openalex.org/types/dissertation        dissertation          2948
       9 https://openalex.org/types/editorial           editorial              412
      10 https://openalex.org/types/erratum             erratum                111
      # i 11 more rows

