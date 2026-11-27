*&---------------------------------------------------------------------*
*& Report Z_ROLE_04_CREATE_COMPOSITE
*&---------------------------------------------------------------------*
*& Purpose: Batch PFCG Composite Role Creation & Single Role Assignment
*& Description:
*&   Reads a CSV (.csv) file containing composite role definitions and
*&   single role assignments (Composite Role Name, Composite Role
*&   Description, Single Role), validates single roles in SAP,
*&   creates or updates the Composite Roles (attributes = 'COLLECTIVE',
*&   flag COLL_AGR = 'X'), assigns member single roles via standard BAPIs
*&   (PRGN_RFC_ADD_AGRS_TO_COLL_AGR), synchronizes assignments, removes
*&   intrusive auto-generated comments from AGR_TEXTS, triggers profile
*&   comparison, and displays results in an interactive ALV cockpit with
*&   one-click navigation to transaction PFCG.
*&
*& File format (CSV .csv):
*&   Col 1: Composite Role Name        (e.g., Z_FI_COMP_CFO_1000)
*&   Col 2: Composite Role Description (e.g., Chief Financial Officer - Entity 1000)
*&   Col 3: Single Role                (e.g., Z_FI_PERIOD_CONTROL_1000 or N/A)
*&
*& Author: Antigravity AI (SAP Basis Engineering)
*& Package: $TMP (Local Object) or Custom Package
*&---------------------------------------------------------------------*
REPORT z_role_04_create_composite.

*----------------------------------------------------------------------*
* 1. TYPES & DATA DEFINITIONS
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_raw_row,
         col1 TYPE string,
         col2 TYPE string,
         col3 TYPE string,
       END OF ty_raw_row.

TYPES: BEGIN OF ty_composite_role,
         role_name     TYPE agr_name,
         role_desc     TYPE agr_title,
         has_na        TYPE abap_bool,
         single_roles  TYPE STANDARD TABLE OF agr_name WITH DEFAULT KEY,
         oversized_sgl TYPE string_table,
       END OF ty_composite_role.

TYPES: BEGIN OF ty_alv_result,
         status         TYPE char12,     " Status Icon & Code: @08@ [OK], @09@ [WARN], @0A@ [ERR]
         action         TYPE char12,     " Action: CREATED / UPDATED / UP-TO-DATE / SIMULATED / SKIPPED / WARNING / ERROR
         composite_role TYPE agr_name,   " Composite Role ID (Hotspot to PFCG)
         role_desc      TYPE agr_title,  " Composite Role Description
         roles_cnt      TYPE i,          " Total Single Roles in CSV
         valid_cnt      TYPE i,          " Valid Single Roles in SAP
         assigned_cnt   TYPE i,          " Total Active Single Roles in SAP
         roles_add_cnt  TYPE i,          " Single Roles Added (Count)
         roles_del_cnt  TYPE i,          " Single Roles Removed (Count)
         roles_keep_cnt TYPE i,          " Single Roles Retained (Count)
         roles_add      TYPE string,     " List of Single Roles Added
         roles_del      TYPE string,     " List of Single Roles Removed
         roles_keep     TYPE string,     " List of Single Roles Retained
         missing_roles  TYPE string,     " Single Roles missing from SAP
         message        TYPE string,     " Status Message / Execution Log
       END OF ty_alv_result.

CONSTANTS: gc_status_ok   TYPE char12 VALUE '@08@ [OK]',
           gc_status_warn TYPE char12 VALUE '@09@ [WARN]',
           gc_status_err  TYPE char12 VALUE '@0A@ [ERR]'.

DATA: gt_raw_rows        TYPE STANDARD TABLE OF ty_raw_row,
      gt_composite_roles TYPE STANDARD TABLE OF ty_composite_role,
      gt_results         TYPE STANDARD TABLE OF ty_alv_result,
      gt_oversized_roles TYPE STANDARD TABLE OF string.

*----------------------------------------------------------------------*
* 2. SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b_file WITH FRAME TITLE b_tit1.
  PARAMETERS: p_file TYPE localfile OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b_file.

SELECTION-SCREEN BEGIN OF BLOCK b_opt WITH FRAME TITLE b_tit2.
  PARAMETERS: p_test   TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_upd    TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_sync   TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_chksgl TYPE abap_bool AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b_opt.

*----------------------------------------------------------------------*
* 3. INITIALIZATION & SCREEN EVENTS
*----------------------------------------------------------------------*
INITIALIZATION.
  b_tit1 = 'Input CSV File (.csv)'(b01).
  b_tit2 = 'Execution & Assignment Options'(b02).

  %_p_file_%_app_%-text   = 'File Path'.
  %_p_test_%_app_%-text   = 'Simulation (Test Run)'.
  %_p_upd_%_app_%-text    = 'Update Composite Roles'.
  %_p_sync_%_app_%-text   = 'Synchronize Single Roles'.
  %_p_chksgl_%_app_%-text = 'Validate Single Roles in SAP'.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  PERFORM f4_file_open CHANGING p_file.

AT SELECTION-SCREEN ON p_file.
  PERFORM validate_filename USING p_file.

*----------------------------------------------------------------------*
* 4. START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.
  PERFORM check_authority.
  PERFORM upload_and_parse_file.
  PERFORM aggregate_input_data.
  PERFORM process_composite_roles.
  PERFORM display_alv_results.

*&---------------------------------------------------------------------*
*& Form f4_file_open
*&---------------------------------------------------------------------*
FORM f4_file_open CHANGING cv_file TYPE localfile.
  DATA: lt_file_table TYPE filetable,
        lv_rc         TYPE i.

  cl_gui_frontend_services=>file_open_dialog(
    EXPORTING
      window_title            = 'Select Composite Roles CSV File'
      file_filter             = 'Composite Role CSV (*04_Composite*.csv)|*04_Composite*.csv|CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'
    CHANGING
      file_table              = lt_file_table
      rc                      = lv_rc
    EXCEPTIONS
      file_open_dialog_failed = 1
      cntl_error              = 2
      error_no_gui            = 3
      not_supported_by_gui    = 4
      OTHERS                  = 5 ).

  IF sy-subrc = 0 AND lines( lt_file_table ) > 0.
    cv_file = lt_file_table[ 1 ]-filename.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form validate_filename
*&---------------------------------------------------------------------*
FORM validate_filename USING iv_file TYPE localfile.
  DATA: lv_fname TYPE string,
        lt_parts TYPE STANDARD TABLE OF string.

  IF iv_file IS INITIAL.
    RETURN.
  ENDIF.

  lv_fname = iv_file.
  REPLACE ALL OCCURRENCES OF '/' IN lv_fname WITH '\'.
  SPLIT lv_fname AT '\' INTO TABLE lt_parts.
  IF lines( lt_parts ) > 0.
    lv_fname = lt_parts[ lines( lt_parts ) ].
  ENDIF.

  DATA(lv_up) = to_upper( condense( lv_fname ) ).
  IF strlen( lv_up ) <= 4 OR NOT ( lv_up CP '*.CSV' ).
    MESSAGE |Invalid file '{ lv_fname }'. Expected CSV file (*_04_Composite_converted.csv).| TYPE 'E'.
  ENDIF.

  IF NOT ( lv_up CS '04_COMPOSITE' OR lv_up CS '_COMPOSITE' )
     OR lv_up CS '01_MASTER' OR lv_up CS '02_DERIVE' OR lv_up CS '03A_ORG'
     OR lv_up CS '03B_AUTH' OR lv_up CS '03B_OBJECT' OR lv_up CS '03C_ACTIVITY'
     OR lv_up CS '01_CREATE' OR lv_up CS '02_ASSIGN'.
    MESSAGE |Invalid file '{ lv_fname }' for Z_ROLE_04_CREATE_COMPOSITE. Expected '*_04_Composite_converted.csv'.| TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form check_authority
*&---------------------------------------------------------------------*
FORM check_authority.
  IF p_test = abap_true.
    AUTHORITY-CHECK OBJECT 'S_USER_AGR'
      ID 'ACT_GROUP' DUMMY
      ID 'ACTVT'     FIELD '03'.
    IF sy-subrc <> 0.
      MESSAGE 'No authorization to display roles (S_USER_AGR, ACTVT 03).' TYPE 'E'.
    ENDIF.
    RETURN.
  ENDIF.

  AUTHORITY-CHECK OBJECT 'S_USER_AGR'
    ID 'ACT_GROUP' DUMMY
    ID 'ACTVT'     FIELD '01'.
  IF sy-subrc <> 0.
    AUTHORITY-CHECK OBJECT 'S_USER_AGR'
      ID 'ACT_GROUP' DUMMY
      ID 'ACTVT'     FIELD '02'.
    IF sy-subrc <> 0.
      MESSAGE 'No authorization to create/maintain roles (S_USER_AGR, ACTVT 01/02).' TYPE 'E'.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form upload_and_parse_file
*&---------------------------------------------------------------------*
FORM upload_and_parse_file.
  CLEAR gt_raw_rows.

  IF p_file IS INITIAL.
    MESSAGE 'Please specify a file path.' TYPE 'E'.
  ENDIF.

  PERFORM read_csv_file USING p_file.

  IF gt_raw_rows IS INITIAL.
    MESSAGE 'No valid data rows found in input file.' TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form read_csv_file
*&---------------------------------------------------------------------*
FORM read_csv_file USING iv_file TYPE localfile.
  DATA: lt_file_records TYPE truxs_t_text_data,
        lv_filepath     TYPE string,
        lv_line         TYPE string,
        lv_line_idx     TYPE i,
        ls_raw          TYPE ty_raw_row,
        lv_c1           TYPE string,
        lv_c2           TYPE string,
        lv_c3           TYPE string.

  lv_filepath = iv_file.

  cl_gui_frontend_services=>gui_upload(
    EXPORTING
      filename                = lv_filepath
      filetype                = 'ASC'
      has_field_separator     = space
      codepage                = '4110'
    CHANGING
      data_tab                = lt_file_records
    EXCEPTIONS
      file_open_error         = 1
      file_read_error         = 2
      no_batch                = 3
      gui_refuse_filetransfer = 4
      invalid_type            = 5
      no_authority            = 6
      unknown_error           = 7
      bad_data_format         = 8
      OTHERS                  = 9 ).

  IF sy-subrc <> 0.
    MESSAGE 'Failed to read CSV file from client workstation.' TYPE 'E'.
  ENDIF.

  DATA(lv_utf8_bom) = cl_abap_conv_in_ce=>uccp( 'FEFF' ).
  DATA: lv_file_delim      TYPE c LENGTH 1 VALUE ',',
        lv_delim_set       TYPE abap_bool VALUE abap_false,
        lv_first_non_empty TYPE abap_bool VALUE abap_false.

  CLEAR lv_line_idx.
  LOOP AT lt_file_records INTO lv_line.
    lv_line_idx = lv_line_idx + 1.
    IF lv_line_idx = 1 AND lv_line IS NOT INITIAL AND lv_line(1) = lv_utf8_bom.
      SHIFT lv_line LEFT BY 1 PLACES.
    ENDIF.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf(1) IN lv_line WITH ''.
    IF lv_line IS INITIAL.
      CONTINUE.
    ENDIF.

    IF lv_delim_set = abap_false.
      PERFORM detect_csv_delimiter USING lv_line CHANGING lv_file_delim.
      lv_delim_set = abap_true.
    ENDIF.

    CLEAR: lv_c1, lv_c2, lv_c3.
    PERFORM parse_csv_line USING lv_line lv_file_delim
                           CHANGING lv_c1 lv_c2 lv_c3.

    " Validate & skip header row on first non-empty line using exact equality
    DATA(lv_c1_up) = to_upper( lv_c1 ).
    DATA(lv_c2_up) = to_upper( lv_c2 ).
    DATA(lv_c3_up) = to_upper( lv_c3 ).

    IF lv_first_non_empty = abap_false.
      lv_first_non_empty = abap_true.
      IF lv_c3_up = 'TCODE' OR lv_c3_up = 'TRANSACTION' OR lv_c3_up = 'TRANSACTION CODE'
         OR lv_c1_up = 'MASTER ROLE' OR lv_c1_up = 'MASTER_ROLE'
         OR lv_c2_up = 'DERIVED ROLE' OR lv_c2_up = 'DERIVED_ROLE'
         OR lv_c2_up = 'ORG LEVEL' OR lv_c2_up = 'ORG_LEVEL' OR lv_c2_up = 'VARBL'
         OR lv_c2_up = 'OBJECT-FIELD' OR lv_c2_up = 'FIELD'
         OR lv_c1_up = 'USERNAME' OR lv_c1_up = 'USER' OR lv_c1_up = 'USER ID'
         OR lv_c1_up = 'BNAME' OR lv_c1_up = 'ROLE'
         OR ( lv_c1_up = 'ROLE NAME' AND lv_c3_up IS INITIAL ).
        MESSAGE 'Invalid CSV header for Z_ROLE_04_CREATE_COMPOSITE. Expected: Composite Role Name, Composite Role Description, Single Role.' TYPE 'E'.
      ENDIF.
      IF lv_c1_up = 'COMPOSITE ROLE' OR lv_c1_up = 'COMPOSITE_ROLE'
         OR lv_c1_up = 'COMPOSITE ROLE NAME' OR lv_c1_up = 'COMPOSITE_ROLE_NAME'
         OR lv_c3_up = 'SINGLE ROLE' OR lv_c3_up = 'SINGLE_ROLE'
         OR lv_c3_up = 'SINGLE ROLE NAME'.
        CONTINUE.
      ENDIF.
    ENDIF.
    IF lv_c1_up = 'COMPOSITE ROLE' OR lv_c1_up = 'COMPOSITE_ROLE'
       OR lv_c1_up = 'COMPOSITE ROLE NAME' OR lv_c1_up = 'COMPOSITE_ROLE_NAME'
       OR lv_c1_up = 'ROLE NAME' OR lv_c1_up = 'ROLE'
       OR lv_c3_up = 'DERIVED ROLE' OR lv_c3_up = 'SINGLE ROLE' OR lv_c3_up = 'CHILD_AGR'.
      CONTINUE.
    ENDIF.

    IF lv_c1 IS NOT INITIAL.
      CLEAR ls_raw.
      ls_raw-col1 = lv_c1.
      ls_raw-col2 = lv_c2.
      ls_raw-col3 = lv_c3.
      APPEND ls_raw TO gt_raw_rows.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form detect_csv_delimiter
*&---------------------------------------------------------------------*
FORM detect_csv_delimiter USING    iv_line  TYPE string
                          CHANGING ev_delim TYPE c.
  DATA: lv_len      TYPE i,
        lv_pos      TYPE i,
        lv_in_q     TYPE abap_bool VALUE abap_false,
        lv_char     TYPE string,
        lv_next     TYPE string,
        lv_cnt_tab  TYPE i,
        lv_cnt_semi TYPE i,
        lv_cnt_com  TYPE i.

  lv_len = strlen( iv_line ).
  lv_pos = 0.
  WHILE lv_pos < lv_len.
    lv_char = substring( val = iv_line off = lv_pos len = 1 ).
    IF lv_char = '"'.
      IF lv_in_q = abap_true AND lv_pos + 1 < lv_len.
        lv_next = substring( val = iv_line off = lv_pos + 1 len = 1 ).
        IF lv_next = '"'.
          lv_pos = lv_pos + 2.
          CONTINUE.
        ENDIF.
      ENDIF.
      lv_in_q = xsdbool( lv_in_q = abap_false ).
    ELSEIF lv_in_q = abap_false.
      IF lv_char = cl_abap_char_utilities=>horizontal_tab.
        lv_cnt_tab = lv_cnt_tab + 1.
      ELSEIF lv_char = ';'.
        lv_cnt_semi = lv_cnt_semi + 1.
      ELSEIF lv_char = ','.
        lv_cnt_com = lv_cnt_com + 1.
      ENDIF.
    ENDIF.
    lv_pos = lv_pos + 1.
  ENDWHILE.

  IF lv_cnt_tab > 0.
    ev_delim = cl_abap_char_utilities=>horizontal_tab.
  ELSEIF lv_cnt_semi > 0 AND lv_cnt_semi >= lv_cnt_com.
    ev_delim = ';'.
  ELSE.
    ev_delim = ','.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form parse_csv_line
*&---------------------------------------------------------------------*
FORM parse_csv_line USING    iv_line  TYPE string
                             iv_delim TYPE c
                    CHANGING ev_col1  TYPE string
                             ev_col2  TYPE string
                             ev_col3  TYPE string.
  DATA: lt_tokens TYPE STANDARD TABLE OF string,
        lv_len    TYPE i,
        lv_in_q   TYPE abap_bool VALUE abap_false,
        lv_cur    TYPE string,
        lv_char   TYPE string,
        lv_next   TYPE string,
        lv_idx    TYPE i,
        lv_delim  TYPE c LENGTH 1.

  CLEAR: ev_col1, ev_col2, ev_col3.

  lv_delim = iv_delim.
  IF lv_delim IS INITIAL.
    lv_delim = ','.
  ENDIF.

  lv_len = strlen( iv_line ).
  lv_idx = 0.
  WHILE lv_idx < lv_len.
    lv_char = substring( val = iv_line off = lv_idx len = 1 ).

    IF lv_char = '"'.
      IF lv_in_q = abap_true.
        IF lv_idx + 1 < lv_len.
          lv_next = substring( val = iv_line off = lv_idx + 1 len = 1 ).
          IF lv_next = '"'.
            lv_cur = lv_cur && '"'.
            lv_idx = lv_idx + 2.
            CONTINUE.
          ENDIF.
        ENDIF.
        lv_in_q = abap_false.
      ELSE.
        lv_in_q = abap_true.
      ENDIF.
    ELSEIF lv_char = lv_delim AND lv_in_q = abap_false.
      APPEND lv_cur TO lt_tokens.
      CLEAR lv_cur.
    ELSE.
      lv_cur = lv_cur && lv_char.
    ENDIF.

    lv_idx = lv_idx + 1.
  ENDWHILE.
  APPEND lv_cur TO lt_tokens.

  IF lines( lt_tokens ) >= 1.
    ev_col1 = lt_tokens[ 1 ].
    ev_col1 = to_upper( condense( ev_col1 ) ).
  ENDIF.
  IF lines( lt_tokens ) >= 2.
    ev_col2 = lt_tokens[ 2 ]. " Keep exact spacing as in input file (no trim/condense)
  ENDIF.
  IF lines( lt_tokens ) >= 3.
    ev_col3 = lt_tokens[ 3 ].
    ev_col3 = to_upper( condense( ev_col3 ) ).
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form aggregate_input_data
*&---------------------------------------------------------------------*
FORM aggregate_input_data.
  DATA: lv_c_raw  TYPE string,
        lv_s_raw  TYPE string,
        lv_c_role TYPE agr_name,
        lv_c_desc TYPE agr_title,
        lv_s_role TYPE agr_name.

  CLEAR: gt_composite_roles, gt_oversized_roles.

  LOOP AT gt_raw_rows INTO DATA(ls_raw).
    lv_c_raw  = to_upper( condense( ls_raw-col1 ) ).
    lv_c_desc = ls_raw-col2. " Exact spacing preserved
    lv_s_raw  = to_upper( condense( ls_raw-col3 ) ).

    IF lv_c_raw IS INITIAL.
      CONTINUE.
    ENDIF.

    " Guard against silent >30-char truncation before assigning to TYPE agr_name
    IF strlen( lv_c_raw ) > 30.
      READ TABLE gt_oversized_roles WITH KEY table_line = lv_c_raw TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND lv_c_raw TO gt_oversized_roles.
      ENDIF.
      CONTINUE.
    ENDIF.

    lv_c_role = lv_c_raw.

    READ TABLE gt_composite_roles ASSIGNING FIELD-SYMBOL(<ls_comp>)
      WITH KEY role_name = lv_c_role.
    IF sy-subrc <> 0.
      APPEND VALUE ty_composite_role(
        role_name = lv_c_role
        role_desc = lv_c_desc
      ) TO gt_composite_roles ASSIGNING <ls_comp>.
    ENDIF.

    IF <ls_comp>-role_desc IS INITIAL AND lv_c_desc IS NOT INITIAL.
      <ls_comp>-role_desc = lv_c_desc.
    ENDIF.

    IF lv_s_raw = 'N/A' OR lv_s_raw = 'NA' OR lv_s_raw = '-' OR lv_s_raw = 'NONE' OR lv_s_raw IS INITIAL.
      <ls_comp>-has_na = abap_true.
    ELSEIF strlen( lv_s_raw ) <= 30.
      lv_s_role = lv_s_raw.
      READ TABLE <ls_comp>-single_roles WITH KEY table_line = lv_s_role
        TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND lv_s_role TO <ls_comp>-single_roles.
      ENDIF.
    ELSE.
      READ TABLE <ls_comp>-oversized_sgl WITH KEY table_line = lv_s_raw
        TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND lv_s_raw TO <ls_comp>-oversized_sgl.
      ENDIF.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form process_composite_roles
*&---------------------------------------------------------------------*
FORM process_composite_roles.
  DATA: ls_res          TYPE ty_alv_result,
        lt_bapiret      TYPE STANDARD TABLE OF bapiret2,
        lv_exists       TYPE abap_bool,
        lv_coll_flag    TYPE char01,
        lv_dummy        TYPE agr_name,
        lt_valid_sgl    TYPE STANDARD TABLE OF agr_name,
        lt_missing_sgl  TYPE STANDARD TABLE OF agr_name,
        lt_colls_sgl    TYPE STANDARD TABLE OF agr_name,
        lt_add_txt      TYPE STANDARD TABLE OF agr_txt,
        lt_del_txt      TYPE STANDARD TABLE OF agr_txt,
        lt_curr_agrs    TYPE STANDARD TABLE OF agr_agrs,
        lv_new_req      TYPE trkorr,
        lv_missing_str  TYPE string,
        lv_colls_str    TYPE string,
        lv_rc           TYPE sy-subrc,
        lv_op_err       TYPE string,
        lv_op_warn      TYPE string,
        lv_desc_warn    TYPE string,
        lv_cur_desc     TYPE agr_title.

  CLEAR gt_results.

  LOOP AT gt_oversized_roles INTO DATA(lv_bad_comp).
    CLEAR ls_res.
    ls_res-status         = gc_status_err.
    ls_res-action         = 'ERROR'.
    ls_res-composite_role = lv_bad_comp.
    ls_res-message        = |Composite role name exceeds SAP 30-character limit: '{ lv_bad_comp }'.|.
    APPEND ls_res TO gt_results.
  ENDLOOP.

  LOOP AT gt_composite_roles INTO DATA(ls_comp).
    CLEAR: ls_res, lt_bapiret, lv_exists, lv_coll_flag, lv_dummy,
           lt_valid_sgl, lt_missing_sgl, lt_colls_sgl, lt_add_txt, lt_del_txt,
           lt_curr_agrs, lv_new_req, lv_missing_str, lv_colls_str,
           lv_rc, lv_op_err, lv_op_warn, lv_desc_warn, lv_cur_desc.

    ls_res-composite_role = ls_comp-role_name.
    ls_res-role_desc      = ls_comp-role_desc.
    ls_res-roles_cnt      = lines( ls_comp-single_roles ).

    " -----------------------------------------------------------------
    " 2. Per-Role Authority Check & Existing Role Type Validation
    " -----------------------------------------------------------------
    IF p_test = abap_true.
      AUTHORITY-CHECK OBJECT 'S_USER_AGR'
        ID 'ACT_GROUP' FIELD ls_comp-role_name
        ID 'ACTVT'     FIELD '03'.
      IF sy-subrc <> 0.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'ERROR'.
        ls_res-message = |No authorization for role '{ ls_comp-role_name }' (S_USER_AGR, ACTVT 03).|.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.
    ELSE.
      AUTHORITY-CHECK OBJECT 'S_USER_AGR'
        ID 'ACT_GROUP' FIELD ls_comp-role_name
        ID 'ACTVT'     FIELD '02'.
      IF sy-subrc <> 0.
        AUTHORITY-CHECK OBJECT 'S_USER_AGR'
          ID 'ACT_GROUP' FIELD ls_comp-role_name
          ID 'ACTVT'     FIELD '01'.
        IF sy-subrc <> 0.
          ls_res-status  = gc_status_err.
          ls_res-action  = 'ERROR'.
          ls_res-message = |No authorization for role '{ ls_comp-role_name }' (S_USER_AGR, ACTVT 01/02).|.
          APPEND ls_res TO gt_results.
          CONTINUE.
        ENDIF.
      ENDIF.
    ENDIF.

    SELECT SINGLE agr_name FROM agr_define INTO lv_dummy
      WHERE agr_name = ls_comp-role_name.
    IF sy-subrc = 0.
      lv_exists = abap_true.
      SELECT SINGLE flag_value FROM agr_flags INTO lv_coll_flag
        WHERE agr_name = ls_comp-role_name AND flag_type = 'COLL_AGR'.
      IF sy-subrc <> 0 OR lv_coll_flag <> 'X'.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'ERROR'.
        ls_res-message = |Role '{ ls_comp-role_name }' exists in SAP as a SINGLE role; cannot overwrite single role as composite role.|.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.
    ELSE.
      lv_exists = abap_false.
    ENDIF.

    DATA(lv_req_actvt) = COND activ_auth(
      WHEN p_test = abap_true THEN '03'
      WHEN lv_exists = abap_true THEN '02'
      ELSE '01' ).
    AUTHORITY-CHECK OBJECT 'S_USER_AGR'
      ID 'ACT_GROUP' FIELD ls_comp-role_name
      ID 'ACTVT'     FIELD lv_req_actvt.
    IF sy-subrc <> 0.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = |No authorization for role '{ ls_comp-role_name }' (S_USER_AGR, ACTVT { lv_req_actvt }).|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " 3. Validate Single Roles in SAP (AGR_DEFINE & AGR_FLAGS)
    " -----------------------------------------------------------------
    IF ls_comp-single_roles IS NOT INITIAL AND p_chksgl = abap_true.
      LOOP AT ls_comp-single_roles INTO DATA(lv_chk_role).
        IF lv_chk_role = ls_comp-role_name.
          APPEND lv_chk_role TO lt_colls_sgl.
          CONTINUE.
        ENDIF.
        CLEAR lv_dummy.
        SELECT SINGLE agr_name FROM agr_define INTO lv_dummy
          WHERE agr_name = lv_chk_role.
        IF sy-subrc <> 0.
          APPEND lv_chk_role TO lt_missing_sgl.
        ELSE.
          CLEAR lv_coll_flag.
          SELECT SINGLE flag_value FROM agr_flags INTO lv_coll_flag
            WHERE agr_name = lv_chk_role AND flag_type = 'COLL_AGR'.
          IF sy-subrc = 0 AND lv_coll_flag = 'X'.
            APPEND lv_chk_role TO lt_colls_sgl.
          ELSE.
            APPEND lv_chk_role TO lt_valid_sgl.
          ENDIF.
        ENDIF.
      ENDLOOP.

      ls_res-valid_cnt = lines( lt_valid_sgl ).

      LOOP AT lt_missing_sgl INTO DATA(lv_m).
        lv_missing_str = COND #( WHEN lv_missing_str IS INITIAL THEN lv_m ELSE lv_missing_str && ', ' && lv_m ).
      ENDLOOP.
      LOOP AT lt_colls_sgl INTO DATA(lv_c_ex).
        lv_colls_str = COND #( WHEN lv_colls_str IS INITIAL THEN lv_c_ex ELSE lv_colls_str && ', ' && lv_c_ex ).
      ENDLOOP.
      ls_res-missing_roles = lv_missing_str.

    ELSEIF ls_comp-single_roles IS NOT INITIAL.
      LOOP AT ls_comp-single_roles INTO lv_chk_role.
        IF lv_chk_role = ls_comp-role_name.
          APPEND lv_chk_role TO lt_colls_sgl.
        ELSE.
          APPEND lv_chk_role TO lt_valid_sgl.
        ENDIF.
      ENDLOOP.
      LOOP AT lt_colls_sgl INTO lv_c_ex.
        lv_colls_str = COND #( WHEN lv_colls_str IS INITIAL THEN lv_c_ex ELSE lv_colls_str && ', ' && lv_c_ex ).
      ENDLOOP.
      ls_res-valid_cnt = lines( lt_valid_sgl ).
    ELSE.
      ls_res-valid_cnt = 0.
    ENDIF.

    " -----------------------------------------------------------------
    " 4. Enqueue (Live updates) BEFORE Reading AGR_AGRS / AGR_TEXTS
    "    (Release before RFC calls which manage their own lock)
    " -----------------------------------------------------------------
    DATA: lt_roles_to_add TYPE STANDARD TABLE OF agr_name,
          lt_roles_to_del TYPE STANDARD TABLE OF agr_name,
          lt_roles_keep   TYPE STANDARD TABLE OF agr_name,
          lv_str_add      TYPE string,
          lv_str_del      TYPE string,
          lv_str_keep     TYPE string,
          lv_enq_held4    TYPE abap_bool.

    CLEAR: lt_roles_to_add, lt_roles_to_del, lt_roles_keep,
           lv_str_add, lv_str_del, lv_str_keep, lv_enq_held4.

    IF p_test = abap_false AND lv_exists = abap_true AND p_upd = abap_true.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
        EXPORTING
          activity_group = ls_comp-role_name
          no_dialog      = 'X'
        EXCEPTIONS
          OTHERS         = 1.
      IF sy-subrc <> 0.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'ERROR'.
        ls_res-message = |Composite role '{ ls_comp-role_name }' is locked before read (rc={ sy-subrc }).|.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.
      lv_enq_held4 = abap_true.
    ENDIF.

    SELECT * FROM agr_agrs INTO TABLE @lt_curr_agrs
      WHERE agr_name = @ls_comp-role_name.

    LOOP AT lt_valid_sgl INTO DATA(lv_s_chk).
      READ TABLE lt_curr_agrs WITH KEY child_agr = lv_s_chk TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND lv_s_chk TO lt_roles_to_add.
      ENDIF.
    ENDLOOP.

    IF p_sync = abap_true.
      LOOP AT lt_curr_agrs INTO DATA(ls_c_del).
        READ TABLE lt_valid_sgl WITH KEY table_line = ls_c_del-child_agr TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          APPEND ls_c_del-child_agr TO lt_roles_to_del.
        ENDIF.
      ENDLOOP.
      LOOP AT lt_curr_agrs INTO DATA(ls_c_keep).
        READ TABLE lt_valid_sgl WITH KEY table_line = ls_c_keep-child_agr TRANSPORTING NO FIELDS.
        IF sy-subrc = 0.
          APPEND ls_c_keep-child_agr TO lt_roles_keep.
        ENDIF.
      ENDLOOP.
    ELSE.
      " Append mode: ALL existing assigned single roles are retained
      LOOP AT lt_curr_agrs INTO ls_c_keep.
        APPEND ls_c_keep-child_agr TO lt_roles_keep.
      ENDLOOP.
    ENDIF.

    ls_res-roles_add_cnt  = lines( lt_roles_to_add ).
    ls_res-roles_del_cnt  = lines( lt_roles_to_del ).
    ls_res-roles_keep_cnt = lines( lt_roles_keep ).

    LOOP AT lt_roles_to_add INTO DATA(lv_a).
      lv_str_add = COND #( WHEN lv_str_add IS INITIAL THEN lv_a ELSE lv_str_add && ', ' && lv_a ).
    ENDLOOP.
    ls_res-roles_add = lv_str_add.

    LOOP AT lt_roles_to_del INTO DATA(lv_d).
      lv_str_del = COND #( WHEN lv_str_del IS INITIAL THEN lv_d ELSE lv_str_del && ', ' && lv_d ).
    ENDLOOP.
    ls_res-roles_del = lv_str_del.

    LOOP AT lt_roles_keep INTO DATA(lv_k).
      lv_str_keep = COND #( WHEN lv_str_keep IS INITIAL THEN lv_k ELSE lv_str_keep && ', ' && lv_k ).
    ENDLOOP.
    ls_res-roles_keep = lv_str_keep.

    DATA: lv_is_up_to_date TYPE abap_bool.
    IF lt_roles_to_add IS INITIAL AND lt_roles_to_del IS INITIAL AND lv_exists = abap_true.
      lv_is_up_to_date = abap_true.
    ELSE.
      lv_is_up_to_date = abap_false.
    ENDIF.

    " Guard: block Sync wipe if CSV contained >30-char member single role names
    IF ls_comp-oversized_sgl IS NOT INITIAL.
      IF lv_enq_held4 = abap_true.
        CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
          EXPORTING
            activity_group = ls_comp-role_name
          EXCEPTIONS
            OTHERS         = 0.
        lv_enq_held4 = abap_false.
      ENDIF.
      DATA: lv_ov_sgl_str TYPE string.
      CLEAR lv_ov_sgl_str.
      LOOP AT ls_comp-oversized_sgl INTO DATA(lv_ovs).
        lv_ov_sgl_str = COND #( WHEN lv_ov_sgl_str IS INITIAL THEN lv_ovs ELSE lv_ov_sgl_str && ', ' && lv_ovs ).
      ENDLOOP.
      ls_res-status       = gc_status_err.
      ls_res-action       = 'ERROR'.
      ls_res-assigned_cnt = lines( lt_curr_agrs ).
      ls_res-message      = |Aborted: { lines( ls_comp-oversized_sgl ) } member role(s) exceed 30-char limit: [{ lv_ov_sgl_str }].|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " Guard (R04-01): block destructive Two-Way Sync removal when CSV has missing/invalid single roles
    IF p_sync = abap_true AND lt_roles_to_del IS NOT INITIAL
       AND ( lt_missing_sgl IS NOT INITIAL OR lt_colls_sgl IS NOT INITIAL
             OR ( lt_valid_sgl IS INITIAL AND ls_comp-has_na = abap_false ) ).
      IF lv_enq_held4 = abap_true.
        CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
          EXPORTING
            activity_group = ls_comp-role_name
          EXCEPTIONS
            OTHERS         = 0.
        lv_enq_held4 = abap_false.
      ENDIF.
      ls_res-status       = gc_status_err.
      ls_res-action       = 'ERROR'.
      ls_res-assigned_cnt = lines( lt_curr_agrs ).
      ls_res-message      = |Two-Way Sync aborted to prevent unintended single-role removal: CSV has missing/invalid role(s). Missing=[{ lv_missing_str }] Excluded=[{ lv_colls_str }].|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " Check if description would change for existing composite role (consistent across Simulation & Live)
    DATA(lv_desc_changed) = abap_false.
    IF lv_exists = abap_true AND ls_comp-role_desc IS NOT INITIAL.
      SELECT SINGLE text FROM agr_texts INTO @lv_cur_desc
        WHERE agr_name = @ls_comp-role_name AND spras = @sy-langu AND line = '00000'.
      IF sy-subrc <> 0 OR lv_cur_desc <> ls_comp-role_desc.
        lv_desc_changed = abap_true.
      ENDIF.
    ENDIF.

    " Member single-role assignment (S_USER_AGR 22/02) & user comparison (S_USER_GRP 22/02) pre-check
    DATA(lv_will_del_pre) = xsdbool( p_sync = abap_true AND lt_roles_to_del IS NOT INITIAL ).
    IF ( lv_exists = abap_false OR p_upd = abap_true )
       AND ( lt_roles_to_add IS NOT INITIAL OR lv_will_del_pre = abap_true ).
      DATA(lv_mbr_auth_err) = ``.
      LOOP AT lt_roles_to_add INTO DATA(lv_ma).
        IF p_test = abap_true.
          AUTHORITY-CHECK OBJECT 'S_USER_AGR' ID 'ACT_GROUP' FIELD lv_ma ID 'ACTVT' FIELD '03'.
          IF sy-subrc <> 0.
            AUTHORITY-CHECK OBJECT 'S_USER_AGR' ID 'ACT_GROUP' FIELD lv_ma ID 'ACTVT' FIELD '22'.
            IF sy-subrc <> 0.
              AUTHORITY-CHECK OBJECT 'S_USER_AGR' ID 'ACT_GROUP' FIELD lv_ma ID 'ACTVT' FIELD '02'.
              IF sy-subrc <> 0.
                lv_mbr_auth_err = |No authorization for member role '{ lv_ma }' (S_USER_AGR 03/22/02).|.
                EXIT.
              ENDIF.
            ENDIF.
          ENDIF.
        ELSE.
          AUTHORITY-CHECK OBJECT 'S_USER_AGR' ID 'ACT_GROUP' FIELD lv_ma ID 'ACTVT' FIELD '22'.
          IF sy-subrc <> 0.
            AUTHORITY-CHECK OBJECT 'S_USER_AGR' ID 'ACT_GROUP' FIELD lv_ma ID 'ACTVT' FIELD '02'.
            IF sy-subrc <> 0.
              lv_mbr_auth_err = |No authorization to assign member role '{ lv_ma }' (S_USER_AGR 22/02).|.
              EXIT.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDLOOP.
      IF lv_mbr_auth_err IS INITIAL AND lv_will_del_pre = abap_true.
        LOOP AT lt_roles_to_del INTO DATA(lv_md).
          IF p_test = abap_true.
            AUTHORITY-CHECK OBJECT 'S_USER_AGR' ID 'ACT_GROUP' FIELD lv_md ID 'ACTVT' FIELD '03'.
            IF sy-subrc <> 0.
              AUTHORITY-CHECK OBJECT 'S_USER_AGR' ID 'ACT_GROUP' FIELD lv_md ID 'ACTVT' FIELD '22'.
              IF sy-subrc <> 0.
                AUTHORITY-CHECK OBJECT 'S_USER_AGR' ID 'ACT_GROUP' FIELD lv_md ID 'ACTVT' FIELD '02'.
                IF sy-subrc <> 0.
                  lv_mbr_auth_err = |No authorization for member role '{ lv_md }' (S_USER_AGR 03/22/02).|.
                  EXIT.
                ENDIF.
              ENDIF.
            ENDIF.
          ELSE.
            AUTHORITY-CHECK OBJECT 'S_USER_AGR' ID 'ACT_GROUP' FIELD lv_md ID 'ACTVT' FIELD '22'.
            IF sy-subrc <> 0.
              AUTHORITY-CHECK OBJECT 'S_USER_AGR' ID 'ACT_GROUP' FIELD lv_md ID 'ACTVT' FIELD '02'.
              IF sy-subrc <> 0.
                lv_mbr_auth_err = |No authorization to remove member role '{ lv_md }' (S_USER_AGR 22/02).|.
                EXIT.
              ENDIF.
            ENDIF.
          ENDIF.
        ENDLOOP.
      ENDIF.
      IF lv_mbr_auth_err IS INITIAL AND p_test = abap_false.
        AUTHORITY-CHECK OBJECT 'S_USER_GRP' ID 'CLASS' DUMMY ID 'ACTVT' FIELD '22'.
        IF sy-subrc <> 0.
          AUTHORITY-CHECK OBJECT 'S_USER_GRP' ID 'CLASS' DUMMY ID 'ACTVT' FIELD '02'.
          IF sy-subrc <> 0.
            lv_mbr_auth_err = 'No authorization for user comparison (S_USER_GRP 22/02).'.
          ENDIF.
        ENDIF.
      ENDIF.
      IF lv_mbr_auth_err IS NOT INITIAL.
        IF lv_enq_held4 = abap_true.
          CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
            EXPORTING
              activity_group = ls_comp-role_name
            EXCEPTIONS
              OTHERS         = 0.
          lv_enq_held4 = abap_false.
        ENDIF.
        ls_res-status       = gc_status_err.
        ls_res-action       = 'ERROR'.
        ls_res-assigned_cnt = lines( lt_curr_agrs ).
        ls_res-message      = lv_mbr_auth_err.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.
    ENDIF.

    " -----------------------------------------------------------------
    " 5. Simulation Mode (Test Run)
    " -----------------------------------------------------------------
    IF p_test = abap_true.
      IF lv_exists = abap_true.
        IF p_upd = abap_true.
          IF lv_is_up_to_date = abap_true AND lv_desc_changed = abap_false.
            ls_res-status  = gc_status_ok.
            ls_res-action  = 'UP-TO-DATE'.
            ls_res-message = |Simulation: Composite role single roles up-to-date ({ ls_res-roles_keep_cnt } roles).|.
          ELSEIF lv_is_up_to_date = abap_true AND lv_desc_changed = abap_true.
            ls_res-status  = gc_status_ok.
            ls_res-action  = 'SIMULATED'.
            ls_res-message = |Simulation OK: Single roles up-to-date ({ ls_res-roles_keep_cnt }); would update role description.|.
          ELSE.
            ls_res-status  = gc_status_ok.
            ls_res-action  = 'SIMULATED'.
            ls_res-message = |Simulation OK: Would add { ls_res-roles_add_cnt } [{ lv_str_add }], remove { ls_res-roles_del_cnt } [{ lv_str_del }], keep { ls_res-roles_keep_cnt }.|.
          ENDIF.
        ELSE.
          ls_res-status  = gc_status_warn.
          ls_res-action  = 'SKIPPED'.
          ls_res-message = 'Simulation: Composite role already exists; would be skipped (Update option unselected).'.
        ENDIF.
      ELSE.
        IF ls_comp-single_roles IS INITIAL AND ls_comp-has_na = abap_true.
          ls_res-status  = gc_status_warn.
          ls_res-action  = 'SIMULATED'.
          ls_res-message = 'Simulation: Role does not exist; would be created without single roles (N/A).'.
        ELSE.
          ls_res-status  = gc_status_ok.
          ls_res-action  = 'SIMULATED'.
          ls_res-message = |Simulation OK: Would create Composite Role with { lines( lt_valid_sgl ) } single roles.|.
        ENDIF.
      ENDIF.

      IF lt_missing_sgl IS NOT INITIAL.
        ls_res-status  = gc_status_warn.
        ls_res-message = |Warning: { lines( lt_missing_sgl ) } role(s) missing in SAP: [{ lv_missing_str }]. { ls_res-message }|.
      ENDIF.
      IF lt_colls_sgl IS NOT INITIAL.
        ls_res-status  = gc_status_warn.
        ls_res-message = |Warning: { lines( lt_colls_sgl ) } composite/self role(s) excluded (cannot nest): [{ lv_colls_str }]. { ls_res-message }|.
      ENDIF.

      ls_res-assigned_cnt = lines( lt_curr_agrs ).
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " 6. Real Execution: Role Shell Creation / Updating
    " -----------------------------------------------------------------
    IF lv_exists = abap_true.
      IF p_upd = abap_false.
        ls_res-status       = gc_status_warn.
        ls_res-action       = 'SKIPPED'.
        ls_res-message      = 'Composite role already exists in SAP; skipped (Update option unselected).'.
        ls_res-assigned_cnt = lines( lt_curr_agrs ).
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.

      " Release read lock BEFORE invoking PRGN_RFC_* FMs (they acquire internal enqueue)
      IF lv_enq_held4 = abap_true.
        CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
          EXPORTING
            activity_group = ls_comp-role_name
          EXCEPTIONS
            OTHERS         = 0.
        lv_enq_held4 = abap_false.
      ENDIF.

      ls_res-action = 'UPDATED'.

    ELSE.
      DATA(lv_create_desc) = COND agr_title(
        WHEN ls_comp-role_desc IS NOT INITIAL THEN ls_comp-role_desc
        ELSE ls_comp-role_name ).
      CLEAR lt_bapiret.
      CALL FUNCTION 'PRGN_RFC_CREATE_AGR_MULTIPLE'
        EXPORTING
          activity_group                = ls_comp-role_name
          activity_group_text           = lv_create_desc
          collective_agr                = 'X'
          no_dialog                     = 'X'
        TABLES
          return                        = lt_bapiret
        EXCEPTIONS
          activity_group_already_exists = 1
          invalid_inheriting_role       = 2
          activity_group_enqueued       = 3
          namespace_problem             = 4
          illegal_characters            = 5
          error_when_creating_actgroup  = 6
          not_authorized                = 7
          OTHERS                        = 8.
      lv_rc = sy-subrc.

      DATA(lv_crt_err4) = xsdbool( lv_rc <> 0 ).
      LOOP AT lt_bapiret INTO DATA(ls_cb4) WHERE type CA 'EAX'.
        lv_crt_err4 = abap_true.
        EXIT.
      ENDLOOP.

      IF lv_crt_err4 = abap_true.
        ROLLBACK WORK.
        CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
        ls_res-status = gc_status_err.
        ls_res-action = 'ERROR'.
        PERFORM format_bapi_message USING lt_bapiret CHANGING ls_res-message.
        IF ls_res-message IS INITIAL.
          ls_res-message = |Failed to create composite role shell (sy-subrc = { lv_rc }).|.
        ENDIF.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.

      PERFORM set_role_description USING ls_comp-role_name lv_create_desc abap_false
                                   CHANGING lv_desc_warn.
      IF lv_desc_warn IS NOT INITIAL.
        lv_op_warn = |Description warning: { lv_desc_warn }|.
      ENDIF.
      COMMIT WORK AND WAIT.
      ls_res-action = 'CREATED'.
    ENDIF.

    " -----------------------------------------------------------------
    " 7. Two-Way Synchronize Single Roles: ADD FIRST, THEN DELETE!
    " -----------------------------------------------------------------
    DATA(lv_will_del) = lv_will_del_pre.

    IF lt_roles_to_add IS NOT INITIAL.
      CLEAR: lt_add_txt, lt_bapiret.
      LOOP AT lt_roles_to_add INTO DATA(lv_add_r).
        APPEND VALUE agr_txt( agr_name = lv_add_r ) TO lt_add_txt.
      ENDLOOP.

      CALL FUNCTION 'PRGN_RFC_ADD_AGRS_TO_COLL_AGR'
        EXPORTING
          activity_group                = ls_comp-role_name
          profile_comparison            = 'X'
          no_dialog                     = 'X'
        TABLES
          activity_groups               = lt_add_txt
          return                        = lt_bapiret
        EXCEPTIONS
          activity_group_does_not_exist = 1
          no_collective_activity_group  = 2
          activity_group_enqueued       = 3
          namespace_problem             = 4
          not_authorized                = 5
          authority_incomplete          = 6
          OTHERS                        = 7.
      lv_rc = sy-subrc.
      DATA(lv_add_msg) = ``.
      PERFORM format_bapi_message USING lt_bapiret CHANGING lv_add_msg.

      DATA(lv_add_fatal) = xsdbool( lv_rc <> 0 ).
      LOOP AT lt_bapiret INTO DATA(ls_ab) WHERE type CA 'EAX'.
        lv_add_fatal = abap_true.
        EXIT.
      ENDLOOP.

      " Verify every requested added single role actually persisted in AGR_AGRS
      IF lv_add_fatal = abap_false.
        SELECT child_agr FROM agr_agrs INTO TABLE @DATA(lt_after_add)
          WHERE agr_name = @ls_comp-role_name.
        LOOP AT lt_roles_to_add INTO DATA(lv_v_add).
          READ TABLE lt_after_add WITH KEY child_agr = lv_v_add TRANSPORTING NO FIELDS.
          IF sy-subrc <> 0.
            lv_add_fatal = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.
      ENDIF.

      IF lv_add_fatal = abap_true.
        lv_op_err = COND #( WHEN lv_add_msg IS NOT INITIAL
                            THEN |Add failed/incomplete: { lv_add_msg }|
                            ELSE |PRGN_RFC_ADD_AGRS_TO_COLL_AGR failed (sy-subrc = { lv_rc }).| ).
      ELSEIF lv_add_msg IS NOT INITIAL.
        lv_op_warn = COND #( WHEN lv_op_warn IS INITIAL
                             THEN |Add comparison warning: { lv_add_msg }|
                             ELSE |{ lv_op_warn } \| Add comparison warning: { lv_add_msg }| ).
      ENDIF.
    ENDIF.

    IF lv_op_err IS INITIAL AND lv_will_del = abap_true.
      CLEAR: lt_del_txt, lt_bapiret.
      LOOP AT lt_roles_to_del INTO DATA(lv_del_r).
        APPEND VALUE agr_txt( agr_name = lv_del_r ) TO lt_del_txt.
      ENDLOOP.

      CALL FUNCTION 'PRGN_RFC_DEL_AGRS_IN_COLL_AGR'
        EXPORTING
          activity_group                = ls_comp-role_name
          profile_comparison            = 'X'
          no_dialog                     = 'X'
        TABLES
          activity_groups               = lt_del_txt
          return                        = lt_bapiret
        EXCEPTIONS
          activity_group_does_not_exist = 1
          no_collective_activity_group  = 2
          activity_group_enqueued       = 3
          namespace_problem             = 4
          not_authorized                = 5
          authority_incomplete          = 6
          OTHERS                        = 7.
      lv_rc = sy-subrc.
      DATA(lv_del_msg) = ``.
      PERFORM format_bapi_message USING lt_bapiret CHANGING lv_del_msg.

      DATA(lv_del_fatal) = xsdbool( lv_rc <> 0 ).
      LOOP AT lt_bapiret INTO DATA(ls_db) WHERE type CA 'EAX'.
        lv_del_fatal = abap_true.
        EXIT.
      ENDLOOP.

      IF lv_del_fatal = abap_false.
        SELECT child_agr FROM agr_agrs INTO TABLE @DATA(lt_after_del)
          WHERE agr_name = @ls_comp-role_name.
        LOOP AT lt_roles_to_del INTO DATA(lv_v_del).
          READ TABLE lt_after_del WITH KEY child_agr = lv_v_del TRANSPORTING NO FIELDS.
          IF sy-subrc = 0.
            lv_del_fatal = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.
      ENDIF.

      IF lv_del_fatal = abap_true.
        lv_op_err = COND #( WHEN lv_del_msg IS NOT INITIAL
                            THEN |Remove failed/incomplete: { lv_del_msg }|
                            ELSE |PRGN_RFC_DEL_AGRS_IN_COLL_AGR failed (sy-subrc = { lv_rc }).| ).
      ELSEIF lv_del_msg IS NOT INITIAL.
        lv_op_warn = COND #( WHEN lv_op_warn IS INITIAL
                             THEN |Remove comparison warning: { lv_del_msg }|
                             ELSE |{ lv_op_warn } \| Remove comparison warning: { lv_del_msg }| ).
      ENDIF.
    ENDIF.

    IF lv_op_err IS NOT INITIAL.
      ROLLBACK WORK.
      CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
      " Reconcile ALV counts & lists directly from live AGR_AGRS (earlier SAP FMs commit internally)
      DATA lt_actual_agrs TYPE STANDARD TABLE OF agr_name.
      SELECT child_agr FROM agr_agrs INTO TABLE @lt_actual_agrs
        WHERE agr_name = @ls_comp-role_name.
      DATA: lt_act_add  TYPE STANDARD TABLE OF agr_name,
            lt_act_del  TYPE STANDARD TABLE OF agr_name,
            lt_act_keep TYPE STANDARD TABLE OF agr_name,
            lv_act_add  TYPE string,
            lv_act_del  TYPE string,
            lv_act_keep TYPE string.
      CLEAR: lt_act_add, lt_act_del, lt_act_keep, lv_act_add, lv_act_del, lv_act_keep.
      LOOP AT lt_actual_agrs INTO DATA(lv_act_c).
        READ TABLE lt_curr_agrs WITH KEY child_agr = lv_act_c TRANSPORTING NO FIELDS.
        IF sy-subrc = 0.
          APPEND lv_act_c TO lt_act_keep.
          lv_act_keep = COND #( WHEN lv_act_keep IS INITIAL THEN lv_act_c ELSE |{ lv_act_keep }, { lv_act_c }| ).
        ELSE.
          APPEND lv_act_c TO lt_act_add.
          lv_act_add = COND #( WHEN lv_act_add IS INITIAL THEN lv_act_c ELSE |{ lv_act_add }, { lv_act_c }| ).
        ENDIF.
      ENDLOOP.
      LOOP AT lt_curr_agrs INTO DATA(ls_orig_c).
        READ TABLE lt_actual_agrs WITH KEY table_line = ls_orig_c-child_agr TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          APPEND ls_orig_c-child_agr TO lt_act_del.
          lv_act_del = COND #( WHEN lv_act_del IS INITIAL THEN ls_orig_c-child_agr
                               ELSE |{ lv_act_del }, { ls_orig_c-child_agr }| ).
        ENDIF.
      ENDLOOP.
      ls_res-roles_add_cnt  = lines( lt_act_add ).
      ls_res-roles_del_cnt  = lines( lt_act_del ).
      ls_res-roles_keep_cnt = lines( lt_act_keep ).
      ls_res-assigned_cnt   = lines( lt_actual_agrs ).
      ls_res-roles_add      = lv_act_add.
      ls_res-roles_del      = lv_act_del.
      ls_res-roles_keep     = lv_act_keep.
      IF lines( lt_act_add ) > 0 OR lines( lt_act_del ) > 0 OR lv_exists = abap_false.
        CALL FUNCTION 'PRGN_SET_ACTGROUP_TIMESTAMP'
          EXPORTING
            activity_group = ls_comp-role_name
            no_commit      = 'X'
          EXCEPTIONS
            OTHERS         = 0.
        COMMIT WORK AND WAIT.
        lv_op_err = |{ lv_op_err } (Note: partial DB changes already committed by SAP — Add={ ls_res-roles_add_cnt }, Del={ ls_res-roles_del_cnt }, Active={ ls_res-assigned_cnt }).|.
      ENDIF.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = lv_op_err.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " Update description ONLY AFTER role additions & deletions succeed
    IF lv_exists = abap_true AND lv_desc_changed = abap_true.
      PERFORM set_role_description USING ls_comp-role_name ls_comp-role_desc abap_true
                                   CHANGING lv_desc_warn.
      IF lv_desc_warn IS NOT INITIAL.
        lv_op_warn = COND #( WHEN lv_op_warn IS INITIAL
                             THEN |Description warning: { lv_desc_warn }|
                             ELSE |{ lv_op_warn } \| Description warning: { lv_desc_warn }| ).
      ENDIF.
    ENDIF.

    " Post-RFC locked verification & timestamp update
    IF lv_is_up_to_date = abap_false OR ( lv_desc_changed = abap_true AND lv_desc_warn IS INITIAL ).
      DATA(lv_post_enq) = abap_false.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
        EXPORTING
          activity_group = ls_comp-role_name
          no_dialog      = 'X'
        EXCEPTIONS
          OTHERS         = 1.
      IF sy-subrc = 0.
        lv_post_enq = abap_true.
        IF p_sync = abap_true.
          SELECT child_agr FROM agr_agrs INTO TABLE @DATA(lt_post_chk)
            WHERE agr_name = @ls_comp-role_name.
          DATA lt_conc_del TYPE STANDARD TABLE OF agr_txt.
          CLEAR lt_conc_del.
          LOOP AT lt_post_chk INTO DATA(ls_pc).
            READ TABLE lt_valid_sgl WITH KEY table_line = ls_pc-child_agr TRANSPORTING NO FIELDS.
            IF sy-subrc <> 0.
              APPEND VALUE agr_txt( agr_name = ls_pc-child_agr ) TO lt_conc_del.
            ENDIF.
          ENDLOOP.
          IF lt_conc_del IS NOT INITIAL.
            CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
              EXPORTING
                activity_group = ls_comp-role_name
              EXCEPTIONS
                OTHERS         = 0.
            lv_post_enq = abap_false.
            CLEAR lt_bapiret.
            CALL FUNCTION 'PRGN_RFC_DEL_AGRS_IN_COLL_AGR'
              EXPORTING
                activity_group     = ls_comp-role_name
                profile_comparison = 'X'
                no_dialog          = 'X'
              TABLES
                activity_groups    = lt_conc_del
                return             = lt_bapiret
              EXCEPTIONS
                OTHERS             = 1.
            IF sy-subrc <> 0.
              lv_op_warn = COND #( WHEN lv_op_warn IS INITIAL
                                   THEN |Concurrent single-role removal warning (rc={ sy-subrc })|
                                   ELSE |{ lv_op_warn } \| Concurrent removal warning (rc={ sy-subrc })| ).
            ENDIF.
            CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
              EXPORTING
                activity_group = ls_comp-role_name
                no_dialog      = 'X'
              EXCEPTIONS
                OTHERS         = 1.
            IF sy-subrc = 0.
              lv_post_enq = abap_true.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.
      CALL FUNCTION 'PRGN_SET_ACTGROUP_TIMESTAMP'
        EXPORTING
          activity_group = ls_comp-role_name
          no_commit      = 'X'
        EXCEPTIONS
          OTHERS         = 0.
      COMMIT WORK AND WAIT.
      IF lv_post_enq = abap_true.
        CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
          EXPORTING
            activity_group = ls_comp-role_name
          EXCEPTIONS
            OTHERS         = 0.
      ENDIF.
    ENDIF.

    SELECT COUNT(*) FROM agr_agrs INTO @ls_res-assigned_cnt
      WHERE agr_name = @ls_comp-role_name.

    IF lv_is_up_to_date = abap_true AND lv_desc_changed = abap_false.
      ls_res-status  = gc_status_ok.
      ls_res-action  = 'UP-TO-DATE'.
      ls_res-message = |Composite role up-to-date. All { ls_res-roles_keep_cnt } single roles match CSV.|.
    ELSEIF lv_is_up_to_date = abap_true AND lv_desc_changed = abap_true.
      IF lv_desc_warn IS NOT INITIAL.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'ERROR'.
        ls_res-message = |Failed to update role description (kept { ls_res-roles_keep_cnt } single roles).|.
      ELSE.
        ls_res-status  = gc_status_ok.
        ls_res-action  = 'UPDATED'.
        ls_res-message = |Updated role description (kept { ls_res-roles_keep_cnt } single roles). Active: { ls_res-assigned_cnt }.|.
      ENDIF.
    ELSE.
      ls_res-status  = gc_status_ok.
      ls_res-action  = COND #( WHEN lv_exists = abap_true THEN 'UPDATED' ELSE 'CREATED' ).
      IF lv_exists = abap_false AND ls_comp-single_roles IS INITIAL AND ls_comp-has_na = abap_true.
        ls_res-status  = gc_status_warn.
        ls_res-message = 'Composite role created without single roles (N/A).'.
      ELSE.
        ls_res-message = |Success: Added { ls_res-roles_add_cnt } [{ lv_str_add }], Removed { ls_res-roles_del_cnt } [{ lv_str_del }], Kept { ls_res-roles_keep_cnt }. Active: { ls_res-assigned_cnt }.|.
      ENDIF.
    ENDIF.

    IF lv_op_warn IS NOT INITIAL.
      IF ls_res-status = gc_status_ok.
        ls_res-status = gc_status_warn.
      ENDIF.
      ls_res-message = |{ ls_res-message } { lv_op_warn }|.
    ENDIF.

    IF lt_missing_sgl IS NOT INITIAL.
      ls_res-status  = gc_status_warn.
      ls_res-message = |Warning: { lines( lt_missing_sgl ) } role(s) missing from SAP: [{ lv_missing_str }]. { ls_res-message }|.
    ENDIF.
    IF lt_colls_sgl IS NOT INITIAL.
      ls_res-status  = gc_status_warn.
      ls_res-message = |Warning: { lines( lt_colls_sgl ) } composite/self role(s) excluded (cannot nest): [{ lv_colls_str }]. { ls_res-message }|.
    ENDIF.

    APPEND ls_res TO gt_results.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form format_bapi_message
*&---------------------------------------------------------------------*
FORM format_bapi_message USING    it_bapiret TYPE bapiret2_t
                         CHANGING cv_msg     TYPE string.
  CLEAR cv_msg.
  LOOP AT it_bapiret INTO DATA(ls_bapi) WHERE type CA 'EAXW'.
    IF cv_msg IS INITIAL.
      cv_msg = ls_bapi-message.
    ELSE.
      CONCATENATE cv_msg '|' ls_bapi-message INTO cv_msg SEPARATED BY space.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form set_role_description
*&---------------------------------------------------------------------*
* Sets role description and clears comments via standard PFCG FM
*&---------------------------------------------------------------------*
FORM set_role_description USING    iv_agr_name      TYPE agr_name
                                   iv_desc          TYPE csequence
                                   iv_preserve_long TYPE abap_bool
                          CHANGING ev_warn          TYPE string.
  DATA: lt_texts TYPE STANDARD TABLE OF agr_texts,
        lt_ret   TYPE bapiret2_t,
        lv_rc    TYPE sy-subrc.
  CLEAR: lt_texts, lt_ret, ev_warn.

  IF iv_preserve_long = abap_true.
    SELECT * FROM agr_texts INTO TABLE @lt_texts
      WHERE agr_name = @iv_agr_name
        AND spras    = @sy-langu
        AND line     > '00000'
      ORDER BY line.
  ENDIF.

  INSERT VALUE agr_texts(
    spras = sy-langu
    line  = '00000'
    text  = iv_desc
  ) INTO lt_texts INDEX 1.

  CALL FUNCTION 'PRGN_RFC_CHANGE_TEXTS'
    EXPORTING
      activity_group                = iv_agr_name
      no_dialog                     = 'X'
    TABLES
      texts                         = lt_texts
      return                        = lt_ret
    EXCEPTIONS
      activity_group_enqueued       = 1
      activity_group_does_not_exist = 2
      namespace_problem             = 3
      not_authorized                = 4
      wrong_language                = 5
      OTHERS                        = 6.
  lv_rc = sy-subrc.

  LOOP AT lt_ret INTO DATA(ls_r) WHERE type CA 'EAXW'.
    IF ev_warn IS INITIAL.
      ev_warn = ls_r-message.
    ELSE.
      ev_warn = |{ ev_warn }; { ls_r-message }|.
    ENDIF.
  ENDLOOP.
  IF lv_rc <> 0 AND ev_warn IS INITIAL.
    ev_warn = |PRGN_RFC_CHANGE_TEXTS failed (rc={ lv_rc }).|.
  ENDIF.
ENDFORM.

*----------------------------------------------------------------------*
* 7. ALV EVENT HANDLER DEFINITION & IMPLEMENTATION
*----------------------------------------------------------------------*
CLASS lcl_alv_event_handler DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS on_link_click FOR EVENT link_click OF cl_salv_events_table
      IMPORTING row column.
ENDCLASS.

CLASS lcl_alv_event_handler IMPLEMENTATION.
  METHOD on_link_click.
    READ TABLE gt_results INTO DATA(ls_row) INDEX row.
    IF sy-subrc = 0 AND column = 'COMPOSITE_ROLE' AND ls_row-composite_role IS NOT INITIAL.
      TRY.
          SET PARAMETER ID 'AGR' FIELD ls_row-composite_role.
          CALL TRANSACTION 'PFCG' WITH AUTHORITY-CHECK AND SKIP FIRST SCREEN.
        CATCH cx_sy_authorization_error.
          MESSAGE 'No authorization to open transaction PFCG.' TYPE 'S' DISPLAY LIKE 'E'.
      ENDTRY.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

*&---------------------------------------------------------------------*
*& Form display_alv_results
*&---------------------------------------------------------------------*
FORM display_alv_results.
  DATA: lo_alv       TYPE REF TO cl_salv_table,
        lo_cols      TYPE REF TO cl_salv_columns_table,
        lo_col       TYPE REF TO cl_salv_column_table,
        lo_functions TYPE REF TO cl_salv_functions_list,
        lo_events    TYPE REF TO cl_salv_events_table.

  IF gt_results IS INITIAL.
    MESSAGE 'No composite roles were processed.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  TRY.
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv
        CHANGING
          t_table      = gt_results
      ).

      lo_functions = lo_alv->get_functions( ).
      lo_functions->set_all( abap_true ).

      lo_cols = lo_alv->get_columns( ).
      lo_cols->set_optimize( abap_true ).

      " Status Column (LED Icon)
      lo_col ?= lo_cols->get_column( 'STATUS' ).
      lo_col->set_short_text( 'Status' ).
      lo_col->set_medium_text( 'Status' ).
      lo_col->set_long_text( 'Execution Status' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " Action Column
      lo_col ?= lo_cols->get_column( 'ACTION' ).
      lo_col->set_short_text( 'Action' ).
      lo_col->set_medium_text( 'Action Taken' ).
      lo_col->set_long_text( 'Action Taken' ).

      " Composite Role Column (Hotspot link to PFCG)
      lo_col ?= lo_cols->get_column( 'COMPOSITE_ROLE' ).
      lo_col->set_short_text( 'Comp Role' ).
      lo_col->set_medium_text( 'Composite Role' ).
      lo_col->set_long_text( 'Composite Role (Click to open PFCG)' ).
      lo_col->set_cell_type( if_salv_c_cell_type=>hotspot ).

      " Role Description
      lo_col ?= lo_cols->get_column( 'ROLE_DESC' ).
      lo_col->set_short_text( 'Role Desc' ).
      lo_col->set_medium_text( 'Role Description' ).
      lo_col->set_long_text( 'Composite Role Description' ).

      " Roles Count (in CSV)
      lo_col ?= lo_cols->get_column( 'ROLES_CNT' ).
      lo_col->set_short_text( 'CSV Cnt' ).
      lo_col->set_medium_text( 'CSV Role Count' ).
      lo_col->set_long_text( 'Single Roles Count in CSV' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " Valid Roles Count (in SAP)
      lo_col ?= lo_cols->get_column( 'VALID_CNT' ).
      lo_col->set_short_text( 'Valid Cnt' ).
      lo_col->set_medium_text( 'Valid in SAP' ).
      lo_col->set_long_text( 'Valid Single Roles in SAP' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " Roles Added Count
      lo_col ?= lo_cols->get_column( 'ROLES_ADD_CNT' ).
      lo_col->set_short_text( 'Add Cnt' ).
      lo_col->set_medium_text( 'Roles Added' ).
      lo_col->set_long_text( 'Single Roles Added (Count)' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " Roles Removed Count
      lo_col ?= lo_cols->get_column( 'ROLES_DEL_CNT' ).
      lo_col->set_short_text( 'Del Cnt' ).
      lo_col->set_medium_text( 'Roles Removed' ).
      lo_col->set_long_text( 'Single Roles Removed (Count)' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " Roles Retained Count
      lo_col ?= lo_cols->get_column( 'ROLES_KEEP_CNT' ).
      lo_col->set_short_text( 'Keep Cnt' ).
      lo_col->set_medium_text( 'Roles Kept' ).
      lo_col->set_long_text( 'Single Roles Retained (Count)' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " Total Assigned Roles Count
      lo_col ?= lo_cols->get_column( 'ASSIGNED_CNT' ).
      lo_col->set_short_text( 'Active' ).
      lo_col->set_medium_text( 'Active Roles' ).
      lo_col->set_long_text( 'Total Active Single Roles in SAP' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " Added Roles List
      lo_col ?= lo_cols->get_column( 'ROLES_ADD' ).
      lo_col->set_short_text( 'Added' ).
      lo_col->set_medium_text( 'Added Roles' ).
      lo_col->set_long_text( 'List of Single Roles Added' ).
      lo_col->set_output_length( 30 ).

      " Removed Roles List
      lo_col ?= lo_cols->get_column( 'ROLES_DEL' ).
      lo_col->set_short_text( 'Removed' ).
      lo_col->set_medium_text( 'Removed Roles' ).
      lo_col->set_long_text( 'List of Single Roles Removed' ).
      lo_col->set_output_length( 30 ).

      " Retained Roles List
      lo_col ?= lo_cols->get_column( 'ROLES_KEEP' ).
      lo_col->set_short_text( 'Retained' ).
      lo_col->set_medium_text( 'Retained Roles' ).
      lo_col->set_long_text( 'List of Single Roles Retained' ).
      lo_col->set_output_length( 30 ).

      " Missing Roles
      lo_col ?= lo_cols->get_column( 'MISSING_ROLES' ).
      lo_col->set_short_text( 'Missing' ).
      lo_col->set_medium_text( 'Missing Roles' ).
      lo_col->set_long_text( 'Single Roles Missing from SAP' ).
      lo_col->set_output_length( 30 ).

      " Message Column
      lo_col ?= lo_cols->get_column( 'MESSAGE' ).
      lo_col->set_short_text( 'Message' ).
      lo_col->set_medium_text( 'Execution Message' ).
      lo_col->set_long_text( 'Execution Message / Details' ).

      " Register Hotspot Event Handler
      lo_events = lo_alv->get_event( ).
      SET HANDLER lcl_alv_event_handler=>on_link_click FOR lo_events.

      lo_alv->display( ).

    CATCH cx_salv_msg cx_salv_not_found INTO DATA(lx_salv).
      MESSAGE lx_salv->get_text( ) TYPE 'E'.
  ENDTRY.
ENDFORM.
