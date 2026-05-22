# pro_query with multiple ids

    Code
      names(req)
    Output
      [1] "chunk_1" "chunk_2" "chunk_3" "chunk_4"
    Code
      req
    Output
      $chunk_1
      [1] "https://api.openalex.org/works?filter=doi%3Ahttps%3A%2F%2Fdoi.org%2F10.1111%2F1468-2346.00131%7Chttps%3A%2F%2Fdoi.org%2F10.18235%2F0008810%7Chttps%3A%2F%2Fdoi.org%2F10.1016%2Fs0048-9697%2899%2900312-5%7Chttps%3A%2F%2Fdoi.org%2F10.1080%2F19390450903350812%7Chttps%3A%2F%2Fdoi.org%2F10.1126%2Fscience.291.5511.2047%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F1813-9450-3630%7Chttps%3A%2F%2Fdoi.org%2F10.1002%2Fldr.687%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.1523-1739.2007.00863.x%7Chttps%3A%2F%2Fdoi.org%2F10.1086%2F262115%7Chttps%3A%2F%2Fdoi.org%2F10.1080%2F10549810902791481%7Chttps%3A%2F%2Fdoi.org%2F10.1073%2Fpnas.0800208105%7Chttps%3A%2F%2Fdoi.org%2F10.1659%2F0276-4741%282005%29025%5B0206%3Apfbcs%5D2.0.co%3B2%7Chttps%3A%2F%2Fdoi.org%2F10.1126%2Fscience.1162756%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.1477-8947.2007.00130.x%7Chttps%3A%2F%2Fdoi.org%2F10.1300%2Fj091v21n01_03%7Chttps%3A%2F%2Fdoi.org%2F10.1177%2F0011392103051003009%7Chttps%3A%2F%2Fdoi.org%2F10.1046%2Fj.1523-1739.2003.01717.x%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.1523-1739.2005.00696.x%7Chttps%3A%2F%2Fdoi.org%2F10.1017%2Fcbo9780511754920%7Chttps%3A%2F%2Fdoi.org%2F10.1787%2F220188577008%7Chttps%3A%2F%2Fdoi.org%2F10.1017%2Fs0376892909990075%7Chttps%3A%2F%2Fdoi.org%2F10.1126%2Fscience.299.5615.1981b%7Chttps%3A%2F%2Fdoi.org%2F10.2139%2Fssrn.200528%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F18393%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.1365-2664.2009.01630.x%7Chttps%3A%2F%2Fdoi.org%2F10.1080%2F02827580510008392%7Chttps%3A%2F%2Fdoi.org%2F10.1186%2F1750-0680-4-11%7Chttps%3A%2F%2Fdoi.org%2F10.18352%2Fijc.147%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F0-8213-5350-0%7Chttps%3A%2F%2Fdoi.org%2F10.1080%2F02508060008686803%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F1813-9450-4370%7Chttps%3A%2F%2Fdoi.org%2F10.5860%2Fchoice.38-6141%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F978-0-1952-0650-0%7Chttps%3A%2F%2Fdoi.org%2F10.1186%2F1744-8603-1-8%7Chttps%3A%2F%2Fdoi.org%2F10.1080%2F00213624.2002.11506447%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F978-0-1952-0876-4%7Chttps%3A%2F%2Fdoi.org%2F10.1098%2Frsta.2002.1034%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F1813-9450-3185%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F1813-9450-4594%7Chttps%3A%2F%2Fdoi.org%2F10.1080%2F10549810902794329%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.1523-1739.2007.00829.x%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F11185%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.1523-1739.2009.01195.x%7Chttps%3A%2F%2Fdoi.org%2F10.1017%2Fs1014233900001978%7Chttps%3A%2F%2Fdoi.org%2F10.1080%2F10549810902791507%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.1523-1739.2007.00812.x%7Chttps%3A%2F%2Fdoi.org%2F10.2307%2F3761935%7Chttps%3A%2F%2Fdoi.org%2F10.1163%2F156854100508845%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F978-0-8213-6727-8%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F0-8213-3428-x"
      
      $chunk_2
      [1] "https://api.openalex.org/works?filter=doi%3Ahttps%3A%2F%2Fdoi.org%2F10.1596%2F0-8213-5150-8%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F1813-9450-3943%7Chttps%3A%2F%2Fdoi.org%2F10.1093%2Foso%2F9780195095548.003.0012%7Chttps%3A%2F%2Fdoi.org%2F10.4324%2F9780203881439%7Chttps%3A%2F%2Fdoi.org%2F10.1017%2Fs0376892908004517%7Chttps%3A%2F%2Fdoi.org%2F10.1098%2Frsta.2002.1038%7Chttps%3A%2F%2Fdoi.org%2F10.1017%2Fs0376892902000309%7Chttps%3A%2F%2Fdoi.org%2F10.1046%2Fj.1523-1739.2003.01748.x%7Chttps%3A%2F%2Fdoi.org%2F10.1300%2Fj091v25n03_03%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F1813-9450-3510%7Chttps%3A%2F%2Fdoi.org%2F10.1071%2Fpc930002%7Chttps%3A%2F%2Fdoi.org%2F10.4337%2F9781035335510%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F1813-9450-4117%7Chttps%3A%2F%2Fdoi.org%2F10.34194%2Fgeusb.v13.4977%7Chttps%3A%2F%2Fdoi.org%2F10.2478%2Fv10129-010-0009-3%7Chttps%3A%2F%2Fdoi.org%2F10.1142%2F7398%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F0-8213-4939-2%7Chttps%3A%2F%2Fdoi.org%2F10.22004%2Fag.econ.37920%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.1523-1739.2005.s01_1.x%7Chttps%3A%2F%2Fdoi.org%2F10.2172%2F843087%7Chttps%3A%2F%2Fdoi.org%2F10.1080%2F13549830802260191%7Chttps%3A%2F%2Fdoi.org%2F10.4404%2Fhystrix-15.1-4324%7Chttps%3A%2F%2Fdoi.org%2F10.1163%2F157180801x00199%7Chttps%3A%2F%2Fdoi.org%2F10.5172%2Fimpp.2003.5.2-3.270%7Chttps%3A%2F%2Fdoi.org%2F10.25501%2Fsoas.00029012%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.1468-2346.2006.00577.x%7Chttps%3A%2F%2Fdoi.org%2F10.1080%2F07329113.2008.10756620%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F1813-9450-3399%7Chttps%3A%2F%2Fdoi.org%2F10.1007%2F978-3-662-06071-1_13%7Chttps%3A%2F%2Fdoi.org%2F10.1080%2F03085140701254308%7Chttps%3A%2F%2Fdoi.org%2F10.3167%2F082279402782311031%7Chttps%3A%2F%2Fdoi.org%2F10.18235%2F0008819%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F1813-9450-3641%7Chttps%3A%2F%2Fdoi.org%2F10.2307%2F3762173%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F978-0-8213-6470-3%7Chttps%3A%2F%2Fdoi.org%2F10.1109%2Ficbbe.2008.538%7Chttps%3A%2F%2Fdoi.org%2F10.1080%2F21580103.2005.9656271%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F1813-9450-4703%7Chttps%3A%2F%2Fdoi.org%2F10.32800%2Fabc.2004.27.0283%7Chttps%3A%2F%2Fdoi.org%2F10.1080%2F00222930903219970%7Chttps%3A%2F%2Fdoi.org%2F10.1179%2F174328610x12682159814867%7Chttps%3A%2F%2Fdoi.org%2F10.1088%2F1748-9326%2F4%2F3%2F031003%7Chttps%3A%2F%2Fdoi.org%2F10.2118%2F98840-ms%7Chttps%3A%2F%2Fdoi.org%2F10.2139%2Fssrn.278513%7Chttps%3A%2F%2Fdoi.org%2F10.4314%2Fgjs.v47i1.15925%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F0-8213-3579-0%7Chttps%3A%2F%2Fdoi.org%2F10.2307%2F3868449%7Chttps%3A%2F%2Fdoi.org%2F10.1504%2Fijsd.2000.001526%7Chttps%3A%2F%2Fdoi.org%2F10.22004%2Fag.econ.51794%7Chttps%3A%2F%2Fdoi.org%2F10.22004%2Fag.econ.44792"
      
      $chunk_3
      [1] "https://api.openalex.org/works?filter=doi%3Ahttps%3A%2F%2Fdoi.org%2F10.1108%2Feb059277%7Chttps%3A%2F%2Fdoi.org%2F10.1093%2F0195125789.003.0014%7Chttps%3A%2F%2Fdoi.org%2F10.1080%2F13880290500343640%7Chttps%3A%2F%2Fdoi.org%2F10.4314%2F255%7Chttps%3A%2F%2Fdoi.org%2F10.1163%2F19426720-01404002%7Chttps%3A%2F%2Fdoi.org%2F10.1596%2F978-0-8213-7849-6%7Chttps%3A%2F%2Fdoi.org%2F10.1355%2Fae25-1a%7Chttps%3A%2F%2Fdoi.org%2F10.3133%2F70157208%7Chttps%3A%2F%2Fdoi.org%2F10.5367%2F000000002101293859%7Chttps%3A%2F%2Fdoi.org%2F10.4314%2Fmcd.v4i1.44010%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.0141-6707.2007.00799.x%7Chttps%3A%2F%2Fdoi.org%2F10.1016%2Fs1569-3740%2807%2907014-9%7Chttps%3A%2F%2Fdoi.org%2F10.1081%2Fpb-120022988%7Chttps%3A%2F%2Fdoi.org%2F10.1163%2F9789004475236_046%7Chttps%3A%2F%2Fdoi.org%2F10.1017%2Fcbo9780511720871.010%7Chttps%3A%2F%2Fdoi.org%2F10.1163%2F19426720-01401008%7Chttps%3A%2F%2Fdoi.org%2F10.1016%2Fs0140-6736%2805%2917953-7%7Chttps%3A%2F%2Fdoi.org%2F10.2523%2F98840-ms%7Chttps%3A%2F%2Fdoi.org%2F10.18174%2F43129%7Chttps%3A%2F%2Fdoi.org%2F10.1126%2Fscience.281.5375.347c%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.1365-2656.2008.01382.x%7Chttps%3A%2F%2Fdoi.org%2F10.4257%2F255%7Chttps%3A%2F%2Fdoi.org%2F10.5075%2Fepfl-thesis-3735%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.1523-1739.2009.01239.x%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.1523-1739.2005.00323_3.x%7Chttps%3A%2F%2Fdoi.org%2F10.1016%2Fs0140-6736%2802%2909773-8%7Chttps%3A%2F%2Fdoi.org%2F10.2307%2F3868101%7Chttps%3A%2F%2Fdoi.org%2F10.22004%2Fag.econ.16608%7Chttps%3A%2F%2Fdoi.org%2F10.1108%2F09566169210010879%7Chttps%3A%2F%2Fdoi.org%2F10.4337%2F9781035335510.00012%7Chttps%3A%2F%2Fdoi.org%2F10.4337%2F9781035335510.00009%7Chttps%3A%2F%2Fdoi.org%2F10.4337%2F9781035335510.00017%7Chttps%3A%2F%2Fdoi.org%2F10.4337%2F9781035335510.00011%7Chttps%3A%2F%2Fdoi.org%2F10.4337%2F9781035335510.00015%7Chttps%3A%2F%2Fdoi.org%2F10.4337%2F9781035335510.00018%7Chttps%3A%2F%2Fdoi.org%2F10.4337%2F9781035335510.00014%7Chttps%3A%2F%2Fdoi.org%2F10.4337%2F9781035335510.00016%7Chttps%3A%2F%2Fdoi.org%2F10.2478%2Fv10061-009-0021-6%7Chttps%3A%2F%2Fdoi.org%2F10.5962%2Fbhl.title.44952%7Chttps%3A%2F%2Fdoi.org%2F10.1890%2F1540-9295%282005%29003%5B0179%3Abf%5D2.0.co%3B2%7Chttps%3A%2F%2Fdoi.org%2F10.5531%2Fcbc.linc.2.1.2%7Chttps%3A%2F%2Fdoi.org%2F10.1890%2F0012-9623-90.3.235%7Chttps%3A%2F%2Fdoi.org%2F10.1093%2Fembo-reports%2Fkvd069%7Chttps%3A%2F%2Fdoi.org%2F10.1017%2Fcbo9780511494659.021%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.1467-7679.1995.tb00102.x%7Chttps%3A%2F%2Fdoi.org%2F10.22004%2Fag.econ.58897%7Chttps%3A%2F%2Fdoi.org%2F10.1016%2F1043-4542%2895%2990148-5%7Chttps%3A%2F%2Fdoi.org%2F10.1017%2Fcbo9780511813511.023%7Chttps%3A%2F%2Fdoi.org%2F10.31357%2Ffesympo.v0i0.1473.g646%7Chttps%3A%2F%2Fdoi.org%2F10.1163%2F9789004190351_002"
      
      $chunk_4
      [1] "https://api.openalex.org/works?filter=doi%3Ahttps%3A%2F%2Fdoi.org%2F10.2139%2Fssrn.1377782%7Chttps%3A%2F%2Fdoi.org%2F10.22004%2Fag.econ.124521%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.1936-704x.2009.00057.x%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.1574-0862.2007.00258.x%7Chttps%3A%2F%2Fdoi.org%2F10.1080%2F0969160x.2002.9651670%7Chttps%3A%2F%2Fdoi.org%2F10.1061%2F40976%28316%29266%7Chttps%3A%2F%2Fdoi.org%2F10.5070%2Fg31410232%7Chttps%3A%2F%2Fdoi.org%2F10.1061%2F40761%28175%2960%7Chttps%3A%2F%2Fdoi.org%2F10.1046%2Fj.1472-4642.2000.00073-2.x%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.1936-704x.2009.00060.x%7Chttps%3A%2F%2Fdoi.org%2F10.2139%2Fssrn.1071862%7Chttps%3A%2F%2Fdoi.org%2F10.4337%2F9781848446083.00039%7Chttps%3A%2F%2Fdoi.org%2F10.2981%2Fwlb.2003.057%7Chttps%3A%2F%2Fdoi.org%2F10.2139%2Fssrn.3371391%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.1523-1739.2005.1877_2.x%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.1936-704x.2009.00036.x%7Chttps%3A%2F%2Fdoi.org%2F10.1890%2F0012-9623%282008%2989%5B475%3Astdacc%5D2.0.co%3B2%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.1467-6435.1995.tb01287.x%7Chttps%3A%2F%2Fdoi.org%2F10.1890%2F0012-9623-90.4.360%7Chttps%3A%2F%2Fdoi.org%2F10.1890%2F1540-9295%282003%29001%5B0455%3Apttu%5D2.0.co%3B2%7Chttps%3A%2F%2Fdoi.org%2F10.1890%2F1540-9295%282004%29002%5B0227%3Atotet%5D2.0.co%3B2%7Chttps%3A%2F%2Fdoi.org%2F10.1111%2Fj.1523-1739.2009.01319.x%7Chttps%3A%2F%2Fdoi.org%2F10.1890%2F0012-9623%282007%2988%5B22%3Amotegb%5D2.0.co%3B2%7Chttps%3A%2F%2Fdoi.org%2F10.18174%2F139413%7Chttps%3A%2F%2Fdoi.org%2F10.1098%2Frsnr.2007.0050"
      

# pro_request with url list  and parallel

    Code
      basename(fns)
    Output
      [1] "results_page_1.json" "results_page_2.json" "results_page_1.json"
      [4] "results_page_2.json" "results_page_1.json" "results_page_2.json"
      [7] "results_page_1.json" "results_page_2.json"

# pro_request_jsonl_parquet with subfolders

    Code
      basename(fns)
    Output
      [1] "results_page_1.json" "results_page_1.json" "results_page_1.json"
      [4] "results_page_1.json"
    Code
      p <- arrow::open_dataset(output_parquet)
      p
    Output
      FileSystemDataset with 4 Parquet files
      53 columns
      id: string
      doi: string
      title: string
      display_name: string
      publication_year: int64
      publication_date: date32[day]
      ids: struct<openalex: string, doi: string, mag: string, pmid: string, pmcid: string>
      language: string
      primary_location: struct<is_oa: bool, landing_page_url: string, pdf_url: string, source: struct<id: string, display_name: string, issn_l: string, issn: list<element: string>, is_oa: bool, is_in_doaj: bool, is_indexed_in_scopus: bool, is_core: bool, host_organization: string, host_organization_name: string, host_organization_lineage: list<element: string>, host_organization_lineage_names: list<element: string>, type: string>, license: string, license_id: string, version: string, is_accepted: bool, is_published: bool>
      type: string
      type_crossref: string
      indexed_in: list<element: string>
      open_access: struct<is_oa: bool, oa_status: string, oa_url: string, any_repository_has_fulltext: bool>
      authorships: list<element: struct<author_position: string, author: struct<id: string, display_name: string, orcid: string>, institutions: list<element: struct<id: string, display_name: string, ror: string, country_code: string, type: string, lineage: list<element: string>>>, countries: list<element: string>, is_corresponding: bool, raw_author_name: string, raw_affiliation_strings: list<element: string>, affiliations: list<element: struct<raw_affiliation_string: string, institution_ids: list<element: string>>>>>
      institution_assertions: list<element: string>
      countries_distinct_count: int64
      institutions_distinct_count: int64
      corresponding_author_ids: list<element: string>
      corresponding_institution_ids: list<element: string>
      apc_list: struct<value: int64, currency: string, value_usd: int64>
      ...
      33 more columns
      Use `schema()` to see entire schema
    Code
      dplyr::collect(dplyr::arrange(dplyr::distinct(dplyr::select(p, page)), page))
    Output
      # A tibble: 4 x 1
        page   
        <chr>  
      1 chunk_1
      2 chunk_2
      3 chunk_3
      4 chunk_4

