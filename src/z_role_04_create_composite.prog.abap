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
         role_name    TYPE agr_name,
         role_desc    TYPE agr_title,
         has_na       TYPE abap_bool,
         single_roles TYPE STANDARD TABLE OF agr_name WITH DEFAULT KEY,
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

  CLEAR lv_line_idx.
  LOOP AT lt_file_records INTO lv_line.
    lv_line_idx = lv_line_idx + 1.
    IF lv_line_idx = 1 AND strlen( lv_line ) >= 1.
      IF lv_line(1) = cl_abap_char_utilities=>byte_order_mark_utf8.
        lv_line = substring( val = lv_line off = 1 ).
      ENDIF.
    ENDIF.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf(1) IN lv_line WITH ''.
    IF lv_line IS INITIAL.
      CONTINUE.
    ENDIF.

    CLEAR: lv_c1, lv_c2, lv_c3.
    PERFORM parse_csv_line USING lv_line
                           CHANGING lv_c1 lv_c2 lv_c3.

    " Validate & skip header row
    DATA(lv_c1_up) = to_upper( lv_c1 ).
    DATA(lv_c2_up) = to_upper( lv_c2 ).
    DATA(lv_c3_up) = to_upper( lv_c3 ).

    IF lv_line_idx = 1.
      IF lv_c3_up CS 'TCODE' OR lv_c1_up CS 'MASTER' OR lv_c2_up CS 'DERIVE'
         OR lv_c2_up CS 'ORG' OR lv_c2_up CS 'OBJECT' OR lv_c2_up = 'FIELD'
         OR lv_c1_up CS 'USER'
         OR ( lv_c1_up CS 'ROLE NAME' AND NOT ( lv_c1_up CS 'COMPOSITE' ) )
         OR lv_c1_up = 'ROLE'.
        MESSAGE 'Invalid CSV header for Z_ROLE_04_CREATE_COMPOSITE. Expected: Composite Role Name, Composite Role Description, Single Role.' TYPE 'E'.
      ENDIF.
      IF lv_c1_up CS 'COMPOSITE' AND ( lv_c3_up CS 'SINGLE' OR lv_c3_up CS 'DERIVE' OR lv_c3_up CS 'ROLE' ).
        CONTINUE.
      ENDIF.
    ENDIF.
    IF lv_c1_up = 'COMPOSITE ROLE NAME' OR lv_c1_up = 'COMPOSITE_ROLE_NAME'
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
*& Form parse_csv_line
*&---------------------------------------------------------------------*
FORM parse_csv_line USING    iv_line TYPE string
                    CHANGING ev_col1 TYPE string
                             ev_col2 TYPE string
                             ev_col3 TYPE string.
  DATA: lt_tokens TYPE STANDARD TABLE OF string,
        lv_len    TYPE i,
        lv_in_q   TYPE abap_bool VALUE abap_false,
        lv_cur    TYPE string,
        lv_char   TYPE string,
        lv_next   TYPE string,
        lv_idx    TYPE i,
        lv_delim  TYPE c LENGTH 1.

  CLEAR: ev_col1, ev_col2, ev_col3.

  IF iv_line CS cl_abap_char_utilities=>horizontal_tab.
    lv_delim = cl_abap_char_utilities=>horizontal_tab.
  ELSEIF iv_line CS ','.
    lv_delim = ','.
  ELSE.
    lv_delim = ';'.
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
           lv_rc, lv_op_err, lv_cur_desc.

    ls_res-composite_role = ls_comp-role_name.
    ls_res-role_desc      = ls_comp-role_desc.
    ls_res-roles_cnt      = lines( ls_comp-single_roles ).

    " -----------------------------------------------------------------
    " 2. Validate Existing Role Type in SAP & Per-Role Authority
    " -----------------------------------------------------------------
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
    " 4. Read Current Single Roles & Compute Two-Way Diff
    " -----------------------------------------------------------------
    DATA: lt_roles_to_add TYPE STANDARD TABLE OF agr_name,
          lt_roles_to_del TYPE STANDARD TABLE OF agr_name,
          lt_roles_keep   TYPE STANDARD TABLE OF agr_name,
          lv_str_add      TYPE string,
          lv_str_del      TYPE string,
          lv_str_keep     TYPE string.

    CLEAR: lt_roles_to_add, lt_roles_to_del, lt_roles_keep,
           lv_str_add, lv_str_del, lv_str_keep.

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

    " -----------------------------------------------------------------
    " 5. Simulation Mode (Test Run)
    " -----------------------------------------------------------------
    IF p_test = abap_true.
      IF lv_exists = abap_true.
        IF p_upd = abap_true.
          IF lv_is_up_to_date = abap_true.
            ls_res-status  = gc_status_ok.
            ls_res-action  = 'UP-TO-DATE'.
            ls_res-message = |Simulation: Composite role single roles up-to-date ({ ls_res-roles_keep_cnt } roles).|.
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
    DATA(lv_desc_changed) = abap_false.
    IF lv_exists = abap_true.
      IF p_upd = abap_false.
        ls_res-status       = gc_status_warn.
        ls_res-action       = 'SKIPPED'.
        ls_res-message      = 'Composite role already exists in SAP; skipped (Update option unselected).'.
        ls_res-assigned_cnt = lines( lt_curr_agrs ).
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.

      " Update description ONLY when non-empty and changed (never wipe existing description!)
      IF ls_comp-role_desc IS NOT INITIAL.
        SELECT SINGLE text FROM agr_texts INTO @lv_cur_desc
          WHERE agr_name = @ls_comp-role_name AND spras = @sy-langu AND line = '00000'.
        IF sy-subrc <> 0 OR lv_cur_desc <> ls_comp-role_desc.
          PERFORM set_role_description USING ls_comp-role_name ls_comp-role_desc.
          lv_desc_changed = abap_true.
        ENDIF.
      ENDIF.
      ls_res-action = 'UPDATED'.

    ELSE.
      DATA(lv_create_desc) = COND agr_title(
        WHEN ls_comp-role_desc IS NOT INITIAL THEN ls_comp-role_desc
        ELSE ls_comp-role_name ).
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

      IF lv_rc <> 0.
        ls_res-status = gc_status_err.
        ls_res-action = 'ERROR'.
        PERFORM format_bapi_message USING lt_bapiret CHANGING ls_res-message.
        IF ls_res-message IS INITIAL.
          ls_res-message = |Failed to create composite role shell (sy-subrc = { lv_rc }).|.
        ENDIF.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.

      PERFORM set_role_description USING ls_comp-role_name lv_create_desc.
      COMMIT WORK AND WAIT.
      ls_res-action = 'CREATED'.
    ENDIF.

    " -----------------------------------------------------------------
    " 7. Two-Way Synchronize Single Roles (strictly check errors!)
    " -----------------------------------------------------------------
    IF p_sync = abap_true AND lt_roles_to_del IS NOT INITIAL.
      CLEAR: lt_del_txt, lt_bapiret.
      LOOP AT lt_roles_to_del INTO DATA(lv_del_r).
        APPEND VALUE agr_txt( agr_name = lv_del_r ) TO lt_del_txt.
      ENDLOOP.

      CALL FUNCTION 'PRGN_RFC_DEL_AGRS_IN_COLL_AGR'
        EXPORTING
          activity_group     = ls_comp-role_name
          profile_comparison = 'X'
          no_dialog          = 'X'
        TABLES
          activity_groups    = lt_del_txt
          return             = lt_bapiret
        EXCEPTIONS
          OTHERS             = 1.
      lv_rc = sy-subrc.
      DATA(lv_del_err) = ``.
      PERFORM format_bapi_message USING lt_bapiret CHANGING lv_del_err.
      IF lv_rc <> 0 OR line_exists( lt_bapiret[ type = 'E' ] ) OR line_exists( lt_bapiret[ type = 'A' ] ).
        lv_op_err = COND #( WHEN lv_del_err IS NOT INITIAL
                            THEN |Remove failed: { lv_del_err }|
                            ELSE |PRGN_RFC_DEL_AGRS_IN_COLL_AGR failed (sy-subrc = { lv_rc }).| ).
      ENDIF.
    ENDIF.

    IF lv_op_err IS INITIAL AND lt_roles_to_add IS NOT INITIAL.
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
      DATA(lv_add_err) = ``.
      PERFORM format_bapi_message USING lt_bapiret CHANGING lv_add_err.
      IF lv_rc <> 0 OR line_exists( lt_bapiret[ type = 'E' ] ) OR line_exists( lt_bapiret[ type = 'A' ] ).
        lv_op_err = COND #( WHEN lv_add_err IS NOT INITIAL
                            THEN |Add failed: { lv_add_err }|
                            ELSE |PRGN_RFC_ADD_AGRS_TO_COLL_AGR failed (sy-subrc = { lv_rc }).| ).
      ENDIF.
    ENDIF.

    IF lv_op_err IS NOT INITIAL.
      ROLLBACK WORK.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = lv_op_err.
      SELECT COUNT(*) FROM agr_agrs INTO @ls_res-assigned_cnt
        WHERE agr_name = @ls_comp-role_name.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    IF lv_is_up_to_date = abap_false OR lv_desc_changed = abap_true.
      CALL FUNCTION 'PRGN_SET_ACTGROUP_TIMESTAMP'
        EXPORTING
          activity_group = ls_comp-role_name
        EXCEPTIONS
          OTHERS         = 0.
      COMMIT WORK AND WAIT.
    ENDIF.

    SELECT COUNT(*) FROM agr_agrs INTO @ls_res-assigned_cnt
      WHERE agr_name = @ls_comp-role_name.

    IF lv_is_up_to_date = abap_true AND lv_desc_changed = abap_false.
      ls_res-status  = gc_status_ok.
      ls_res-action  = 'UP-TO-DATE'.
      ls_res-message = |Composite role up-to-date. All { ls_res-roles_keep_cnt } single roles match CSV.|.
    ELSE.
      ls_res-status  = gc_status_ok.
      ls_res-action  = COND #( WHEN lv_exists = abap_true THEN 'UPDATED' ELSE 'CREATED' ).
      ls_res-message = |Success: Added { ls_res-roles_add_cnt } [{ lv_str_add }], Removed { ls_res-roles_del_cnt } [{ lv_str_del }], Kept { ls_res-roles_keep_cnt }. Active: { ls_res-assigned_cnt }.|.
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
FORM set_role_description USING iv_agr_name TYPE agr_name
                                iv_desc     TYPE csequence.
  DATA: lt_texts TYPE STANDARD TABLE OF agr_texts.
  CLEAR lt_texts.
  APPEND VALUE agr_texts(
    spras = sy-langu
    line  = '00000'
    text  = iv_desc
  ) TO lt_texts.

  CALL FUNCTION 'PRGN_RFC_CHANGE_TEXTS'
    EXPORTING
      activity_group = iv_agr_name
      no_dialog      = 'X'
    TABLES
      texts          = lt_texts
    EXCEPTIONS
      OTHERS         = 0.
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
