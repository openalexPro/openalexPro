# pro_request_jsonl_parquet `biodiversity` and group by type

    Code
      nrow(results_openalexPro)
    Output
      [1] 17
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
      # A tibble: 17 x 3
         key                                        key_display_name  count
         <chr>                                      <chr>             <int>
       1 https://openalex.org/types/article         article          130804
       2 https://openalex.org/types/book            book               3073
       3 https://openalex.org/types/book-chapter    book-chapter       6220
       4 https://openalex.org/types/database        database              1
       5 https://openalex.org/types/dataset         dataset             278
       6 https://openalex.org/types/dissertation    dissertation       2193
       7 https://openalex.org/types/editorial       editorial           219
       8 https://openalex.org/types/erratum         erratum              60
       9 https://openalex.org/types/letter          letter              663
      10 https://openalex.org/types/libguides       libguides            22
      11 https://openalex.org/types/other           other               677
      12 https://openalex.org/types/paratext        paratext            188
      13 https://openalex.org/types/preprint        preprint           1396
      14 https://openalex.org/types/reference-entry reference-entry      25
      15 https://openalex.org/types/report          report              411
      16 https://openalex.org/types/review          review             1943
      17 https://openalex.org/types/standard        standard              1

