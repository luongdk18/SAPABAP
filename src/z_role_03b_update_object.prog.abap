*&---------------------------------------------------------------------*
*& Report Z_ROLE_03B_UPDATE_OBJECT
*&---------------------------------------------------------------------*
*& Purpose: Batch Update Authorization Objects & Fields for PFCG Roles
*& Description:
*&   Reads a CSV (.csv) file containing Authorization Object & Field
*&   values for roles (Role Name, Object-Field, Value).
*&   Strictly validates whether each authorization object and field
*&   actually exists in the role before updating. Does NOT insert or inject
*&   unauthorized/foreign objects from the CSV into the role.
*&   Updates table AGR_1251, regenerates authorization profiles,
*&   and displays detailed results with hotspot links in an interactive ALV grid.
*&
*& File format (CSV .csv):
*&   Col 1: Role Name        (e.g., Z_FI_PERIOD_CONTROL_1000)
*&   Col 2: Object-Field     (e.g., K_CSKS-KOSTL, F_FAGL_SEG-SEGMENT)
*&   Col 3: Value-Low        (e.g., 00000000, 1000*, *)
*&   Col 4: Value-High       (e.g., 00000080, optional)
*&
*& Author: Antigravity AI (SAP Basis Engineering)
*& Package: $TMP (Local Object) or Custom Package
*&---------------------------------------------------------------------*
REPORT z_role_03b_update_object.

*----------------------------------------------------------------------*
* 1. TYPES & DATA DEFINITIONS
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_raw_row,
         col1 TYPE string,
         col2 TYPE string,
         col3 TYPE string,
         col4 TYPE string,
       END OF ty_raw_row.

TYPES: BEGIN OF ty_role_entry,
         agr_name TYPE agr_name,
         item_cnt TYPE i,
       END OF ty_role_entry.

TYPES: BEGIN OF ty_role_auth,
         agr_name TYPE agr_name,
         object   TYPE xuobject,
         field    TYPE xufield,
         val_low  TYPE xuval,
         val_high TYPE xuval,
       END OF ty_role_auth.

TYPES: BEGIN OF ty_obj_fld,
         object TYPE xuobject,
         field  TYPE xufield,
       END OF ty_obj_fld.

TYPES: BEGIN OF ty_invalid_item,
         agr_name TYPE string,
         item     TYPE string,
         reason   TYPE string,
       END OF ty_invalid_item.

TYPES: BEGIN OF ty_alv_result,
         status        TYPE char12,    " Status Icon: @08@ [OK], @09@ [WARN], @0A@ [ERR]
         action        TYPE char12,    " Action: UPDATED / UP-TO-DATE / SIMULATE / ERROR
         agr_name      TYPE agr_name,  " Role ID (Hotspot to PFCG)
         role_desc     TYPE agr_title, " Role Description
         parent_agr    TYPE agr_name,  " Parent Master Role (Hotspot to PFCG)
         auth_file_cnt TYPE i,         " Number of Object-Fields in input file
         auth_upd_cnt  TYPE i,         " Number of Authorization Fields updated
         auth_skip_cnt TYPE i,         " Number of Object-Fields skipped (not in role)
         auth_upd_det  TYPE string,    " Summary of updated Object-Fields
         auth_skip_det TYPE string,    " Summary of skipped Object-Fields
         profile       TYPE xuprofile, " Generated Profile Name
         message       TYPE string,    " Status Message / Execution Log
       END OF ty_alv_result.

CONSTANTS: gc_status_ok   TYPE char12 VALUE '@08@ [OK]',
           gc_status_warn TYPE char12 VALUE '@09@ [WARN]',
           gc_status_err  TYPE char12 VALUE '@0A@ [ERR]'.

DATA: gt_raw_rows        TYPE STANDARD TABLE OF ty_raw_row,
      gt_roles           TYPE STANDARD TABLE OF ty_role_entry,
      gt_role_auths      TYPE SORTED TABLE OF ty_role_auth
                           WITH NON-UNIQUE KEY agr_name object field,
      gt_results         TYPE STANDARD TABLE OF ty_alv_result,
      gt_usorg_map       TYPE SORTED TABLE OF usorg WITH NON-UNIQUE KEY field,
      gt_tactz           TYPE SORTED TABLE OF tactz WITH NON-UNIQUE KEY brobj actvt,
      gt_oversized_roles TYPE STANDARD TABLE OF string,
      gt_invalid_items   TYPE STANDARD TABLE OF ty_invalid_item.

*----------------------------------------------------------------------*
* 2. SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b_file WITH FRAME TITLE b_tit1.
  PARAMETERS: p_file TYPE localfile OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b_file.

SELECTION-SCREEN BEGIN OF BLOCK b_opt WITH FRAME TITLE b_tit2.
  PARAMETERS: p_test   TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_genprf TYPE abap_bool AS CHECKBOX DEFAULT 'X'.
  SELECTION-SCREEN ULINE.
  PARAMETERS: rb_sync  RADIOBUTTON GROUP rmod DEFAULT 'X',
              rb_app   RADIOBUTTON GROUP rmod.
SELECTION-SCREEN END OF BLOCK b_opt.

*----------------------------------------------------------------------*
* 3. INITIALIZATION & SCREEN EVENTS
*----------------------------------------------------------------------*
INITIALIZATION.
  b_tit1 = 'Input CSV File (.csv)'(b01).
  b_tit2 = 'Execution & Profile Generation Options'(b02).

  %_p_file_%_app_%-text   = 'File Path'.
  %_p_test_%_app_%-text   = 'Simulation (Test Run)'.
  %_p_genprf_%_app_%-text = 'Regenerate Auth Profiles'.
  %_rb_sync_%_app_%-text  = 'Two-Way Sync (Replace Values)'.
  %_rb_app_%_app_%-text   = 'Append Only (Keep Existing)'.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  PERFORM f4_file_open CHANGING p_file.

AT SELECTION-SCREEN ON p_file.
  PERFORM validate_filename USING p_file.

*----------------------------------------------------------------------*
* 4. START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.
  PERFORM check_authority.
  PERFORM load_usorg_mapping.
  PERFORM upload_and_parse_file.
  PERFORM aggregate_input_data.
  PERFORM process_object_update.
  PERFORM display_alv_results.

*&---------------------------------------------------------------------*
*& Form load_usorg_mapping
*&---------------------------------------------------------------------*
FORM load_usorg_mapping.
  CLEAR: gt_usorg_map, gt_tactz.
  SELECT * FROM usorg INTO TABLE @gt_usorg_map.
  SELECT * FROM tactz INTO TABLE @gt_tactz.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form f4_file_open
*&---------------------------------------------------------------------*
FORM f4_file_open CHANGING cv_file TYPE localfile.
  DATA: lt_file_table TYPE filetable,
        lv_rc         TYPE i.

  cl_gui_frontend_services=>file_open_dialog(
    EXPORTING
      window_title            = 'Select Role Auth Objects CSV File'
      file_filter             = 'Role Auth Objects CSV (*03b_Auth*.csv)|*03b_Auth*.csv|CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'
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
    MESSAGE |Invalid file '{ lv_fname }'. Expected CSV file (*_03b_Auth_Objects_converted.csv).| TYPE 'E'.
  ENDIF.

  IF NOT ( lv_up CS '03B_AUTH' OR lv_up CS '03B_OBJECT' OR lv_up CS 'AUTH_OBJECT' OR lv_up CS '_OBJECT' )
     OR lv_up CS '01_MASTER' OR lv_up CS '02_DERIVE' OR lv_up CS '03A_ORG'
     OR lv_up CS '03C_ACTIVITY' OR lv_up CS '04_COMPOSITE'
     OR lv_up CS '01_CREATE' OR lv_up CS '02_ASSIGN' OR lv_up = 'OBJECT_LEVELS.CSV'.
    MESSAGE |Invalid file '{ lv_fname }' for Z_ROLE_03B_UPDATE_OBJECT. Expected '*_03b_Auth_Objects_converted.csv'.| TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form check_authority
*&---------------------------------------------------------------------*
FORM check_authority.
  DATA(lv_actvt) = COND activ_auth( WHEN p_test = abap_true THEN '03' ELSE '02' ).

  AUTHORITY-CHECK OBJECT 'S_USER_AGR'
    ID 'ACT_GROUP' DUMMY
    ID 'ACTVT'     FIELD lv_actvt.
  IF sy-subrc <> 0.
    MESSAGE |No authorization for roles (S_USER_AGR, ACTVT { lv_actvt }).| TYPE 'E'.
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
  DATA: lv_file_delim TYPE c LENGTH 1 VALUE ',',
        lv_delim_set  TYPE abap_bool VALUE abap_false.

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
                           CHANGING ls_raw-col1 ls_raw-col2 ls_raw-col3 ls_raw-col4.

    " Validate & skip header row (avoid rejecting real data like M_BEST_EKO-EKORG or Z_FI_GL_MASTER_*)
    DATA(lv_c1_up) = to_upper( ls_raw-col1 ).
    DATA(lv_c2_up) = to_upper( ls_raw-col2 ).
    IF lv_line_idx = 1.
      IF lv_c2_up = 'ORG_LEVEL' OR lv_c2_up = 'ORG LEVEL VARIABLE' OR lv_c2_up = 'ORG_LEVEL_VARIABLE'
         OR lv_c2_up = 'FIELD' OR lv_c2_up = 'ACTIVITY'
         OR lv_c2_up = 'ROLE DESCRIPTION' OR lv_c2_up = 'DERIVED ROLE'
         OR lv_c2_up = 'DERIVED ROLE DESCRIPTION' OR lv_c2_up = 'COMPOSITE ROLE DESCRIPTION'
         OR lv_c1_up = 'MASTER ROLE' OR lv_c1_up = 'MASTER_ROLE'
         OR lv_c1_up = 'COMPOSITE ROLE' OR lv_c1_up = 'COMPOSITE ROLE NAME'
         OR lv_c1_up = 'USERNAME' OR lv_c1_up = 'USER NAME'.
        MESSAGE 'Invalid CSV header for Z_ROLE_03B_UPDATE_OBJECT. Expected: Role, object-field, value-low, value-high.' TYPE 'E'.
      ENDIF.
      IF ( lv_c1_up = 'ROLE' OR lv_c1_up = 'ROLE NAME' OR lv_c1_up = 'ROLE_NAME' )
         AND lv_c2_up CS 'OBJECT'.
        CONTINUE.
      ENDIF.
    ENDIF.
    IF lv_c1_up = 'ROLE' OR lv_c1_up = 'ROLE NAME' OR lv_c1_up = 'ROLE_NAME'
       OR lv_c2_up = 'OBJECT-FIELD' OR lv_c2_up = 'OBJECT_FIELD'.
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
    ev_col3 = lt_tokens[ 3 ].
    DATA(lv_trim_col3) = condense( ev_col3 ).
    IF lv_trim_col3 = ''' ''' OR lv_trim_col3 = '''  '''.
      ev_col3 = ''' '''.
    ELSE.
      ev_col3 = lv_trim_col3.
    ENDIF.
  ENDIF.
  IF lines( lt_tokens ) >= 4.
    ev_col4 = lt_tokens[ 4 ].
    ev_col4 = condense( ev_col4 ).
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form aggregate_input_data
*&---------------------------------------------------------------------*
FORM aggregate_input_data.
  DATA: lv_role_raw     TYPE string,
        lv_role         TYPE agr_name,
        lv_obj_fld      TYPE string,
        lv_obj_str      TYPE string,
        lv_fld_str      TYPE string,
        lv_object       TYPE xuobject,
        lv_field        TYPE xufield,
        lv_low_str      TYPE string,
        lv_high_str     TYPE string,
        lv_low          TYPE xuval,
        lv_high         TYPE xuval,
        lv_vnr_8        TYPE c LENGTH 8,
        lv_alpha_obj_10 TYPE c LENGTH 10,
        ls_role_ent     TYPE ty_role_entry.

  CLEAR: gt_roles, gt_role_auths, gt_oversized_roles, gt_invalid_items.

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

    lv_role     = lv_role_raw.
    lv_obj_fld  = to_upper( condense( ls_raw-col2 ) ).
    lv_low_str  = condense( ls_raw-col3 ).
    lv_high_str = condense( ls_raw-col4 ).

    IF lv_obj_fld IS INITIAL.
      CONTINUE.
    ENDIF.

    " Parse OBJECT-FIELD on STRING first so >10-char typos or malformed rows never fail silently
    CLEAR: lv_obj_str, lv_fld_str, lv_object, lv_field.
    IF lv_obj_fld CS '-'.
      SPLIT lv_obj_fld AT '-' INTO lv_obj_str lv_fld_str.
      lv_obj_str = condense( lv_obj_str ).
      lv_fld_str = condense( lv_fld_str ).
    ELSE.
      READ TABLE gt_invalid_items WITH KEY agr_name = lv_role_raw item = lv_obj_fld TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND VALUE ty_invalid_item(
          agr_name = lv_role_raw
          item     = lv_obj_fld
          reason   = |Malformed Object-Field '{ lv_obj_fld }' (missing '-' separator). Skipped.|
        ) TO gt_invalid_items.
      ENDIF.
      CONTINUE.
    ENDIF.

    IF lv_obj_str IS INITIAL OR lv_fld_str IS INITIAL.
      READ TABLE gt_invalid_items WITH KEY agr_name = lv_role_raw item = lv_obj_fld TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND VALUE ty_invalid_item(
          agr_name = lv_role_raw
          item     = lv_obj_fld
          reason   = |Malformed Object-Field '{ lv_obj_fld }' (empty object or field). Skipped.|
        ) TO gt_invalid_items.
      ENDIF.
      CONTINUE.
    ENDIF.
    IF strlen( lv_obj_str ) > 10 OR strlen( lv_fld_str ) > 10.
      READ TABLE gt_invalid_items WITH KEY agr_name = lv_role_raw item = lv_obj_fld TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND VALUE ty_invalid_item(
          agr_name = lv_role_raw
          item     = lv_obj_fld
          reason   = |Object or field name exceeds SAP 10-character limit: '{ lv_obj_fld }'. Skipped.|
        ) TO gt_invalid_items.
      ENDIF.
      CONTINUE.
    ENDIF.
    lv_object = lv_obj_str.
    lv_field  = lv_fld_str.

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

    " Parse range (LOW - HIGH) if col4 is empty (do NOT split on ':' which breaks paths/URLs/times)
    IF lv_high_str IS INITIAL AND lv_low_str CS ' - '.
      SPLIT lv_low_str AT ' - ' INTO lv_low_str lv_high_str.
      lv_low_str  = condense( lv_low_str ).
      lv_high_str = condense( lv_high_str ).
    ENDIF.

    " Skip genuinely blank CSV value rows (avoid wiping existing values in Sync mode)
    IF lv_low_str IS INITIAL AND lv_high_str IS INITIAL.
      CONTINUE.
    ENDIF.

    " Strict ACTVT validation (matches 03C rules: uppercase, <=2 chars, no wildcard ranges)
    IF lv_field = 'ACTVT'.
      lv_low_str  = to_upper( lv_low_str ).
      lv_high_str = to_upper( lv_high_str ).
      DATA(lv_act_inv_rsn) = ``.
      IF strlen( lv_low_str ) > 2 OR ( lv_high_str IS NOT INITIAL AND strlen( lv_high_str ) > 2 ).
        lv_act_inv_rsn = |ACTVT value exceeds 2 characters for '{ lv_obj_fld }'. Skipped.|.
      ELSEIF lv_high_str IS NOT INITIAL AND ( lv_low_str CA '*+' OR lv_high_str CA '*+' ).
        lv_act_inv_rsn = |Wildcards are not allowed inside ACTVT range for '{ lv_obj_fld }'. Skipped.|.
      ELSEIF lv_high_str IS NOT INITIAL AND lv_low_str > lv_high_str.
        lv_act_inv_rsn = |Invalid ACTVT range '{ lv_low_str }-{ lv_high_str }' (low > high) for '{ lv_obj_fld }'. Skipped.|.
      ENDIF.
      IF lv_act_inv_rsn IS NOT INITIAL.
        DATA(lv_act_key) = |{ lv_obj_fld }={ lv_low_str }-{ lv_high_str }|.
        READ TABLE gt_invalid_items WITH KEY agr_name = lv_role_raw item = lv_act_key TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          APPEND VALUE ty_invalid_item(
            agr_name = lv_role_raw
            item     = lv_act_key
            reason   = lv_act_inv_rsn
          ) TO gt_invalid_items.
        ENDIF.
        CONTINUE.
      ENDIF.
    ENDIF.

    " Apply conversion exit ALPHA on condensed string (avoids CHAR 40 trailing-blank CO bug)
    IF lv_field = 'PS_VERNR'.
      IF lv_low_str IS NOT INITIAL AND strlen( lv_low_str ) <= 8 AND lv_low_str CO '0123456789'.
        lv_vnr_8 = lv_low_str.
        CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
          EXPORTING
            input  = lv_vnr_8
          IMPORTING
            output = lv_vnr_8.
        lv_low_str = lv_vnr_8.
      ENDIF.
      IF lv_high_str IS NOT INITIAL AND strlen( lv_high_str ) <= 8 AND lv_high_str CO '0123456789'.
        lv_vnr_8 = lv_high_str.
        CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
          EXPORTING
            input  = lv_vnr_8
          IMPORTING
            output = lv_vnr_8.
        lv_high_str = lv_vnr_8.
      ENDIF.
    ELSEIF lv_field = 'KOSTL' OR lv_field = 'PRCTR'.
      IF lv_low_str IS NOT INITIAL AND strlen( lv_low_str ) <= 10 AND lv_low_str CO '0123456789'.
        lv_alpha_obj_10 = lv_low_str.
        CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
          EXPORTING
            input  = lv_alpha_obj_10
          IMPORTING
            output = lv_alpha_obj_10.
        lv_low_str = lv_alpha_obj_10.
      ENDIF.
      IF lv_high_str IS NOT INITIAL AND strlen( lv_high_str ) <= 10 AND lv_high_str CO '0123456789'.
        lv_alpha_obj_10 = lv_high_str.
        CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
          EXPORTING
            input  = lv_alpha_obj_10
          IMPORTING
            output = lv_alpha_obj_10.
        lv_high_str = lv_alpha_obj_10.
      ENDIF.
    ENDIF.

    lv_low  = lv_low_str.
    lv_high = lv_high_str.

    " Deduplicate identical (agr_name, object, field, val_low, val_high) CSV rows
    DATA(lv_dup_auth) = abap_false.
    LOOP AT gt_role_auths TRANSPORTING NO FIELDS
      WHERE agr_name = lv_role AND object = lv_object AND field = lv_field
        AND val_low = lv_low AND val_high = lv_high.
      lv_dup_auth = abap_true.
      EXIT.
    ENDLOOP.
    IF lv_dup_auth = abap_true.
      CONTINUE.
    ENDIF.

    " Maintain Role Header count
    READ TABLE gt_roles ASSIGNING FIELD-SYMBOL(<ls_r>) WITH KEY agr_name = lv_role.
    IF sy-subrc = 0.
      <ls_r>-item_cnt = <ls_r>-item_cnt + 1.
    ELSE.
      CLEAR ls_role_ent.
      ls_role_ent-agr_name = lv_role.
      ls_role_ent-item_cnt = 1.
      APPEND ls_role_ent TO gt_roles.
    ENDIF.

    " Insert into sorted role authorization table
    INSERT VALUE ty_role_auth(
      agr_name = lv_role
      object   = lv_object
      field    = lv_field
      val_low  = lv_low
      val_high = lv_high
    ) INTO TABLE gt_role_auths.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form process_object_update
*&---------------------------------------------------------------------*
FORM process_object_update.
  DATA: ls_res        TYPE ty_alv_result,
        lt_pt1250     TYPE STANDARD TABLE OF pt1250,
        lt_pt1251     TYPE STANDARD TABLE OF pt1251,
        lt_bapiret    TYPE STANDARD TABLE OF bapiret2,
        lv_agr_chk    TYPE agr_name,
        lv_parent_chk TYPE agr_name,
        lv_upd_cnt    TYPE i,
        lv_skip_cnt   TYPE i,
        lv_upd_det    TYPE string,
        lv_skip_det   TYPE string,
        lv_mod1250    TYPE abap_bool,
        lv_gen_subrc  TYPE sy-subrc,
        lv_gen_err    TYPE string,
        lv_save_err   TYPE string,
        lv_chk_color  TYPE char10,
        lv_chk_msg    TYPE c LENGTH 255.

  CLEAR gt_results.

  " Report any oversized (>30 char) CSV role names explicitly
  LOOP AT gt_oversized_roles INTO DATA(lv_bad_role).
    CLEAR ls_res.
    ls_res-status   = gc_status_err.
    ls_res-action   = 'ERROR'.
    ls_res-agr_name = lv_bad_role.
    ls_res-message  = |Role name exceeds SAP 30-character limit: '{ lv_bad_role }'.|.
    APPEND ls_res TO gt_results.
  ENDLOOP.

  LOOP AT gt_invalid_items INTO DATA(ls_bad_of).
    CLEAR ls_res.
    ls_res-status   = gc_status_err.
    ls_res-action   = 'ERROR'.
    ls_res-agr_name = ls_bad_of-agr_name.
    ls_res-message  = ls_bad_of-reason.
    APPEND ls_res TO gt_results.
  ENDLOOP.

  LOOP AT gt_roles INTO DATA(ls_role).
    CLEAR: ls_res, lt_pt1250, lt_pt1251, lt_bapiret,
           lv_agr_chk, lv_parent_chk, lv_upd_cnt, lv_skip_cnt,
           lv_upd_det, lv_skip_det, lv_mod1250, lv_gen_subrc,
           lv_gen_err, lv_save_err, lv_chk_color, lv_chk_msg.

    ls_res-agr_name      = ls_role-agr_name.
    ls_res-auth_file_cnt = ls_role-item_cnt.

    " -----------------------------------------------------------------
    " 0. Per-Role Authority Check
    " -----------------------------------------------------------------
    DATA(lv_req_actvt) = COND activ_auth( WHEN p_test = abap_true THEN '03' ELSE '02' ).
    AUTHORITY-CHECK OBJECT 'S_USER_AGR'
      ID 'ACT_GROUP' FIELD ls_role-agr_name
      ID 'ACTVT'     FIELD lv_req_actvt.
    IF sy-subrc <> 0.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = |No authorization for role '{ ls_role-agr_name }' (S_USER_AGR, ACTVT { lv_req_actvt }).|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " 1. Validate Role in SAP
    " -----------------------------------------------------------------
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
      ls_res-message = |Role '{ ls_role-agr_name }' is a Composite Role (no direct auth objects). Skipped.|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    ls_res-parent_agr = lv_parent_chk.

    " Fetch Role Description from AGR_TEXTS
    SELECT SINGLE text FROM agr_texts INTO @ls_res-role_desc
      WHERE agr_name = @ls_role-agr_name AND spras = @sy-langu AND line = '00000'.
    IF sy-subrc <> 0.
      SELECT SINGLE text FROM agr_texts INTO @ls_res-role_desc
        WHERE agr_name = @ls_role-agr_name AND line = '00000'.
    ENDIF.

    " TOCTOU Prevention (HIGH-1): Enqueue role BEFORE reading AGR_1250/1251 in Real Execution
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

    " -----------------------------------------------------------------
    " 2. Read Existing Authorization Data ONCE via Standard PFCG FMs
    "    Strictly check sy-subrc to prevent saving an empty table!
    " -----------------------------------------------------------------
    CALL FUNCTION 'PRGN_1250_READ_AUTH_DATA'
      EXPORTING
        activity_group    = ls_role-agr_name
        no_texts          = 'X'
      TABLES
        auth_data         = lt_pt1250
      EXCEPTIONS
        no_data_available = 1
        OTHERS            = 2.

    IF sy-subrc = 2.
      IF lv_enq_held = abap_true.
        CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
          EXPORTING
            activity_group = ls_role-agr_name
          EXCEPTIONS
            OTHERS         = 0.
      ENDIF.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = |Failed to read AGR_1250 auth data for role '{ ls_role-agr_name }'.|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    CALL FUNCTION 'PRGN_1251_READ_FIELD_VALUES'
      EXPORTING
        activity_group    = ls_role-agr_name
      TABLES
        field_values      = lt_pt1251
      EXCEPTIONS
        no_data_available = 1
        OTHERS            = 2.

    IF sy-subrc = 2.
      IF lv_enq_held = abap_true.
        CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
          EXPORTING
            activity_group = ls_role-agr_name
          EXCEPTIONS
            OTHERS         = 0.
      ENDIF.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = |Failed to read AGR_1251 field values for role '{ ls_role-agr_name }'.|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " Assemble distinct (object, field) pairs from input file for this role
    DATA: lt_distinct_of TYPE STANDARD TABLE OF ty_obj_fld.
    CLEAR lt_distinct_of.

    LOOP AT gt_role_auths INTO DATA(ls_raw_auth) WHERE agr_name = ls_role-agr_name.
      READ TABLE lt_distinct_of WITH KEY object = ls_raw_auth-object field = ls_raw_auth-field TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND VALUE ty_obj_fld( object = ls_raw_auth-object field = ls_raw_auth-field ) TO lt_distinct_of.
      ENDIF.
    ENDLOOP.

    " -----------------------------------------------------------------
    " 3. Validate & Apply Changes Per (OBJECT, AUTH, FIELD) Instance
    "    Strict Rules:
    "      - Never inject foreign objects/fields not already in role
    "      - Strictly protect Org Level fields (USORG)
    "      - Validate ACTVT against TACTZ and enforce S_USER_VAL
    "      - Only rewrite (object, auth, field) instances that actually changed
    " -----------------------------------------------------------------
    DATA(lv_sval_abort) = abap_false.
    DATA(lv_sval_msg)   = ``.

    LOOP AT lt_distinct_of INTO DATA(ls_of).
      IF line_exists( gt_usorg_map[ field = ls_of-field ] ).
        lv_skip_cnt = lv_skip_cnt + 1.
        IF lv_skip_det IS INITIAL.
          lv_skip_det = |{ ls_of-object }-{ ls_of-field }(OrgLvl)|.
        ELSEIF strlen( lv_skip_det ) < 150.
          lv_skip_det = |{ lv_skip_det }, { ls_of-object }-{ ls_of-field }(OrgLvl)|.
        ENDIF.
        CONTINUE.
      ENDIF.

      " Find all distinct ACTIVE (object, auth) instances containing this field
      DATA: lt_auth_ids TYPE STANDARD TABLE OF xuauth.
      CLEAR lt_auth_ids.
      LOOP AT lt_pt1251 INTO DATA(ls_p_chk)
        WHERE object = ls_of-object AND field = ls_of-field
          AND deleted = space AND copied <> 'I'.
        DATA(lv_hdr_active) = abap_false.
        LOOP AT lt_pt1250 TRANSPORTING NO FIELDS
          WHERE object = ls_p_chk-object AND auth = ls_p_chk-auth
            AND deleted = space AND copied <> 'I'.
          lv_hdr_active = abap_true.
          EXIT.
        ENDLOOP.
        IF lv_hdr_active = abap_true.
          READ TABLE lt_auth_ids WITH KEY table_line = ls_p_chk-auth TRANSPORTING NO FIELDS.
          IF sy-subrc <> 0.
            APPEND ls_p_chk-auth TO lt_auth_ids.
          ENDIF.
        ENDIF.
      ENDLOOP.

      IF lt_auth_ids IS INITIAL.
        lv_skip_cnt = lv_skip_cnt + 1.
        IF lv_skip_det IS INITIAL.
          lv_skip_det = |{ ls_of-object }-{ ls_of-field }|.
        ELSEIF strlen( lv_skip_det ) < 150.
          lv_skip_det = |{ lv_skip_det }, { ls_of-object }-{ ls_of-field }|.
        ENDIF.
        CONTINUE.
      ENDIF.

      " Validate / expand ACTVT values against SAP TACTZ for this object (MEDIUM-3)
      DATA lt_obj_csv_vals TYPE STANDARD TABLE OF ty_role_auth.
      CLEAR lt_obj_csv_vals.
      IF ls_of-field = 'ACTVT' AND line_exists( gt_tactz[ brobj = ls_of-object ] ).
        LOOP AT gt_role_auths INTO DATA(ls_tz_in)
          WHERE agr_name = ls_role-agr_name AND object = ls_of-object AND field = 'ACTVT'.
          DATA(lv_tz_row_cnt) = 0.
          IF ls_tz_in-val_low = '*' AND ls_tz_in-val_high IS INITIAL.
            READ TABLE lt_obj_csv_vals WITH KEY val_low = '*' val_high = space TRANSPORTING NO FIELDS.
            IF sy-subrc <> 0.
              APPEND ls_tz_in TO lt_obj_csv_vals.
            ENDIF.
            lv_tz_row_cnt = 1.
          ELSEIF ls_tz_in-val_high IS NOT INITIAL.
            LOOP AT gt_tactz INTO DATA(ls_tz_r)
              WHERE brobj = ls_of-object
                AND actvt >= ls_tz_in-val_low
                AND actvt <= ls_tz_in-val_high.
              lv_tz_row_cnt = lv_tz_row_cnt + 1.
              READ TABLE lt_obj_csv_vals WITH KEY val_low = ls_tz_r-actvt val_high = space TRANSPORTING NO FIELDS.
              IF sy-subrc <> 0.
                APPEND VALUE ty_role_auth(
                  agr_name = ls_tz_in-agr_name
                  object   = ls_tz_in-object
                  field    = ls_tz_in-field
                  val_low  = ls_tz_r-actvt
                  val_high = space
                ) TO lt_obj_csv_vals.
              ENDIF.
            ENDLOOP.
          ELSEIF ls_tz_in-val_low CA '*+'.
            DATA(lv_tz_pat) = condense( CONV string( ls_tz_in-val_low ) ).
            IF lv_tz_pat CO 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789*+'.
              REPLACE ALL OCCURRENCES OF '+' IN lv_tz_pat WITH '.'.
              REPLACE ALL OCCURRENCES OF '*' IN lv_tz_pat WITH '.*'.
              lv_tz_pat = '\A' && lv_tz_pat && '\z'.
              LOOP AT gt_tactz INTO ls_tz_r WHERE brobj = ls_of-object.
                FIND PCRE lv_tz_pat IN ls_tz_r-actvt RESPECTING CASE.
                IF sy-subrc = 0.
                  lv_tz_row_cnt = lv_tz_row_cnt + 1.
                  READ TABLE lt_obj_csv_vals WITH KEY val_low = ls_tz_r-actvt val_high = space TRANSPORTING NO FIELDS.
                  IF sy-subrc <> 0.
                    APPEND VALUE ty_role_auth(
                      agr_name = ls_tz_in-agr_name
                      object   = ls_tz_in-object
                      field    = ls_tz_in-field
                      val_low  = ls_tz_r-actvt
                      val_high = space
                    ) TO lt_obj_csv_vals.
                  ENDIF.
                ENDIF.
              ENDLOOP.
            ENDIF.
          ELSE.
            DATA(lv_tz_str) = condense( CONV string( ls_tz_in-val_low ) ).
            IF strlen( lv_tz_str ) <= 2
               AND line_exists( gt_tactz[ brobj = ls_of-object actvt = ls_tz_in-val_low ] ).
              lv_tz_row_cnt = 1.
              READ TABLE lt_obj_csv_vals WITH KEY val_low = ls_tz_in-val_low val_high = space TRANSPORTING NO FIELDS.
              IF sy-subrc <> 0.
                APPEND ls_tz_in TO lt_obj_csv_vals.
              ENDIF.
            ENDIF.
          ENDIF.
          IF lv_tz_row_cnt = 0.
            lv_skip_cnt = lv_skip_cnt + 1.
            IF lv_skip_det IS INITIAL.
              lv_skip_det = |{ ls_of-object }-ACTVT={ ls_tz_in-val_low }(TACTZ)|.
            ELSEIF strlen( lv_skip_det ) < 150.
              lv_skip_det = |{ lv_skip_det }, { ls_of-object }-ACTVT={ ls_tz_in-val_low }(TACTZ)|.
            ENDIF.
          ENDIF.
        ENDLOOP.
        IF lt_obj_csv_vals IS INITIAL.
          CONTINUE.
        ENDIF.
      ELSE.
        LOOP AT gt_role_auths INTO DATA(ls_n_in)
          WHERE agr_name = ls_role-agr_name AND object = ls_of-object AND field = ls_of-field.
          APPEND ls_n_in TO lt_obj_csv_vals.
        ENDLOOP.
      ENDIF.

      DATA(lv_any_inst_chg) = abap_false.
      DATA: lv_disp_val TYPE string.
      CLEAR lv_disp_val.

      LOOP AT lt_auth_ids INTO DATA(lv_auth_id).
        DATA: lt_cur_inst    TYPE STANDARD TABLE OF pt1251,
              lt_target_vals TYPE STANDARD TABLE OF ty_role_auth.
        CLEAR: lt_cur_inst, lt_target_vals.

        LOOP AT lt_pt1251 INTO DATA(ls_ci)
          WHERE object = ls_of-object AND auth = lv_auth_id AND field = ls_of-field
            AND deleted = space AND copied <> 'I'.
          APPEND ls_ci TO lt_cur_inst.
        ENDLOOP.

        IF rb_app = abap_true.
          LOOP AT lt_cur_inst INTO DATA(ls_keep_p)
            WHERE low IS NOT INITIAL OR high IS NOT INITIAL.
            READ TABLE lt_target_vals WITH KEY val_low = ls_keep_p-low val_high = ls_keep_p-high TRANSPORTING NO FIELDS.
            IF sy-subrc <> 0.
              APPEND VALUE ty_role_auth(
                agr_name = ls_role-agr_name
                object   = ls_of-object
                field    = ls_of-field
                val_low  = ls_keep_p-low
                val_high = ls_keep_p-high
              ) TO lt_target_vals.
            ENDIF.
          ENDLOOP.
        ENDIF.

        LOOP AT lt_obj_csv_vals INTO DATA(ls_new).
          READ TABLE lt_target_vals WITH KEY val_low = ls_new-val_low val_high = ls_new-val_high TRANSPORTING NO FIELDS.
          IF sy-subrc <> 0.
            APPEND ls_new TO lt_target_vals.
          ENDIF.
        ENDLOOP.

        " Symmetric per-instance comparison
        DATA(lv_inst_chg) = abap_false.
        IF lines( lt_cur_inst ) <> lines( lt_target_vals ).
          lv_inst_chg = abap_true.
        ELSE.
          LOOP AT lt_target_vals INTO DATA(ls_tv).
            READ TABLE lt_cur_inst WITH KEY low = ls_tv-val_low high = ls_tv-val_high TRANSPORTING NO FIELDS.
            IF sy-subrc <> 0.
              lv_inst_chg = abap_true.
              EXIT.
            ENDIF.
          ENDLOOP.
        ENDIF.

        IF lv_inst_chg = abap_true.
          " S_USER_VAL check for any newly added authorization value(s)
          LOOP AT lt_target_vals INTO DATA(ls_sv_chk).
            READ TABLE lt_cur_inst WITH KEY low = ls_sv_chk-val_low high = ls_sv_chk-val_high
              TRANSPORTING NO FIELDS.
            IF sy-subrc = 0.
              CONTINUE.
            ENDIF.
            DATA(lv_sv_lo) = COND xuval( WHEN ls_sv_chk-val_low = ''' ''' THEN space ELSE ls_sv_chk-val_low ).
            AUTHORITY-CHECK OBJECT 'S_USER_VAL'
              ID 'OBJECT'     FIELD ls_of-object
              ID 'AUTH_FIELD' FIELD ls_of-field
              ID 'AUTH_VALUE' FIELD lv_sv_lo.
            IF sy-subrc <> 0.
              lv_sval_abort = abap_true.
              lv_sval_msg   = |No authorization (S_USER_VAL) for { ls_of-object }-{ ls_of-field } = '{ ls_sv_chk-val_low }'.|.
              EXIT.
            ENDIF.
            IF ls_sv_chk-val_high IS NOT INITIAL.
              DATA(lv_sv_hi) = COND xuval( WHEN ls_sv_chk-val_high = ''' ''' THEN space ELSE ls_sv_chk-val_high ).
              AUTHORITY-CHECK OBJECT 'S_USER_VAL'
                ID 'OBJECT'     FIELD ls_of-object
                ID 'AUTH_FIELD' FIELD ls_of-field
                ID 'AUTH_VALUE' FIELD lv_sv_hi.
              IF sy-subrc <> 0.
                lv_sval_abort = abap_true.
                lv_sval_msg   = |No authorization (S_USER_VAL) for { ls_of-object }-{ ls_of-field } = '{ ls_sv_chk-val_high }'.|.
                EXIT.
              ENDIF.
            ENDIF.
          ENDLOOP.
          IF lv_sval_abort = abap_true.
            EXIT.
          ENDIF.

          lv_any_inst_chg = abap_true.
          READ TABLE lt_target_vals INTO DATA(ls_first_nv) INDEX 1.
          IF sy-subrc = 0 AND lv_disp_val IS INITIAL.
            lv_disp_val = COND #( WHEN ls_first_nv-val_high IS NOT INITIAL
                                  THEN |{ ls_first_nv-val_low }-{ ls_first_nv-val_high }|
                                  ELSE |{ ls_first_nv-val_low }| ).
          ENDIF.

          " Apply in memory only for this changed (object, auth, field) instance
          " TPR_ST_MOD: overwriting populated Standard ('S') or Changed ('M') sets 'M'; filling open sets 'G'
          READ TABLE lt_cur_inst INTO DATA(ls_tmpl) INDEX 1.
          IF sy-subrc = 0.
            DATA(lv_overrode_std) = abap_false.
            LOOP AT lt_cur_inst INTO DATA(ls_chk_mod).
              IF ( ls_chk_mod-modified = 'S' AND ( ls_chk_mod-low IS NOT INITIAL OR ls_chk_mod-high IS NOT INITIAL ) )
                 OR ls_chk_mod-modified = 'M'.
                lv_overrode_std = abap_true.
                EXIT.
              ENDIF.
            ENDLOOP.

            DATA(lv_fld_mod) = COND char1( WHEN lv_overrode_std = abap_true THEN 'M' ELSE 'G' ).
            LOOP AT lt_pt1250 ASSIGNING FIELD-SYMBOL(<ls_a50>)
              WHERE object = ls_of-object AND auth = lv_auth_id
                AND deleted = space AND copied <> 'I'.
              IF <ls_a50>-modified = 'U'.
                lv_fld_mod = 'U'.
              ELSEIF lv_overrode_std = abap_true.
                lv_fld_mod = 'M'.
                IF <ls_a50>-modified <> 'M'.
                  <ls_a50>-modified = 'M'.
                  <ls_a50>-neu      = COND #( WHEN <ls_a50>-neu IS NOT INITIAL THEN <ls_a50>-neu ELSE 'O' ).
                  lv_mod1250        = abap_true.
                ENDIF.
              ELSE.
                lv_fld_mod = 'G'.
                IF <ls_a50>-modified = 'S'.
                  <ls_a50>-modified = 'G'.
                  <ls_a50>-neu      = COND #( WHEN <ls_a50>-neu IS NOT INITIAL THEN <ls_a50>-neu ELSE 'O' ).
                  lv_mod1250        = abap_true.
                ENDIF.
              ENDIF.
              EXIT.
            ENDLOOP.

            DELETE lt_pt1251 WHERE object = ls_of-object AND auth = lv_auth_id
                               AND field = ls_of-field
                               AND deleted = space AND copied <> 'I'.

            LOOP AT lt_target_vals INTO DATA(ls_fv).
              DATA(ls_new_51) = ls_tmpl.
              ls_new_51-low      = ls_fv-val_low.
              ls_new_51-high     = ls_fv-val_high.
              READ TABLE lt_cur_inst INTO DATA(ls_orig_v)
                WITH KEY low = ls_fv-val_low high = ls_fv-val_high.
              IF sy-subrc = 0 AND ls_orig_v-modified IS NOT INITIAL.
                ls_new_51-modified = ls_orig_v-modified.
                ls_new_51-neu      = COND #( WHEN ls_orig_v-neu IS NOT INITIAL THEN ls_orig_v-neu ELSE 'O' ).
              ELSE.
                ls_new_51-modified = lv_fld_mod.
                ls_new_51-neu      = COND #( WHEN ls_tmpl-neu IS NOT INITIAL THEN ls_tmpl-neu ELSE 'O' ).
              ENDIF.
              APPEND ls_new_51 TO lt_pt1251.
            ENDLOOP.
          ENDIF.
        ENDIF.
      ENDLOOP.
      IF lv_sval_abort = abap_true.
        EXIT.
      ENDIF.

      IF lv_any_inst_chg = abap_true.
        lv_upd_cnt = lv_upd_cnt + 1.
        IF lv_upd_det IS INITIAL.
          lv_upd_det = |{ ls_of-object }-{ ls_of-field }={ lv_disp_val }|.
        ELSEIF strlen( lv_upd_det ) < 150.
          lv_upd_det = |{ lv_upd_det }, { ls_of-object }-{ ls_of-field }={ lv_disp_val }|.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF lv_sval_abort = abap_true.
      IF lv_enq_held = abap_true.
        CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
          EXPORTING
            activity_group = ls_role-agr_name
          EXCEPTIONS
            OTHERS         = 0.
      ENDIF.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = lv_sval_msg.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    ls_res-auth_upd_cnt  = lv_upd_cnt.
    ls_res-auth_skip_cnt = lv_skip_cnt.
    ls_res-auth_upd_det  = lv_upd_det.
    ls_res-auth_skip_det = lv_skip_det.

    " -----------------------------------------------------------------
    " 4. Simulation Mode
    " -----------------------------------------------------------------
    IF p_test = abap_true.
      SELECT SINGLE profile FROM agr_1016 INTO @ls_res-profile
        WHERE agr_name = @ls_role-agr_name.

      IF lv_upd_cnt > 0.
        ls_res-status  = gc_status_ok.
        ls_res-action  = 'SIMULATE'.
        ls_res-message = |[Simulated] { lv_upd_cnt } auth field(s) will be updated.|.
      ELSE.
        ls_res-status  = COND #( WHEN lv_skip_cnt > 0 THEN gc_status_warn ELSE gc_status_ok ).
        ls_res-action  = 'UP-TO-DATE'.
        ls_res-message = |[Simulated] All matching auth fields are already up-to-date.|.
      ENDIF.

      IF lv_skip_cnt > 0.
        IF ls_res-status = gc_status_ok.
          ls_res-status = gc_status_warn.
        ENDIF.
        ls_res-message = |{ ls_res-message } { lv_skip_cnt } item(s) in CSV skipped (not in role / OrgLvl / TACTZ).|.
      ENDIF.

      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " 5. Real Run Execution (Enqueue held from Step 2 -> Save -> Timestamp -> Commit -> Dequeue -> Gen)
    " -----------------------------------------------------------------
    IF lv_upd_cnt > 0.
      IF lv_enq_held = abap_false.
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
      ENDIF.

      CALL FUNCTION 'PRGN_CLEAR_BUFFER'.

      CALL FUNCTION 'PRGN_1251_SAVE_FIELD_VALUES'
        EXPORTING
          activity_group = ls_role-agr_name
        TABLES
          field_values   = lt_pt1251
        EXCEPTIONS
          OTHERS         = 1.
      IF sy-subrc <> 0.
        lv_save_err = |PRGN_1251_SAVE_FIELD_VALUES failed (sy-subrc = { sy-subrc }).|.
      ENDIF.

      IF lv_save_err IS INITIAL AND lv_mod1250 = abap_true.
        CALL FUNCTION 'PRGN_1250_SAVE_AUTH_DATA'
          EXPORTING
            activity_group = ls_role-agr_name
          TABLES
            auth_data      = lt_pt1250
          EXCEPTIONS
            OTHERS         = 1.
        IF sy-subrc <> 0.
          lv_save_err = |PRGN_1250_SAVE_AUTH_DATA failed (sy-subrc = { sy-subrc }).|.
        ENDIF.
      ENDIF.

      IF lv_save_err IS INITIAL.
        CALL FUNCTION 'PRGN_UPDATE_DATABASE'
          EXCEPTIONS
            OTHERS = 1.
        IF sy-subrc <> 0.
          lv_save_err = |PRGN_UPDATE_DATABASE failed (sy-subrc = { sy-subrc }).|.
        ENDIF.
      ENDIF.

      IF lv_save_err IS INITIAL.
        CALL FUNCTION 'PRGN_SET_ACTGROUP_TIMESTAMP'
          EXPORTING
            activity_group = ls_role-agr_name
            no_commit      = 'X'
          EXCEPTIONS
            OTHERS         = 0.
        COMMIT WORK AND WAIT.
      ELSE.
        ROLLBACK WORK.
        CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
      ENDIF.

      " Crucial: Always DEQUEUE before SUPRN_DARK_MANIPULATE_PROFILE
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
        EXPORTING
          activity_group = ls_role-agr_name
        EXCEPTIONS
          OTHERS         = 0.

      IF lv_save_err IS NOT INITIAL.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'ERROR'.
        ls_res-message = lv_save_err.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.

      " Skip profile generation on Master/non-derived roles with unmaintained '-1'/blank orgs (avoids false RED)
      DATA(lv_skip_m_gen) = abap_false.
      IF p_genprf = abap_true AND lv_parent_chk IS INITIAL.
        SELECT SINGLE @abap_true FROM agr_1252
          WHERE agr_name = @ls_role-agr_name AND ( low = '-1' OR low = @space )
          INTO @lv_skip_m_gen.
      ENDIF.
      DATA(lv_eff_genprf) = COND abap_bool( WHEN p_genprf = abap_true AND lv_skip_m_gen = abap_false
                                            THEN abap_true ELSE abap_false ).

      " Regenerate Authorization Profile (only check LED when lv_eff_genprf = 'X')
      IF lv_eff_genprf = abap_true.
        CLEAR lt_bapiret.
        CALL FUNCTION 'SUPRN_DARK_MANIPULATE_PROFILE'
          EXPORTING
            activity_group        = ls_role-agr_name
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

        LOOP AT lt_bapiret INTO DATA(ls_ret) WHERE type CA 'EAX'.
          IF lv_gen_err IS INITIAL.
            lv_gen_err = ls_ret-message.
          ELSE.
            lv_gen_err = |{ lv_gen_err }; { ls_ret-message }|.
          ENDIF.
        ENDLOOP.
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

        SELECT SINGLE profile FROM agr_1016 INTO @ls_res-profile
          WHERE agr_name = @ls_role-agr_name.

        CALL FUNCTION 'PRGN_CHECK_PROFILE_STATUS'
          EXPORTING
            activity_group = ls_role-agr_name
          IMPORTING
            message_text   = lv_chk_msg
            led_color      = lv_chk_color
          EXCEPTIONS
            OTHERS         = 1.

        IF lv_chk_color = 'RED'.
          ls_res-status  = gc_status_err.
          ls_res-action  = 'WARNING'.
          ls_res-message = |Updated { lv_upd_cnt } auth field(s). Profile Red: { lv_gen_err } { lv_chk_msg }|.
        ELSEIF lv_gen_subrc <> 0 OR lv_gen_err IS NOT INITIAL.
          ls_res-status  = gc_status_warn.
          ls_res-action  = 'UPDATED'.
          ls_res-message = |Updated { lv_upd_cnt } auth field(s). Profile warning: { lv_gen_err } { lv_chk_msg }|.
        ELSEIF lv_chk_color = 'GREEN'.
          ls_res-status  = gc_status_ok.
          ls_res-action  = 'UPDATED'.
          ls_res-message = |Updated { lv_upd_cnt } auth field(s). Profile '{ ls_res-profile }' is GREEN.|.
        ELSEIF lv_chk_color = 'YELLOW'.
          ls_res-status  = gc_status_warn.
          ls_res-action  = 'UPDATED'.
          ls_res-message = |Updated { lv_upd_cnt } auth field(s). Profile Yellow: { lv_chk_msg }|.
        ELSE.
          ls_res-status  = gc_status_ok.
          ls_res-action  = 'UPDATED'.
          ls_res-message = |Updated { lv_upd_cnt } auth field(s). Profile status: { lv_chk_color } { lv_chk_msg }|.
        ENDIF.
      ELSE.
        SELECT SINGLE profile FROM agr_1016 INTO @ls_res-profile
          WHERE agr_name = @ls_role-agr_name.
        ls_res-status  = gc_status_ok.
        ls_res-action  = 'UPDATED'.
        IF lv_skip_m_gen = abap_true AND p_genprf = abap_true.
          ls_res-message = |Updated { lv_upd_cnt } auth field(s) on Master Role (unmaintained '-1' orgs: profile generation skipped).|.
        ELSE.
          ls_res-message = |Updated { lv_upd_cnt } auth field(s). Profile regeneration skipped.|.
        ENDIF.
      ENDIF.

      IF lv_skip_cnt > 0.
        IF ls_res-status = gc_status_ok.
          ls_res-status = gc_status_warn.
        ENDIF.
        ls_res-message = |{ ls_res-message } { lv_skip_cnt } item(s) in CSV skipped (not in role / OrgLvl / TACTZ).|.
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
      ls_res-message = |All matching auth fields in role are already up-to-date.|.
      IF lv_skip_cnt > 0.
        ls_res-message = |{ ls_res-message } { lv_skip_cnt } item(s) in CSV skipped (not in role / OrgLvl / TACTZ).|.
      ENDIF.
    ENDIF.

    APPEND ls_res TO gt_results.
  ENDLOOP.
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

      " Enable Standard ALV Functions
      lo_functions = lo_alv->get_functions( ).
      lo_functions->set_all( abap_true ).

      " Enable Zebra Striping
      DATA(lo_display) = lo_alv->get_display_settings( ).
      lo_display->set_striped_pattern( abap_true ).
      lo_display->set_list_header( 'Batch Authorization Objects Update Execution Results' ).

      " Format Columns
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

      " Format Column: AGR_NAME (Hotspot to PFCG)
      lo_col ?= lo_cols->get_column( 'AGR_NAME' ).
      lo_col->set_short_text( 'Role ID' ).
      lo_col->set_medium_text( 'Role Name' ).
      lo_col->set_long_text( 'Role Identifier' ).
      lo_col->set_cell_type( if_salv_c_cell_type=>hotspot ).

      " Format Column: ROLE_DESC
      lo_col ?= lo_cols->get_column( 'ROLE_DESC' ).
      lo_col->set_short_text( 'Role Desc' ).
      lo_col->set_medium_text( 'Role Description' ).
      lo_col->set_long_text( 'Role Description' ).

      " Format Column: PARENT_AGR (Hotspot to PFCG)
      lo_col ?= lo_cols->get_column( 'PARENT_AGR' ).
      lo_col->set_short_text( 'Parent' ).
      lo_col->set_medium_text( 'Parent Master Role' ).
      lo_col->set_long_text( 'Parent Master Role' ).
      lo_col->set_cell_type( if_salv_c_cell_type=>hotspot ).

      " Format Column: AUTH_FILE_CNT
      lo_col ?= lo_cols->get_column( 'AUTH_FILE_CNT' ).
      lo_col->set_short_text( 'File Items' ).
      lo_col->set_medium_text( 'File Items Cnt' ).
      lo_col->set_long_text( 'Object-Fields in Input File' ).
      lo_col->set_alignment( if_salv_c_alignment=>right ).

      " Format Column: AUTH_UPD_CNT
      lo_col ?= lo_cols->get_column( 'AUTH_UPD_CNT' ).
      lo_col->set_short_text( 'Upd Fields' ).
      lo_col->set_medium_text( 'Updated Fields' ).
      lo_col->set_long_text( 'Fields Updated in Role' ).
      lo_col->set_alignment( if_salv_c_alignment=>right ).

      " Format Column: AUTH_SKIP_CNT
      lo_col ?= lo_cols->get_column( 'AUTH_SKIP_CNT' ).
      lo_col->set_short_text( 'Skip Items' ).
      lo_col->set_medium_text( 'Skipped Items' ).
      lo_col->set_long_text( 'Skipped (Not in Role)' ).
      lo_col->set_alignment( if_salv_c_alignment=>right ).

      " Format Column: AUTH_UPD_DET
      lo_col ?= lo_cols->get_column( 'AUTH_UPD_DET' ).
      lo_col->set_short_text( 'Upd Det' ).
      lo_col->set_medium_text( 'Updated Details' ).
      lo_col->set_long_text( 'Summary of Updated Object-Fields' ).

      " Format Column: AUTH_SKIP_DET
      lo_col ?= lo_cols->get_column( 'AUTH_SKIP_DET' ).
      lo_col->set_short_text( 'Skip Det' ).
      lo_col->set_medium_text( 'Skipped Details' ).
      lo_col->set_long_text( 'Summary of Skipped Object-Fields' ).

      " Format Column: PROFILE
      lo_col ?= lo_cols->get_column( 'PROFILE' ).
      lo_col->set_short_text( 'Profile' ).
      lo_col->set_medium_text( 'Auth Profile' ).
      lo_col->set_long_text( 'Generated Profile Name' ).

      " Format Column: MESSAGE
      lo_col ?= lo_cols->get_column( 'MESSAGE' ).
      lo_col->set_short_text( 'Log Msg' ).
      lo_col->set_medium_text( 'Status Message' ).
      lo_col->set_long_text( 'Execution Message / Details' ).

      " Register Hotspot Event Handler
      lo_events = lo_alv->get_event( ).
      SET HANDLER lcl_alv_event_handler=>on_link_click FOR lo_events.

      " Display ALV Grid
      lo_alv->display( ).

    CATCH cx_salv_msg cx_salv_not_found INTO DATA(lx_salv_err).
      MESSAGE lx_salv_err->get_text( ) TYPE 'E'.
  ENDTRY.
ENDFORM.
