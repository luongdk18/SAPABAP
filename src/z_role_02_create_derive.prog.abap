*&---------------------------------------------------------------------*
*& Report Z_ROLE_02_CREATE_DERIVE
*&---------------------------------------------------------------------*
*& Purpose: Batch PFCG Derived Role Creation & Inheritance Synchronization
*& Description:
*&   Reads a CSV (.csv) file containing role derivation
*&   mappings (Master Role, Derived Role, Derived Role Description), validates
*&   the Master Roles in SAP, creates the Derived Single Roles linked to the
*&   Master Role (PARENT_AGR), inherits authorization data while strictly
*&   preserving existing Organizational Levels (optionally defaulting only
*&   unmaintained levels to '-1'), and generates authorization profiles.
*&
*& File format (CSV .csv):
*&   Col 1: Master Role             (e.g., Z_FI_PERIOD_CONTROL)
*&   Col 2: Derived Role            (e.g., Z_FI_PERIOD_CONTROL_1000)
*&   Col 3: Derived Role Description(e.g., GL Period Control - Entity 1000)
*&
*& Author: Antigravity AI (SAP Basis Engineering)
*& Package: $TMP (Local Object) or Custom Package
*&---------------------------------------------------------------------*
REPORT z_role_02_create_derive.

*----------------------------------------------------------------------*
* 1. TYPES & DATA DEFINITIONS
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_raw_row,
         col1 TYPE string,
         col2 TYPE string,
         col3 TYPE string,
       END OF ty_raw_row.

TYPES: BEGIN OF ty_derive_entry,
         master_role  TYPE agr_name,
         derived_role TYPE agr_name,
         derived_desc TYPE agr_title,
       END OF ty_derive_entry.

TYPES: BEGIN OF ty_oversized_role,
         role_kind TYPE string,
         role_name TYPE string,
       END OF ty_oversized_role.

TYPES: ty_t_agr_1252 TYPE STANDARD TABLE OF agr_1252 WITH DEFAULT KEY.

TYPES: BEGIN OF ty_alv_result,
         status       TYPE char12,     " Status Icon & Code: @08@ [OK], @09@ [WARN], @0A@ [ERR]
         action       TYPE char12,     " Action: CREATED / UPDATED / SIMULATED / SKIPPED / ERROR
         derived_role TYPE agr_name,   " Derived Role ID (Hotspot to PFCG)
         derived_desc TYPE agr_title,  " Derived Role Description
         master_role  TYPE agr_name,   " Master Role ID (Hotspot to PFCG)
         master_desc  TYPE agr_title,  " Master Role Description
         profile      TYPE xuprofile,  " Generated Profile Name
         message      TYPE string,     " Status Message / BAPI Return Details
       END OF ty_alv_result.

CONSTANTS: gc_status_ok   TYPE char12 VALUE '@08@ [OK]',
           gc_status_warn TYPE char12 VALUE '@09@ [WARN]',
           gc_status_err  TYPE char12 VALUE '@0A@ [ERR]'.

DATA: gt_raw_rows        TYPE STANDARD TABLE OF ty_raw_row,
      gt_derive_roles    TYPE STANDARD TABLE OF ty_derive_entry,
      gt_results         TYPE STANDARD TABLE OF ty_alv_result,
      gt_usorg_map       TYPE SORTED TABLE OF usorg WITH NON-UNIQUE KEY field,
      gt_oversized_roles TYPE STANDARD TABLE OF ty_oversized_role.

*----------------------------------------------------------------------*
* 2. SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b_file WITH FRAME TITLE b_tit1.
  PARAMETERS: p_file TYPE localfile OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b_file.

SELECTION-SCREEN BEGIN OF BLOCK b_opt WITH FRAME TITLE b_tit2.
  PARAMETERS: p_test   TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_upd    TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_adjust TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_genprf TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_orgdef TYPE abap_bool AS CHECKBOX.
SELECTION-SCREEN END OF BLOCK b_opt.

*----------------------------------------------------------------------*
* 3. INITIALIZATION & SCREEN EVENTS
*----------------------------------------------------------------------*
INITIALIZATION.
  b_tit1 = 'Input CSV File (.csv)'(b01).
  b_tit2 = 'Execution & Derivation Options'(b02).

  %_p_file_%_app_%-text   = 'File Path'.
  %_p_test_%_app_%-text   = 'Simulation (Test Run)'.
  %_p_upd_%_app_%-text    = 'Update Existing Derived Roles'.
  %_p_adjust_%_app_%-text = 'Adjust Auth from Master Role'.
  %_p_genprf_%_app_%-text = 'Auto-Generate Auth Profiles'.
  %_p_orgdef_%_app_%-text = 'Default Org Levels to "-1"'.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  PERFORM f4_file_open CHANGING p_file.

AT SELECTION-SCREEN ON p_file.
  PERFORM validate_filename USING p_file.

*----------------------------------------------------------------------*
* 4. START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.
  PERFORM check_authority.
  CLEAR gt_usorg_map.
  SELECT * FROM usorg INTO TABLE @gt_usorg_map.
  PERFORM upload_and_parse_file.
  PERFORM aggregate_input_data.
  PERFORM process_role_derivation.
  PERFORM display_alv_results.

*&---------------------------------------------------------------------*
*& Form f4_file_open
*&---------------------------------------------------------------------*
FORM f4_file_open CHANGING cv_file TYPE localfile.
  DATA: lt_file_table TYPE filetable,
        lv_rc         TYPE i.

  cl_gui_frontend_services=>file_open_dialog(
    EXPORTING
      window_title            = 'Select Derived Role CSV File'
      file_filter             = 'Derived Role CSV (*02_Derived*.csv)|*02_Derived*.csv|CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'
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
    MESSAGE |Invalid file '{ lv_fname }'. Expected CSV file (*_02_Derived_converted.csv).| TYPE 'E'.
  ENDIF.

  IF NOT ( lv_up CS '02_DERIVE' OR lv_up CS '_DERIVE' )
     OR lv_up CS '01_MASTER' OR lv_up CS '03A_ORG' OR lv_up CS '03B_AUTH'
     OR lv_up CS '03B_OBJECT' OR lv_up CS '03C_ACTIVITY' OR lv_up CS '04_COMPOSITE'
     OR lv_up CS '01_CREATE' OR lv_up CS '02_ASSIGN'.
    MESSAGE |Invalid file '{ lv_fname }' for Z_ROLE_02_CREATE_DERIVE. Expected '*_02_Derived_converted.csv'.| TYPE 'E'.
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
        ls_raw          TYPE ty_raw_row.

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

    CLEAR ls_raw.
    PERFORM parse_csv_line USING lv_line lv_file_delim
                           CHANGING ls_raw-col1 ls_raw-col2 ls_raw-col3.

    " Skip Header row: validate structure first on first non-empty line
    DATA(lv_c1_up) = to_upper( ls_raw-col1 ).
    DATA(lv_c2_up) = to_upper( ls_raw-col2 ).
    DATA(lv_c3_up) = to_upper( ls_raw-col3 ).
    IF lv_first_non_empty = abap_false.
      lv_first_non_empty = abap_true.
      IF lv_c1_up = 'ROLE' OR lv_c1_up = 'ROLE NAME' OR lv_c1_up = 'ROLE_NAME'
         OR lv_c1_up = 'USERNAME' OR lv_c1_up = 'USER NAME'
         OR lv_c1_up = 'COMPOSITE ROLE' OR lv_c1_up = 'COMPOSITE ROLE NAME'
         OR lv_c2_up = 'ORG_LEVEL' OR lv_c2_up = 'OBJECT-FIELD' OR lv_c2_up = 'FIELD'
         OR lv_c3_up = 'TCODE' OR lv_c3_up = 'SINGLE ROLE'.
        MESSAGE 'Invalid CSV header for Z_ROLE_02_CREATE_DERIVE. Expected: Master Role, Derived Role, Derived Role Description.' TYPE 'E'.
      ENDIF.
      IF lv_c1_up = 'MASTER ROLE' OR lv_c1_up = 'MASTER_ROLE'
         OR lv_c2_up = 'DERIVED ROLE' OR lv_c2_up = 'DERIVED_ROLE'.
        CONTINUE.
      ENDIF.
    ENDIF.
    IF lv_c1_up = 'MASTER ROLE' OR lv_c1_up = 'MASTER_ROLE' OR lv_c1_up = 'ROLE NAME'
       OR lv_c2_up = 'DERIVED ROLE' OR lv_c2_up = 'DERIVED_ROLE'.
      CONTINUE.
    ENDIF.

    IF ls_raw-col1 IS NOT INITIAL AND ls_raw-col2 IS NOT INITIAL.
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
    ev_col2 = lt_tokens[ 2 ].
    ev_col2 = to_upper( condense( ev_col2 ) ).
  ENDIF.
  IF lines( lt_tokens ) >= 3.
    ev_col3 = lt_tokens[ 3 ]. " Keep exact spacing as in input file (no trim/condense)
  ENDIF.
ENDFORM.


*&---------------------------------------------------------------------*
*& Form aggregate_input_data
*&---------------------------------------------------------------------*
FORM aggregate_input_data.
  DATA: lv_m_raw  TYPE string,
        lv_d_raw  TYPE string,
        lv_m_role TYPE agr_name,
        lv_d_role TYPE agr_name,
        lv_d_desc TYPE agr_title.

  CLEAR: gt_derive_roles, gt_oversized_roles.

  LOOP AT gt_raw_rows INTO DATA(ls_raw).
    lv_m_raw = to_upper( condense( ls_raw-col1 ) ).
    lv_d_raw = to_upper( condense( ls_raw-col2 ) ).
    lv_d_desc = ls_raw-col3. " Keep exact spacing

    IF lv_m_raw IS INITIAL OR lv_d_raw IS INITIAL.
      CONTINUE.
    ENDIF.

    " Guard against silent >30-char truncation on BOTH master and derived role names
    IF strlen( lv_d_raw ) > 30.
      READ TABLE gt_oversized_roles WITH KEY role_kind = 'Derived' role_name = lv_d_raw TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND VALUE ty_oversized_role( role_kind = 'Derived' role_name = lv_d_raw ) TO gt_oversized_roles.
      ENDIF.
      CONTINUE.
    ENDIF.
    IF strlen( lv_m_raw ) > 30.
      READ TABLE gt_oversized_roles WITH KEY role_kind = 'Master' role_name = lv_m_raw TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND VALUE ty_oversized_role( role_kind = 'Master' role_name = lv_m_raw ) TO gt_oversized_roles.
      ENDIF.
      CONTINUE.
    ENDIF.

    lv_m_role = lv_m_raw.
    lv_d_role = lv_d_raw.

    " Prevent duplicate derived roles in same upload batch
    READ TABLE gt_derive_roles WITH KEY derived_role = lv_d_role
      TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      CONTINUE.
    ENDIF.

    APPEND VALUE ty_derive_entry(
      master_role  = lv_m_role
      derived_role = lv_d_role
      derived_desc = lv_d_desc
    ) TO gt_derive_roles.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form process_role_derivation
*&---------------------------------------------------------------------*
FORM process_role_derivation.
  DATA: ls_res             TYPE ty_alv_result,
        lt_bapiret         TYPE STANDARD TABLE OF bapiret2,
        lt_orig_child_orgs TYPE ty_t_agr_1252,
        lv_master_chk      TYPE agr_name,
        lv_master_par      TYPE agr_name,
        lv_master_coll     TYPE char01,
        lv_drv_coll        TYPE char01,
        lv_child_of_drv    TYPE agr_name,
        lv_exists          TYPE abap_bool,
        lv_curr_par        TYPE agr_name,
        lv_new_req         TYPE trkorr,
        lv_drv_ok          TYPE char01,
        lv_adj_ok          TYPE char01,
        lv_prf_ok          TYPE char01,
        lv_rc              TYPE sy-subrc,
        lv_gen_subrc       TYPE sy-subrc,
        lv_gen_err         TYPE string,
        lv_desc_warn       TYPE string.

  CLEAR gt_results.

  " Report oversized (>30 char) master/derived role names explicitly
  LOOP AT gt_oversized_roles INTO DATA(ls_bad_ov).
    CLEAR ls_res.
    ls_res-status = gc_status_err.
    ls_res-action = 'ERROR'.
    IF ls_bad_ov-role_kind = 'Master'.
      ls_res-master_role = ls_bad_ov-role_name.
    ELSE.
      ls_res-derived_role = ls_bad_ov-role_name.
    ENDIF.
    ls_res-message = |{ ls_bad_ov-role_kind } role name exceeds SAP 30-character limit: '{ ls_bad_ov-role_name }'.|.
    APPEND ls_res TO gt_results.
  ENDLOOP.

  LOOP AT gt_derive_roles INTO DATA(ls_drv).
    CLEAR: ls_res, lt_bapiret, lt_orig_child_orgs, lv_master_chk, lv_master_par, lv_master_coll,
           lv_drv_coll, lv_child_of_drv, lv_exists, lv_curr_par, lv_new_req,
           lv_drv_ok, lv_adj_ok, lv_prf_ok, lv_rc, lv_gen_subrc, lv_gen_err, lv_desc_warn.

    ls_res-derived_role = ls_drv-derived_role.
    ls_res-derived_desc = ls_drv-derived_desc.
    ls_res-master_role  = ls_drv-master_role.

    " -----------------------------------------------------------------
    " 1. Authorize & Validate Master Role (S_USER_AGR 03 before metadata read)
    " -----------------------------------------------------------------
    AUTHORITY-CHECK OBJECT 'S_USER_AGR'
      ID 'ACT_GROUP' FIELD ls_drv-master_role
      ID 'ACTVT'     FIELD '03'.
    IF sy-subrc <> 0.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = |No display authorization (S_USER_AGR, ACTVT 03) for master role '{ ls_drv-master_role }'.|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    SELECT SINGLE agr_name, parent_agr FROM agr_define
      INTO (@lv_master_chk, @lv_master_par)
      WHERE agr_name = @ls_drv-master_role.
    IF sy-subrc <> 0 OR lv_master_chk IS INITIAL.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = |Master role '{ ls_drv-master_role }' does not exist in SAP.|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.
    IF lv_master_par IS NOT INITIAL.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = |Master role '{ ls_drv-master_role }' is itself derived from '{ lv_master_par }'; multi-level derivation is not allowed.|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    SELECT SINGLE text FROM agr_texts INTO ls_res-master_desc
      WHERE agr_name = ls_drv-master_role AND spras = sy-langu AND line = '00000'.
    IF sy-subrc <> 0.
      SELECT SINGLE text FROM agr_texts INTO ls_res-master_desc
        WHERE agr_name = ls_drv-master_role AND line = '00000'.
    ENDIF.

    SELECT SINGLE flag_value FROM agr_flags INTO lv_master_coll
      WHERE agr_name = ls_drv-master_role AND flag_type = 'COLL_AGR'.
    IF sy-subrc = 0 AND lv_master_coll = 'X'.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = |Master role '{ ls_drv-master_role }' is a collective role; cannot derive from collective role.|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " 2. Authorize Target Role Before Reading Metadata (S_USER_AGR)
    " -----------------------------------------------------------------
    IF ls_drv-derived_role = ls_drv-master_role.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = 'Derived role name cannot be identical to master role.'.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    IF p_test = abap_true.
      AUTHORITY-CHECK OBJECT 'S_USER_AGR'
        ID 'ACT_GROUP' FIELD ls_drv-derived_role
        ID 'ACTVT'     FIELD '03'.
      IF sy-subrc <> 0.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'ERROR'.
        ls_res-message = |No authorization for role '{ ls_drv-derived_role }' (S_USER_AGR, ACTVT 03).|.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.
    ELSE.
      AUTHORITY-CHECK OBJECT 'S_USER_AGR'
        ID 'ACT_GROUP' FIELD ls_drv-derived_role
        ID 'ACTVT'     FIELD '02'.
      IF sy-subrc <> 0.
        AUTHORITY-CHECK OBJECT 'S_USER_AGR'
          ID 'ACT_GROUP' FIELD ls_drv-derived_role
          ID 'ACTVT'     FIELD '01'.
        IF sy-subrc <> 0.
          ls_res-status  = gc_status_err.
          ls_res-action  = 'ERROR'.
          ls_res-message = |No authorization for role '{ ls_drv-derived_role }' (S_USER_AGR, ACTVT 01/02).|.
          APPEND ls_res TO gt_results.
          CONTINUE.
        ENDIF.
      ENDIF.
    ENDIF.

    SELECT SINGLE parent_agr FROM agr_define INTO lv_curr_par
      WHERE agr_name = ls_drv-derived_role.
    IF sy-subrc = 0.
      lv_exists = abap_true.
      " Guard: Target cannot be a collective role or already a Master parent of other derived roles
      SELECT SINGLE flag_value FROM agr_flags INTO lv_drv_coll
        WHERE agr_name = ls_drv-derived_role AND flag_type = 'COLL_AGR'.
      IF sy-subrc = 0 AND lv_drv_coll = 'X'.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'ERROR'.
        ls_res-message = |Target '{ ls_drv-derived_role }' is an existing collective role; cannot convert to derived role.|.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.
      SELECT SINGLE agr_name FROM agr_define INTO lv_child_of_drv
        WHERE parent_agr = ls_drv-derived_role.
      IF sy-subrc = 0.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'ERROR'.
        ls_res-message = |Target '{ ls_drv-derived_role }' is already a Master Role for '{ lv_child_of_drv }'.|.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.
    ELSE.
      lv_exists = abap_false.
    ENDIF.

    " Exact per-role authority check (ACTVT 02 existing / 01 create)
    DATA(lv_req_actvt) = COND activ_auth(
      WHEN p_test = abap_true THEN '03'
      WHEN lv_exists = abap_true THEN '02'
      ELSE '01' ).
    AUTHORITY-CHECK OBJECT 'S_USER_AGR'
      ID 'ACT_GROUP' FIELD ls_drv-derived_role
      ID 'ACTVT'     FIELD lv_req_actvt.
    IF sy-subrc <> 0.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = |No authorization for role '{ ls_drv-derived_role }' (S_USER_AGR, ACTVT { lv_req_actvt }).|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " 4. Simulation Mode (Test Run)
    " -----------------------------------------------------------------
    IF p_test = abap_true.
      IF lv_exists = abap_true.
        IF p_upd = abap_true.
          IF lv_curr_par NE ls_drv-master_role AND p_adjust = abap_false.
            ls_res-status  = gc_status_err.
            ls_res-action  = 'ERROR'.
            IF lv_curr_par IS NOT INITIAL.
              ls_res-message = |Cannot reparent '{ ls_drv-derived_role }' from '{ lv_curr_par }' to '{ ls_drv-master_role }' with Adjust Authorizations disabled (would create hybrid role).|.
            ELSE.
              ls_res-message = |Cannot convert standalone role '{ ls_drv-derived_role }' to derived role of '{ ls_drv-master_role }' with Adjust Authorizations disabled (would wipe menu while keeping old auths).|.
            ENDIF.
          ELSE.
            ls_res-status  = gc_status_ok.
            ls_res-action  = 'SIMULATE'.
            ls_res-message = |[Simulated] Role exists (Parent: '{ lv_curr_par }'); would be updated & synchronized from master '{ ls_drv-master_role }'.|.
          ENDIF.
        ELSE.
          ls_res-status  = gc_status_warn.
          ls_res-action  = 'SIMULATE'.
          ls_res-message = |[Simulated] Role already exists; would be skipped (Update option unselected).|.
        ENDIF.
      ELSE.
        ls_res-status  = gc_status_ok.
        ls_res-action  = 'SIMULATE'.
        ls_res-message = |[Simulated] Role does not exist; would be created & derived from master '{ ls_drv-master_role }'.|.
      ENDIF.

      SELECT SINGLE profile FROM agr_1016 INTO ls_res-profile
        WHERE agr_name = ls_drv-derived_role.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " 5. Real Execution
    " -----------------------------------------------------------------
    IF lv_exists = abap_true.
      IF p_upd = abap_false.
        ls_res-status  = gc_status_warn.
        ls_res-action  = 'SKIPPED'.
        ls_res-message = |Derived role already exists in SAP; skipped (Update option unselected).|.
        SELECT SINGLE profile FROM agr_1016 INTO ls_res-profile
          WHERE agr_name = ls_drv-derived_role.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.

      IF lv_curr_par NE ls_drv-master_role AND p_adjust = abap_false.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'ERROR'.
        IF lv_curr_par IS NOT INITIAL.
          ls_res-message = |Cannot reparent '{ ls_drv-derived_role }' from '{ lv_curr_par }' to '{ ls_drv-master_role }' with Adjust Authorizations disabled (would create hybrid role).|.
        ELSE.
          ls_res-message = |Cannot convert standalone role '{ ls_drv-derived_role }' to derived role of '{ ls_drv-master_role }' with Adjust Authorizations disabled (would wipe menu while keeping old auths).|.
        ENDIF.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.

      " 1. Pre-derivation (TOCTOU-safe): Enqueue briefly to snapshot existing Org Levels
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
        EXPORTING
          activity_group = ls_drv-derived_role
          no_dialog      = 'X'
        EXCEPTIONS
          OTHERS         = 1.
      IF sy-subrc <> 0.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'ERROR'.
        ls_res-message = |Role '{ ls_drv-derived_role }' is locked before org snapshot (rc={ sy-subrc }).|.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.

      CLEAR lt_orig_child_orgs.
      SELECT * FROM agr_1252 INTO TABLE @lt_orig_child_orgs
        WHERE agr_name = @ls_drv-derived_role
        ORDER BY counter.

      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
        EXPORTING
          activity_group = ls_drv-derived_role
        EXCEPTIONS
          OTHERS         = 0.

      " 2. Standard reparenting when switching from an existing DIFFERENT parent
      DATA: lv_reparented TYPE abap_bool,
            lv_cur_desc   TYPE agr_title.
      CLEAR: lv_reparented, lv_cur_desc.

      IF lv_curr_par IS NOT INITIAL AND lv_curr_par NE ls_drv-master_role.
        CLEAR lt_bapiret.
        CALL FUNCTION 'PRGN_RFC_DELETE_DERIVATION'
          EXPORTING
            role          = ls_drv-derived_role
            no_dialog     = 'X'
          TABLES
            return        = lt_bapiret
          EXCEPTIONS
            error_message = 98
            OTHERS        = 99.
        lv_rc = sy-subrc.

        DATA(lv_del_der_err) = xsdbool( lv_rc <> 0 ).
        LOOP AT lt_bapiret INTO DATA(ls_del_chk) WHERE type CA 'EAX'.
          lv_del_der_err = abap_true.
          EXIT.
        ENDLOOP.
        IF lv_del_der_err = abap_true.
          ROLLBACK WORK.
          CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
          ls_res-status = gc_status_err.
          ls_res-action = 'ERROR'.
          PERFORM format_bapi_message USING lt_bapiret CHANGING ls_res-message.
          IF ls_res-message IS INITIAL.
            ls_res-message = |PRGN_RFC_DELETE_DERIVATION failed while reparenting from '{ lv_curr_par }' (rc={ lv_rc }).|.
          ENDIF.
          APPEND ls_res TO gt_results.
          CONTINUE.
        ENDIF.
        COMMIT WORK AND WAIT.
        lv_reparented = abap_true.
      ENDIF.

      " 3. Synchronize / Adjust Auth data from master role
      CLEAR: lt_bapiret, lv_drv_ok, lv_adj_ok, lv_prf_ok.
      CALL FUNCTION 'PRGN_RFC_CREATE_DERIVATION'
        EXPORTING
          role            = ls_drv-derived_role
          parent_role     = ls_drv-master_role
          adjust_auths    = p_adjust
          profile_gen     = space
          no_dialog       = 'X'
        IMPORTING
          new_request     = lv_new_req
          derivation_ok   = lv_drv_ok
          adjust_auths_ok = lv_adj_ok
          profile_gen_ok  = lv_prf_ok
        TABLES
          return          = lt_bapiret
        EXCEPTIONS
          error_message   = 98
          OTHERS          = 99.
      lv_rc = sy-subrc.

      DATA(lv_has_err) = xsdbool( lv_rc <> 0 OR lv_drv_ok <> 'Y'
                                  OR ( p_adjust = abap_true AND lv_adj_ok <> 'Y' ) ).
      LOOP AT lt_bapiret INTO DATA(ls_bapi_chk) WHERE type CA 'EAX'.
        lv_has_err = abap_true.
        EXIT.
      ENDLOOP.

      IF lv_has_err = abap_true.
        ROLLBACK WORK.
        CALL FUNCTION 'PRGN_CLEAR_BUFFER'.

        DATA: lv_rev_note    TYPE string,
              lv_rev_comp    TYPE string,
              lv_db_par      TYPE agr_name,
              lt_rev_del_ret TYPE STANDARD TABLE OF bapiret2,
              lv_rev_del_rc  TYPE sy-subrc,
              lv_rev_del_err TYPE abap_bool,
              lv_rev_del_msg TYPE string,
              lt_rev_ret     TYPE STANDARD TABLE OF bapiret2,
              lv_rev_ok      TYPE char01,
              lv_rev_adj_ok  TYPE char01,
              lv_rev_rc      TYPE sy-subrc,
              lv_rev_err     TYPE abap_bool,
              lv_rev_msg     TYPE string.
        CLEAR: lv_rev_note, lv_rev_comp, lv_db_par, lt_rev_del_ret, lv_rev_del_rc,
               lv_rev_del_err, lv_rev_del_msg, lt_rev_ret, lv_rev_ok, lv_rev_adj_ok,
               lv_rev_rc, lv_rev_err, lv_rev_msg.

        SELECT SINGLE parent_agr FROM agr_define INTO @lv_db_par
          WHERE agr_name = @ls_drv-derived_role.

        " Revert via DELETE_DERIVATION -> CREATE_DERIVATION when CREATE_DERIVATION committed PARENT_AGR
        IF lv_reparented = abap_true AND lv_curr_par IS NOT INITIAL.
          IF lv_db_par IS NOT INITIAL AND lv_db_par <> lv_curr_par.
            CALL FUNCTION 'PRGN_RFC_DELETE_DERIVATION'
              EXPORTING
                role          = ls_drv-derived_role
                no_dialog     = 'X'
              TABLES
                return        = lt_rev_del_ret
              EXCEPTIONS
                error_message = 98
                OTHERS        = 99.
            lv_rev_del_rc  = sy-subrc.
            lv_rev_del_err = xsdbool( lv_rev_del_rc <> 0 ).
            LOOP AT lt_rev_del_ret INTO DATA(ls_rdel_chk) WHERE type CA 'EAX'.
              lv_rev_del_err = abap_true.
              EXIT.
            ENDLOOP.
            IF lv_rev_del_err = abap_true.
              ROLLBACK WORK.
              CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
              PERFORM format_bapi_message USING lt_rev_del_ret CHANGING lv_rev_del_msg.
              lv_rev_note = | CRITICAL: Rollback delete derivation from '{ lv_db_par }' failed (rc={ lv_rev_del_rc }): { lv_rev_del_msg }|.
            ELSE.
              COMMIT WORK AND WAIT.
            ENDIF.
          ENDIF.

          IF lv_rev_del_err = abap_false.
            CALL FUNCTION 'PRGN_RFC_CREATE_DERIVATION'
              EXPORTING
                role            = ls_drv-derived_role
                parent_role     = lv_curr_par
                adjust_auths    = 'X'
                profile_gen     = space
                no_dialog       = 'X'
              IMPORTING
                derivation_ok   = lv_rev_ok
                adjust_auths_ok = lv_rev_adj_ok
              TABLES
                return          = lt_rev_ret
              EXCEPTIONS
                error_message   = 98
                OTHERS          = 99.
            lv_rev_rc  = sy-subrc.
            lv_rev_err = xsdbool( lv_rev_rc <> 0 OR lv_rev_ok <> 'Y' OR lv_rev_adj_ok <> 'Y' ).
            LOOP AT lt_rev_ret INTO DATA(ls_rev_chk) WHERE type CA 'EAX'.
              lv_rev_err = abap_true.
              EXIT.
            ENDLOOP.
            IF lv_rev_err = abap_true.
              ROLLBACK WORK.
              CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
              CLEAR: lt_rev_ret, lv_rev_ok.
              CALL FUNCTION 'PRGN_RFC_CREATE_DERIVATION'
                EXPORTING
                  role          = ls_drv-derived_role
                  parent_role   = lv_curr_par
                  adjust_auths  = space
                  profile_gen   = space
                  no_dialog     = 'X'
                IMPORTING
                  derivation_ok = lv_rev_ok
                TABLES
                  return        = lt_rev_ret
                EXCEPTIONS
                  error_message = 98
                  OTHERS        = 99.
              lv_rev_rc  = sy-subrc.
              lv_rev_err = xsdbool( lv_rev_rc <> 0 OR lv_rev_ok <> 'Y' ).
              LOOP AT lt_rev_ret INTO ls_rev_chk WHERE type CA 'EAX'.
                lv_rev_err = abap_true.
                EXIT.
              ENDLOOP.
            ENDIF.
            IF lv_rev_err = abap_true.
              ROLLBACK WORK.
              CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
              PERFORM format_bapi_message USING lt_rev_ret CHANGING lv_rev_msg.
              lv_rev_note = | CRITICAL: Rollback to '{ lv_curr_par }' failed (rc={ lv_rev_rc }, ok={ lv_rev_ok }): { lv_rev_msg }|.
            ELSE.
              COMMIT WORK AND WAIT.
              PERFORM compensate_restore_child_orgs USING ls_drv-derived_role abap_false lt_orig_child_orgs
                                                    CHANGING lv_rev_comp.
              lv_rev_note = | Reverted parent link back to '{ lv_curr_par }'.|.
              IF lv_rev_comp IS NOT INITIAL.
                lv_rev_note = |{ lv_rev_note } { lv_rev_comp }|.
              ENDIF.
            ENDIF.
          ENDIF.
        ELSEIF lv_curr_par IS INITIAL AND lv_db_par = ls_drv-master_role.
          CALL FUNCTION 'PRGN_RFC_DELETE_DERIVATION'
            EXPORTING
              role          = ls_drv-derived_role
              no_dialog     = 'X'
            TABLES
              return        = lt_rev_del_ret
            EXCEPTIONS
              error_message = 98
              OTHERS        = 99.
          lv_rev_del_rc  = sy-subrc.
          lv_rev_del_err = xsdbool( lv_rev_del_rc <> 0 ).
          LOOP AT lt_rev_del_ret INTO ls_rdel_chk WHERE type CA 'EAX'.
            lv_rev_del_err = abap_true.
            EXIT.
          ENDLOOP.
          IF lv_rev_del_err = abap_true.
            ROLLBACK WORK.
            CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
            PERFORM format_bapi_message USING lt_rev_del_ret CHANGING lv_rev_del_msg.
            lv_rev_note = | Partial link to '{ ls_drv-master_role }' remained (cleanup failed rc={ lv_rev_del_rc }: { lv_rev_del_msg }).|.
          ELSE.
            COMMIT WORK AND WAIT.
            PERFORM compensate_restore_child_orgs USING ls_drv-derived_role abap_false lt_orig_child_orgs
                                                  CHANGING lv_rev_comp.
            lv_rev_note = | Detached partial derivation link from '{ ls_drv-master_role }'.|.
            IF lv_rev_comp IS NOT INITIAL.
              lv_rev_note = |{ lv_rev_note } { lv_rev_comp }|.
            ENDIF.
          ENDIF.
        ELSE.
          PERFORM compensate_restore_child_orgs USING ls_drv-derived_role abap_false lt_orig_child_orgs
                                                CHANGING lv_rev_comp.
          IF lv_rev_comp IS NOT INITIAL.
            lv_rev_note = | { lv_rev_comp }|.
          ENDIF.
        ENDIF.

        ls_res-status = gc_status_err.
        ls_res-action = 'ERROR'.
        PERFORM format_bapi_message USING lt_bapiret CHANGING ls_res-message.
        IF ls_res-message IS INITIAL.
          ls_res-message = |Error occurred during role synchronization (rc={ lv_rc }, drv={ lv_drv_ok }, adj={ lv_adj_ok }).|.
        ENDIF.
        IF lv_rev_note IS NOT INITIAL.
          ls_res-message = |{ ls_res-message }{ lv_rev_note }|.
        ENDIF.
      ELSE.
        COMMIT WORK AND WAIT.
        " 4. Reconcile & restore ALL multi-value Org Levels + clean AGR_1251 BEFORE description & profile gen
        DATA: lv_org_err TYPE string.
        CLEAR lv_org_err.
        PERFORM restore_and_sync_org_levels USING ls_drv-derived_role ls_drv-master_role lt_orig_child_orgs
                                            CHANGING lv_org_err.
        IF lv_org_err IS NOT INITIAL.
          ls_res-status  = gc_status_err.
          ls_res-action  = 'ERROR'.
          ls_res-message = lv_org_err.
          APPEND ls_res TO gt_results.
          CONTINUE.
        ENDIF.

        " 5. Update Role Description AFTER org sync succeeds (preserve long text)
        IF ls_drv-derived_desc IS NOT INITIAL.
          SELECT SINGLE text FROM agr_texts INTO @lv_cur_desc
            WHERE agr_name = @ls_drv-derived_role AND spras = @sy-langu AND line = '00000'.
          IF sy-subrc <> 0 OR lv_cur_desc <> ls_drv-derived_desc.
            PERFORM set_role_description USING ls_drv-derived_role ls_drv-derived_desc abap_true
                                         CHANGING lv_desc_warn.
          ENDIF.
        ENDIF.

        " 6. Regenerate profile after Org Levels are properly restored
        IF p_genprf = abap_true.
          CLEAR lt_bapiret.
          CALL FUNCTION 'SUPRN_DARK_MANIPULATE_PROFILE'
            EXPORTING
              activity_group        = ls_drv-derived_role
              fill_orgs_with_star   = space
              fill_fields_with_star = space
              no_dialog             = 'X'
              rebuild_auth_data     = space
              generate_profile      = 'X'
            IMPORTING
              return                = lt_bapiret
            EXCEPTIONS
              open_auths                     = 1
              no_auth_for_gen                = 2
              no_auths                       = 3
              too_many_auths                 = 4
              error_when_generating_profile  = 5
              OTHERS                         = 6.
          lv_gen_subrc = sy-subrc.
          PERFORM format_bapi_message USING lt_bapiret CHANGING lv_gen_err.
          IF lv_gen_subrc <> 0 AND lv_gen_err IS INITIAL.
            IF sy-msgid IS NOT INITIAL.
              MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno
                WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 INTO lv_gen_err.
            ENDIF.
            IF lv_gen_err IS INITIAL.
              lv_gen_err = SWITCH #( lv_gen_subrc
                WHEN 1 THEN 'Open/unmaintained authorizations or org levels'
                WHEN 2 THEN 'Missing profile generation authorization (S_USER_PRO)'
                WHEN 3 THEN 'No authorization data found'
                WHEN 4 THEN 'Too many authorizations for profile'
                ELSE |Profile generation failed (sy-subrc = { lv_gen_subrc })| ).
            ENDIF.
          ENDIF.
          IF lv_gen_subrc = 0 AND lv_gen_err IS INITIAL.
            COMMIT WORK AND WAIT.
          ELSE.
            ROLLBACK WORK.
            CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
          ENDIF.
        ENDIF.

        IF lv_gen_subrc <> 0 OR lv_gen_err IS NOT INITIAL OR lv_desc_warn IS NOT INITIAL.
          ls_res-status  = gc_status_warn.
          ls_res-action  = 'UPDATED'.
          IF lv_gen_subrc <> 0 OR lv_gen_err IS NOT INITIAL.
            ls_res-message = |Derived role synced from '{ ls_drv-master_role }'. Profile warning: { lv_gen_err }|.
          ELSE.
            ls_res-message = |Derived role updated & synchronized from master '{ ls_drv-master_role }'. Org levels preserved.|.
          ENDIF.
          IF lv_desc_warn IS NOT INITIAL.
            ls_res-message = |{ ls_res-message } Description warning: { lv_desc_warn }|.
          ENDIF.
        ELSE.
          ls_res-status  = gc_status_ok.
          ls_res-action  = 'UPDATED'.
          ls_res-message = |Derived role updated & synchronized from master '{ ls_drv-master_role }'. Org levels preserved.|.
          IF p_orgdef = abap_true.
            ls_res-message = |{ ls_res-message } Unmaintained org levels defaulted to '-1'.|.
          ENDIF.
        ENDIF.
      ENDIF.

    ELSE.
      " --- Create New Derived Role ---
      DATA(lv_create_desc) = COND agr_title(
        WHEN ls_drv-derived_desc IS NOT INITIAL THEN ls_drv-derived_desc
        ELSE ls_drv-derived_role ).

      CLEAR lt_bapiret.
      CALL FUNCTION 'PRGN_RFC_CREATE_AGR_MULTIPLE'
        EXPORTING
          activity_group                = ls_drv-derived_role
          parent_role                   = ls_drv-master_role
          activity_group_text           = lv_create_desc
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

      DATA(lv_crt_drv_err) = xsdbool( lv_rc <> 0 ).
      LOOP AT lt_bapiret INTO DATA(ls_cd_chk) WHERE type CA 'EAX'.
        lv_crt_drv_err = abap_true.
        EXIT.
      ENDLOOP.

      IF lv_crt_drv_err = abap_true.
        ROLLBACK WORK.
        CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
        ls_res-status = gc_status_err.
        ls_res-action = 'ERROR'.
        PERFORM format_bapi_message USING lt_bapiret CHANGING ls_res-message.
        IF ls_res-message IS INITIAL.
          ls_res-message = |Failed to create derived role definition (sy-subrc = { lv_rc }).|.
        ENDIF.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.

      COMMIT WORK AND WAIT.

      PERFORM set_role_description USING ls_drv-derived_role lv_create_desc abap_false
                                   CHANGING lv_desc_warn.

      CLEAR: lt_bapiret, lv_drv_ok, lv_adj_ok, lv_prf_ok.
      CALL FUNCTION 'PRGN_RFC_CREATE_DERIVATION'
        EXPORTING
          role            = ls_drv-derived_role
          parent_role     = ls_drv-master_role
          adjust_auths    = p_adjust
          profile_gen     = space
          no_dialog       = 'X'
        IMPORTING
          new_request     = lv_new_req
          derivation_ok   = lv_drv_ok
          adjust_auths_ok = lv_adj_ok
          profile_gen_ok  = lv_prf_ok
        TABLES
          return          = lt_bapiret
        EXCEPTIONS
          error_message   = 98
          OTHERS          = 99.
      lv_rc = sy-subrc.

      lv_has_err = xsdbool( lv_rc <> 0 OR lv_drv_ok <> 'Y'
                            OR ( p_adjust = abap_true AND lv_adj_ok <> 'Y' ) ).
      LOOP AT lt_bapiret INTO ls_bapi_chk WHERE type CA 'EAX'.
        lv_has_err = abap_true.
        EXIT.
      ENDLOOP.

      IF lv_has_err = abap_true.
        ROLLBACK WORK.
        CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
        ls_res-status = gc_status_err.
        ls_res-action = 'ERROR'.
        PERFORM format_bapi_message USING lt_bapiret CHANGING ls_res-message.
        IF ls_res-message IS INITIAL.
          ls_res-message = |Error occurred during auth transfer from master role (rc={ lv_rc }, drv={ lv_drv_ok }, adj={ lv_adj_ok }).|.
        ENDIF.
        SELECT SINGLE agr_name FROM agr_define INTO @DATA(lv_new_sh_chk)
          WHERE agr_name = @ls_drv-derived_role.
        IF sy-subrc = 0.
          ls_res-message = |{ ls_res-message } (Note: derived role shell already committed in AGR_DEFINE without synced authorizations).|.
        ENDIF.
      ELSE.
        COMMIT WORK AND WAIT.
        IF p_adjust = abap_true.
          CLEAR: lt_orig_child_orgs, lv_org_err.
          PERFORM restore_and_sync_org_levels USING ls_drv-derived_role ls_drv-master_role lt_orig_child_orgs
                                              CHANGING lv_org_err.
          IF lv_org_err IS NOT INITIAL.
            ls_res-status  = gc_status_err.
            ls_res-action  = 'ERROR'.
            ls_res-message = lv_org_err.
            APPEND ls_res TO gt_results.
            CONTINUE.
          ENDIF.
        ENDIF.

        IF p_genprf = abap_true.
          CLEAR lt_bapiret.
          CALL FUNCTION 'SUPRN_DARK_MANIPULATE_PROFILE'
            EXPORTING
              activity_group        = ls_drv-derived_role
              fill_orgs_with_star   = space
              fill_fields_with_star = space
              no_dialog             = 'X'
              rebuild_auth_data     = space
              generate_profile      = 'X'
            IMPORTING
              return                = lt_bapiret
            EXCEPTIONS
              open_auths                     = 1
              no_auth_for_gen                = 2
              no_auths                       = 3
              too_many_auths                 = 4
              error_when_generating_profile  = 5
              OTHERS                         = 6.
          lv_gen_subrc = sy-subrc.
          PERFORM format_bapi_message USING lt_bapiret CHANGING lv_gen_err.
          IF lv_gen_subrc <> 0 AND lv_gen_err IS INITIAL.
            IF sy-msgid IS NOT INITIAL.
              MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno
                WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 INTO lv_gen_err.
            ENDIF.
            IF lv_gen_err IS INITIAL.
              lv_gen_err = SWITCH #( lv_gen_subrc
                WHEN 1 THEN 'Open/unmaintained authorizations or org levels'
                WHEN 2 THEN 'Missing profile generation authorization (S_USER_PRO)'
                WHEN 3 THEN 'No authorization data found'
                WHEN 4 THEN 'Too many authorizations for profile'
                ELSE |Profile generation failed (sy-subrc = { lv_gen_subrc })| ).
            ENDIF.
          ENDIF.
          IF lv_gen_subrc = 0 AND lv_gen_err IS INITIAL.
            COMMIT WORK AND WAIT.
          ELSE.
            ROLLBACK WORK.
            CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
          ENDIF.
        ENDIF.

        IF lv_gen_subrc <> 0 OR lv_gen_err IS NOT INITIAL OR lv_desc_warn IS NOT INITIAL.
          ls_res-status  = gc_status_warn.
          ls_res-action  = 'CREATED'.
          IF lv_gen_subrc <> 0 OR lv_gen_err IS NOT INITIAL.
            ls_res-message = |Derived role created from '{ ls_drv-master_role }'. Profile warning: { lv_gen_err }|.
          ELSE.
            ls_res-message = |Derived role successfully created from master '{ ls_drv-master_role }'.|.
          ENDIF.
          IF lv_desc_warn IS NOT INITIAL.
            ls_res-message = |{ ls_res-message } Description warning: { lv_desc_warn }|.
          ENDIF.
        ELSE.
          ls_res-status  = gc_status_ok.
          ls_res-action  = 'CREATED'.
          ls_res-message = |Derived role successfully created from master '{ ls_drv-master_role }'.|.
          IF p_genprf = abap_true.
            ls_res-message = |{ ls_res-message } Profile generated.|.
          ENDIF.
          IF p_orgdef = abap_true.
            ls_res-message = |{ ls_res-message } Org levels defaulted to '-1'.|.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.

    " Retrieve Generated Profile Name from AGR_1016
    SELECT SINGLE profile FROM agr_1016 INTO ls_res-profile
      WHERE agr_name = ls_drv-derived_role.

    APPEND ls_res TO gt_results.
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
  DATA: lt_texts   TYPE STANDARD TABLE OF agr_texts,
        lt_ret     TYPE bapiret2_t,
        lv_rc      TYPE sy-subrc,
        lv_txt_err TYPE abap_bool.
  CLEAR: lt_texts, lt_ret, ev_warn, lv_txt_err.

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
  lv_txt_err = xsdbool( lv_rc <> 0 ).

  LOOP AT lt_ret INTO DATA(ls_r) WHERE type CA 'EAXW'.
    IF ls_r-type CA 'EAX'.
      lv_txt_err = abap_true.
    ENDIF.
    IF ev_warn IS INITIAL.
      ev_warn = ls_r-message.
    ELSE.
      ev_warn = |{ ev_warn }; { ls_r-message }|.
    ENDIF.
  ENDLOOP.
  IF lv_rc <> 0 AND ev_warn IS INITIAL.
    ev_warn = |PRGN_RFC_CHANGE_TEXTS failed (rc={ lv_rc }).|.
  ENDIF.

  IF lv_txt_err = abap_true.
    ROLLBACK WORK.
    CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
  ELSE.
    COMMIT WORK AND WAIT.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form format_bapi_message
*&---------------------------------------------------------------------*
FORM format_bapi_message USING    it_bapiret TYPE bapiret2_t
                         CHANGING cv_msg     TYPE string.
  CLEAR cv_msg.
  LOOP AT it_bapiret INTO DATA(ls_bapi) WHERE type CA 'EAX'.
    IF cv_msg IS INITIAL.
      cv_msg = ls_bapi-message.
    ELSE.
      CONCATENATE cv_msg '|' ls_bapi-message INTO cv_msg SEPARATED BY space.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form restore_and_sync_org_levels
*&---------------------------------------------------------------------*
* Restores and synchronizes Organizational Levels for Derived Roles:
* 1. First cleans AGR_1251 $VARBL bindings (S) so new org variables appear.
* 2. Preserves existing maintained values in AGR_1252.
* 3. For unmaintained org levels: '-1' if p_orgdef = 'X', else empty.
*&---------------------------------------------------------------------*
FORM restore_and_sync_org_levels USING    iv_role      TYPE agr_name
                                          iv_master    TYPE agr_name
                                          it_orig_orgs TYPE ty_t_agr_1252
                                 CHANGING ev_err       TYPE string.
  DATA: lt_cur_orgs   TYPE STANDARD TABLE OF pt1252,
        lt_dist_vars  TYPE STANDARD TABLE OF agval,
        lt_role_vars  TYPE STANDARD TABLE OF agval,
        lt_mast_vars  TYPE STANDARD TABLE OF agval,
        lt_final_orgs TYPE STANDARD TABLE OF pt1252,
        lv_comp_note  TYPE string.

  CLEAR: lt_cur_orgs, lt_dist_vars, lt_role_vars, lt_mast_vars,
         lt_final_orgs, lv_comp_note, ev_err.

  " TOCTOU Prevention (HIGH-04): Hold continuous lock from pre-read repair through 1252 save
  CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
    EXPORTING
      activity_group = iv_role
      no_dialog      = 'X'
    EXCEPTIONS
      OTHERS         = 1.
  IF sy-subrc <> 0.
    PERFORM compensate_restore_child_orgs USING iv_role abap_false it_orig_orgs
                                          CHANGING lv_comp_note.
    ev_err = |Role '{ iv_role }' is locked or cannot be enqueued for org sync (rc={ sy-subrc }). { lv_comp_note }|.
    RETURN.
  ENDIF.

  CALL FUNCTION 'PRGN_CLEAR_BUFFER'.

  " Clean Org variable bindings in AGR_1251/1250 FIRST so new $VARBLs are visible
  PERFORM fix_derived_1251_org_bindings USING iv_role abap_true CHANGING ev_err.
  IF ev_err IS NOT INITIAL.
    PERFORM compensate_restore_child_orgs USING iv_role abap_true it_orig_orgs
                                          CHANGING lv_comp_note.
    IF lv_comp_note IS NOT INITIAL.
      ev_err = |{ ev_err } { lv_comp_note }|.
    ENDIF.
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
      EXPORTING
        activity_group = iv_role
      EXCEPTIONS
        OTHERS         = 0.
    RETURN.
  ENDIF.

  CALL FUNCTION 'PRGN_1252_READ_ORG_LEVELS'
    EXPORTING
      activity_group    = iv_role
    TABLES
      org_levels        = lt_cur_orgs
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.
  IF sy-subrc = 2.
    ev_err = |PRGN_1252_READ_ORG_LEVELS failed for '{ iv_role }' (rc=2).|.
    PERFORM compensate_restore_child_orgs USING iv_role abap_true it_orig_orgs
                                          CHANGING lv_comp_note.
    IF lv_comp_note IS NOT INITIAL.
      ev_err = |{ ev_err } { lv_comp_note }|.
    ENDIF.
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
      EXPORTING
        activity_group = iv_role
      EXCEPTIONS
        OTHERS         = 0.
    RETURN.
  ENDIF.

  " Unconditionally union org variables from AGR_1252, active AGR_1251, and Master AGR_1252
  LOOP AT lt_cur_orgs INTO DATA(ls_cv).
    APPEND ls_cv-varbl TO lt_dist_vars.
  ENDLOOP.

  IF gt_usorg_map IS INITIAL.
    SELECT * FROM usorg INTO TABLE @gt_usorg_map.
  ENDIF.

  SELECT DISTINCT f~low FROM agr_1251 AS f
    INNER JOIN agr_1250 AS h
      ON  h~agr_name = f~agr_name
      AND h~object   = f~object
      AND h~auth     = f~auth
    INTO TABLE @lt_role_vars
    WHERE f~agr_name = @iv_role AND f~low LIKE '$%'
      AND f~deleted  = @space AND f~copied <> 'I'
      AND h~deleted  = @space AND h~copied <> 'I'.
  LOOP AT lt_role_vars INTO DATA(lv_rv).
    READ TABLE gt_usorg_map TRANSPORTING NO FIELDS WITH KEY varbl = lv_rv.
    IF sy-subrc = 0.
      APPEND lv_rv TO lt_dist_vars.
    ENDIF.
  ENDLOOP.

  SELECT DISTINCT varbl FROM agr_1252 INTO TABLE @lt_mast_vars
    WHERE agr_name = @iv_master.
  LOOP AT lt_mast_vars INTO DATA(lv_mv).
    READ TABLE gt_usorg_map TRANSPORTING NO FIELDS WITH KEY varbl = lv_mv.
    IF sy-subrc = 0.
      APPEND lv_mv TO lt_dist_vars.
    ENDIF.
  ENDLOOP.

  SORT lt_dist_vars.
  DELETE ADJACENT DUPLICATES FROM lt_dist_vars.
  DELETE lt_dist_vars WHERE table_line IS INITIAL.

  LOOP AT lt_dist_vars INTO DATA(lv_varbl).
    DATA(lv_found_maint) = abap_false.
    LOOP AT it_orig_orgs INTO DATA(ls_orig)
      WHERE varbl = lv_varbl
        AND ( low IS NOT INITIAL OR high IS NOT INITIAL ).
      lv_found_maint = abap_true.
      APPEND VALUE pt1252(
        varbl = ls_orig-varbl
        low   = ls_orig-low
        high  = ls_orig-high
      ) TO lt_final_orgs.
    ENDLOOP.

    IF lv_found_maint = abap_false.
      IF p_orgdef = abap_true.
        APPEND VALUE pt1252( varbl = lv_varbl low = '-1' high = space ) TO lt_final_orgs.
      ELSE.
        APPEND VALUE pt1252( varbl = lv_varbl low = space high = space ) TO lt_final_orgs.
      ENDIF.
    ENDIF.
  ENDLOOP.

  SORT lt_final_orgs BY varbl low high.
  DELETE ADJACENT DUPLICATES FROM lt_final_orgs COMPARING varbl low high.

  IF lt_final_orgs IS NOT INITIAL.
    CALL FUNCTION 'PRGN_CLEAR_BUFFER'.

    CALL FUNCTION 'PRGN_1252_SAVE_ORG_LEVELS'
      EXPORTING
        activity_group = iv_role
      TABLES
        org_levels     = lt_final_orgs
      EXCEPTIONS
        OTHERS         = 1.
    IF sy-subrc <> 0.
      ev_err = |PRGN_1252_SAVE_ORG_LEVELS failed for '{ iv_role }' (rc={ sy-subrc }).|.
    ENDIF.

    IF ev_err IS INITIAL.
      CALL FUNCTION 'PRGN_UPDATE_DATABASE'
        EXCEPTIONS
          OTHERS = 1.
      IF sy-subrc <> 0.
        ev_err = |PRGN_UPDATE_DATABASE failed during org sync for '{ iv_role }' (rc={ sy-subrc }).|.
      ENDIF.
    ENDIF.

    IF ev_err IS INITIAL.
      CALL FUNCTION 'PRGN_SET_ACTGROUP_TIMESTAMP'
        EXPORTING
          activity_group = iv_role
          no_commit      = 'X'
        EXCEPTIONS
          OTHERS         = 0.
      COMMIT WORK AND WAIT.
    ELSE.
      ROLLBACK WORK.
      CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
      PERFORM compensate_restore_child_orgs USING iv_role abap_true it_orig_orgs
                                            CHANGING lv_comp_note.
      IF lv_comp_note IS NOT INITIAL.
        ev_err = |{ ev_err } { lv_comp_note }|.
      ENDIF.
    ENDIF.
  ENDIF.

  CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
    EXPORTING
      activity_group = iv_role
    EXCEPTIONS
      OTHERS         = 0.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form fix_derived_1251_org_bindings
*&---------------------------------------------------------------------*
* Rebinds active Org Level fields to $VARBL while honoring TPR_ST_MOD:
*   'S' = Standard, 'G' = Maintained, 'M' = Changed, 'U' = Manual.
* Manual ('U') headers & concrete overrides preserved; per LSUPRNF1H,
* active $VARBL rows in AGR_1251 use MODIFIED = 'S'.
*&---------------------------------------------------------------------*
FORM fix_derived_1251_org_bindings USING    iv_role        TYPE agr_name
                                            iv_already_enq TYPE abap_bool
                                   CHANGING ev_err         TYPE string.
  TYPES: BEGIN OF ty_hdr_mod,
           object   TYPE xuobject,
           auth     TYPE xuauth,
           modified TYPE char1,
         END OF ty_hdr_mod,
         BEGIN OF ty_obj_auth_key,
           object TYPE xuobject,
           auth   TYPE xuauth,
         END OF ty_obj_auth_key,
         BEGIN OF ty_obj_auth_fld,
           object TYPE xuobject,
           auth   TYPE xuauth,
           field  TYPE xufield,
         END OF ty_obj_auth_fld.

  DATA: lt_pt1251         TYPE STANDARD TABLE OF pt1251,
        lt_clean          TYPE STANDARD TABLE OF pt1251,
        lt_pt1250         TYPE STANDARD TABLE OF pt1250,
        lt_act_hdr        TYPE HASHED TABLE OF ty_hdr_mod WITH UNIQUE KEY object auth,
        lt_seen_key       TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line,
        lt_healed_auths   TYPE HASHED TABLE OF ty_obj_auth_key WITH UNIQUE KEY object auth,
        lt_decoupled_flds TYPE HASHED TABLE OF ty_obj_auth_fld WITH UNIQUE KEY object auth field,
        lv_key            TYPE string,
        lv_mod51          TYPE abap_bool,
        lv_mod50          TYPE abap_bool.

  CLEAR: lt_pt1251, lt_clean, lt_pt1250, lt_act_hdr, lt_seen_key,
         lt_healed_auths, lt_decoupled_flds, lv_mod51, lv_mod50.

  IF gt_usorg_map IS INITIAL.
    RETURN.
  ENDIF.

  IF iv_already_enq = abap_false.
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
      EXPORTING
        activity_group = iv_role
        no_dialog      = 'X'
      EXCEPTIONS
        OTHERS         = 1.
    IF sy-subrc <> 0.
      ev_err = |Role '{ iv_role }' is locked during $VARBL repair (rc={ sy-subrc }).|.
      RETURN.
    ENDIF.
  ENDIF.

  CALL FUNCTION 'PRGN_CLEAR_BUFFER'.

  CALL FUNCTION 'PRGN_1250_READ_AUTH_DATA'
    EXPORTING
      activity_group    = iv_role
      no_texts          = 'X'
    TABLES
      auth_data         = lt_pt1250
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.
  IF sy-subrc = 2.
    ev_err = |PRGN_1250_READ_AUTH_DATA failed for '{ iv_role }' (rc=2).|.
    IF iv_already_enq = abap_false.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
        EXPORTING
          activity_group = iv_role
        EXCEPTIONS
          OTHERS         = 0.
    ENDIF.
    RETURN.
  ENDIF.
  IF sy-subrc <> 0 OR lt_pt1250 IS INITIAL.
    IF iv_already_enq = abap_false.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
        EXPORTING
          activity_group = iv_role
        EXCEPTIONS
          OTHERS         = 0.
    ENDIF.
    RETURN.
  ENDIF.

  LOOP AT lt_pt1250 INTO DATA(ls_h50) WHERE deleted = space AND copied <> 'I'.
    INSERT VALUE ty_hdr_mod(
      object   = ls_h50-object
      auth     = ls_h50-auth
      modified = ls_h50-modified
    ) INTO TABLE lt_act_hdr.
  ENDLOOP.

  CALL FUNCTION 'PRGN_1251_READ_FIELD_VALUES'
    EXPORTING
      activity_group    = iv_role
    TABLES
      field_values      = lt_pt1251
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.
  IF sy-subrc = 2.
    ev_err = |PRGN_1251_READ_FIELD_VALUES failed for '{ iv_role }' (rc=2).|.
    IF iv_already_enq = abap_false.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
        EXPORTING
          activity_group = iv_role
        EXCEPTIONS
          OTHERS         = 0.
    ENDIF.
    RETURN.
  ENDIF.
  IF sy-subrc <> 0 OR lt_pt1251 IS INITIAL.
    IF iv_already_enq = abap_false.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
        EXPORTING
          activity_group = iv_role
        EXCEPTIONS
          OTHERS         = 0.
    ENDIF.
    RETURN.
  ENDIF.

  " Pre-scan: identify any (object, auth, field) having a decoupled concrete 'G'/'M'/'U' override
  LOOP AT lt_pt1251 INTO DATA(ls_pre).
    IF ls_pre-deleted <> space OR ls_pre-copied = 'I'.
      CONTINUE.
    ENDIF.
    IF NOT line_exists( lt_act_hdr[ object = ls_pre-object auth = ls_pre-auth ] ).
      CONTINUE.
    ENDIF.
    READ TABLE gt_usorg_map INTO DATA(ls_uo_pre) WITH TABLE KEY field = ls_pre-field.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.
    IF ( ls_pre-modified = 'G' OR ls_pre-modified = 'M' OR ls_pre-modified = 'U' )
       AND ( ( ls_pre-low IS NOT INITIAL AND ls_pre-low <> '-1'
               AND ls_pre-low <> '$' AND ls_pre-low <> ls_uo_pre-varbl )
             OR ls_pre-high IS NOT INITIAL ).
      INSERT VALUE ty_obj_auth_fld(
        object = ls_pre-object auth = ls_pre-auth field = ls_pre-field )
        INTO TABLE lt_decoupled_flds.
    ENDIF.
  ENDLOOP.

  " SAPLSUPRN LSUPRNF1H: AGR_1251 $VARBL rows MUST have MODIFIED = 'S' (even under 'U' header!)
  LOOP AT lt_pt1251 INTO DATA(ls_f51).
    IF ls_f51-deleted = space AND ls_f51-copied <> 'I'.
      READ TABLE lt_act_hdr INTO DATA(ls_hdr)
        WITH TABLE KEY object = ls_f51-object auth = ls_f51-auth.
      IF sy-subrc = 0.
        READ TABLE gt_usorg_map INTO DATA(ls_uo) WITH TABLE KEY field = ls_f51-field.
        IF sy-subrc = 0.
          IF line_exists( lt_decoupled_flds[
               object = ls_f51-object auth = ls_f51-auth field = ls_f51-field ] ).
            IF ( ls_f51-low IS INITIAL OR ls_f51-low = '-1'
                 OR ls_f51-low = '$' OR ls_f51-low = ls_uo-varbl )
               AND ls_f51-high IS INITIAL.
              lv_mod51 = abap_true.
              INSERT VALUE ty_obj_auth_key( object = ls_f51-object auth = ls_f51-auth )
                INTO TABLE lt_healed_auths.
              CONTINUE.
            ENDIF.
            APPEND ls_f51 TO lt_clean.
            CONTINUE.
          ENDIF.

          lv_key = |{ ls_f51-object }:{ ls_f51-auth }:{ ls_f51-field }|.
          IF line_exists( lt_seen_key[ table_line = lv_key ] ).
            lv_mod51 = abap_true.
            INSERT VALUE ty_obj_auth_key( object = ls_f51-object auth = ls_f51-auth )
              INTO TABLE lt_healed_auths.
            CONTINUE.
          ENDIF.
          INSERT lv_key INTO TABLE lt_seen_key.
          IF ls_f51-low <> ls_uo-varbl OR ls_f51-high IS NOT INITIAL
             OR ls_f51-modified <> 'S'.
            ls_f51-low      = ls_uo-varbl.
            ls_f51-high     = space.
            ls_f51-modified = 'S'.
            ls_f51-neu      = 'O'.
            lv_mod51        = abap_true.
            INSERT VALUE ty_obj_auth_key( object = ls_f51-object auth = ls_f51-auth )
              INTO TABLE lt_healed_auths.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.
    APPEND ls_f51 TO lt_clean.
  ENDLOOP.
  lt_pt1251 = lt_clean.

  " Normalize ONLY 'M' (Changed) headers that were actually healed; NEVER touch unrelated 'M' or 'U'
  IF lt_healed_auths IS NOT INITIAL.
    LOOP AT lt_pt1250 ASSIGNING FIELD-SYMBOL(<ls_a50>)
      WHERE deleted = space AND copied <> 'I' AND modified = 'M'.
      IF NOT line_exists( lt_healed_auths[ object = <ls_a50>-object auth = <ls_a50>-auth ] ).
        CONTINUE.
      ENDIF.
      DATA(lv_has_m) = abap_false.
      DATA(lv_has_g) = abap_false.
      LOOP AT lt_pt1251 INTO DATA(ls_chk_f)
        WHERE object = <ls_a50>-object AND auth = <ls_a50>-auth
          AND deleted = space AND copied <> 'I'.
        IF ls_chk_f-modified = 'M'.
          lv_has_m = abap_true.
          EXIT.
        ELSEIF ls_chk_f-modified = 'G'.
          lv_has_g = abap_true.
        ENDIF.
      ENDLOOP.
      IF lv_has_m = abap_false.
        <ls_a50>-modified = COND #( WHEN lv_has_g = abap_true THEN 'G' ELSE 'S' ).
        <ls_a50>-neu      = 'O'.
        lv_mod50          = abap_true.
      ENDIF.
    ENDLOOP.
  ENDIF.

  IF lv_mod51 = abap_true OR lv_mod50 = abap_true.
    CALL FUNCTION 'PRGN_CLEAR_BUFFER'.

    IF lv_mod51 = abap_true.
      CALL FUNCTION 'PRGN_1251_SAVE_FIELD_VALUES'
        EXPORTING
          activity_group = iv_role
        TABLES
          field_values   = lt_pt1251
        EXCEPTIONS
          OTHERS         = 1.
      IF sy-subrc <> 0.
        ev_err = |PRGN_1251_SAVE_FIELD_VALUES failed for '{ iv_role }' (rc={ sy-subrc }).|.
      ENDIF.
    ENDIF.

    IF ev_err IS INITIAL AND lv_mod50 = abap_true.
      CALL FUNCTION 'PRGN_1250_SAVE_AUTH_DATA'
        EXPORTING
          activity_group = iv_role
        TABLES
          auth_data      = lt_pt1250
        EXCEPTIONS
          OTHERS         = 1.
      IF sy-subrc <> 0.
        ev_err = |PRGN_1250_SAVE_AUTH_DATA failed for '{ iv_role }' (rc={ sy-subrc }).|.
      ENDIF.
    ENDIF.

    IF ev_err IS INITIAL.
      CALL FUNCTION 'PRGN_UPDATE_DATABASE'
        EXCEPTIONS
          OTHERS = 1.
      IF sy-subrc <> 0.
        ev_err = |PRGN_UPDATE_DATABASE failed during $VARBL repair for '{ iv_role }' (rc={ sy-subrc }).|.
      ENDIF.
    ENDIF.

    IF ev_err IS INITIAL.
      CALL FUNCTION 'PRGN_SET_ACTGROUP_TIMESTAMP'
        EXPORTING
          activity_group = iv_role
          no_commit      = 'X'
        EXCEPTIONS
          OTHERS         = 0.
      COMMIT WORK AND WAIT.
    ELSE.
      ROLLBACK WORK.
      CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
    ENDIF.
  ENDIF.

  IF iv_already_enq = abap_false.
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
      EXPORTING
        activity_group = iv_role
      EXCEPTIONS
        OTHERS         = 0.
  ENDIF.
ENDFORM.

*----------------------------------------------------------------------*
* 6. ALV EVENT HANDLER DEFINITION & IMPLEMENTATION
*----------------------------------------------------------------------*
CLASS lcl_alv_event_handler DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS on_link_click FOR EVENT link_click OF cl_salv_events_table
      IMPORTING row column.
ENDCLASS.

CLASS lcl_alv_event_handler IMPLEMENTATION.
  METHOD on_link_click.
    READ TABLE gt_results INTO DATA(ls_row) INDEX row.
    IF sy-subrc = 0.
      TRY.
          IF column = 'DERIVED_ROLE' AND ls_row-derived_role IS NOT INITIAL.
            SET PARAMETER ID 'AGR' FIELD ls_row-derived_role.
            CALL TRANSACTION 'PFCG' WITH AUTHORITY-CHECK AND SKIP FIRST SCREEN.
          ELSEIF column = 'MASTER_ROLE' AND ls_row-master_role IS NOT INITIAL.
            SET PARAMETER ID 'AGR' FIELD ls_row-master_role.
            CALL TRANSACTION 'PFCG' WITH AUTHORITY-CHECK AND SKIP FIRST SCREEN.
          ENDIF.
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
    MESSAGE 'No derived roles were processed.' TYPE 'S' DISPLAY LIKE 'W'.
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

      " Format Column: STATUS
      lo_col ?= lo_cols->get_column( 'STATUS' ).
      lo_col->set_short_text( 'Status' ).
      lo_col->set_medium_text( 'Status' ).
      lo_col->set_long_text( 'Status' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " Format Column: ACTION
      lo_col ?= lo_cols->get_column( 'ACTION' ).
      lo_col->set_short_text( 'Action' ).
      lo_col->set_medium_text( 'Action' ).
      lo_col->set_long_text( 'Execution Action' ).

      " Format Column: DERIVED_ROLE (Hotspot to PFCG)
      lo_col ?= lo_cols->get_column( 'DERIVED_ROLE' ).
      lo_col->set_short_text( 'Derived' ).
      lo_col->set_medium_text( 'Derived Role' ).
      lo_col->set_long_text( 'Derived Role Name' ).
      lo_col->set_cell_type( if_salv_c_cell_type=>hotspot ).

      " Format Column: DERIVED_DESC
      lo_col ?= lo_cols->get_column( 'DERIVED_DESC' ).
      lo_col->set_short_text( 'D.Desc' ).
      lo_col->set_medium_text( 'Derived Description' ).
      lo_col->set_long_text( 'Derived Role Description' ).

      " Format Column: MASTER_ROLE (Hotspot to PFCG)
      lo_col ?= lo_cols->get_column( 'MASTER_ROLE' ).
      lo_col->set_short_text( 'Master' ).
      lo_col->set_medium_text( 'Master Role' ).
      lo_col->set_long_text( 'Master Reference Role' ).
      lo_col->set_cell_type( if_salv_c_cell_type=>hotspot ).

      " Format Column: MASTER_DESC
      lo_col ?= lo_cols->get_column( 'MASTER_DESC' ).
      lo_col->set_short_text( 'M.Desc' ).
      lo_col->set_medium_text( 'Master Description' ).
      lo_col->set_long_text( 'Master Role Description' ).

      " Format Column: PROFILE
      lo_col ?= lo_cols->get_column( 'PROFILE' ).
      lo_col->set_short_text( 'Profile' ).
      lo_col->set_medium_text( 'Auth Profile' ).
      lo_col->set_long_text( 'Generated Profile Name' ).

      " Format Column: MESSAGE
      lo_col ?= lo_cols->get_column( 'MESSAGE' ).
      lo_col->set_short_text( 'Message' ).
      lo_col->set_medium_text( 'Execution Log' ).
      lo_col->set_long_text( 'Status Message / Log' ).

      " Set event handler for hotspots
      lo_events = lo_alv->get_event( ).
      SET HANDLER lcl_alv_event_handler=>on_link_click FOR lo_events.

      lo_alv->display( ).

    CATCH cx_root INTO DATA(lx_salv_err).
      DATA(lv_salv_msg) = lx_salv_err->get_text( ).
      MESSAGE |Error displaying ALV: { lv_salv_msg }| TYPE 'E'.
  ENDTRY.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form compensate_restore_child_orgs
*&---------------------------------------------------------------------*
FORM compensate_restore_child_orgs USING    iv_role        TYPE agr_name
                                            iv_already_enq TYPE abap_bool
                                            it_orig_orgs   TYPE ty_t_agr_1252
                                   CHANGING cv_note        TYPE string.
  DATA: lt_pt1252_cmp TYPE STANDARD TABLE OF pt1252,
        lt_pt1252_db  TYPE STANDARD TABLE OF pt1252,
        lt_db_1252    TYPE STANDARD TABLE OF agr_1252,
        lv_err_cmp    TYPE abap_bool.

  CLEAR: cv_note, lt_pt1252_cmp, lt_pt1252_db, lt_db_1252, lv_err_cmp.

  IF it_orig_orgs IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT it_orig_orgs INTO DATA(ls_comp_o).
    APPEND VALUE pt1252(
      varbl = ls_comp_o-varbl
      low   = ls_comp_o-low
      high  = ls_comp_o-high
    ) TO lt_pt1252_cmp.
  ENDLOOP.
  SORT lt_pt1252_cmp BY varbl low high.
  DELETE ADJACENT DUPLICATES FROM lt_pt1252_cmp COMPARING varbl low high.

  SELECT * FROM agr_1252 INTO TABLE @lt_db_1252
    WHERE agr_name = @iv_role
    ORDER BY counter.
  LOOP AT lt_db_1252 INTO DATA(ls_db_o).
    APPEND VALUE pt1252(
      varbl = ls_db_o-varbl
      low   = ls_db_o-low
      high  = ls_db_o-high
    ) TO lt_pt1252_db.
  ENDLOOP.
  SORT lt_pt1252_db BY varbl low high.
  DELETE ADJACENT DUPLICATES FROM lt_pt1252_db COMPARING varbl low high.

  IF lt_pt1252_db = lt_pt1252_cmp.
    RETURN.
  ENDIF.

  IF iv_already_enq = abap_false.
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
      EXPORTING
        activity_group = iv_role
        no_dialog      = 'X'
      EXCEPTIONS
        OTHERS         = 1.
    IF sy-subrc <> 0.
      cv_note = |Compensation failed: could not enqueue '{ iv_role }' to restore original AGR_1252 (rc={ sy-subrc }).|.
      RETURN.
    ENDIF.
  ENDIF.

  CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
  CALL FUNCTION 'PRGN_1252_SAVE_ORG_LEVELS'
    EXPORTING
      activity_group = iv_role
    TABLES
      org_levels     = lt_pt1252_cmp
    EXCEPTIONS
      OTHERS         = 1.
  IF sy-subrc <> 0.
    lv_err_cmp = abap_true.
  ENDIF.

  IF lv_err_cmp = abap_false.
    CALL FUNCTION 'PRGN_UPDATE_DATABASE'
      EXCEPTIONS
        OTHERS = 1.
    IF sy-subrc <> 0.
      lv_err_cmp = abap_true.
    ENDIF.
  ENDIF.

  IF lv_err_cmp = abap_false.
    CALL FUNCTION 'PRGN_SET_ACTGROUP_TIMESTAMP'
      EXPORTING
        activity_group = iv_role
        no_commit      = 'X'
      EXCEPTIONS
        OTHERS         = 0.
    COMMIT WORK AND WAIT.
    cv_note = |Compensated: restored { lines( lt_pt1252_cmp ) } original AGR_1252 org row(s).|.
  ELSE.
    ROLLBACK WORK.
    CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
    cv_note = |CRITICAL: Failed to restore original AGR_1252 org row(s) during rollback compensation.|.
  ENDIF.

  IF iv_already_enq = abap_false.
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
      EXPORTING
        activity_group = iv_role
      EXCEPTIONS
        OTHERS         = 0.
  ENDIF.
ENDFORM.
