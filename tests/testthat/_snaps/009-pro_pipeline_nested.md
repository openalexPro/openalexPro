# pro_request with nested list creates nested output dirs

    Code
      json_files
    Output
      [1] "grp_a/chunk_1/results_page_1.json" "grp_a/chunk_2/results_page_1.json"
      [3] "grp_b/chunk_3/results_page_1.json" "grp_b/chunk_4/results_page_1.json"

# pro_request_jsonl_R with nested subdirs

    Code
      jsonl_files
    Output
      [1] "grp_a/chunk_1/results_page_1.json" "grp_a/chunk_2/results_page_1.json"
      [3] "grp_b/chunk_3/results_page_1.json" "grp_b/chunk_4/results_page_1.json"

# pro_request_jsonl_parquet with nested subdirs produces hive partitions

    Code
      parquet_files
    Output
      [1] "query=grp_a/query_l2=chunk_1/results_page_1.parquet"
      [2] "query=grp_a/query_l2=chunk_2/results_page_1.parquet"
      [3] "query=grp_b/query_l2=chunk_3/results_page_1.parquet"
      [4] "query=grp_b/query_l2=chunk_4/results_page_1.parquet"
    Code
      ds
    Output
      FileSystemDataset with 4 Parquet files
      53 columns
      id: string
      doi: string
      title: string
      display_name: string
      publication_year: int64
      publication_date: date32[day]
      ids: struct<openalex: string, doi: string, mag: string, pmid: string>
      language: string
      primary_location: struct<id: string, is_oa: bool, landing_page_url: string, pdf_url: string, source: struct<id: string, display_name: string, issn_l: string, issn: list<element: string>, is_oa: bool, is_in_doaj: bool, is_core: bool, host_organization: string, host_organization_name: string, host_organization_lineage: list<element: string>, host_organization_lineage_names: list<element: string>, type: string>, license: string, license_id: string, version: string, is_accepted: bool, is_published: bool, raw_source_name: string, raw_type: string>
      type: string
      indexed_in: list<element: string>
      open_access: struct<is_oa: bool, oa_status: string, oa_url: string, any_repository_has_fulltext: bool>
      authorships: list<element: struct<author_position: string, author: struct<id: string, display_name: string, orcid: string>, institutions: list<element: struct<id: string, display_name: string, ror: string, country_code: string, type: string, lineage: list<element: string>>>, countries: list<element: string>, is_corresponding: bool, raw_author_name: string, raw_affiliation_strings: list<element: string>, raw_orcid: string, affiliations: list<element: struct<raw_affiliation_string: string, institution_ids: list<element: string>>>>>
      institutions: list<element: string>
      countries_distinct_count: int64
      institutions_distinct_count: int64
      corresponding_author_ids: list<element: string>
      corresponding_institution_ids: list<element: string>
      apc_list: struct<value: int64, currency: string, value_usd: int64>
      apc_paid: struct<value: int64, currency: string, value_usd: int64>
      ...
      33 more columns
      Use `schema()` to see entire schema
    Code
      dplyr::collect(dplyr::arrange(dplyr::distinct(dplyr::select(ds, page)), page))
    Output
      # A tibble: 4 x 1
        page   
        <chr>  
      1 chunk_1
      2 chunk_2
      3 chunk_3
      4 chunk_4

