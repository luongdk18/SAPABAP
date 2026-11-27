*&---------------------------------------------------------------------*
*& Report Z_ROLE_03A_UPDATE_ORG
*&---------------------------------------------------------------------*
*& Purpose: Batch Update Organizational Levels & Repair $VARBL Bindings
*& Description:
*&   Consolidated PFCG Organizational Level maintenance cockpit with two
*&   execution modes:
*&
*&   Mode 1 - Update Org Levels from CSV (rb_m_csv = 'X'):
*&     Reads a CSV (.csv) file containing Organizational Level values
*&     (Role Name, Org Level Variable, Value-Low, Value-High), updates
*&     AGR_1252 via standard PFCG FMs supporting both Two-Way Sync
*&     (rb_sync) and Append Only (rb_app), optionally defaults unlisted
*&     or empty Org Levels to '*' (p_astnon = 'X') for Green profiles,
*&     heals corrupted/manual $VARBL bindings in AGR_1251/AGR_1250
*&     (p_fix51 = 'X'), auto-heals parent Master Roles (p_parhea = 'X'),
*&     and compiles runtime profiles in dark mode.
*&
*&   Mode 2 - Repair $VARBL Bindings Only (rb_m_fix = 'X'):
*&     Merged from Z_ROLE_03A_UPDATE_ORG_FIX. Accepts direct role ranges
*&     (s_role) and/or an optional CSV role list (p_file col 1). Repairs
*&     Red/Manually Org Level bindings in AGR_1251/AGR_1250 back to
*&     Standard ($VARBL, MODIFIED='S', NEU='O'), ensures AGR_1252
*&     consistency (Master: '-1', Derived empty: '*'), auto-heals parent
*&     Master Roles (p_parhea = 'X'), and regenerates profiles without
*&     altering non-org business authorization fields.
*&
*& File format (CSV .csv for Mode 1):
*&   Col 1: Role Name             (e.g., Z_FI_PERIOD_CONTROL_1000)
*&   Col 2: Org Level Variable    (e.g., $ERKRS or $BUKRS or BUKRS)
*&   Col 3: Org Value-Low         (e.g., 1000, 1000*, *)
*&   Col 4: Org Value-High        (e.g., 2000, optional)
*&
*& Author: Antigravity AI (SAP Basis Engineering)
*& Package: $TMP (Local Object) or Custom Package
*&---------------------------------------------------------------------*
REPORT z_role_03a_update_org.

*----------------------------------------------------------------------*
* 1. TYPES & DATA DEFINITIONS
*----------------------------------------------------------------------*
TYPES: ty_t_pt1250 TYPE STANDARD TABLE OF pt1250,
       ty_t_pt1251 TYPE STANDARD TABLE OF pt1251,
       ty_t_pt1252 TYPE STANDARD TABLE OF pt1252.

TYPES: BEGIN OF ty_raw_row,
         col1 TYPE string,
         col2 TYPE string,
         col3 TYPE string,
         col4 TYPE string,
       END OF ty_raw_row.

TYPES: BEGIN OF ty_role_entry,
         agr_name  TYPE agr_name,
         org_cnt   TYPE i,
         sort_rank TYPE i,
       END OF ty_role_entry.

TYPES: BEGIN OF ty_parent_err,
         parent_agr TYPE agr_name,
         err_msg    TYPE string,
       END OF ty_parent_err.

TYPES: BEGIN OF ty_role_org,
         agr_name TYPE agr_name,
         varbl    TYPE agval,
         val_low  TYPE agval,
         val_high TYPE agval,
       END OF ty_role_org,
       BEGIN OF ty_var_objfld,
         object TYPE xuobject,
         field  TYPE xufield,
         varbl  TYPE agval,
       END OF ty_var_objfld,
       ty_t_var_objfld TYPE SORTED TABLE OF ty_var_objfld WITH UNIQUE KEY varbl object field.

TYPES: BEGIN OF ty_alv_result,
         status        TYPE char12,    " Status Icon: @08@ [OK], @09@ [WARN], @0A@ [ERR]
         action        TYPE char12,    " UPDATED / FIXED / UP-TO-DATE / SIMULATE / ERROR / WARNING
         agr_name      TYPE agr_name,  " Role ID (Hotspot to PFCG)
         role_desc     TYPE agr_title, " Role Description
         parent_agr    TYPE agr_name,  " Parent Master Role (Hotspot to PFCG)
         orgs_file_cnt TYPE i,         " Number of Org Levels in input file
         orgs_upd_cnt  TYPE i,         " Number of Org Levels updated from file
         orgs_rst_cnt  TYPE i,         " Number of Unlisted Org Levels reset to default
         orgs_keep_cnt TYPE i,         " Number of Org Levels kept unchanged
         orgs_skip_cnt TYPE i,         " Number of Org Levels in file skipped (not in role)
         fixed_fields  TYPE i,         " Count of Org fields rebound to $VARBL in AGR_1251
         fixed_auths   TYPE i,         " Count of Auth nodes restored in AGR_1250
         orgs_detail   TYPE string,    " Detail summary of updated/healed Org Levels
         profile       TYPE xuprofile, " Generated Profile Name
         message       TYPE string,    " Status Message / Execution Log
       END OF ty_alv_result.

CONSTANTS: gc_status_ok   TYPE char12 VALUE '@08@ [OK]',
           gc_status_warn TYPE char12 VALUE '@09@ [WARN]',
           gc_status_err  TYPE char12 VALUE '@0A@ [ERR]'.

DATA: gv_agr_sel         TYPE agr_name,
      gt_raw_rows        TYPE STANDARD TABLE OF ty_raw_row,
      gt_roles           TYPE STANDARD TABLE OF ty_role_entry,
      gt_role_orgs       TYPE SORTED TABLE OF ty_role_org
                           WITH NON-UNIQUE KEY agr_name varbl,
      gt_results         TYPE STANDARD TABLE OF ty_alv_result,
      gt_usorg_map       TYPE SORTED TABLE OF usorg
                           WITH NON-UNIQUE KEY field
                           WITH NON-UNIQUE SORTED KEY by_varbl COMPONENTS varbl,
      gt_checked_parents TYPE HASHED TABLE OF agr_name WITH UNIQUE KEY table_line,
      gt_healed_parents  TYPE HASHED TABLE OF agr_name WITH UNIQUE KEY table_line,
      gt_parent_errors   TYPE HASHED TABLE OF ty_parent_err WITH UNIQUE KEY parent_agr,
      gt_oversized_roles TYPE STANDARD TABLE OF string.

*----------------------------------------------------------------------*
* 2. SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b_mode WITH FRAME TITLE b_tit0.
  PARAMETERS: rb_m_csv RADIOBUTTON GROUP rrun DEFAULT 'X' USER-COMMAND ucmd,
              rb_m_fix RADIOBUTTON GROUP rrun.
SELECTION-SCREEN END OF BLOCK b_mode.

SELECTION-SCREEN BEGIN OF BLOCK b_file WITH FRAME TITLE b_tit1.
  PARAMETERS: p_file TYPE localfile.
  SELECT-OPTIONS: s_role FOR gv_agr_sel.
SELECTION-SCREEN END OF BLOCK b_file.

SELECTION-SCREEN BEGIN OF BLOCK b_opt WITH FRAME TITLE b_tit2.
  PARAMETERS: rb_sync  RADIOBUTTON GROUP rmod DEFAULT 'X',
              rb_app   RADIOBUTTON GROUP rmod.
  SELECTION-SCREEN ULINE.
  PARAMETERS: p_test   TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_genprf TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_astnon TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_fix51  TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_parhea TYPE abap_bool AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b_opt.

*----------------------------------------------------------------------*
* 3. INITIALIZATION & SCREEN EVENTS
*----------------------------------------------------------------------*
INITIALIZATION.
  b_tit0 = 'Execution Mode'(b00).
  b_tit1 = 'Input Source (CSV File / Role Selection)'(b01).
  b_tit2 = 'Update, Healing & Profile Options'(b02).

  %_rb_m_csv_%_app_%-text = 'Update Org Levels from CSV'.
  %_rb_m_fix_%_app_%-text = 'Repair $VARBL Bindings Only'.
  %_p_file_%_app_%-text   = 'CSV File Path'.
  %_s_role_%_app_%-text   = 'Target Role(s) (Repair Mode)'.
  %_rb_sync_%_app_%-text  = 'Two-Way Sync (Replace & Reset)'.
  %_rb_app_%_app_%-text   = 'Append Only (Keep Existing)'.
  %_p_test_%_app_%-text   = 'Simulation (Test Run)'.
  %_p_genprf_%_app_%-text = 'Regenerate Auth Profiles'.
  %_p_astnon_%_app_%-text = 'Default Unlisted Orgs to *'.
  %_p_fix51_%_app_%-text  = 'Restore Variables in AGR_1251'.
  %_p_parhea_%_app_%-text = 'Auto-Heal Parent Master Role'.

AT SELECTION-SCREEN OUTPUT.
  LOOP AT SCREEN.
    IF rb_m_csv = abap_true.
      IF screen-name CS 'S_ROLE'.
        screen-input = '0'.
      ENDIF.
    ELSE.
      IF screen-name = 'RB_SYNC' OR screen-name = 'RB_APP'
         OR screen-name = 'P_FIX51'.
        screen-input = '0'.
      ENDIF.
    ENDIF.
    MODIFY SCREEN.
  ENDLOOP.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  PERFORM f4_file_open CHANGING p_file.

AT SELECTION-SCREEN.
  IF sy-ucomm <> 'ONLI' AND sy-ucomm <> 'PRIN' AND sy-ucomm <> 'SJOB' AND sy-batch IS INITIAL.
    RETURN.
  ENDIF.
  IF rb_m_csv = abap_true.
    IF p_file IS INITIAL.
      MESSAGE 'Please specify an Org Levels CSV file path.' TYPE 'E'.
    ENDIF.
    PERFORM validate_filename USING p_file abap_true.
  ELSE.
    IF s_role[] IS INITIAL AND p_file IS INITIAL.
      MESSAGE 'Specify at least one Role (s_role) or a CSV file for Repair mode.' TYPE 'E'.
    ENDIF.
    IF p_file IS NOT INITIAL.
      PERFORM validate_filename USING p_file abap_false.
    ENDIF.
  ENDIF.

*----------------------------------------------------------------------*
* 4. START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.
  PERFORM check_authority_global.
  PERFORM load_usorg_mapping.
  IF rb_m_csv = abap_true.
    PERFORM upload_and_parse_file.
    PERFORM aggregate_input_data.
    PERFORM process_org_update.
  ELSE.
    PERFORM collect_repair_roles.
    PERFORM process_repair_only.
  ENDIF.
  PERFORM display_alv_results.

*&---------------------------------------------------------------------*
*& Form load_usorg_mapping
*&---------------------------------------------------------------------*
FORM load_usorg_mapping.
  CLEAR: gt_usorg_map, gt_checked_parents, gt_healed_parents, gt_parent_errors.
  SELECT * FROM usorg INTO TABLE @gt_usorg_map.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form f4_file_open
*&---------------------------------------------------------------------*
FORM f4_file_open CHANGING cv_file TYPE localfile.
  DATA: lt_file_table TYPE filetable,
        lv_rc         TYPE i.

  cl_gui_frontend_services=>file_open_dialog(
    EXPORTING
      window_title            = 'Select Role Org Levels CSV File'
      file_filter             = 'Role Org Levels CSV (*03a_Org*.csv)|*03a_Org*.csv|CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'
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
FORM validate_filename USING iv_file        TYPE localfile
                             iv_strict_org  TYPE abap_bool.
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
    MESSAGE |Invalid file '{ lv_fname }'. Expected CSV file (*.csv).| TYPE 'E'.
  ENDIF.

  IF iv_strict_org = abap_true.
    IF NOT ( lv_up CS '03A_ORG' OR lv_up CS 'ORG_LEVEL' OR lv_up CS '_ORG' )
       OR lv_up CS '01_MASTER' OR lv_up CS '02_DERIVE' OR lv_up CS '03B_AUTH'
       OR lv_up CS '03B_OBJECT' OR lv_up CS '03C_ACTIVITY' OR lv_up CS '04_COMPOSITE'
       OR lv_up CS '01_CREATE' OR lv_up CS '02_ASSIGN' OR lv_up = 'ORG_LEVELS.CSV'.
      MESSAGE |Invalid file '{ lv_fname }' for Org Update mode. Expected '*_03a_Org_Levels_converted.csv'.| TYPE 'E'.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form check_authority_global
*&---------------------------------------------------------------------*
FORM check_authority_global.
  DATA(lv_actvt) = COND activ_auth( WHEN p_test = abap_true THEN '03' ELSE '02' ).

  AUTHORITY-CHECK OBJECT 'S_USER_AGR'
    ID 'ACT_GROUP' DUMMY
    ID 'ACTVT'     FIELD lv_actvt.
  IF sy-subrc <> 0.
    MESSAGE |No authorization for roles (S_USER_AGR, ACTVT { lv_actvt }).| TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form check_role_authority
*&---------------------------------------------------------------------*
FORM check_role_authority USING    iv_role   TYPE agr_name
                                   iv_test   TYPE abap_bool
                          CHANGING ev_ok     TYPE abap_bool
                                   ev_reason TYPE string.
  DATA(lv_actvt) = COND activ_auth( WHEN iv_test = abap_true THEN '03' ELSE '02' ).
  CLEAR: ev_ok, ev_reason.

  AUTHORITY-CHECK OBJECT 'S_USER_AGR'
    ID 'ACT_GROUP' FIELD iv_role
    ID 'ACTVT'     FIELD lv_actvt.
  IF sy-subrc = 0.
    ev_ok = abap_true.
  ELSE.
    ev_ok     = abap_false.
    ev_reason = |No authorization for role '{ iv_role }' (S_USER_AGR, ACTVT { lv_actvt }).|.
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

  PERFORM read_csv_file USING p_file abap_true.

  IF gt_raw_rows IS INITIAL.
    MESSAGE 'No valid data rows found in input file.' TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form read_csv_file
*&---------------------------------------------------------------------*
FORM read_csv_file USING iv_file       TYPE localfile
                         iv_org_format TYPE abap_bool.
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
  DATA: lv_file_delim TYPE c LENGTH 1 VALUE ',',
        lv_delim_set  TYPE abap_bool VALUE abap_false.

  CLEAR lv_line_idx.
  LOOP AT lt_file_records INTO lv_line.
    lv_line_idx = lv_line_idx + 1.

    " Strip UTF-8 BOM (U+FEFF) on line 1 if present (e.g. Excel UTF-8 CSV)
    IF lv_line_idx = 1 AND lv_line IS NOT INITIAL AND lv_line(1) = lv_utf8_bom.
      SHIFT lv_line LEFT BY 1 PLACES.
    ENDIF.

    " Strip trailing CR if mixed line endings
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
                           CHANGING ls_raw-col1 ls_raw-col2 ls_raw-col3 ls_raw-col4.

    DATA(lv_c1_up) = to_upper( ls_raw-col1 ).
    DATA(lv_c2_up) = to_upper( ls_raw-col2 ).

    IF iv_org_format = abap_true.
      IF lv_line_idx = 1.
        IF lv_c2_up = 'OBJECT-FIELD' OR lv_c2_up = 'OBJECT_FIELD'
           OR lv_c2_up = 'FIELD' OR lv_c2_up = 'ACTIVITY'
           OR lv_c2_up = 'ROLE DESCRIPTION' OR lv_c2_up = 'DERIVED ROLE'
           OR lv_c2_up = 'DERIVED ROLE DESCRIPTION' OR lv_c2_up = 'COMPOSITE ROLE DESCRIPTION'
           OR lv_c1_up = 'MASTER ROLE' OR lv_c1_up = 'MASTER_ROLE'
           OR lv_c1_up = 'COMPOSITE ROLE' OR lv_c1_up = 'COMPOSITE ROLE NAME'
           OR lv_c1_up = 'USERNAME' OR lv_c1_up = 'USER NAME'.
          MESSAGE 'Invalid CSV header for Org Update mode. Expected: Role, Org_Level, value-low, value-high.' TYPE 'E'.
        ENDIF.
        IF ( lv_c1_up = 'ROLE' OR lv_c1_up = 'ROLE NAME' OR lv_c1_up = 'ROLE_NAME' )
           AND ( lv_c2_up CS 'ORG' OR lv_c2_up CS 'VAR' ).
          CONTINUE.
        ENDIF.
      ENDIF.
      IF lv_c1_up = 'ROLE NAME' OR lv_c1_up = 'ROLE_NAME' OR lv_c1_up = 'ROLE'
         OR lv_c2_up = 'ORG LEVEL VARIABLE' OR lv_c2_up = 'ORG_LEVEL_VARIABLE'
         OR lv_c2_up = 'ORG_LEVEL' OR lv_c2_up = 'VARIABLE'.
        CONTINUE.
      ENDIF.
      IF ls_raw-col1 IS NOT INITIAL AND ls_raw-col2 IS NOT INITIAL.
        APPEND ls_raw TO gt_raw_rows.
      ENDIF.
    ELSE.
      " Repair mode: only column 1 (Role Name) is needed
      IF lv_c1_up = 'ROLE' OR lv_c1_up = 'ROLE NAME' OR lv_c1_up = 'ROLE_NAME'
         OR lv_c1_up = 'AGR_NAME' OR lv_c1_up = 'DERIVED ROLE' OR lv_c1_up = 'MASTER ROLE'.
        CONTINUE.
      ENDIF.
      IF ls_raw-col1 IS NOT INITIAL.
        APPEND ls_raw TO gt_raw_rows.
      ENDIF.
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
                             ev_col3  TYPE string
                             ev_col4  TYPE string.
  DATA: lt_tokens TYPE STANDARD TABLE OF string,
        lv_len    TYPE i,
        lv_in_q   TYPE abap_bool VALUE abap_false,
        lv_cur    TYPE string,
        lv_char   TYPE string,
        lv_next   TYPE string,
        lv_idx    TYPE i,
        lv_delim  TYPE c LENGTH 1.

  CLEAR: ev_col1, ev_col2, ev_col3, ev_col4.

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
        " Handle RFC 4180 escaped double quote ("")
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
    ev_col1 = to_upper( condense( lt_tokens[ 1 ] ) ).
  ENDIF.
  IF lines( lt_tokens ) >= 2.
    ev_col2 = to_upper( condense( lt_tokens[ 2 ] ) ).
  ENDIF.
  IF lines( lt_tokens ) >= 3.
    DATA(lv_trim_col3) = condense( lt_tokens[ 3 ] ).
    IF lv_trim_col3 = ''' ''' OR lv_trim_col3 = '''  '''.
      ev_col3 = ''' '''.
    ELSE.
      ev_col3 = lv_trim_col3.
    ENDIF.
  ENDIF.
  IF lines( lt_tokens ) >= 4.
    ev_col4 = condense( lt_tokens[ 4 ] ).
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form aggregate_input_data
*&---------------------------------------------------------------------*
FORM aggregate_input_data.
  DATA: lv_role_raw TYPE string,
        lv_role     TYPE agr_name,
        lv_var      TYPE agval,
        lv_low_str  TYPE string,
        lv_high_str TYPE string,
        lv_low      TYPE agval,
        lv_high     TYPE agval,
        lv_alpha_10 TYPE c LENGTH 10,
        ls_role_ent TYPE ty_role_entry.

  CLEAR: gt_roles, gt_role_orgs, gt_oversized_roles.

  LOOP AT gt_raw_rows INTO DATA(ls_raw).
    lv_role_raw = to_upper( condense( ls_raw-col1 ) ).
    IF lv_role_raw IS INITIAL.
      CONTINUE.
    ENDIF.

    " Guard against silent >30-char truncation
    IF strlen( lv_role_raw ) > 30.
      READ TABLE gt_oversized_roles WITH KEY table_line = lv_role_raw TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND lv_role_raw TO gt_oversized_roles.
      ENDIF.
      CONTINUE.
    ENDIF.

    lv_role     = lv_role_raw.
    lv_var      = to_upper( condense( ls_raw-col2 ) ).
    lv_low_str  = condense( ls_raw-col3 ).
    lv_high_str = condense( ls_raw-col4 ).

    IF lv_var IS INITIAL.
      CONTINUE.
    ENDIF.

    " Ensure Org Variable has leading '$' (e.g. BUKRS -> $BUKRS)
    IF lv_var(1) NE '$'.
      lv_var = '$' && lv_var.
    ENDIF.

    " Preserve valid empty/space value ' ' or strip Excel formula wrapping
    IF lv_low_str = ''' ''' OR lv_low_str = '''  ''' OR lv_low_str = '''   '''.
      lv_low_str = ''' '''.
    ELSEIF lv_low_str CP '="*"' OR lv_low_str CP '=*'.
      REPLACE FIRST OCCURRENCE OF '="' IN lv_low_str WITH ''.
      REPLACE FIRST OCCURRENCE OF '=' IN lv_low_str WITH ''.
      REPLACE ALL OCCURRENCES OF '"' IN lv_low_str WITH ''.
      lv_low_str = condense( lv_low_str ).
    ENDIF.

    IF lv_high_str = ''' ''' OR lv_high_str = '''  ''' OR lv_high_str = '''   '''.
      lv_high_str = ''' '''.
    ELSEIF lv_high_str CP '="*"' OR lv_high_str CP '=*'.
      REPLACE FIRST OCCURRENCE OF '="' IN lv_high_str WITH ''.
      REPLACE FIRST OCCURRENCE OF '=' IN lv_high_str WITH ''.
      REPLACE ALL OCCURRENCES OF '"' IN lv_high_str WITH ''.
      lv_high_str = condense( lv_high_str ).
    ENDIF.

    " Backwards-compatible range parsing when col4 is empty
    IF lv_high_str IS INITIAL.
      IF lv_low_str CS ' - '.
        SPLIT lv_low_str AT ' - ' INTO lv_low_str lv_high_str.
        lv_low_str  = condense( lv_low_str ).
        lv_high_str = condense( lv_high_str ).
      ELSEIF lv_low_str CS ':'.
        SPLIT lv_low_str AT ':' INTO lv_low_str lv_high_str.
        lv_low_str  = condense( lv_low_str ).
        lv_high_str = condense( lv_high_str ).
      ENDIF.
    ENDIF.

    " Skip rows where both low and high values are genuinely blank (avoid overwriting with empty)
    IF lv_low_str IS INITIAL AND lv_high_str IS INITIAL.
      CONTINUE.
    ENDIF.

    " Apply CONVERSION_EXIT_ALPHA_INPUT for $PRCTR and $KOSTL on condensed string (<=10 pure digits)
    IF lv_var = '$PRCTR' OR lv_var = '$KOSTL'.
      IF lv_low_str IS NOT INITIAL AND strlen( lv_low_str ) <= 10 AND lv_low_str CO '0123456789'.
        lv_alpha_10 = lv_low_str.
        CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
          EXPORTING
            input  = lv_alpha_10
          IMPORTING
            output = lv_alpha_10.
        lv_low_str = lv_alpha_10.
      ENDIF.
      IF lv_high_str IS NOT INITIAL AND strlen( lv_high_str ) <= 10 AND lv_high_str CO '0123456789'.
        lv_alpha_10 = lv_high_str.
        CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
          EXPORTING
            input  = lv_alpha_10
          IMPORTING
            output = lv_alpha_10.
        lv_high_str = lv_alpha_10.
      ENDIF.
    ENDIF.

    lv_low  = lv_low_str.
    lv_high = lv_high_str.

    " Deduplicate identical (agr_name, varbl, val_low, val_high) CSV entries
    DATA(lv_dup_row) = abap_false.
    LOOP AT gt_role_orgs TRANSPORTING NO FIELDS
      WHERE agr_name = lv_role AND varbl = lv_var
        AND val_low  = lv_low  AND val_high = lv_high.
      lv_dup_row = abap_true.
      EXIT.
    ENDLOOP.
    IF lv_dup_row = abap_true.
      CONTINUE.
    ENDIF.

    READ TABLE gt_roles ASSIGNING FIELD-SYMBOL(<ls_r>) WITH KEY agr_name = lv_role.
    IF sy-subrc = 0.
      <ls_r>-org_cnt = <ls_r>-org_cnt + 1.
    ELSE.
      CLEAR ls_role_ent.
      ls_role_ent-agr_name = lv_role.
      ls_role_ent-org_cnt  = 1.
      APPEND ls_role_ent TO gt_roles.
    ENDIF.

    INSERT VALUE ty_role_org(
      agr_name = lv_role
      varbl    = lv_var
      val_low  = lv_low
      val_high = lv_high
    ) INTO TABLE gt_role_orgs.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form collect_repair_roles
*&---------------------------------------------------------------------*
FORM collect_repair_roles.
  DATA: lt_db_roles TYPE STANDARD TABLE OF agr_name,
        lv_role_raw TYPE string,
        lv_role     TYPE agr_name.

  CLEAR: gt_roles, gt_raw_rows, gt_oversized_roles.

  IF s_role[] IS NOT INITIAL.
    SELECT agr_name FROM agr_define
      INTO TABLE @lt_db_roles
      WHERE agr_name IN @s_role.
    LOOP AT lt_db_roles INTO lv_role.
      READ TABLE gt_roles WITH KEY agr_name = lv_role TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND VALUE ty_role_entry( agr_name = lv_role org_cnt = 0 ) TO gt_roles.
      ENDIF.
    ENDLOOP.
  ENDIF.

  IF p_file IS NOT INITIAL.
    PERFORM read_csv_file USING p_file abap_false.
    LOOP AT gt_raw_rows INTO DATA(ls_raw).
      lv_role_raw = to_upper( condense( ls_raw-col1 ) ).
      IF lv_role_raw IS INITIAL.
        CONTINUE.
      ENDIF.
      IF strlen( lv_role_raw ) > 30.
        READ TABLE gt_oversized_roles WITH KEY table_line = lv_role_raw TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          APPEND lv_role_raw TO gt_oversized_roles.
        ENDIF.
        CONTINUE.
      ENDIF.
      lv_role = lv_role_raw.
      READ TABLE gt_roles WITH KEY agr_name = lv_role TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND VALUE ty_role_entry( agr_name = lv_role org_cnt = 0 ) TO gt_roles.
      ENDIF.
    ENDLOOP.
  ENDIF.

  IF gt_roles IS INITIAL AND gt_oversized_roles IS INITIAL.
    MESSAGE 'No matching roles found to repair.' TYPE 'S' DISPLAY LIKE 'W'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form process_org_update (Mode 1: CSV Org Update - Sync / Append)
*&---------------------------------------------------------------------*
FORM process_org_update.
  DATA: ls_res          TYPE ty_alv_result,
        lt_curr_1252    TYPE STANDARD TABLE OF agr_1252,
        lt_parent_1252  TYPE STANDARD TABLE OF agr_1252,
        lt_auth_vars    TYPE STANDARD TABLE OF agval,
        lt_all_vars     TYPE STANDARD TABLE OF agval,
        lt_pt1252       TYPE STANDARD TABLE OF pt1252,
        lt_pt1251_fix   TYPE STANDARD TABLE OF pt1251,
        lt_pt1250_fix   TYPE STANDARD TABLE OF pt1250,
        lt_bapiret      TYPE STANDARD TABLE OF bapiret2,
        lv_agr_chk      TYPE agr_name,
        lv_parent_chk   TYPE agr_name,
        lv_auth_ok      TYPE abap_bool,
        lv_auth_msg     TYPE string,
        lv_fix_1251     TYPE abap_bool,
        lv_fix_1250     TYPE abap_bool,
        lv_fixed_flds   TYPE i,
        lv_fixed_auths  TYPE i,
        lv_heal_det     TYPE string,
        lv_par_healed   TYPE abap_bool,
        lv_par_err      TYPE string,
        lv_skip_cnt     TYPE i,
        lv_file_upd_cnt TYPE i,
        lv_rst_cnt      TYPE i,
        lv_keep_cnt     TYPE i,
        lv_any_1252_chg TYPE abap_bool,
        lv_detail       TYPE string,
        lv_enq_ok       TYPE abap_bool,
        lv_save_err     TYPE string,
        lv_gen_subrc    TYPE sy-subrc,
        lv_gen_err      TYPE string,
        lv_chk_color    TYPE char10,
        lv_chk_msg      TYPE c LENGTH 255.

  CLEAR gt_results.

  " Process Master Roles (parent_agr IS INITIAL) before Derived Roles
  PERFORM sort_roles_master_first.

  " Report any oversized (>30 char) CSV role names explicitly
  LOOP AT gt_oversized_roles INTO DATA(lv_bad_role).
    CLEAR ls_res.
    ls_res-status  = gc_status_err.
    ls_res-action  = 'ERROR'.
    ls_res-agr_name = lv_bad_role.
    ls_res-message = |Role name exceeds SAP 30-character limit: '{ lv_bad_role }'.|.
    APPEND ls_res TO gt_results.
  ENDLOOP.

  LOOP AT gt_roles INTO DATA(ls_role).
    DATA: lv_heal_read_err TYPE string,
          lv_widened_vars  TYPE string.
    CLEAR: ls_res, lt_curr_1252, lt_parent_1252, lt_auth_vars, lt_all_vars,
           lt_pt1252, lt_pt1251_fix, lt_pt1250_fix, lt_bapiret,
           lv_agr_chk, lv_parent_chk, lv_auth_ok, lv_auth_msg,
           lv_fix_1251, lv_fix_1250, lv_fixed_flds, lv_fixed_auths, lv_heal_det,
           lv_par_healed, lv_par_err, lv_skip_cnt, lv_file_upd_cnt,
           lv_rst_cnt, lv_keep_cnt, lv_any_1252_chg, lv_detail,
           lv_enq_ok, lv_save_err, lv_gen_subrc, lv_gen_err, lv_chk_color, lv_chk_msg,
           lv_heal_read_err, lv_widened_vars.

    ls_res-agr_name      = ls_role-agr_name.
    ls_res-orgs_file_cnt = ls_role-org_cnt.

    " 1. Per-role Authority Check
    PERFORM check_role_authority USING ls_role-agr_name p_test
                                 CHANGING lv_auth_ok lv_auth_msg.
    IF lv_auth_ok = abap_false.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = lv_auth_msg.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " 2. Validate Role in SAP
    SELECT SINGLE agr_name, parent_agr FROM agr_define
      INTO ( @lv_agr_chk, @lv_parent_chk )
      WHERE agr_name = @ls_role-agr_name.
    IF sy-subrc <> 0 OR lv_agr_chk IS INITIAL.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = |Role '{ ls_role-agr_name }' does not exist in SAP.|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    DATA(lv_coll_flag) = VALUE agr_flags-flag_value( ).
    SELECT SINGLE flag_value FROM agr_flags INTO @lv_coll_flag
      WHERE agr_name = @ls_role-agr_name AND flag_type = 'COLL_AGR'.
    IF sy-subrc = 0 AND lv_coll_flag = 'X'.
      ls_res-status  = gc_status_warn.
      ls_res-action  = 'COMPOSITE'.
      ls_res-message = |Role '{ ls_role-agr_name }' is a Composite Role (no Org Levels). Skipped.|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    ls_res-parent_agr = lv_parent_chk.

    SELECT SINGLE text FROM agr_texts INTO @ls_res-role_desc
      WHERE agr_name = @ls_role-agr_name AND spras = @sy-langu AND line = '00000'.
    IF sy-subrc <> 0.
      SELECT SINGLE text FROM agr_texts INTO @ls_res-role_desc
        WHERE agr_name = @ls_role-agr_name AND line = '00000'.
    ENDIF.

    " 3. Optional Auto-Heal Parent Master Role (once per parent BEFORE enqueuing child role)
    IF p_fix51 = abap_true AND p_parhea = abap_true AND lv_parent_chk IS NOT INITIAL.
      IF NOT line_exists( gt_checked_parents[ table_line = lv_parent_chk ] ).
        INSERT lv_parent_chk INTO TABLE gt_checked_parents.
        PERFORM heal_parent_master_role USING    lv_parent_chk
                                                 p_test
                                                 p_genprf
                                        CHANGING lv_par_healed
                                                 lv_par_err.
        IF lv_par_healed = abap_true.
          INSERT lv_parent_chk INTO TABLE gt_healed_parents.
        ENDIF.
        IF lv_par_err IS NOT INITIAL.
          INSERT VALUE ty_parent_err( parent_agr = lv_parent_chk err_msg = lv_par_err )
            INTO TABLE gt_parent_errors.
        ENDIF.
      ELSE.
        READ TABLE gt_parent_errors INTO DATA(ls_cached_pe)
          WITH TABLE KEY parent_agr = lv_parent_chk.
        IF sy-subrc = 0.
          lv_par_err = ls_cached_pe-err_msg.
        ENDIF.
      ENDIF.
    ENDIF.

    " TOCTOU Prevention (03A-3): Enqueue role BEFORE reading AGR_1250/1251/1252 in Real Execution
    DATA(lv_enq_held) = abap_false.
    IF p_test = abap_false.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
        EXPORTING
          activity_group          = ls_role-agr_name
          no_dialog               = 'X'
        EXCEPTIONS
          foreign_lock            = 1
          transport_check_problem = 2
          OTHERS                  = 3.
      IF sy-subrc <> 0.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'ERROR'.
        ls_res-message = |Role '{ ls_role-agr_name }' is locked or cannot be enqueued (sy-subrc = { sy-subrc }).|.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.
      lv_enq_held = abap_true.
    ENDIF.

    " 4. Analyze / Heal Org Variable Bindings in Memory (AGR_1251 / AGR_1250)
    DATA lt_newly_bound1 TYPE ty_t_var_objfld.
    CLEAR lt_newly_bound1.
    IF p_fix51 = abap_true.
      PERFORM analyze_and_heal_1251_1250 USING    ls_role-agr_name
                                         CHANGING lt_pt1251_fix
                                                  lt_pt1250_fix
                                                  lv_fix_1251
                                                  lv_fix_1250
                                                  lv_fixed_flds
                                                  lv_fixed_auths
                                                  lv_heal_det
                                                  lv_heal_read_err
                                                  lt_newly_bound1.
      IF lv_heal_read_err IS NOT INITIAL.
        IF lv_enq_held = abap_true.
          CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
            EXPORTING
              activity_group = ls_role-agr_name
            EXCEPTIONS
              OTHERS         = 0.
        ENDIF.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'ERROR'.
        ls_res-message = lv_heal_read_err.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.
      ls_res-fixed_fields = lv_fixed_flds.
      ls_res-fixed_auths  = lv_fixed_auths.
    ENDIF.

    " 5. Read Current Role & Parent Org Levels (AGR_1252) and Active Auth Variables
    SELECT * FROM agr_1252 INTO TABLE @lt_curr_1252
      WHERE agr_name = @ls_role-agr_name
      ORDER BY counter.

    IF lv_parent_chk IS NOT INITIAL.
      SELECT * FROM agr_1252 INTO TABLE @lt_parent_1252
        WHERE agr_name = @lv_parent_chk
        ORDER BY counter.
    ENDIF.

    " Collect ONLY $VARBLs from ACTIVE AGR_1250 headers + build active (object, field, varbl) catalog
    DATA lt_var_objflds TYPE ty_t_var_objfld.
    CLEAR lt_var_objflds.
    IF p_fix51 = abap_true AND lt_pt1251_fix IS NOT INITIAL.
      TYPES: BEGIN OF ty_act_k1,
               object TYPE xuobject,
               auth   TYPE xuauth,
             END OF ty_act_k1.
      DATA lt_act_k1 TYPE HASHED TABLE OF ty_act_k1 WITH UNIQUE KEY object auth.
      CLEAR lt_act_k1.
      LOOP AT lt_pt1250_fix INTO DATA(ls_h1) WHERE deleted = space AND copied <> 'I'.
        INSERT VALUE ty_act_k1( object = ls_h1-object auth = ls_h1-auth ) INTO TABLE lt_act_k1.
      ENDLOOP.
      LOOP AT lt_pt1251_fix INTO DATA(ls_mem_51)
        WHERE deleted = space AND copied <> 'I'.
        IF NOT line_exists( lt_act_k1[ object = ls_mem_51-object auth = ls_mem_51-auth ] ).
          CONTINUE.
        ENDIF.
        READ TABLE gt_usorg_map INTO DATA(ls_uo_m1) WITH TABLE KEY field = ls_mem_51-field.
        IF sy-subrc = 0 AND ls_uo_m1-varbl IS NOT INITIAL.
          INSERT VALUE ty_var_objfld(
            object = ls_mem_51-object field = ls_mem_51-field varbl = ls_uo_m1-varbl )
            INTO TABLE lt_var_objflds.
          IF ls_mem_51-low = ls_uo_m1-varbl AND ls_mem_51-high IS INITIAL.
            APPEND ls_mem_51-low TO lt_auth_vars.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ELSE.
      SELECT DISTINCT f~object, f~field, u~varbl, f~low, f~high
        FROM agr_1251 AS f
        INNER JOIN agr_1250 AS h
          ON  h~agr_name = f~agr_name
          AND h~object   = f~object
          AND h~auth     = f~auth
        INNER JOIN usorg AS u
          ON u~field = f~field
        INTO TABLE @DATA(lt_db_org_refs1)
        WHERE f~agr_name = @ls_role-agr_name
          AND f~deleted  = @space AND f~copied <> 'I'
          AND h~deleted  = @space AND h~copied <> 'I'.
      LOOP AT lt_db_org_refs1 INTO DATA(ls_dr1).
        INSERT VALUE ty_var_objfld(
          object = ls_dr1-object field = ls_dr1-field varbl = ls_dr1-varbl )
          INTO TABLE lt_var_objflds.
        IF ls_dr1-low = ls_dr1-varbl AND ls_dr1-high IS INITIAL.
          APPEND ls_dr1-low TO lt_auth_vars.
        ENDIF.
      ENDLOOP.
    ENDIF.
    IF lv_parent_chk IS NOT INITIAL.
      SELECT DISTINCT f~object, f~field, u~varbl, f~low, f~high
        FROM agr_1251 AS f
        INNER JOIN agr_1250 AS h
          ON  h~agr_name = f~agr_name
          AND h~object   = f~object
          AND h~auth     = f~auth
        INNER JOIN usorg AS u
          ON u~field = f~field
        INTO TABLE @DATA(lt_db_par_refs1)
        WHERE f~agr_name = @lv_parent_chk
          AND f~deleted  = @space AND f~copied <> 'I'
          AND h~deleted  = @space AND h~copied <> 'I'.
      LOOP AT lt_db_par_refs1 INTO DATA(ls_dpr1).
        INSERT VALUE ty_var_objfld(
          object = ls_dpr1-object field = ls_dpr1-field varbl = ls_dpr1-varbl )
          INTO TABLE lt_var_objflds.
        IF ls_dpr1-low = ls_dpr1-varbl AND ls_dpr1-high IS INITIAL.
          APPEND ls_dpr1-low TO lt_auth_vars.
        ENDIF.
      ENDLOOP.
    ENDIF.
    SORT lt_auth_vars.
    DELETE ADJACENT DUPLICATES FROM lt_auth_vars.

    " 6. Assemble Full Set of Valid Org Variables Belonging to Role
    LOOP AT lt_curr_1252 INTO DATA(ls_c1252).
      IF line_exists( gt_usorg_map[ KEY by_varbl COMPONENTS varbl = ls_c1252-varbl ] ).
        APPEND ls_c1252-varbl TO lt_all_vars.
      ENDIF.
    ENDLOOP.
    LOOP AT lt_parent_1252 INTO DATA(ls_p1252).
      IF line_exists( gt_usorg_map[ KEY by_varbl COMPONENTS varbl = ls_p1252-varbl ] ).
        APPEND ls_p1252-varbl TO lt_all_vars.
      ENDIF.
    ENDLOOP.
    LOOP AT lt_auth_vars INTO DATA(lv_av).
      IF line_exists( gt_usorg_map[ KEY by_varbl COMPONENTS varbl = lv_av ] ).
        APPEND lv_av TO lt_all_vars.
      ENDIF.
    ENDLOOP.

    SORT lt_all_vars.
    DELETE ADJACENT DUPLICATES FROM lt_all_vars.
    DELETE lt_all_vars WHERE table_line IS INITIAL.

    " Count Org Levels in CSV that do NOT belong to this role
    LOOP AT gt_role_orgs INTO DATA(ls_chk_file) WHERE agr_name = ls_role-agr_name.
      READ TABLE lt_all_vars WITH KEY table_line = ls_chk_file-varbl TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        lv_skip_cnt = lv_skip_cnt + 1.
      ENDIF.
    ENDLOOP.
    ls_res-orgs_skip_cnt = lv_skip_cnt.

    " Role has no Org Levels at all
    IF lt_all_vars IS INITIAL AND lv_fix_1251 = abap_false AND lv_fix_1250 = abap_false.
      IF lv_enq_held = abap_true.
        CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
          EXPORTING
            activity_group = ls_role-agr_name
          EXCEPTIONS
            OTHERS         = 0.
      ENDIF.
      ls_res-status       = COND #( WHEN lv_skip_cnt > 0 THEN gc_status_warn ELSE gc_status_ok ).
      ls_res-action       = 'UP-TO-DATE'.
      ls_res-orgs_upd_cnt = 0.
      IF lv_skip_cnt > 0.
        ls_res-message = |Role contains no Org Levels. { lv_skip_cnt } CSV Org Level(s) skipped (not in role).|.
      ELSE.
        ls_res-message = 'Role contains no Org Levels in authorizations.'.
      ENDIF.
      SELECT SINGLE profile FROM agr_1016 INTO @ls_res-profile
        WHERE agr_name = @ls_role-agr_name.
      PERFORM append_parent_heal_note USING lv_parent_chk p_test lv_par_err CHANGING ls_res-status ls_res-message.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " 7. Build Target Org Levels Table (PT1252) supporting Two-Way Sync vs Append Only
    "    D3 rule: Derived Roles (lv_parent_chk IS NOT INITIAL) default unlisted/empty orgs to '*'
    "    when p_astnon = 'X'; Master/non-derived Roles (lv_parent_chk IS INITIAL) ALWAYS get '-1'!
    DATA(lv_sval_err1) = ``.
    LOOP AT lt_all_vars INTO DATA(lv_varbl).
      DATA: lt_file_orgs   TYPE STANDARD TABLE OF ty_role_org,
            lt_var_target  TYPE STANDARD TABLE OF pt1252,
            lt_curr_maint  TYPE STANDARD TABLE OF agr_1252.
      CLEAR: lt_file_orgs, lt_var_target, lt_curr_maint.

      LOOP AT gt_role_orgs INTO DATA(ls_fo)
        WHERE agr_name = ls_role-agr_name AND varbl = lv_varbl.
        APPEND ls_fo TO lt_file_orgs.
      ENDLOOP.

      LOOP AT lt_curr_1252 INTO DATA(ls_cm)
        WHERE varbl = lv_varbl
          AND ( ( low IS NOT INITIAL AND low <> '$' AND low <> '-1' ) OR high IS NOT INITIAL ).
        APPEND ls_cm TO lt_curr_maint.
      ENDLOOP.

      IF lt_file_orgs IS NOT INITIAL.
        " Variable is present in CSV
        IF rb_app = abap_true AND lt_curr_maint IS NOT INITIAL.
          " Append Mode: preserve existing maintained values first, then append new CSV values
          LOOP AT lt_curr_maint INTO DATA(ls_km).
            READ TABLE lt_var_target WITH KEY low = ls_km-low high = ls_km-high TRANSPORTING NO FIELDS.
            IF sy-subrc <> 0.
              APPEND VALUE pt1252( varbl = lv_varbl low = ls_km-low high = ls_km-high ) TO lt_var_target.
            ENDIF.
          ENDLOOP.
        ENDIF.

        LOOP AT lt_file_orgs INTO DATA(ls_org_in).
          READ TABLE lt_var_target WITH KEY low = ls_org_in-val_low high = ls_org_in-val_high TRANSPORTING NO FIELDS.
          IF sy-subrc <> 0.
            APPEND VALUE pt1252( varbl = lv_varbl low = ls_org_in-val_low high = ls_org_in-val_high ) TO lt_var_target.
          ENDIF.

          DATA(lv_val_disp) = COND string(
            WHEN ls_org_in-val_high IS NOT INITIAL
            THEN |{ ls_org_in-val_low }-{ ls_org_in-val_high }|
            ELSE |{ ls_org_in-val_low }| ).
          IF lv_detail IS INITIAL.
            lv_detail = |{ lv_varbl }={ lv_val_disp }|.
          ELSEIF strlen( lv_detail ) < 200.
            lv_detail = |{ lv_detail }, { lv_varbl }={ lv_val_disp }|.
          ENDIF.
        ENDLOOP.

      ELSEIF rb_sync = abap_true.
        " Two-Way Sync Mode: unlisted Org Level -> '*' ONLY on Derived Roles (D3), '-1' on Master/non-derived
        IF p_astnon = abap_true AND lv_parent_chk IS NOT INITIAL.
          APPEND VALUE pt1252( varbl = lv_varbl low = '*' high = space ) TO lt_var_target.
          IF lt_curr_maint IS NOT INITIAL
             AND NOT ( lines( lt_curr_maint ) = 1 AND lt_curr_maint[ 1 ]-low = '*' AND lt_curr_maint[ 1 ]-high IS INITIAL ).
            lv_widened_vars = COND #( WHEN lv_widened_vars IS INITIAL THEN |{ lv_varbl }|
                                      ELSE |{ lv_widened_vars }, { lv_varbl }| ).
          ENDIF.
        ELSE.
          DATA: lv_has_par_sync TYPE abap_bool.
          CLEAR lv_has_par_sync.
          LOOP AT lt_parent_1252 INTO DATA(ls_ps)
            WHERE varbl = lv_varbl AND low IS NOT INITIAL AND low <> '$'.
            lv_has_par_sync = abap_true.
            APPEND VALUE pt1252( varbl = lv_varbl low = ls_ps-low high = ls_ps-high ) TO lt_var_target.
            IF ls_ps-low = '*' AND lt_curr_maint IS NOT INITIAL
               AND NOT ( lines( lt_curr_maint ) = 1 AND lt_curr_maint[ 1 ]-low = '*' AND lt_curr_maint[ 1 ]-high IS INITIAL ).
              lv_widened_vars = COND #( WHEN lv_widened_vars IS INITIAL THEN |{ lv_varbl }|
                                        ELSE |{ lv_widened_vars }, { lv_varbl }| ).
            ENDIF.
          ENDLOOP.
          IF lv_has_par_sync = abap_false.
            APPEND VALUE pt1252( varbl = lv_varbl low = '-1' high = space ) TO lt_var_target.
          ENDIF.
        ENDIF.

      ELSE.
        " Append Mode: unlisted Org Level -> keep existing maintained values; default empty to '*' on Derived (D3) or '-1'
        IF lt_curr_maint IS NOT INITIAL.
          lv_keep_cnt = lv_keep_cnt + 1.
          LOOP AT lt_curr_maint INTO DATA(ls_ck).
            APPEND VALUE pt1252( varbl = lv_varbl low = ls_ck-low high = ls_ck-high ) TO lt_var_target.
          ENDLOOP.
        ELSEIF p_astnon = abap_true AND lv_parent_chk IS NOT INITIAL.
          APPEND VALUE pt1252( varbl = lv_varbl low = '*' high = space ) TO lt_var_target.
        ELSE.
          DATA: lv_has_par_app TYPE abap_bool.
          CLEAR lv_has_par_app.
          LOOP AT lt_parent_1252 INTO DATA(ls_pa)
            WHERE varbl = lv_varbl AND low IS NOT INITIAL AND low <> '$'.
            lv_has_par_app = abap_true.
            APPEND VALUE pt1252( varbl = lv_varbl low = ls_pa-low high = ls_pa-high ) TO lt_var_target.
          ENDLOOP.
          IF lv_has_par_app = abap_false.
            APPEND VALUE pt1252( varbl = lv_varbl low = '-1' high = space ) TO lt_var_target.
          ENDIF.
        ENDIF.
      ENDIF.

      " Deduplicate target rows for this variable & verify S_USER_VAL for newly added/defaulted values
      SORT lt_var_target BY varbl low high.
      DELETE ADJACENT DUPLICATES FROM lt_var_target COMPARING varbl low high.

      LOOP AT lt_var_target INTO DATA(ls_vt_auth).
        READ TABLE lt_curr_maint WITH KEY low = ls_vt_auth-low high = ls_vt_auth-high
          TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          PERFORM check_org_s_user_val USING ls_vt_auth-varbl
                                             ls_vt_auth-low
                                             ls_vt_auth-high
                                             lt_var_objflds
                                       CHANGING lv_sval_err1.
        ELSEIF line_exists( lt_newly_bound1[ varbl = ls_vt_auth-varbl ] ).
          PERFORM check_org_s_user_val USING ls_vt_auth-varbl
                                             ls_vt_auth-low
                                             ls_vt_auth-high
                                             lt_newly_bound1
                                       CHANGING lv_sval_err1.
        ENDIF.
        IF lv_sval_err1 IS NOT INITIAL.
          EXIT.
        ENDIF.
      ENDLOOP.
      IF lv_sval_err1 IS NOT INITIAL.
        EXIT.
      ENDIF.

      APPEND LINES OF lt_var_target TO lt_pt1252.

      " Symmetric comparison against deduplicated current AGR_1252 rows for this variable
      DATA: lt_curr_chk TYPE STANDARD TABLE OF pt1252.
      CLEAR lt_curr_chk.
      LOOP AT lt_curr_1252 INTO DATA(ls_cc) WHERE varbl = lv_varbl.
        APPEND VALUE pt1252( varbl = ls_cc-varbl low = ls_cc-low high = ls_cc-high ) TO lt_curr_chk.
      ENDLOOP.
      DATA(lv_raw_curr_cnt) = lines( lt_curr_chk ).
      SORT lt_curr_chk BY varbl low high.
      DELETE ADJACENT DUPLICATES FROM lt_curr_chk COMPARING varbl low high.

      DATA(lv_var_changed) = abap_false.
      IF lv_raw_curr_cnt <> lines( lt_var_target ) OR lines( lt_curr_chk ) <> lines( lt_var_target ).
        lv_var_changed = abap_true.
      ELSE.
        LOOP AT lt_var_target INTO DATA(ls_vt).
          READ TABLE lt_curr_chk WITH KEY low = ls_vt-low high = ls_vt-high TRANSPORTING NO FIELDS.
          IF sy-subrc <> 0.
            lv_var_changed = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.
      ENDIF.

      IF lv_var_changed = abap_true.
        lv_any_1252_chg = abap_true.
        IF lt_file_orgs IS NOT INITIAL.
          lv_file_upd_cnt = lv_file_upd_cnt + 1.
        ELSE.
          lv_rst_cnt = lv_rst_cnt + 1.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF lv_sval_err1 IS NOT INITIAL.
      IF lv_enq_held = abap_true.
        CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
          EXPORTING
            activity_group = ls_role-agr_name
          EXCEPTIONS
            OTHERS         = 0.
      ENDIF.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = lv_sval_err1.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    IF lines( lt_curr_1252 ) <> lines( lt_pt1252 ).
      lv_any_1252_chg = abap_true.
    ENDIF.

    ls_res-orgs_upd_cnt  = lv_file_upd_cnt.
    ls_res-orgs_rst_cnt  = lv_rst_cnt.
    ls_res-orgs_keep_cnt = lv_keep_cnt.
    ls_res-orgs_detail   = COND #( WHEN lv_detail IS NOT INITIAL THEN lv_detail ELSE lv_heal_det ).

    DATA(lv_needs_save) = xsdbool( lv_any_1252_chg = abap_true OR lv_fix_1251 = abap_true OR lv_fix_1250 = abap_true ).

    " 8. Simulation Mode
    IF p_test = abap_true.
      SELECT SINGLE profile FROM agr_1016 INTO @ls_res-profile
        WHERE agr_name = @ls_role-agr_name.

      IF lv_needs_save = abap_true.
        ls_res-status = gc_status_ok.
        ls_res-action = 'SIMULATE'.
        IF lv_any_1252_chg = abap_true.
          ls_res-message = |[Simulated] { lv_file_upd_cnt } file Org(s) updated, { lv_rst_cnt } unlisted reset (Total: { lines( lt_pt1252 ) }).|.
        ELSE.
          ls_res-message = |[Simulated] Org Levels in AGR_1252 up-to-date.|.
        ENDIF.
        IF lv_fix_1251 = abap_true OR lv_fix_1250 = abap_true.
          ls_res-message = |{ ls_res-message } Will heal { lv_fixed_flds } field(s) / { lv_fixed_auths } auth(s) to Standard.|.
        ENDIF.
        IF lv_widened_vars IS NOT INITIAL.
          ls_res-status  = gc_status_warn.
          ls_res-message = |{ ls_res-message } Caution: Unlisted restricted org(s) [{ lv_widened_vars }] would reset to '*' (use Append Only to keep existing).|.
        ENDIF.
      ELSE.
        ls_res-status  = gc_status_ok.
        ls_res-action  = 'UP-TO-DATE'.
        ls_res-message = |[Simulated] All { lines( lt_pt1252 ) } Org Level(s) already up-to-date.|.
      ENDIF.
      IF lv_skip_cnt > 0.
        IF ls_res-status = gc_status_ok.
          ls_res-status = gc_status_warn.
        ENDIF.
        ls_res-message = |{ ls_res-message } { lv_skip_cnt } CSV Org Level(s) skipped (not in role).|.
      ENDIF.
      PERFORM append_parent_heal_note USING lv_parent_chk p_test lv_par_err CHANGING ls_res-status ls_res-message.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " 9. Real Execution (Strict Enqueue -> Save -> Timestamp -> Commit -> Dequeue -> GenProfile)
    IF lv_needs_save = abap_true.
      DATA(lv_skip_m_gen) = xsdbool( lv_parent_chk IS INITIAL AND line_exists( lt_pt1252[ low = '-1' ] ) ).
      DATA(lv_eff_genprf) = COND abap_bool( WHEN p_genprf = abap_true AND lv_skip_m_gen = abap_false
                                            THEN abap_true ELSE abap_false ).

      PERFORM save_and_generate_role USING    ls_role-agr_name
                                              lt_pt1251_fix
                                              lt_pt1250_fix
                                              lt_pt1252
                                              lv_fix_1251
                                              lv_fix_1250
                                              lv_any_1252_chg
                                              lv_eff_genprf
                                              lv_enq_held
                                     CHANGING lv_enq_ok
                                              lv_save_err
                                              lv_gen_subrc
                                              lv_gen_err
                                              ls_res-profile
                                              lv_chk_color
                                              lv_chk_msg.

      IF lv_enq_ok = abap_false OR lv_save_err IS NOT INITIAL.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'ERROR'.
        ls_res-message = lv_save_err.
      ELSEIF lv_eff_genprf = abap_true.
        IF lv_chk_color = 'RED'.
          ls_res-status  = gc_status_err.
          ls_res-action  = 'WARNING'.
          ls_res-message = |Maintained { lines( lt_pt1252 ) } Org Level(s). Profile Red: { lv_gen_err } { lv_chk_msg }|.
        ELSEIF lv_gen_subrc <> 0 OR lv_gen_err IS NOT INITIAL.
          ls_res-status  = gc_status_warn.
          ls_res-action  = 'UPDATED'.
          ls_res-message = |Saved { lines( lt_pt1252 ) } Org Level(s). Profile generation issue: { lv_gen_err } { lv_chk_msg }|.
        ELSEIF lv_chk_color = 'GREEN'.
          ls_res-status  = gc_status_ok.
          ls_res-action  = 'UPDATED'.
          ls_res-message = |Maintained { lines( lt_pt1252 ) } Org Level(s) ({ lv_file_upd_cnt } from CSV). Profile '{ ls_res-profile }' is GREEN.|.
        ELSEIF lv_chk_color = 'YELLOW'.
          ls_res-status  = gc_status_warn.
          ls_res-action  = 'UPDATED'.
          ls_res-message = |Maintained { lines( lt_pt1252 ) } Org Level(s). Profile Yellow: { lv_chk_msg }|.
        ELSE.
          ls_res-status  = gc_status_ok.
          ls_res-action  = 'UPDATED'.
          ls_res-message = |Maintained { lines( lt_pt1252 ) } Org Level(s). Profile status: { lv_chk_color } { lv_chk_msg }|.
        ENDIF.
      ELSE.
        ls_res-status  = gc_status_ok.
        ls_res-action  = 'UPDATED'.
        IF lv_skip_m_gen = abap_true AND p_genprf = abap_true.
          ls_res-message = |Maintained { lines( lt_pt1252 ) } Org Level(s) on Master Role (unmaintained '-1' orgs: profile generation skipped).|.
        ELSE.
          ls_res-message = |Maintained { lines( lt_pt1252 ) } Org Level(s) ({ lv_file_upd_cnt } from CSV). Profile regeneration skipped.|.
        ENDIF.
      ENDIF.

      IF lv_enq_ok = abap_true AND lv_save_err IS INITIAL.
        IF lv_fix_1251 = abap_true OR lv_fix_1250 = abap_true.
          ls_res-message = |{ ls_res-message } Healed { lv_fixed_flds } field(s) / { lv_fixed_auths } auth(s) to Standard.|.
        ENDIF.
        IF lv_widened_vars IS NOT INITIAL.
          IF ls_res-status = gc_status_ok.
            ls_res-status = gc_status_warn.
          ENDIF.
          ls_res-message = |{ ls_res-message } WARNING: Unlisted restricted org(s) [{ lv_widened_vars }] widened to '*'.|.
        ENDIF.
        IF lv_skip_cnt > 0 AND ls_res-status = gc_status_ok.
          ls_res-status = gc_status_warn.
        ENDIF.
      ENDIF.
      IF lv_skip_cnt > 0.
        ls_res-message = |{ ls_res-message } { lv_skip_cnt } CSV Org Level(s) skipped (not in role).|.
      ENDIF.
    ELSE.
      IF lv_enq_held = abap_true.
        CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
          EXPORTING
            activity_group = ls_role-agr_name
          EXCEPTIONS
            OTHERS         = 0.
      ENDIF.
      SELECT SINGLE profile FROM agr_1016 INTO @ls_res-profile
        WHERE agr_name = @ls_role-agr_name.
      ls_res-status  = COND #( WHEN lv_skip_cnt > 0 THEN gc_status_warn ELSE gc_status_ok ).
      ls_res-action  = 'UP-TO-DATE'.
      ls_res-message = |All { lines( lt_pt1252 ) } Org Level(s) already up-to-date.|.
      IF lv_skip_cnt > 0.
        ls_res-message = |{ ls_res-message } { lv_skip_cnt } CSV Org Level(s) skipped (not in role).|.
      ENDIF.
    ENDIF.

    PERFORM append_parent_heal_note USING lv_parent_chk p_test lv_par_err CHANGING ls_res-status ls_res-message.
    APPEND ls_res TO gt_results.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form sort_roles_master_first
*&---------------------------------------------------------------------*
FORM sort_roles_master_first.
  IF gt_roles IS INITIAL.
    RETURN.
  ENDIF.

  SELECT agr_name, parent_agr FROM agr_define
    FOR ALL ENTRIES IN @gt_roles
    WHERE agr_name = @gt_roles-agr_name
    INTO TABLE @DATA(lt_def_sort).

  LOOP AT gt_roles ASSIGNING FIELD-SYMBOL(<ls_rs>).
    READ TABLE lt_def_sort INTO DATA(ls_ds) WITH KEY agr_name = <ls_rs>-agr_name.
    IF sy-subrc = 0 AND ls_ds-parent_agr IS INITIAL.
      <ls_rs>-sort_rank = 1.
    ELSE.
      <ls_rs>-sort_rank = 2.
    ENDIF.
  ENDLOOP.
  SORT gt_roles BY sort_rank ASCENDING agr_name ASCENDING.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form process_repair_only (Mode 2: Merged from Z_ROLE_03A_UPDATE_ORG_FIX)
*&---------------------------------------------------------------------*
FORM process_repair_only.
  DATA: ls_res         TYPE ty_alv_result,
        lt_pt1251      TYPE STANDARD TABLE OF pt1251,
        lt_pt1250      TYPE STANDARD TABLE OF pt1250,
        lt_pt1252      TYPE STANDARD TABLE OF pt1252,
        lt_active_vars TYPE STANDARD TABLE OF agval,
        lv_agr_chk     TYPE agr_name,
        lv_parent_chk  TYPE agr_name,
        lv_auth_ok     TYPE abap_bool,
        lv_auth_msg    TYPE string,
        lv_fix_1251    TYPE abap_bool,
        lv_fix_1250    TYPE abap_bool,
        lv_fix_1252    TYPE abap_bool,
        lv_fixed_flds  TYPE i,
        lv_fixed_auths TYPE i,
        lv_heal_det    TYPE string,
        lv_par_healed  TYPE abap_bool,
        lv_par_err     TYPE string,
        lv_enq_ok      TYPE abap_bool,
        lv_save_err    TYPE string,
        lv_gen_subrc   TYPE sy-subrc,
        lv_gen_err     TYPE string,
        lv_chk_color   TYPE char10,
        lv_chk_msg     TYPE c LENGTH 255.

  CLEAR gt_results.

  " Process Master Roles before Derived Roles
  PERFORM sort_roles_master_first.

  LOOP AT gt_oversized_roles INTO DATA(lv_bad_role).
    CLEAR ls_res.
    ls_res-status   = gc_status_err.
    ls_res-action   = 'ERROR'.
    ls_res-agr_name = lv_bad_role.
    ls_res-message  = |Role name exceeds SAP 30-character limit: '{ lv_bad_role }'.|.
    APPEND ls_res TO gt_results.
  ENDLOOP.

  LOOP AT gt_roles INTO DATA(ls_role).
    DATA lv_heal_read_err TYPE string.
    CLEAR: ls_res, lt_pt1251, lt_pt1250, lt_pt1252, lt_active_vars,
           lv_agr_chk, lv_parent_chk, lv_auth_ok, lv_auth_msg,
           lv_fix_1251, lv_fix_1250, lv_fix_1252, lv_fixed_flds, lv_fixed_auths,
           lv_heal_det, lv_par_healed, lv_par_err, lv_enq_ok, lv_save_err,
           lv_gen_subrc, lv_gen_err, lv_chk_color, lv_chk_msg, lv_heal_read_err.

    ls_res-agr_name = ls_role-agr_name.

    " 1. Per-role Authority Check
    PERFORM check_role_authority USING ls_role-agr_name p_test
                                 CHANGING lv_auth_ok lv_auth_msg.
    IF lv_auth_ok = abap_false.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = lv_auth_msg.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " 2. Validate Role in SAP
    SELECT SINGLE agr_name, parent_agr FROM agr_define
      INTO ( @lv_agr_chk, @lv_parent_chk )
      WHERE agr_name = @ls_role-agr_name.
    IF sy-subrc <> 0 OR lv_agr_chk IS INITIAL.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = |Role '{ ls_role-agr_name }' does not exist in SAP.|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    DATA(lv_coll_flag) = VALUE agr_flags-flag_value( ).
    SELECT SINGLE flag_value FROM agr_flags INTO @lv_coll_flag
      WHERE agr_name = @ls_role-agr_name AND flag_type = 'COLL_AGR'.
    IF sy-subrc = 0 AND lv_coll_flag = 'X'.
      ls_res-status  = gc_status_warn.
      ls_res-action  = 'COMPOSITE'.
      ls_res-message = |Role '{ ls_role-agr_name }' is a Composite Role (no Org Levels). Skipped.|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    ls_res-parent_agr = lv_parent_chk.

    SELECT SINGLE text FROM agr_texts INTO @ls_res-role_desc
      WHERE agr_name = @ls_role-agr_name AND spras = @sy-langu AND line = '00000'.
    IF sy-subrc <> 0.
      SELECT SINGLE text FROM agr_texts INTO @ls_res-role_desc
        WHERE agr_name = @ls_role-agr_name AND line = '00000'.
    ENDIF.

    " 3. Auto-Heal Parent Master Role first BEFORE enqueuing child role
    IF p_parhea = abap_true AND lv_parent_chk IS NOT INITIAL.
      IF NOT line_exists( gt_checked_parents[ table_line = lv_parent_chk ] ).
        INSERT lv_parent_chk INTO TABLE gt_checked_parents.
        PERFORM heal_parent_master_role USING    lv_parent_chk
                                                 p_test
                                                 p_genprf
                                        CHANGING lv_par_healed
                                                 lv_par_err.
        IF lv_par_healed = abap_true.
          INSERT lv_parent_chk INTO TABLE gt_healed_parents.
        ENDIF.
        IF lv_par_err IS NOT INITIAL.
          INSERT VALUE ty_parent_err( parent_agr = lv_parent_chk err_msg = lv_par_err )
            INTO TABLE gt_parent_errors.
        ENDIF.
      ELSE.
        READ TABLE gt_parent_errors INTO DATA(ls_cached_pe2)
          WITH TABLE KEY parent_agr = lv_parent_chk.
        IF sy-subrc = 0.
          lv_par_err = ls_cached_pe2-err_msg.
        ENDIF.
      ENDIF.
    ENDIF.

    " TOCTOU Prevention (03A-3): Enqueue role BEFORE reading AGR_1250/1251/1252 in Real Execution
    DATA(lv_enq_held2) = abap_false.
    IF p_test = abap_false.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
        EXPORTING
          activity_group          = ls_role-agr_name
          no_dialog               = 'X'
        EXCEPTIONS
          foreign_lock            = 1
          transport_check_problem = 2
          OTHERS                  = 3.
      IF sy-subrc <> 0.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'ERROR'.
        ls_res-message = |Role '{ ls_role-agr_name }' is locked or cannot be enqueued (sy-subrc = { sy-subrc }).|.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.
      lv_enq_held2 = abap_true.
    ENDIF.

    " 4. Heal AGR_1251 & AGR_1250
    DATA lt_newly_bound2 TYPE ty_t_var_objfld.
    CLEAR lt_newly_bound2.
    PERFORM analyze_and_heal_1251_1250 USING    ls_role-agr_name
                                       CHANGING lt_pt1251
                                                lt_pt1250
                                                lv_fix_1251
                                                lv_fix_1250
                                                lv_fixed_flds
                                                lv_fixed_auths
                                                lv_heal_det
                                                lv_heal_read_err
                                                lt_newly_bound2.
    IF lv_heal_read_err IS NOT INITIAL.
      IF lv_enq_held2 = abap_true.
        CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
          EXPORTING
            activity_group = ls_role-agr_name
          EXCEPTIONS
            OTHERS         = 0.
      ENDIF.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = lv_heal_read_err.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    ls_res-fixed_fields = lv_fixed_flds.
    ls_res-fixed_auths  = lv_fixed_auths.
    ls_res-orgs_detail  = lv_heal_det.

    " 5. Ensure AGR_1252 Consistency (check sy-subrc strictly to NEVER wipe AGR_1252!)
    CALL FUNCTION 'PRGN_1252_READ_ORG_LEVELS'
      EXPORTING
        activity_group    = ls_role-agr_name
      TABLES
        org_levels        = lt_pt1252
      EXCEPTIONS
        no_data_available = 1
        OTHERS            = 2.

    IF sy-subrc = 2.
      IF lv_enq_held2 = abap_true.
        CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
          EXPORTING
            activity_group = ls_role-agr_name
          EXCEPTIONS
            OTHERS         = 0.
      ENDIF.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = |Failed to read AGR_1252 org levels for '{ ls_role-agr_name }' (sy-subrc = 2).|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " Collect $VARBLs ONLY from ACTIVE AGR_1250 headers
    TYPES: BEGIN OF ty_act_k2,
             object TYPE xuobject,
             auth   TYPE xuauth,
           END OF ty_act_k2.
    DATA lt_act_k2 TYPE HASHED TABLE OF ty_act_k2 WITH UNIQUE KEY object auth.
    CLEAR lt_act_k2.
    LOOP AT lt_pt1250 INTO DATA(ls_h2) WHERE deleted = space AND copied <> 'I'.
      INSERT VALUE ty_act_k2( object = ls_h2-object auth = ls_h2-auth ) INTO TABLE lt_act_k2.
    ENDLOOP.

    DATA lt_var_objflds2 TYPE ty_t_var_objfld.
    CLEAR lt_var_objflds2.
    LOOP AT lt_pt1251 INTO DATA(ls_p51)
      WHERE deleted = space AND copied <> 'I' AND low CP '$*'.
      IF line_exists( lt_act_k2[ object = ls_p51-object auth = ls_p51-auth ] )
         AND line_exists( gt_usorg_map[ KEY by_varbl COMPONENTS varbl = ls_p51-low ] ).
        APPEND ls_p51-low TO lt_active_vars.
        READ TABLE lt_var_objflds2
          WITH KEY varbl = ls_p51-low object = ls_p51-object field = ls_p51-field
          TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          INSERT VALUE ty_var_objfld(
            object = ls_p51-object field = ls_p51-field varbl = ls_p51-low )
            INTO TABLE lt_var_objflds2.
        ENDIF.
      ENDIF.
    ENDLOOP.
    SORT lt_active_vars.
    DELETE ADJACENT DUPLICATES FROM lt_active_vars.

    " Check each active $VARBL (preserve ALL maintained multi-value rows!)
    DATA lv_sval_err2 TYPE string.
    CLEAR lv_sval_err2.
    LOOP AT lt_active_vars INTO DATA(lv_avar).
      DATA(lv_has_any_row)   = abap_false.
      DATA(lv_has_maint_row) = abap_false.
      DATA(lv_has_blank_row) = abap_false.
      LOOP AT lt_pt1252 INTO DATA(ls_1252_chk) WHERE varbl = lv_avar.
        lv_has_any_row = abap_true.
        IF ( ls_1252_chk-low IS NOT INITIAL AND ls_1252_chk-low <> '-1' AND ls_1252_chk-low <> '$' )
           OR ls_1252_chk-high IS NOT INITIAL.
          lv_has_maint_row = abap_true.
        ELSE.
          lv_has_blank_row = abap_true.
        ENDIF.
      ENDLOOP.

      IF lv_has_any_row = abap_false.
        " Missing in AGR_1252: Master/Standalone -> '-1', Derived -> '*' (if p_astnon) else '-1'
        DATA(lv_new_def) = COND agval(
          WHEN lv_parent_chk IS NOT INITIAL AND p_astnon = abap_true THEN '*'
          ELSE '-1' ).
        IF lv_new_def = '*'.
          PERFORM check_org_s_user_val USING lv_avar lv_new_def space lt_var_objflds2
                                       CHANGING lv_sval_err2.
          IF lv_sval_err2 IS NOT INITIAL.
            EXIT.
          ENDIF.
        ENDIF.
        APPEND VALUE pt1252( varbl = lv_avar low = lv_new_def high = space ) TO lt_pt1252.
        lv_fix_1252 = abap_true.
      ELSEIF lv_has_maint_row = abap_true AND lv_has_blank_row = abap_true.
        " Remove stray empty/'-1'/'$' rows alongside maintained values
        DELETE lt_pt1252 WHERE varbl = lv_avar
                           AND ( low IS INITIAL OR low = '-1' OR low = '$' )
                           AND high IS INITIAL.
        lv_fix_1252 = abap_true.
      ELSEIF lv_has_maint_row = abap_false.
        DATA(lv_unm_def) = COND agval(
          WHEN lv_parent_chk IS NOT INITIAL AND p_astnon = abap_true THEN '*'
          ELSE '-1' ).
        DATA(lv_need_norm) = abap_false.
        DATA(lv_cnt_avar)  = 0.
        LOOP AT lt_pt1252 INTO ls_1252_chk WHERE varbl = lv_avar.
          lv_cnt_avar = lv_cnt_avar + 1.
          IF ls_1252_chk-low <> lv_unm_def OR ls_1252_chk-high IS NOT INITIAL.
            lv_need_norm = abap_true.
          ENDIF.
        ENDLOOP.
        IF lv_need_norm = abap_true OR lv_cnt_avar > 1.
          IF lv_unm_def = '*'.
            PERFORM check_org_s_user_val USING lv_avar lv_unm_def space lt_var_objflds2
                                         CHANGING lv_sval_err2.
            IF lv_sval_err2 IS NOT INITIAL.
              EXIT.
            ENDIF.
          ENDIF.
          DELETE lt_pt1252 WHERE varbl = lv_avar.
          APPEND VALUE pt1252( varbl = lv_avar low = lv_unm_def high = space ) TO lt_pt1252.
          lv_fix_1252 = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.

    " Verify S_USER_VAL for every newly bound AGR_1251 (object, field) against maintained AGR_1252 values
    IF lv_sval_err2 IS INITIAL AND lt_newly_bound2 IS NOT INITIAL.
      LOOP AT lt_pt1252 INTO DATA(ls_52_nb).
        IF ( ls_52_nb-low IS INITIAL OR ls_52_nb-low = '-1' OR ls_52_nb-low = '$' )
           AND ls_52_nb-high IS INITIAL.
          CONTINUE.
        ENDIF.
        IF line_exists( lt_newly_bound2[ varbl = ls_52_nb-varbl ] ).
          PERFORM check_org_s_user_val USING ls_52_nb-varbl
                                             ls_52_nb-low
                                             ls_52_nb-high
                                             lt_newly_bound2
                                       CHANGING lv_sval_err2.
          IF lv_sval_err2 IS NOT INITIAL.
            EXIT.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDIF.

    IF lv_sval_err2 IS NOT INITIAL.
      IF lv_enq_held2 = abap_true.
        CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
          EXPORTING
            activity_group = ls_role-agr_name
          EXCEPTIONS
            OTHERS         = 0.
      ENDIF.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = lv_sval_err2.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    DATA(lv_needs_save) = xsdbool( lv_fix_1251 = abap_true OR lv_fix_1250 = abap_true OR lv_fix_1252 = abap_true ).

    " 6. Simulation Mode
    IF p_test = abap_true.
      SELECT SINGLE profile FROM agr_1016 INTO @ls_res-profile
        WHERE agr_name = @ls_role-agr_name.

      IF lv_needs_save = abap_true.
        ls_res-status  = gc_status_ok.
        ls_res-action  = 'SIMULATE'.
        ls_res-message = |[Simulated] Will repair { lv_fixed_flds } Org field(s) and { lv_fixed_auths } Auth node(s) to Standard.|.
        IF lv_fix_1252 = abap_true.
          ls_res-message = |{ ls_res-message } Will sync missing/empty AGR_1252 org entries.|.
        ENDIF.
      ELSE.
        ls_res-status  = gc_status_ok.
        ls_res-action  = 'UP-TO-DATE'.
        ls_res-message = |[Simulated] Role Org bindings are 100% Standard and clean.|.
      ENDIF.
      PERFORM append_parent_heal_note USING lv_parent_chk p_test lv_par_err CHANGING ls_res-status ls_res-message.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " 7. Real Execution (ONLY saves & regenerates when changes actually occurred!)
    IF lv_needs_save = abap_true.
      DATA(lv_skip_m_gen2) = xsdbool( lv_parent_chk IS INITIAL AND line_exists( lt_pt1252[ low = '-1' ] ) ).
      DATA(lv_eff_genprf2) = COND abap_bool( WHEN p_genprf = abap_true AND lv_skip_m_gen2 = abap_false
                                             THEN abap_true ELSE abap_false ).

      PERFORM save_and_generate_role USING    ls_role-agr_name
                                              lt_pt1251
                                              lt_pt1250
                                              lt_pt1252
                                              lv_fix_1251
                                              lv_fix_1250
                                              lv_fix_1252
                                              lv_eff_genprf2
                                              lv_enq_held2
                                     CHANGING lv_enq_ok
                                              lv_save_err
                                              lv_gen_subrc
                                              lv_gen_err
                                              ls_res-profile
                                              lv_chk_color
                                              lv_chk_msg.

      IF lv_enq_ok = abap_false OR lv_save_err IS NOT INITIAL.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'ERROR'.
        ls_res-message = lv_save_err.
      ELSEIF lv_eff_genprf2 = abap_true.
        IF lv_chk_color = 'RED'.
          ls_res-status  = gc_status_err.
          ls_res-action  = 'WARNING'.
          ls_res-message = |Repaired { lv_fixed_flds } field(s) / { lv_fixed_auths } auth(s). Profile Red: { lv_gen_err } { lv_chk_msg }|.
        ELSEIF lv_gen_subrc <> 0 OR lv_gen_err IS NOT INITIAL.
          ls_res-status  = gc_status_warn.
          ls_res-action  = 'FIXED'.
          ls_res-message = |Repaired { lv_fixed_flds } field(s) / { lv_fixed_auths } auth(s). Profile warning: { lv_gen_err } { lv_chk_msg }|.
        ELSEIF lv_chk_color = 'GREEN'.
          ls_res-status  = gc_status_ok.
          ls_res-action  = 'FIXED'.
          ls_res-message = |Repaired { lv_fixed_flds } field(s) / { lv_fixed_auths } auth(s). Profile '{ ls_res-profile }' is GREEN.|.
        ELSEIF lv_chk_color = 'YELLOW'.
          ls_res-status  = gc_status_warn.
          ls_res-action  = 'FIXED'.
          ls_res-message = |Repaired { lv_fixed_flds } field(s) / { lv_fixed_auths } auth(s). Profile Yellow: { lv_chk_msg }|.
        ELSE.
          ls_res-status  = gc_status_ok.
          ls_res-action  = 'FIXED'.
          ls_res-message = |Repaired { lv_fixed_flds } field(s) / { lv_fixed_auths } auth(s).|.
        ENDIF.
      ELSE.
        ls_res-status  = gc_status_ok.
        ls_res-action  = 'FIXED'.
        IF lv_skip_m_gen2 = abap_true AND p_genprf = abap_true.
          ls_res-message = |Repaired { lv_fixed_flds } field(s) / { lv_fixed_auths } auth(s) on Master Role (unmaintained '-1' orgs: profile gen skipped).|.
        ELSE.
          ls_res-message = |Repaired { lv_fixed_flds } field(s) / { lv_fixed_auths } auth(s). Profile regeneration skipped.|.
        ENDIF.
      ENDIF.
    ELSE.
      IF lv_enq_held2 = abap_true.
        CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
          EXPORTING
            activity_group = ls_role-agr_name
          EXCEPTIONS
            OTHERS         = 0.
      ENDIF.
      SELECT SINGLE profile FROM agr_1016 INTO @ls_res-profile
        WHERE agr_name = @ls_role-agr_name.
      ls_res-status  = gc_status_ok.
      ls_res-action  = 'UP-TO-DATE'.
      ls_res-message = 'Role Org bindings are 100% Standard and clean.'.
    ENDIF.

    PERFORM append_parent_heal_note USING lv_parent_chk p_test lv_par_err CHANGING ls_res-status ls_res-message.
    APPEND ls_res TO gt_results.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form analyze_and_heal_1251_1250
*&---------------------------------------------------------------------*
* Reads AGR_1250 & AGR_1251 and restores corrupted Org Level fields
* back to $VARBL while honoring SAP TPR_ST_MOD domain semantics:
*   'S' = Standard, 'G' = Maintained, 'M' = Changed, 'U' = Manual.
* Manual ('U') AGR_1250 headers & concrete overrides are NEVER downgraded;
* per SAP LSUPRNF1H, $VARBL rows in AGR_1251 MUST have MODIFIED = 'S'.
* Only 'M' headers whose Org fields were actually healed are re-evaluated.
*&---------------------------------------------------------------------*
FORM analyze_and_heal_1251_1250 USING    iv_role        TYPE agr_name
                                CHANGING ct_pt1251      TYPE ty_t_pt1251
                                         ct_pt1250      TYPE ty_t_pt1250
                                         ev_fix_1251    TYPE abap_bool
                                         ev_fix_1250    TYPE abap_bool
                                         ev_fixed_flds  TYPE i
                                         ev_fixed_auth  TYPE i
                                         ev_detail      TYPE string
                                         ev_read_err    TYPE string
                                         et_newly_bound TYPE ty_t_var_objfld.
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

  DATA: lt_act_hdr        TYPE HASHED TABLE OF ty_hdr_mod WITH UNIQUE KEY object auth,
        lt_seen_key       TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line,
        lt_healed_auths   TYPE HASHED TABLE OF ty_obj_auth_key WITH UNIQUE KEY object auth,
        lt_decoupled_flds TYPE HASHED TABLE OF ty_obj_auth_fld WITH UNIQUE KEY object auth field,
        lt_clean          TYPE STANDARD TABLE OF pt1251,
        lv_key            TYPE string,
        lv_det_item       TYPE string.

  CLEAR: ct_pt1251, ct_pt1250, ev_fix_1251, ev_fix_1250,
         ev_fixed_flds, ev_fixed_auth, ev_detail, ev_read_err, et_newly_bound.

  CALL FUNCTION 'PRGN_CLEAR_BUFFER'.

  CALL FUNCTION 'PRGN_1250_READ_AUTH_DATA'
    EXPORTING
      activity_group    = iv_role
      no_texts          = 'X'
    TABLES
      auth_data         = ct_pt1250
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.

  IF sy-subrc = 2.
    ev_read_err = |Failed to read AGR_1250 auth data for role '{ iv_role }' (sy-subrc = 2).|.
    RETURN.
  ENDIF.
  IF sy-subrc <> 0 OR ct_pt1250 IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT ct_pt1250 INTO DATA(ls_h50) WHERE deleted = space AND copied <> 'I'.
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
      field_values      = ct_pt1251
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.

  IF sy-subrc = 2.
    ev_read_err = |Failed to read AGR_1251 field values for role '{ iv_role }' (sy-subrc = 2).|.
    RETURN.
  ENDIF.
  IF sy-subrc <> 0 OR ct_pt1251 IS INITIAL.
    RETURN.
  ENDIF.

  " Pre-scan: detect decoupled concrete 'G'/'M'/'U' org overrides (never compare low(1) = '$' so '$TMP' survives)
  LOOP AT ct_pt1251 INTO DATA(ls_pre).
    IF ls_pre-deleted <> space OR ls_pre-copied = 'I'.
      CONTINUE.
    ENDIF.
    IF NOT line_exists( lt_act_hdr[ object = ls_pre-object auth = ls_pre-auth ] ).
      CONTINUE.
    ENDIF.
    READ TABLE gt_usorg_map INTO DATA(ls_um_pre) WITH TABLE KEY field = ls_pre-field.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.
    IF ( ls_pre-modified = 'G' OR ls_pre-modified = 'M' OR ls_pre-modified = 'U' )
       AND ( ( ls_pre-low IS NOT INITIAL AND ls_pre-low <> '-1'
               AND ls_pre-low <> '$' AND ls_pre-low <> ls_um_pre-varbl )
             OR ls_pre-high IS NOT INITIAL ).
      INSERT VALUE ty_obj_auth_fld(
        object = ls_pre-object auth = ls_pre-auth field = ls_pre-field )
        INTO TABLE lt_decoupled_flds.
    ENDIF.
  ENDLOOP.

  " Rebind non-decoupled Org fields on ACTIVE auth instances with MODIFIED = 'S' (SAPLSUPRN LSUPRNF1H)
  LOOP AT ct_pt1251 INTO DATA(ls_f51).
    IF ls_f51-deleted = space AND ls_f51-copied <> 'I'.
      READ TABLE lt_act_hdr INTO DATA(ls_hdr)
        WITH TABLE KEY object = ls_f51-object auth = ls_f51-auth.
      IF sy-subrc = 0.
        READ TABLE gt_usorg_map INTO DATA(ls_um) WITH TABLE KEY field = ls_f51-field.
        IF sy-subrc = 0.
          IF line_exists( lt_decoupled_flds[
               object = ls_f51-object auth = ls_f51-auth field = ls_f51-field ] ).
            IF ( ls_f51-low IS INITIAL OR ls_f51-low = '-1'
                 OR ls_f51-low = '$' OR ls_f51-low = ls_um-varbl )
               AND ls_f51-high IS INITIAL.
              ev_fix_1251   = abap_true.
              ev_fixed_flds = ev_fixed_flds + 1.
              INSERT VALUE ty_obj_auth_key( object = ls_f51-object auth = ls_f51-auth )
                INTO TABLE lt_healed_auths.
              CONTINUE.
            ENDIF.
            APPEND ls_f51 TO lt_clean.
            CONTINUE.
          ENDIF.

          lv_key = |{ ls_f51-object }:{ ls_f51-auth }:{ ls_f51-field }|.
          IF line_exists( lt_seen_key[ table_line = lv_key ] ).
            ev_fix_1251   = abap_true.
            ev_fixed_flds = ev_fixed_flds + 1.
            INSERT VALUE ty_obj_auth_key( object = ls_f51-object auth = ls_f51-auth )
              INTO TABLE lt_healed_auths.
            CONTINUE.
          ENDIF.
          INSERT lv_key INTO TABLE lt_seen_key.

          IF ls_f51-low <> ls_um-varbl OR ls_f51-high IS NOT INITIAL
             OR ls_f51-modified <> 'S'.
            ls_f51-low      = ls_um-varbl.
            ls_f51-high     = space.
            ls_f51-modified = 'S'.
            ls_f51-neu      = 'O'.
            ev_fix_1251     = abap_true.
            ev_fixed_flds   = ev_fixed_flds + 1.
            INSERT VALUE ty_obj_auth_key( object = ls_f51-object auth = ls_f51-auth )
              INTO TABLE lt_healed_auths.
            INSERT VALUE ty_var_objfld(
              object = ls_f51-object field = ls_f51-field varbl = ls_um-varbl )
              INTO TABLE et_newly_bound.

            lv_det_item = |{ ls_f51-object }-{ ls_f51-field }={ ls_um-varbl }|.
            IF ev_detail IS INITIAL.
              ev_detail = lv_det_item.
            ELSEIF strlen( ev_detail ) < 180.
              ev_detail = |{ ev_detail }; { lv_det_item }|.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.
    APPEND ls_f51 TO lt_clean.
  ENDLOOP.
  ct_pt1251 = lt_clean.

  " Normalize ONLY 'M' (Changed) headers whose Org fields were actually healed; NEVER touch unrelated 'M' or 'U'
  IF lt_healed_auths IS NOT INITIAL.
    LOOP AT ct_pt1250 ASSIGNING FIELD-SYMBOL(<ls_a50>)
      WHERE deleted = space AND copied <> 'I' AND modified = 'M'.
      IF NOT line_exists( lt_healed_auths[ object = <ls_a50>-object auth = <ls_a50>-auth ] ).
        CONTINUE.
      ENDIF.
      DATA(lv_has_m) = abap_false.
      DATA(lv_has_g) = abap_false.
      LOOP AT ct_pt1251 INTO DATA(ls_chk_f)
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
        ev_fix_1250       = abap_true.
        ev_fixed_auth     = ev_fixed_auth + 1.
      ENDIF.
    ENDLOOP.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form save_and_generate_role
*&---------------------------------------------------------------------*
* Certified PFCG lifecycle:
*   ENQUEUE -> SAVE 1251/1250/1252 -> PRGN_UPDATE_DATABASE ->
*   PRGN_SET_ACTGROUP_TIMESTAMP -> COMMIT WORK AND WAIT -> DEQUEUE ->
*   SUPRN_DARK_MANIPULATE_PROFILE (fill_fields_with_star = space) ->
*   COMMIT WORK AND WAIT -> PRGN_CHECK_PROFILE_STATUS
*&---------------------------------------------------------------------*
FORM save_and_generate_role USING    iv_role        TYPE agr_name
                                     it_pt1251      TYPE ty_t_pt1251
                                     it_pt1250      TYPE ty_t_pt1250
                                     it_pt1252      TYPE ty_t_pt1252
                                     iv_save_1251   TYPE abap_bool
                                     iv_save_1250   TYPE abap_bool
                                     iv_save_1252   TYPE abap_bool
                                     iv_genprf      TYPE abap_bool
                                     iv_already_enq TYPE abap_bool
                            CHANGING ev_enq_ok      TYPE abap_bool
                                     ev_save_err    TYPE string
                                     ev_gen_subrc   TYPE sy-subrc
                                     ev_gen_err     TYPE string
                                     ev_profile     TYPE xuprofile
                                     ev_chk_color   TYPE char10
                                     ev_chk_msg     TYPE c.
  DATA: lt_pt1251_loc TYPE STANDARD TABLE OF pt1251,
        lt_pt1250_loc TYPE STANDARD TABLE OF pt1250,
        lt_pt1252_loc TYPE STANDARD TABLE OF pt1252,
        lt_bapiret    TYPE STANDARD TABLE OF bapiret2.

  CLEAR: ev_enq_ok, ev_save_err, ev_gen_subrc, ev_gen_err,
         ev_profile, ev_chk_color, ev_chk_msg.

  " 1. Enqueue Role (unless caller already holds enqueue lock across Read -> Save!)
  IF iv_already_enq = abap_false.
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
      EXPORTING
        activity_group          = iv_role
        no_dialog               = 'X'
      EXCEPTIONS
        foreign_lock            = 1
        transport_check_problem = 2
        OTHERS                  = 3.

    IF sy-subrc <> 0.
      ev_enq_ok   = abap_false.
      ev_save_err = |Role '{ iv_role }' is currently locked or cannot be enqueued (sy-subrc = { sy-subrc }).|.
      RETURN.
    ENDIF.
  ENDIF.
  ev_enq_ok = abap_true.

  " 2. Clear SAPLPRGN globals & save modified structures via standard PFCG FMs
  CALL FUNCTION 'PRGN_CLEAR_BUFFER'.

  IF iv_save_1251 = abap_true.
    lt_pt1251_loc = it_pt1251.
    CALL FUNCTION 'PRGN_1251_SAVE_FIELD_VALUES'
      EXPORTING
        activity_group = iv_role
      TABLES
        field_values   = lt_pt1251_loc
      EXCEPTIONS
        OTHERS         = 1.
    IF sy-subrc <> 0.
      ev_save_err = |PRGN_1251_SAVE_FIELD_VALUES failed (sy-subrc = { sy-subrc }).|.
    ENDIF.
  ENDIF.

  IF ev_save_err IS INITIAL AND iv_save_1250 = abap_true.
    lt_pt1250_loc = it_pt1250.
    CALL FUNCTION 'PRGN_1250_SAVE_AUTH_DATA'
      EXPORTING
        activity_group = iv_role
      TABLES
        auth_data      = lt_pt1250_loc
      EXCEPTIONS
        OTHERS         = 1.
    IF sy-subrc <> 0.
      ev_save_err = |PRGN_1250_SAVE_AUTH_DATA failed (sy-subrc = { sy-subrc }).|.
    ENDIF.
  ENDIF.

  IF ev_save_err IS INITIAL AND iv_save_1252 = abap_true.
    lt_pt1252_loc = it_pt1252.
    CALL FUNCTION 'PRGN_1252_SAVE_ORG_LEVELS'
      EXPORTING
        activity_group = iv_role
      TABLES
        org_levels     = lt_pt1252_loc
      EXCEPTIONS
        OTHERS         = 1.
    IF sy-subrc <> 0.
      ev_save_err = |PRGN_1252_SAVE_ORG_LEVELS failed (sy-subrc = { sy-subrc }).|.
    ENDIF.
  ENDIF.

  IF ev_save_err IS INITIAL.
    CALL FUNCTION 'PRGN_UPDATE_DATABASE'
      EXCEPTIONS
        OTHERS = 1.
    IF sy-subrc <> 0.
      ev_save_err = |PRGN_UPDATE_DATABASE failed (sy-subrc = { sy-subrc }).|.
    ENDIF.
  ENDIF.

  IF ev_save_err IS INITIAL.
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

  " 3. Crucial: Always DEQUEUE before SUPRN_DARK_MANIPULATE_PROFILE
  CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
    EXPORTING
      activity_group = iv_role
    EXCEPTIONS
      OTHERS         = 0.

  IF ev_save_err IS NOT INITIAL.
    RETURN.
  ENDIF.

  " 4. Dark Profile Generation (NEVER fill non-org fields with '*')
  IF iv_genprf = abap_true.
    CLEAR lt_bapiret.
    CALL FUNCTION 'SUPRN_DARK_MANIPULATE_PROFILE'
      EXPORTING
        activity_group        = iv_role
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
    ev_gen_subrc = sy-subrc.

    LOOP AT lt_bapiret INTO DATA(ls_ret) WHERE type CA 'EAX'.
      IF ev_gen_err IS INITIAL.
        ev_gen_err = ls_ret-message.
      ELSE.
        ev_gen_err = |{ ev_gen_err }; { ls_ret-message }|.
      ENDIF.
    ENDLOOP.

    IF ev_gen_subrc <> 0 AND ev_gen_err IS INITIAL.
      IF sy-msgid IS NOT INITIAL.
        MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno
          WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 INTO ev_gen_err.
      ENDIF.
      IF ev_gen_err IS INITIAL.
        ev_gen_err = SWITCH #( ev_gen_subrc
          WHEN 1 THEN 'Open/unmaintained authorizations or org levels'
          WHEN 2 THEN 'Missing profile generation authorization (S_USER_PRO)'
          WHEN 3 THEN 'No authorization data found'
          WHEN 4 THEN 'Too many authorizations for profile'
          ELSE |Profile generation failed (sy-subrc = { ev_gen_subrc })| ).
      ENDIF.
    ENDIF.

    IF ev_gen_subrc = 0 AND ev_gen_err IS INITIAL.
      COMMIT WORK AND WAIT.
    ELSE.
      ROLLBACK WORK.
      CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
    ENDIF.

    CALL FUNCTION 'PRGN_CHECK_PROFILE_STATUS'
      EXPORTING
        activity_group = iv_role
      IMPORTING
        message_text   = ev_chk_msg
        led_color      = ev_chk_color
      EXCEPTIONS
        OTHERS         = 1.
  ENDIF.

  SELECT SINGLE profile FROM agr_1016 INTO @ev_profile
    WHERE agr_name = @iv_role.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form heal_parent_master_role
*&---------------------------------------------------------------------*
FORM heal_parent_master_role USING    iv_parent_role TYPE agr_name
                                      iv_test        TYPE abap_bool
                                      iv_genprf      TYPE abap_bool
                             CHANGING ev_healed      TYPE abap_bool
                                      ev_error       TYPE string.
  TYPES: BEGIN OF ty_par_act_k,
           object TYPE xuobject,
           auth   TYPE xuauth,
         END OF ty_par_act_k.

  DATA: lt_pt1251_par  TYPE STANDARD TABLE OF pt1251,
        lt_pt1250_par  TYPE STANDARD TABLE OF pt1250,
        lt_pt1252_par  TYPE STANDARD TABLE OF pt1252,
        lt_par_act_k   TYPE HASHED TABLE OF ty_par_act_k WITH UNIQUE KEY object auth,
        lt_par_vars    TYPE STANDARD TABLE OF agval,
        lv_auth_ok     TYPE abap_bool,
        lv_auth_msg    TYPE string,
        lv_par_enq     TYPE abap_bool,
        lv_fix_51      TYPE abap_bool,
        lv_fix_50      TYPE abap_bool,
        lv_fix_52      TYPE abap_bool,
        lv_flds        TYPE i,
        lv_auths       TYPE i,
        lv_det         TYPE string,
        lv_read_err    TYPE string,
        lv_enq_ok      TYPE abap_bool,
        lv_save_err    TYPE string,
        lv_gen_subrc   TYPE sy-subrc,
        lv_gen_err     TYPE string,
        lv_prof        TYPE xuprofile,
        lv_color       TYPE char10,
        lv_msg         TYPE c LENGTH 255.

  CLEAR: ev_healed, ev_error, lv_par_enq.

  PERFORM check_role_authority USING iv_parent_role iv_test
                               CHANGING lv_auth_ok lv_auth_msg.
  IF lv_auth_ok = abap_false.
    ev_error = lv_auth_msg.
    RETURN.
  ENDIF.

  " TOCTOU Prevention (03A-3): Enqueue parent master role BEFORE reading AGR_1250/1251/1252
  IF iv_test = abap_false.
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
      EXPORTING
        activity_group          = iv_parent_role
        no_dialog               = 'X'
      EXCEPTIONS
        foreign_lock            = 1
        transport_check_problem = 2
        OTHERS                  = 3.
    IF sy-subrc <> 0.
      ev_error = |Parent role '{ iv_parent_role }' is locked or cannot be enqueued (sy-subrc = { sy-subrc }).|.
      RETURN.
    ENDIF.
    lv_par_enq = abap_true.
  ENDIF.

  DATA lt_newly_bound_par TYPE ty_t_var_objfld.
  CLEAR lt_newly_bound_par.
  PERFORM analyze_and_heal_1251_1250 USING    iv_parent_role
                                     CHANGING lt_pt1251_par
                                              lt_pt1250_par
                                              lv_fix_51
                                              lv_fix_50
                                              lv_flds
                                              lv_auths
                                              lv_det
                                              lv_read_err
                                              lt_newly_bound_par.
  IF lv_read_err IS NOT INITIAL.
    IF lv_par_enq = abap_true.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
        EXPORTING
          activity_group = iv_parent_role
        EXCEPTIONS
          OTHERS         = 0.
    ENDIF.
    ev_error = lv_read_err.
    RETURN.
  ENDIF.

  " Ensure any active $VARBL introduced/healed in parent AGR_1251 also has a '-1' entry in parent AGR_1252
  CALL FUNCTION 'PRGN_1252_READ_ORG_LEVELS'
    EXPORTING
      activity_group    = iv_parent_role
    TABLES
      org_levels        = lt_pt1252_par
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.
  IF sy-subrc = 2.
    IF lv_par_enq = abap_true.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
        EXPORTING
          activity_group = iv_parent_role
        EXCEPTIONS
          OTHERS         = 0.
    ENDIF.
    ev_error = |Failed to read parent AGR_1252 for '{ iv_parent_role }' (rc=2).|.
    RETURN.
  ENDIF.

  LOOP AT lt_pt1250_par INTO DATA(ls_ph) WHERE deleted = space AND copied <> 'I'.
    INSERT VALUE ty_par_act_k( object = ls_ph-object auth = ls_ph-auth ) INTO TABLE lt_par_act_k.
  ENDLOOP.
  LOOP AT lt_pt1251_par INTO DATA(ls_pf)
    WHERE deleted = space AND copied <> 'I' AND low CP '$*'.
    IF line_exists( lt_par_act_k[ object = ls_pf-object auth = ls_pf-auth ] )
       AND line_exists( gt_usorg_map[ KEY by_varbl COMPONENTS varbl = ls_pf-low ] ).
      APPEND ls_pf-low TO lt_par_vars.
    ENDIF.
  ENDLOOP.
  SORT lt_par_vars.
  DELETE ADJACENT DUPLICATES FROM lt_par_vars.

  LOOP AT lt_par_vars INTO DATA(lv_pv).
    READ TABLE lt_pt1252_par WITH KEY varbl = lv_pv TRANSPORTING NO FIELDS.
    IF sy-subrc <> 0.
      APPEND VALUE pt1252( varbl = lv_pv low = '-1' high = space ) TO lt_pt1252_par.
      lv_fix_52 = abap_true.
    ENDIF.
  ENDLOOP.

  " Verify S_USER_VAL for newly rebound parent AGR_1251 org fields against maintained parent AGR_1252
  DATA lv_par_sval_err TYPE string.
  CLEAR lv_par_sval_err.
  IF lt_newly_bound_par IS NOT INITIAL.
    LOOP AT lt_pt1252_par INTO DATA(ls_p52_nb).
      IF ( ls_p52_nb-low IS INITIAL OR ls_p52_nb-low = '-1' OR ls_p52_nb-low = '$' )
         AND ls_p52_nb-high IS INITIAL.
        CONTINUE.
      ENDIF.
      IF line_exists( lt_newly_bound_par[ varbl = ls_p52_nb-varbl ] ).
        PERFORM check_org_s_user_val USING ls_p52_nb-varbl
                                           ls_p52_nb-low
                                           ls_p52_nb-high
                                           lt_newly_bound_par
                                     CHANGING lv_par_sval_err.
        IF lv_par_sval_err IS NOT INITIAL.
          IF lv_par_enq = abap_true.
            CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
              EXPORTING
                activity_group = iv_parent_role
              EXCEPTIONS
                OTHERS         = 0.
          ENDIF.
          ev_error  = lv_par_sval_err.
          ev_healed = abap_false.
          RETURN.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDIF.

  IF lv_fix_51 = abap_true OR lv_fix_50 = abap_true OR lv_fix_52 = abap_true.
    ev_healed = abap_true.
    IF iv_test = abap_false.
      DATA(lv_par_has_m1) = xsdbool( line_exists( lt_pt1252_par[ low = '-1' ] )
                                     OR line_exists( lt_pt1252_par[ low = space ] ) ).
      DATA(lv_par_gen) = COND abap_bool( WHEN iv_genprf = abap_true AND lv_par_has_m1 = abap_false
                                         THEN abap_true ELSE abap_false ).

      PERFORM save_and_generate_role USING    iv_parent_role
                                              lt_pt1251_par
                                              lt_pt1250_par
                                              lt_pt1252_par
                                              lv_fix_51
                                              lv_fix_50
                                              lv_fix_52
                                              lv_par_gen
                                              lv_par_enq
                                     CHANGING lv_enq_ok
                                              lv_save_err
                                              lv_gen_subrc
                                              lv_gen_err
                                              lv_prof
                                              lv_color
                                              lv_msg.
      IF lv_enq_ok = abap_false OR lv_save_err IS NOT INITIAL.
        ev_error  = lv_save_err.
        ev_healed = abap_false.
      ELSEIF lv_par_gen = abap_true AND ( lv_gen_subrc <> 0 OR lv_gen_err IS NOT INITIAL ).
        ev_error = |Parent '{ iv_parent_role }' profile warning: { lv_gen_err }|.
      ENDIF.
    ENDIF.
  ELSEIF lv_par_enq = abap_true.
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
      EXPORTING
        activity_group = iv_parent_role
      EXCEPTIONS
        OTHERS         = 0.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form append_parent_heal_note
*&---------------------------------------------------------------------*
FORM append_parent_heal_note USING    iv_parent TYPE agr_name
                                      iv_test   TYPE abap_bool
                                      iv_err    TYPE string
                             CHANGING cv_status TYPE char12
                                      cv_msg    TYPE string.
  IF iv_parent IS INITIAL.
    RETURN.
  ENDIF.
  IF iv_err IS NOT INITIAL.
    IF cv_status = gc_status_ok.
      cv_status = gc_status_warn.
    ENDIF.
    cv_msg = |{ cv_msg } Parent heal warning: { iv_err }|.
  ELSEIF line_exists( gt_healed_parents[ table_line = iv_parent ] ).
    IF iv_test = abap_true.
      cv_msg = |{ cv_msg } [Simulated] Master Role '{ iv_parent }' will also be healed to Standard.|.
    ELSE.
      cv_msg = |{ cv_msg } Master Role '{ iv_parent }' also healed to Standard.|.
    ENDIF.
  ENDIF.
ENDFORM.

*----------------------------------------------------------------------*
* 5. ALV EVENT HANDLER DEFINITION & IMPLEMENTATION
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
          IF column = 'AGR_NAME' AND ls_row-agr_name IS NOT INITIAL.
            SET PARAMETER ID 'AGR' FIELD ls_row-agr_name.
            CALL TRANSACTION 'PFCG' WITH AUTHORITY-CHECK AND SKIP FIRST SCREEN.
          ELSEIF column = 'PARENT_AGR' AND ls_row-parent_agr IS NOT INITIAL.
            SET PARAMETER ID 'AGR' FIELD ls_row-parent_agr.
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
    MESSAGE 'No roles were processed.' TYPE 'S' DISPLAY LIKE 'W'.
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

      DATA(lo_display) = lo_alv->get_display_settings( ).
      lo_display->set_striped_pattern( abap_true ).
      IF rb_m_csv = abap_true.
        lo_display->set_list_header( 'Batch Organizational Levels Update Results' ).
      ELSE.
        lo_display->set_list_header( 'Batch Org Variable ($VARBL) Binding Repair Results' ).
      ENDIF.

      lo_cols = lo_alv->get_columns( ).
      lo_cols->set_optimize( abap_true ).

      lo_col ?= lo_cols->get_column( 'STATUS' ).
      lo_col->set_short_text( 'Status' ).
      lo_col->set_medium_text( 'Status' ).
      lo_col->set_long_text( 'Status' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      lo_col ?= lo_cols->get_column( 'ACTION' ).
      lo_col->set_short_text( 'Action' ).
      lo_col->set_medium_text( 'Action' ).
      lo_col->set_long_text( 'Execution Action' ).

      lo_col ?= lo_cols->get_column( 'AGR_NAME' ).
      lo_col->set_short_text( 'Role ID' ).
      lo_col->set_medium_text( 'Role Name' ).
      lo_col->set_long_text( 'Role Identifier' ).
      lo_col->set_cell_type( if_salv_c_cell_type=>hotspot ).

      lo_col ?= lo_cols->get_column( 'ROLE_DESC' ).
      lo_col->set_short_text( 'Role Desc' ).
      lo_col->set_medium_text( 'Role Description' ).
      lo_col->set_long_text( 'Role Description' ).

      lo_col ?= lo_cols->get_column( 'PARENT_AGR' ).
      lo_col->set_short_text( 'Parent' ).
      lo_col->set_medium_text( 'Parent Master Role' ).
      lo_col->set_long_text( 'Parent Master Role' ).
      lo_col->set_cell_type( if_salv_c_cell_type=>hotspot ).

      lo_col ?= lo_cols->get_column( 'ORGS_FILE_CNT' ).
      lo_col->set_short_text( 'File Orgs' ).
      lo_col->set_medium_text( 'File Org Cnt' ).
      lo_col->set_long_text( 'Org Levels in Input File' ).
      lo_col->set_alignment( if_salv_c_alignment=>right ).
      IF rb_m_fix = abap_true.
        lo_col->set_visible( abap_false ).
      ENDIF.

      lo_col ?= lo_cols->get_column( 'ORGS_UPD_CNT' ).
      lo_col->set_short_text( 'Upd Orgs' ).
      lo_col->set_medium_text( 'Updated Orgs' ).
      lo_col->set_long_text( 'Org Levels Updated from File' ).
      lo_col->set_alignment( if_salv_c_alignment=>right ).
      IF rb_m_fix = abap_true.
        lo_col->set_visible( abap_false ).
      ENDIF.

      lo_col ?= lo_cols->get_column( 'ORGS_RST_CNT' ).
      lo_col->set_short_text( 'Reset Orgs' ).
      lo_col->set_medium_text( 'Reset Unlisted' ).
      lo_col->set_long_text( 'Unlisted Org Levels Reset to Default' ).
      lo_col->set_alignment( if_salv_c_alignment=>right ).
      IF rb_m_fix = abap_true.
        lo_col->set_visible( abap_false ).
      ENDIF.

      lo_col ?= lo_cols->get_column( 'ORGS_KEEP_CNT' ).
      lo_col->set_short_text( 'Keep Orgs' ).
      lo_col->set_medium_text( 'Kept Orgs' ).
      lo_col->set_long_text( 'Org Levels Kept Unchanged' ).
      lo_col->set_alignment( if_salv_c_alignment=>right ).
      IF rb_m_fix = abap_true.
        lo_col->set_visible( abap_false ).
      ENDIF.

      lo_col ?= lo_cols->get_column( 'ORGS_SKIP_CNT' ).
      lo_col->set_short_text( 'Skip Orgs' ).
      lo_col->set_medium_text( 'Skipped Orgs' ).
      lo_col->set_long_text( 'Org Levels Skipped (Not in Role)' ).
      lo_col->set_alignment( if_salv_c_alignment=>right ).
      IF rb_m_fix = abap_true.
        lo_col->set_visible( abap_false ).
      ENDIF.

      lo_col ?= lo_cols->get_column( 'FIXED_FIELDS' ).
      lo_col->set_short_text( 'Fix Flds' ).
      lo_col->set_medium_text( 'Fixed Org Fields' ).
      lo_col->set_long_text( 'Healed Org Fields in AGR_1251' ).
      lo_col->set_alignment( if_salv_c_alignment=>right ).

      lo_col ?= lo_cols->get_column( 'FIXED_AUTHS' ).
      lo_col->set_short_text( 'Fix Auths' ).
      lo_col->set_medium_text( 'Fixed Auth Nodes' ).
      lo_col->set_long_text( 'Healed Auth Nodes in AGR_1250' ).
      lo_col->set_alignment( if_salv_c_alignment=>right ).

      lo_col ?= lo_cols->get_column( 'ORGS_DETAIL' ).
      lo_col->set_short_text( 'Details' ).
      lo_col->set_medium_text( 'Org / Fix Details' ).
      lo_col->set_long_text( 'Summary of Updated / Repaired Details' ).

      lo_col ?= lo_cols->get_column( 'PROFILE' ).
      lo_col->set_short_text( 'Profile' ).
      lo_col->set_medium_text( 'Auth Profile' ).
      lo_col->set_long_text( 'Generated Profile Name' ).

      lo_col ?= lo_cols->get_column( 'MESSAGE' ).
      lo_col->set_short_text( 'Log Msg' ).
      lo_col->set_medium_text( 'Status Message' ).
      lo_col->set_long_text( 'Execution Message / Result Log' ).

      lo_events = lo_alv->get_event( ).
      SET HANDLER lcl_alv_event_handler=>on_link_click FOR lo_events.

      lo_alv->display( ).

    CATCH cx_salv_msg cx_salv_not_found INTO DATA(lx_salv_err).
      DATA(lv_salv_msg) = lx_salv_err->get_text( ).
      MESSAGE |Error displaying ALV grid: { lv_salv_msg }| TYPE 'E'.
  ENDTRY.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form check_org_s_user_val
*&---------------------------------------------------------------------*
FORM check_org_s_user_val USING    iv_varbl       TYPE clike
                                   iv_low         TYPE clike
                                   iv_high        TYPE clike
                                   it_var_objflds TYPE ty_t_var_objfld
                          CHANGING ev_err         TYPE string.
  CLEAR ev_err.

  DATA: lv_varbl    TYPE agval,
        lt_chk_vals TYPE STANDARD TABLE OF agval,
        lv_chk_v    TYPE xuval,
        lv_checked  TYPE abap_bool.

  lv_varbl = iv_varbl.

  IF ( iv_low IS INITIAL OR iv_low = '-1' OR iv_low = '$' )
     AND iv_high IS INITIAL.
    RETURN.
  ENDIF.

  IF iv_low IS NOT INITIAL AND iv_low <> '-1' AND iv_low <> '$'.
    APPEND iv_low TO lt_chk_vals.
  ENDIF.
  IF iv_high IS NOT INITIAL.
    APPEND iv_high TO lt_chk_vals.
  ENDIF.

  LOOP AT lt_chk_vals INTO DATA(lv_raw_v).
    lv_chk_v = COND #( WHEN lv_raw_v = ''' ''' THEN space ELSE lv_raw_v ).
    lv_checked = abap_false.

    LOOP AT it_var_objflds INTO DATA(ls_vof) WHERE varbl = lv_varbl.
      lv_checked = abap_true.
      AUTHORITY-CHECK OBJECT 'S_USER_VAL'
        ID 'OBJECT'     FIELD ls_vof-object
        ID 'AUTH_FIELD' FIELD ls_vof-field
        ID 'AUTH_VALUE' FIELD lv_chk_v.
      IF sy-subrc <> 0.
        ev_err = |Missing S_USER_VAL auth for { lv_varbl } ({ ls_vof-object }/{ ls_vof-field } = '{ lv_raw_v }').|.
        RETURN.
      ENDIF.
    ENDLOOP.

    IF lv_checked = abap_false.
      LOOP AT gt_usorg_map INTO DATA(ls_uo_fb)
        USING KEY by_varbl WHERE varbl = lv_varbl.
        lv_checked = abap_true.
        AUTHORITY-CHECK OBJECT 'S_USER_VAL'
          ID 'OBJECT'     FIELD '*'
          ID 'AUTH_FIELD' FIELD ls_uo_fb-field
          ID 'AUTH_VALUE' FIELD lv_chk_v.
        IF sy-subrc <> 0.
          ev_err = |Missing S_USER_VAL auth for { lv_varbl } (*/{ ls_uo_fb-field } = '{ lv_raw_v }').|.
          RETURN.
        ENDIF.
      ENDLOOP.
      IF lv_checked = abap_false.
        ev_err = |No USORG mapping found to verify S_USER_VAL for { lv_varbl }.|.
        RETURN.
      ENDIF.
    ENDIF.
  ENDLOOP.
ENDFORM.
