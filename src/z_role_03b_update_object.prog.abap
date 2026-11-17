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

TABLES: agr_define, agr_texts, agr_1250, agr_1251, agr_1016, usorg.

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

DATA: gt_raw_rows   TYPE STANDARD TABLE OF ty_raw_row,
      gt_roles      TYPE STANDARD TABLE OF ty_role_entry,
      gt_role_auths TYPE STANDARD TABLE OF ty_role_auth,
      gt_results    TYPE STANDARD TABLE OF ty_alv_result,
      gt_usorg_map  TYPE HASHED TABLE OF usorg WITH UNIQUE KEY field.

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
  CLEAR gt_usorg_map.
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
  IF p_test = abap_true.
    RETURN.
  ENDIF.

  AUTHORITY-CHECK OBJECT 'S_USER_AGR'
    ID 'ACT_GROUP' DUMMY
    ID 'ACTVT'     FIELD '02'.
  IF sy-subrc <> 0.
    MESSAGE 'No authorization to change roles (S_USER_AGR, ACTVT 02).' TYPE 'E'.
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
    CLEAR ls_raw.
    PERFORM parse_csv_line USING lv_line
                           CHANGING ls_raw-col1 ls_raw-col2 ls_raw-col3 ls_raw-col4.

    " Validate & skip header row
    DATA(lv_c1_up) = to_upper( ls_raw-col1 ).
    DATA(lv_c2_up) = to_upper( ls_raw-col2 ).
    IF lv_line_idx = 1.
      IF lv_c2_up CS 'ORG' OR lv_c2_up = 'FIELD' OR lv_c2_up = 'ACTIVITY'
         OR lv_c1_up CS 'MASTER' OR lv_c1_up CS 'COMPOSITE' OR lv_c1_up CS 'USER'
         OR lv_c2_up CS 'DESC'.
        MESSAGE 'Invalid CSV header for Z_ROLE_03B_UPDATE_OBJECT. Expected: Role, object-field, value-low, value-high.' TYPE 'E'.
      ENDIF.
      IF lv_c1_up CS 'ROLE' AND lv_c2_up CS 'OBJECT'.
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
*& Form parse_csv_line
*&---------------------------------------------------------------------*
FORM parse_csv_line USING    iv_line TYPE string
                    CHANGING ev_col1 TYPE string
                             ev_col2 TYPE string
                             ev_col3 TYPE string
                             ev_col4 TYPE string.
  DATA: lt_tokens TYPE STANDARD TABLE OF string,
        lv_len    TYPE i,
        lv_in_q   TYPE abap_bool VALUE abap_false,
        lv_cur    TYPE string,
        lv_char   TYPE string.

  CLEAR: ev_col1, ev_col2, ev_col3, ev_col4.

  lv_len = strlen( iv_line ).
  DO lv_len TIMES.
    DATA(lv_idx) = sy-index - 1.
    lv_char = substring( val = iv_line off = lv_idx len = 1 ).

    IF lv_char = '"'.
      IF lv_in_q = abap_true.
        lv_in_q = abap_false.
      ELSE.
        lv_in_q = abap_true.
      ENDIF.
    ELSEIF ( lv_char = ',' OR lv_char = ';' OR lv_char = cl_abap_char_utilities=>horizontal_tab ) AND lv_in_q = abap_false.
      APPEND lv_cur TO lt_tokens.
      CLEAR lv_cur.
    ELSE.
      lv_cur = lv_cur && lv_char.
    ENDIF.
  ENDDO.
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
  DATA: lv_role     TYPE agr_name,
        lv_obj_fld  TYPE string,
        lv_object   TYPE xuobject,
        lv_field    TYPE xufield,
        lv_low      TYPE xuval,
        lv_high     TYPE xuval,
        ls_role_ent TYPE ty_role_entry.

  CLEAR: gt_roles, gt_role_auths.

  LOOP AT gt_raw_rows INTO DATA(ls_raw).
    lv_role    = to_upper( condense( ls_raw-col1 ) ).
    lv_obj_fld = to_upper( condense( ls_raw-col2 ) ).
    lv_low     = condense( ls_raw-col3 ).
    lv_high    = condense( ls_raw-col4 ).

    IF lv_role IS INITIAL OR lv_obj_fld IS INITIAL.
      CONTINUE.
    ENDIF.

    " Parse OBJECT-FIELD format (e.g. K_CSKS-KOSTL)
    CLEAR: lv_object, lv_field.
    IF lv_obj_fld CS '-'.
      SPLIT lv_obj_fld AT '-' INTO lv_object lv_field.
      lv_object = condense( lv_object ).
      lv_field  = condense( lv_field ).
    ELSEIF lv_obj_fld CS '_'.
      " Fallback if underscore separated
      SPLIT lv_obj_fld AT '_' INTO lv_object lv_field.
      lv_object = condense( lv_object ).
      lv_field  = condense( lv_field ).
    ELSE.
      CONTINUE.
    ENDIF.

    IF lv_object IS INITIAL OR lv_field IS INITIAL.
      CONTINUE.
    ENDIF.

    " Preserve valid empty/space value ' '
    IF lv_low = ''' ''' OR lv_low = '''  ''' OR lv_low = '''   '''.
      lv_low = ''' '''.
    ELSE.
      " Strip surrounding quotes or Excel formula wrapping (e.g. ="00000000" -> 00000000)
      IF lv_low CP '="*"' OR lv_low CP '=*'.
        REPLACE FIRST OCCURRENCE OF '="' IN lv_low WITH ''.
        REPLACE FIRST OCCURRENCE OF '=' IN lv_low WITH ''.
        REPLACE ALL OCCURRENCES OF '"' IN lv_low WITH ''.
        lv_low = condense( lv_low ).
      ENDIF.
    ENDIF.
    IF lv_high = ''' ''' OR lv_high = '''  ''' OR lv_high = '''   '''.
      lv_high = ''' '''.
    ELSE.
      IF lv_high CP '="*"' OR lv_high CP '=*'.
        REPLACE FIRST OCCURRENCE OF '="' IN lv_high WITH ''.
        REPLACE FIRST OCCURRENCE OF '=' IN lv_high WITH ''.
        REPLACE ALL OCCURRENCES OF '"' IN lv_high WITH ''.
        lv_high = condense( lv_high ).
      ENDIF.
    ENDIF.

    " Parse potential ranges (LOW - HIGH or LOW:HIGH) if col4 is initial (backwards compatibility)
    IF lv_high IS INITIAL.
      IF lv_low CS ' - '.
        SPLIT lv_low AT ' - ' INTO lv_low lv_high.
        lv_low  = condense( lv_low ).
        lv_high = condense( lv_high ).
      ELSEIF lv_low CS ':'.
        SPLIT lv_low AT ':' INTO lv_low lv_high.
        lv_low  = condense( lv_low ).
        lv_high = condense( lv_high ).
      ENDIF.
    ENDIF.

    " Apply conversion exit ALPHA for PS_VERNR (8 digits) and KOSTL / PRCTR (10 digits) if pure digits
    IF lv_field = 'PS_VERNR'.
      IF lv_low CO '0123456789' AND lv_low IS NOT INITIAL.
        DATA: lv_vnr_8 TYPE c LENGTH 8.
        lv_vnr_8 = lv_low.
        CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
          EXPORTING
            input  = lv_vnr_8
          IMPORTING
            output = lv_vnr_8.
        lv_low = lv_vnr_8.
      ENDIF.
      IF lv_high CO '0123456789' AND lv_high IS NOT INITIAL.
        lv_vnr_8 = lv_high.
        CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
          EXPORTING
            input  = lv_vnr_8
          IMPORTING
            output = lv_vnr_8.
        lv_high = lv_vnr_8.
      ENDIF.
    ELSEIF lv_field = 'KOSTL' OR lv_field = 'PRCTR'.
      IF lv_low CO '0123456789' AND lv_low IS NOT INITIAL.
        DATA: lv_alpha_obj_10 TYPE c LENGTH 10.
        lv_alpha_obj_10 = lv_low.
        CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
          EXPORTING
            input  = lv_alpha_obj_10
          IMPORTING
            output = lv_alpha_obj_10.
        lv_low = lv_alpha_obj_10.
      ENDIF.
      IF lv_high CO '0123456789' AND lv_high IS NOT INITIAL.
        lv_alpha_obj_10 = lv_high.
        CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
          EXPORTING
            input  = lv_alpha_obj_10
          IMPORTING
            output = lv_alpha_obj_10.
        lv_high = lv_alpha_obj_10.
      ENDIF.
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

    " Append role authorization object-field entry
    APPEND VALUE ty_role_auth(
      agr_name = lv_role
      object   = lv_object
      field    = lv_field
      val_low  = lv_low
      val_high = lv_high
    ) TO gt_role_auths.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form process_object_update
*&---------------------------------------------------------------------*
FORM process_object_update.
  DATA: ls_res        TYPE ty_alv_result,
        lt_curr_1250  TYPE STANDARD TABLE OF agr_1250,
        lt_curr_1251  TYPE STANDARD TABLE OF agr_1251,
        lt_bapiret    TYPE STANDARD TABLE OF bapiret2,
        lv_agr_chk    TYPE agr_name,
        lv_parent_chk TYPE agr_name,
        lv_upd_cnt    TYPE i,
        lv_skip_cnt   TYPE i,
        lv_upd_det    TYPE string,
        lv_skip_det   TYPE string.

  CLEAR gt_results.

  LOOP AT gt_roles INTO DATA(ls_role).
    CLEAR: ls_res, lt_curr_1250, lt_curr_1251, lt_bapiret,
           lv_agr_chk, lv_parent_chk, lv_upd_cnt, lv_skip_cnt,
           lv_upd_det, lv_skip_det.

    ls_res-agr_name      = ls_role-agr_name.
    ls_res-auth_file_cnt = ls_role-item_cnt.

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

    ls_res-parent_agr = lv_parent_chk.

    " Fetch Role Description from AGR_TEXTS
    SELECT SINGLE text FROM agr_texts INTO @ls_res-role_desc
      WHERE agr_name = @ls_role-agr_name AND spras = @sy-langu AND line = '00000'.
    IF sy-subrc <> 0.
      SELECT SINGLE text FROM agr_texts INTO @ls_res-role_desc
        WHERE agr_name = @ls_role-agr_name AND line = '00000'.
    ENDIF.

    " -----------------------------------------------------------------
    " 2. Read Existing Active Authorization Objects & Fields in Role
    "    Strict Rule: Skip inactive/deactivated nodes (deleted='X'/copied='I')!
    " -----------------------------------------------------------------
    SELECT * FROM agr_1250 INTO TABLE @lt_curr_1250
      WHERE agr_name = @ls_role-agr_name
        AND deleted  = @space
        AND copied  <> 'I'.

    SELECT * FROM agr_1251 INTO TABLE @lt_curr_1251
      WHERE agr_name = @ls_role-agr_name
        AND deleted  = @space
        AND copied  <> 'I'.

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
    " 3. Validate Each Distinct Object-Field Against Real Role Data
    "    Strict Rule: Only update if OBJECT exists in AGR_1250
    "                 AND FIELD exists in AGR_1251
    "                 AND FIELD is NOT an Org Level in USORG!
    "                 DO NOT add foreign objects from CSV into role!
    " -----------------------------------------------------------------
    LOOP AT lt_distinct_of INTO DATA(ls_of).
      " Check 0: Protect Org Level fields (must remain bound to $VARBL in AGR_1251; values belong in AGR_1252)
      IF line_exists( gt_usorg_map[ field = ls_of-field ] ).
        lv_skip_cnt = lv_skip_cnt + 1.
        IF lv_skip_det IS INITIAL.
          lv_skip_det = |{ ls_of-object }-{ ls_of-field }(OrgLvl)|.
        ELSEIF strlen( lv_skip_det ) < 150.
          lv_skip_det = |{ lv_skip_det }, { ls_of-object }-{ ls_of-field }(OrgLvl)|.
        ENDIF.
        CONTINUE.
      ENDIF.

      " Check 1: Does OBJECT exist in role?
      READ TABLE lt_curr_1250 WITH KEY object = ls_of-object TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        lv_skip_cnt = lv_skip_cnt + 1.
        IF lv_skip_det IS INITIAL.
          lv_skip_det = |{ ls_of-object }-{ ls_of-field }|.
        ELSEIF strlen( lv_skip_det ) < 150.
          lv_skip_det = |{ lv_skip_det }, { ls_of-object }-{ ls_of-field }|.
        ENDIF.
        CONTINUE.
      ENDIF.

      " Check 2: Does FIELD exist under this OBJECT in role?
      READ TABLE lt_curr_1251 WITH KEY object = ls_of-object field = ls_of-field TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        lv_skip_cnt = lv_skip_cnt + 1.
        IF lv_skip_det IS INITIAL.
          lv_skip_det = |{ ls_of-object }-{ ls_of-field }|.
        ELSEIF strlen( lv_skip_det ) < 150.
          lv_skip_det = |{ lv_skip_det }, { ls_of-object }-{ ls_of-field }|.
        ENDIF.
        CONTINUE.
      ENDIF.

      " Check 3: Build target values (Sync vs Append) and check if different from current role values
      DATA: lt_new_vals TYPE STANDARD TABLE OF ty_role_auth,
            lt_cur_vals TYPE STANDARD TABLE OF agr_1251.
      CLEAR: lt_new_vals, lt_cur_vals.

      LOOP AT lt_curr_1251 INTO DATA(ls_c)
        WHERE object = ls_of-object AND field = ls_of-field.
        APPEND ls_c TO lt_cur_vals.
      ENDLOOP.

      IF rb_app = abap_true.
        " Append Mode: Keep existing non-empty values first
        LOOP AT lt_cur_vals INTO DATA(ls_c_app) WHERE low IS NOT INITIAL OR high IS NOT INITIAL.
          READ TABLE lt_new_vals WITH KEY val_low = ls_c_app-low val_high = ls_c_app-high TRANSPORTING NO FIELDS.
          IF sy-subrc <> 0.
            APPEND VALUE ty_role_auth(
              agr_name = ls_role-agr_name
              object   = ls_of-object
              field    = ls_of-field
              val_low  = ls_c_app-low
              val_high = ls_c_app-high
            ) TO lt_new_vals.
          ENDIF.
        ENDLOOP.
      ENDIF.

      " Add CSV values (in Sync mode: only CSV values; in Append mode: appended to existing)
      LOOP AT gt_role_auths INTO DATA(ls_n)
        WHERE agr_name = ls_role-agr_name AND object = ls_of-object AND field = ls_of-field.
        READ TABLE lt_new_vals WITH KEY val_low = ls_n-val_low val_high = ls_n-val_high TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          APPEND ls_n TO lt_new_vals.
        ENDIF.
      ENDLOOP.

      DATA(lv_field_changed) = abap_false.
      IF lines( lt_new_vals ) <> lines( lt_cur_vals ).
        lv_field_changed = abap_true.
      ELSE.
        LOOP AT lt_new_vals INTO DATA(ls_nv).
          READ TABLE lt_cur_vals WITH KEY low = ls_nv-val_low high = ls_nv-val_high TRANSPORTING NO FIELDS.
          IF sy-subrc <> 0.
            lv_field_changed = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.
      ENDIF.

      IF lv_field_changed = abap_true.
        lv_upd_cnt = lv_upd_cnt + 1.
        READ TABLE lt_new_vals INTO DATA(ls_first_nv) INDEX 1.
        IF sy-subrc = 0.
          IF lv_upd_det IS INITIAL.
            lv_upd_det = |{ ls_of-object }-{ ls_of-field }={ ls_first_nv-val_low }|.
          ELSEIF strlen( lv_upd_det ) < 150.
            lv_upd_det = |{ lv_upd_det }, { ls_of-object }-{ ls_of-field }={ ls_first_nv-val_low }|.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDLOOP.

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
        ls_res-status  = gc_status_ok.
        ls_res-action  = 'UP-TO-DATE'.
        ls_res-message = |[Simulated] All matching auth fields are already up-to-date.|.
      ENDIF.

      IF lv_skip_cnt > 0.
        ls_res-message = |{ ls_res-message } { lv_skip_cnt } item(s) in CSV skipped (not in role / OrgLvl).|.
      ENDIF.

      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " 5. Real Run Execution
    " -----------------------------------------------------------------
    IF lv_upd_cnt > 0.
      " Read current auth nodes & field values via standard PFCG FMs
      DATA: lt_pt1250  TYPE STANDARD TABLE OF pt1250,
            lt_pt1251  TYPE STANDARD TABLE OF pt1251,
            lv_mod1250 TYPE abap_bool.
      CLEAR: lt_pt1250, lt_pt1251, lv_mod1250.

      CALL FUNCTION 'PRGN_1250_READ_AUTH_DATA'
        EXPORTING
          activity_group    = ls_role-agr_name
          no_texts          = 'X'
        TABLES
          auth_data         = lt_pt1250
        EXCEPTIONS
          OTHERS            = 0.

      CALL FUNCTION 'PRGN_1251_READ_FIELD_VALUES'
        EXPORTING
          activity_group    = ls_role-agr_name
        TABLES
          field_values      = lt_pt1251
        EXCEPTIONS
          no_data_available = 1
          OTHERS            = 2.

      " Apply modifications to matching non-org objects and fields in internal table
      LOOP AT lt_distinct_of INTO ls_of.
        IF line_exists( gt_usorg_map[ field = ls_of-field ] ).
          CONTINUE.
        ENDIF.
        READ TABLE lt_curr_1250 WITH KEY object = ls_of-object TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.
        READ TABLE lt_curr_1251 WITH KEY object = ls_of-object field = ls_of-field TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.

        " Find all distinct ACTIVE authorization IDs (AUTH) for this object & field in lt_pt1251
        DATA: lt_auth_ids TYPE STANDARD TABLE OF xuauth.
        CLEAR lt_auth_ids.
        LOOP AT lt_pt1251 INTO DATA(ls_p)
          WHERE object = ls_of-object AND field = ls_of-field
            AND deleted = space AND copied <> 'I'.
          READ TABLE lt_curr_1250 WITH KEY object = ls_p-object auth = ls_p-auth TRANSPORTING NO FIELDS.
          IF sy-subrc = 0.
            READ TABLE lt_auth_ids WITH KEY table_line = ls_p-auth TRANSPORTING NO FIELDS.
            IF sy-subrc <> 0.
              APPEND ls_p-auth TO lt_auth_ids.
            ENDIF.
          ENDIF.
        ENDLOOP.

        " For each AUTH instance, synchronize or append field rows
        LOOP AT lt_auth_ids INTO DATA(lv_auth_id).
          READ TABLE lt_pt1251 INTO DATA(ls_tmpl)
            WITH KEY object = ls_of-object auth = lv_auth_id field = ls_of-field
                     deleted = space.
          IF sy-subrc = 0.
            " Determine proper PFCG status: 'G' (Changed/Maintained) for standard nodes, 'U' only if node itself is 'U'
            DATA(lv_fld_mod) = CONV char1( 'G' ).
            READ TABLE lt_pt1250 ASSIGNING FIELD-SYMBOL(<ls_a50>)
              WITH KEY object = ls_of-object auth = lv_auth_id deleted = space.
            IF sy-subrc = 0.
              IF <ls_a50>-modified = 'U'.
                lv_fld_mod = 'U'.
              ELSEIF <ls_a50>-modified = 'S'.
                <ls_a50>-modified = 'G'.
                <ls_a50>-neu      = COND #( WHEN <ls_a50>-neu IS NOT INITIAL THEN <ls_a50>-neu ELSE 'O' ).
                lv_mod1250        = abap_true.
              ENDIF.
            ENDIF.

            DATA: lt_final_fvals TYPE STANDARD TABLE OF ty_role_auth.
            CLEAR lt_final_fvals.

            IF rb_app = abap_true.
              " Append Mode: Keep existing non-empty values for this AUTH instance
              LOOP AT lt_pt1251 INTO DATA(ls_keep_p)
                WHERE object = ls_of-object AND auth = lv_auth_id AND field = ls_of-field
                  AND deleted = space AND copied <> 'I'
                  AND ( low IS NOT INITIAL OR high IS NOT INITIAL ).
                READ TABLE lt_final_fvals WITH KEY val_low = ls_keep_p-low val_high = ls_keep_p-high TRANSPORTING NO FIELDS.
                IF sy-subrc <> 0.
                  APPEND VALUE ty_role_auth(
                    agr_name = ls_role-agr_name
                    object   = ls_of-object
                    field    = ls_of-field
                    val_low  = ls_keep_p-low
                    val_high = ls_keep_p-high
                  ) TO lt_final_fvals.
                ENDIF.
              ENDLOOP.
            ENDIF.

            LOOP AT gt_role_auths INTO DATA(ls_new)
              WHERE agr_name = ls_role-agr_name
                AND object   = ls_of-object
                AND field    = ls_of-field.
              READ TABLE lt_final_fvals WITH KEY val_low = ls_new-val_low val_high = ls_new-val_high TRANSPORTING NO FIELDS.
              IF sy-subrc <> 0.
                APPEND ls_new TO lt_final_fvals.
              ENDIF.
            ENDLOOP.

            DELETE lt_pt1251 WHERE object = ls_of-object AND auth = lv_auth_id AND field = ls_of-field.

            LOOP AT lt_final_fvals INTO DATA(ls_fv).
              APPEND VALUE pt1251(
                object   = ls_of-object
                auth     = lv_auth_id
                variant  = ls_tmpl-variant
                field    = ls_of-field
                low      = ls_fv-val_low
                high     = ls_fv-val_high
                modified = lv_fld_mod
                neu      = COND #( WHEN ls_tmpl-neu IS NOT INITIAL THEN ls_tmpl-neu ELSE 'O' )
                copied   = ls_tmpl-copied
              ) TO lt_pt1251.
            ENDLOOP.
          ENDIF.
        ENDLOOP.
      ENDLOOP.

      " Save via standard PFCG FMs (replaces direct OpenSQL UPDATE on AGR_1251/1250)
      CALL FUNCTION 'PRGN_1251_SAVE_FIELD_VALUES'
        EXPORTING
          activity_group = ls_role-agr_name
        TABLES
          field_values   = lt_pt1251.

      IF lv_mod1250 = abap_true.
        CALL FUNCTION 'PRGN_1250_SAVE_AUTH_DATA'
          EXPORTING
            activity_group = ls_role-agr_name
          TABLES
            auth_data      = lt_pt1250.
      ENDIF.

      CALL FUNCTION 'PRGN_UPDATE_DATABASE'.
      COMMIT WORK AND WAIT.

      " Ensure all Org Level fields in AGR_1251 remain strictly bound to $VARBL (MODIFIED = 'S', NEU = 'O')
      PERFORM restore_1251_org_bindings USING ls_role-agr_name.

      " Update Role Timestamp in PFCG
      CALL FUNCTION 'PRGN_SET_ACTGROUP_TIMESTAMP'
        EXPORTING
          activity_group = ls_role-agr_name
        EXCEPTIONS
          OTHERS         = 0.

      " Regenerate Authorization Profile
      IF p_genprf = abap_true.
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
            OTHERS                = 1.

        PERFORM restore_1251_org_bindings USING ls_role-agr_name.
      ENDIF.

      COMMIT WORK AND WAIT.

      " Retrieve Profile Name
      SELECT SINGLE profile FROM agr_1016 INTO @ls_res-profile
        WHERE agr_name = @ls_role-agr_name.

      " Verify Final Role & Profile Status
      DATA: lv_chk_color TYPE char10,
            lv_chk_msg   TYPE c LENGTH 255.
      CLEAR: lv_chk_color, lv_chk_msg.
      CALL FUNCTION 'PRGN_CHECK_PROFILE_STATUS'
        EXPORTING
          activity_group = ls_role-agr_name
        IMPORTING
          message_text   = lv_chk_msg
          led_color      = lv_chk_color.

      IF lv_chk_color = 'GREEN'.
        ls_res-status  = gc_status_ok.
        ls_res-action  = 'UPDATED'.
        ls_res-message = |Updated { lv_upd_cnt } auth field(s). Profile '{ ls_res-profile }' is GREEN.|.
      ELSEIF lv_chk_color = 'YELLOW'.
        ls_res-status  = gc_status_warn.
        ls_res-action  = 'UPDATED'.
        ls_res-message = |Updated { lv_upd_cnt } auth field(s). Profile Yellow: { lv_chk_msg }|.
      ELSE.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'WARNING'.
        ls_res-message = |Profile Red: { lv_chk_msg }|.
      ENDIF.

      IF lv_skip_cnt > 0.
        ls_res-message = |{ ls_res-message } { lv_skip_cnt } item(s) in CSV skipped (not in role).|.
      ENDIF.

    ELSE.
      SELECT SINGLE profile FROM agr_1016 INTO @ls_res-profile
        WHERE agr_name = @ls_role-agr_name.

      ls_res-status  = gc_status_ok.
      ls_res-action  = 'UP-TO-DATE'.
      ls_res-message = |All matching auth fields in role are already up-to-date.|.
      IF lv_skip_cnt > 0.
        ls_res-message = |{ ls_res-message } { lv_skip_cnt } item(s) in CSV skipped (not in role).|.
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
      IF column = 'AGR_NAME' AND ls_row-agr_name IS NOT INITIAL.
        SET PARAMETER ID 'AGR' FIELD ls_row-agr_name.
        CALL TRANSACTION 'PFCG' AND SKIP FIRST SCREEN.
      ELSEIF column = 'PARENT_AGR' AND ls_row-parent_agr IS NOT INITIAL.
        SET PARAMETER ID 'AGR' FIELD ls_row-parent_agr.
        CALL TRANSACTION 'PFCG' AND SKIP FIRST SCREEN.
      ENDIF.
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

*&---------------------------------------------------------------------*
*& Form restore_1251_org_bindings
*&---------------------------------------------------------------------*
* Ensures all Org Level fields in AGR_1251 are strictly bound to their
* respective Org Variable ($VARBL) with MODIFIED = 'S' and NEU = 'O'.
*&---------------------------------------------------------------------*
FORM restore_1251_org_bindings USING iv_agr_name TYPE agr_name.
  DATA: lt_pt1251 TYPE STANDARD TABLE OF pt1251,
        lv_mod51  TYPE abap_bool.

  CLEAR: lt_pt1251, lv_mod51.

  IF gt_usorg_map IS INITIAL.
    RETURN.
  ENDIF.

  CALL FUNCTION 'PRGN_1251_READ_FIELD_VALUES'
    EXPORTING
      activity_group = iv_agr_name
    TABLES
      field_values   = lt_pt1251
    EXCEPTIONS
      OTHERS         = 0.

  IF lt_pt1251 IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT gt_usorg_map INTO DATA(ls_uo).
    LOOP AT lt_pt1251 ASSIGNING FIELD-SYMBOL(<ls_f51>)
      WHERE field = ls_uo-field
        AND deleted = space AND copied <> 'I'.
      IF <ls_f51>-low <> ls_uo-varbl OR <ls_f51>-modified <> 'S' OR <ls_f51>-neu <> 'O' OR <ls_f51>-high IS NOT INITIAL.
        <ls_f51>-low      = ls_uo-varbl.
        <ls_f51>-high     = space.
        <ls_f51>-modified = 'S'.
        <ls_f51>-neu      = 'O'.
        lv_mod51          = abap_true.
      ENDIF.
    ENDLOOP.
  ENDLOOP.

  IF lv_mod51 = abap_true.
    CALL FUNCTION 'PRGN_1251_SAVE_FIELD_VALUES'
      EXPORTING
        activity_group = iv_agr_name
      TABLES
        field_values   = lt_pt1251.
    CALL FUNCTION 'PRGN_UPDATE_DATABASE'.
    COMMIT WORK AND WAIT.
  ENDIF.
ENDFORM.
