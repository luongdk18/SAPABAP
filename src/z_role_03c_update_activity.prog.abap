*&---------------------------------------------------------------------*
*& Report Z_ROLE_03C_UPDATE_ACTIVITY
*&---------------------------------------------------------------------*
*& Purpose: Batch Update Authorization Activity Fields for PFCG Roles
*& Description:
*&   Reads a CSV (.csv) file containing Activity field values for roles
*&   (Role Name, Field, Value-Low, Value-High), typically generated as
*&   <stem>_03c_Activity_converted.csv.
*&
*&   Logic:
*&   - Scans all authorization objects and authorizations (AUTH) in each
*&     role that contain the target field (e.g. ACTVT, PS_ACTVT).
*&   - Updates matching field values with the specified activity values
*&     (e.g., *, 03, 08, F4).
*&   - If an object in the role does NOT contain the target field, it
*&     remains completely untouched.
*&   - All other authorization fields under each object (e.g. BUKRS,
*&     WERKS, KOSTL, etc.) are strictly preserved.
*&   - Saves changes via standard PFCG FM PRGN_1251_SAVE_FIELD_VALUES
*&     (Zero direct database updates - 100% standard SAP API compliance).
*&   - Regenerates authorization profiles and displays detailed execution
*&     results in an interactive ALV grid with PFCG hotspots.
*&
*& File format (CSV .csv):
*&   Col 1: Role Name        (e.g., Z_FI_GL_MASTER_MAINT_1000, Z_FI_GL_MASTER_MAINT)
*&   Col 2: Field            (e.g., ACTVT, PS_ACTVT)
*&   Col 3: Value-Low        (e.g., 03, *, 08, F4)
*&   Col 4: Value-High       (optional high value)
*&
*& Author: Antigravity AI (SAP Basis Engineering)
*& Package: $TMP (Local Object) or Custom Package
*&---------------------------------------------------------------------*
REPORT z_role_03c_update_activity.

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

TYPES: BEGIN OF ty_role_actvt,
         agr_name TYPE agr_name,
         field    TYPE xufield,
         val_low  TYPE xuval,
         val_high TYPE xuval,
       END OF ty_role_actvt.

TYPES: BEGIN OF ty_obj_auth,
         object TYPE xuobject,
         auth   TYPE xuauth,
       END OF ty_obj_auth.

TYPES: BEGIN OF ty_alv_result,
         status        TYPE char12,    " Status Icon: @08@ [OK], @09@ [WARN], @0A@ [ERR]
         action        TYPE char12,    " Action: UPDATED / UP-TO-DATE / SIMULATE / ERROR / NO-FIELD
         agr_name      TYPE agr_name,  " Role ID (Hotspot to PFCG)
         role_desc     TYPE agr_title, " Role Description
         parent_agr    TYPE agr_name,  " Parent Master Role (Hotspot to PFCG)
         file_item_cnt TYPE i,         " Number of Activity items in input file for this role
         field_names   TYPE string,    " Field(s) targeted (ACTVT, PS_ACTVT)
         obj_scan_cnt  TYPE i,         " Total objects present in role
         obj_fld_cnt   TYPE i,         " Objects in role containing the target field
         obj_upd_cnt   TYPE i,         " Objects updated with new activity values
         new_val_str   TYPE string,    " Summary of new Activity values (e.g. 03, 08, F4)
         obj_upd_det   TYPE string,    " Summary of updated objects (e.g. F_BKPF_BUK, F_BKPF_KOA...)
         profile       TYPE xuprofile, " Generated Profile Name
         message       TYPE string,    " Execution Log / Status Message
       END OF ty_alv_result.

CONSTANTS: gc_status_ok   TYPE char12 VALUE '@08@ [OK]',
           gc_status_warn TYPE char12 VALUE '@09@ [WARN]',
           gc_status_err  TYPE char12 VALUE '@0A@ [ERR]'.

DATA: gt_raw_rows        TYPE STANDARD TABLE OF ty_raw_row,
      gt_roles           TYPE STANDARD TABLE OF ty_role_entry,
      gt_role_actvts     TYPE SORTED TABLE OF ty_role_actvt
                           WITH NON-UNIQUE KEY agr_name field,
      gt_results         TYPE STANDARD TABLE OF ty_alv_result,
      gt_usorg_map       TYPE SORTED TABLE OF usorg WITH NON-UNIQUE KEY field,
      gt_oversized_roles TYPE STANDARD TABLE OF string.

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
  b_tit1 = 'Input Activity CSV File (.csv)'(b01).
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
  PERFORM process_activity_update.
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
      window_title            = 'Select Role Activity CSV File'
      file_filter             = 'Role Activity CSV (*03c_Activity*.csv)|*03c_Activity*.csv|CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'
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
    MESSAGE |Invalid file '{ lv_fname }'. Expected CSV file (*_03c_Activity_converted.csv).| TYPE 'E'.
  ENDIF.

  IF NOT ( lv_up CS '03C_ACTIVITY' OR lv_up CS '_ACTIVITY' )
     OR lv_up CS '01_MASTER' OR lv_up CS '02_DERIVE' OR lv_up CS '03A_ORG'
     OR lv_up CS '03B_AUTH' OR lv_up CS '03B_OBJECT' OR lv_up CS '04_COMPOSITE'
     OR lv_up CS '01_CREATE' OR lv_up CS '02_ASSIGN'.
    MESSAGE |Invalid file '{ lv_fname }' for Z_ROLE_03C_UPDATE_ACTIVITY. Expected '*_03c_Activity_converted.csv'.| TYPE 'E'.
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

  CLEAR lv_line_idx.
  LOOP AT lt_file_records INTO lv_line.
    lv_line_idx = lv_line_idx + 1.
    IF lv_line_idx = 1 AND strlen( lv_line ) >= 1.
      IF lv_line(1) = cl_abap_char_utilities=>byte_order_mark_utf8.
        lv_line = substring( val = lv_line off = 1 ).
      ENDIF.
    ENDIF.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf(1) IN lv_line WITH ''.
    CLEAR ls_raw.
    PERFORM parse_csv_line USING lv_line
                           CHANGING ls_raw-col1 ls_raw-col2 ls_raw-col3 ls_raw-col4.

    " Validate & skip header row
    DATA(lv_c1_up) = to_upper( ls_raw-col1 ).
    DATA(lv_c2_up) = to_upper( ls_raw-col2 ).
    IF lv_line_idx = 1.
      IF lv_c2_up CS 'OBJECT' OR lv_c2_up CS 'ORG' OR lv_c1_up CS 'MASTER'
         OR lv_c1_up CS 'COMPOSITE' OR lv_c1_up CS 'USER' OR lv_c2_up CS 'DESC'.
        MESSAGE 'Invalid CSV header for Z_ROLE_03C_UPDATE_ACTIVITY. Expected: Role, Field, value-low, value-high.' TYPE 'E'.
      ENDIF.
      IF lv_c1_up CS 'ROLE' AND ( lv_c2_up = 'FIELD' OR lv_c2_up = 'ACTIVITY' OR lv_c2_up = 'ACTVT' ).
        CONTINUE.
      ENDIF.
    ENDIF.
    IF lv_c1_up = 'ROLE' OR lv_c1_up = 'ROLE NAME' OR lv_c1_up = 'ROLE_NAME'
       OR lv_c2_up = 'FIELD' OR lv_c2_up = 'ACTIVITY'.
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
        lv_char   TYPE string,
        lv_next   TYPE string,
        lv_idx    TYPE i,
        lv_delim  TYPE c LENGTH 1.

  CLEAR: ev_col1, ev_col2, ev_col3, ev_col4.

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
  DATA: lv_role_raw TYPE string,
        lv_role     TYPE agr_name,
        lv_field    TYPE xufield,
        lv_low      TYPE xuval,
        lv_high     TYPE xuval,
        ls_role_ent TYPE ty_role_entry.

  CLEAR: gt_roles, gt_role_actvts, gt_oversized_roles.

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

    lv_role  = lv_role_raw.
    lv_field = to_upper( condense( ls_raw-col2 ) ).
    lv_low   = condense( ls_raw-col3 ).
    lv_high  = condense( ls_raw-col4 ).

    IF lv_field IS INITIAL.
      CONTINUE.
    ENDIF.

    " If col2 contains object-field (e.g. C_PRPS_ART-PS_ACTVT), extract field part
    IF lv_field CS '-'.
      SPLIT lv_field AT '-' INTO DATA(lv_dummy) lv_field.
      lv_field = condense( lv_field ).
    ENDIF.

    " Strip surrounding quotes or Excel formula wrapping (e.g. ="03" -> 03)
    IF lv_low CP '="*"' OR lv_low CP '=*'.
      REPLACE FIRST OCCURRENCE OF '="' IN lv_low WITH ''.
      REPLACE FIRST OCCURRENCE OF '=' IN lv_low WITH ''.
      REPLACE ALL OCCURRENCES OF '"' IN lv_low WITH ''.
      lv_low = condense( lv_low ).
    ENDIF.
    IF lv_high CP '="*"' OR lv_high CP '=*'.
      REPLACE FIRST OCCURRENCE OF '="' IN lv_high WITH ''.
      REPLACE FIRST OCCURRENCE OF '=' IN lv_high WITH ''.
      REPLACE ALL OCCURRENCES OF '"' IN lv_high WITH ''.
      lv_high = condense( lv_high ).
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

    " Insert into sorted role activity table
    INSERT VALUE ty_role_actvt(
      agr_name = lv_role
      field    = lv_field
      val_low  = lv_low
      val_high = lv_high
    ) INTO TABLE gt_role_actvts.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form process_activity_update
*&---------------------------------------------------------------------*
FORM process_activity_update.
  DATA: ls_res           TYPE ty_alv_result,
        lt_pt1250        TYPE STANDARD TABLE OF pt1250,
        lt_pt1251        TYPE STANDARD TABLE OF pt1251,
        lt_bapiret       TYPE STANDARD TABLE OF bapiret2,
        lv_agr_chk       TYPE agr_name,
        lv_parent_chk    TYPE agr_name,
        lt_obj_auth      TYPE STANDARD TABLE OF ty_obj_auth,
        lt_active_1250   TYPE SORTED TABLE OF ty_obj_auth WITH NON-UNIQUE KEY object auth,
        lt_flds          TYPE STANDARD TABLE OF xufield,
        lt_obj_all       TYPE STANDARD TABLE OF xuobject,
        lt_matched_objs  TYPE STANDARD TABLE OF xuobject,
        lt_seen_vals     TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line,
        lt_seen_upd_objs TYPE HASHED TABLE OF xuobject WITH UNIQUE KEY table_line,
        lv_role_modified TYPE abap_bool,
        lv_org_skipped   TYPE string,
        lv_upd_cnt       TYPE i,
        lv_upd_det       TYPE string,
        lv_vals_str      TYPE string,
        lv_flds_str      TYPE string,
        lv_mod1250       TYPE abap_bool,
        lv_save_err      TYPE string,
        lv_gen_subrc     TYPE sy-subrc,
        lv_gen_err       TYPE string,
        lv_chk_color     TYPE char10,
        lv_chk_msg       TYPE c LENGTH 255.

  CLEAR gt_results.

  LOOP AT gt_oversized_roles INTO DATA(lv_bad_role).
    CLEAR ls_res.
    ls_res-status   = gc_status_err.
    ls_res-action   = 'ERROR'.
    ls_res-agr_name = lv_bad_role.
    ls_res-message  = |Role name exceeds SAP 30-character limit: '{ lv_bad_role }'.|.
    APPEND ls_res TO gt_results.
  ENDLOOP.

  LOOP AT gt_roles INTO DATA(ls_role).
    CLEAR: ls_res, lt_pt1250, lt_pt1251, lt_bapiret,
           lv_agr_chk, lv_parent_chk, lt_obj_auth, lt_active_1250,
           lt_flds, lt_obj_all, lt_matched_objs, lt_seen_vals, lt_seen_upd_objs,
           lv_role_modified, lv_org_skipped, lv_upd_cnt, lv_upd_det,
           lv_vals_str, lv_flds_str, lv_mod1250, lv_save_err,
           lv_gen_subrc, lv_gen_err, lv_chk_color, lv_chk_msg.

    ls_res-agr_name      = ls_role-agr_name.
    ls_res-file_item_cnt = ls_role-item_cnt.

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

    ls_res-parent_agr = lv_parent_chk.

    SELECT SINGLE text FROM agr_texts INTO @ls_res-role_desc
      WHERE agr_name = @ls_role-agr_name AND spras = @sy-langu AND line = '00000'.
    IF sy-subrc <> 0.
      SELECT SINGLE text FROM agr_texts INTO @ls_res-role_desc
        WHERE agr_name = @ls_role-agr_name AND line = '00000'.
    ENDIF.

    " -----------------------------------------------------------------
    " 2. Read Existing Authorization Objects & Field Values via PFCG FM
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

    IF sy-subrc <> 0 OR lt_pt1251 IS INITIAL.
      ls_res-status  = gc_status_warn.
      ls_res-action  = 'NO-AUTH'.
      ls_res-message = |No authorization data maintained in role '{ ls_role-agr_name }'.|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " Derive active (object, auth) pairs directly from lt_pt1250 (no redundant DB SELECT)
    LOOP AT lt_pt1250 INTO DATA(ls_a50_act) WHERE deleted = space AND copied <> 'I'.
      INSERT VALUE ty_obj_auth( object = ls_a50_act-object auth = ls_a50_act-auth ) INTO TABLE lt_active_1250.
    ENDLOOP.

    LOOP AT lt_pt1251 INTO DATA(ls_p_scan) WHERE deleted = space AND copied <> 'I'.
      IF line_exists( lt_active_1250[ object = ls_p_scan-object auth = ls_p_scan-auth ] ).
        READ TABLE lt_obj_all WITH KEY table_line = ls_p_scan-object TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          APPEND ls_p_scan-object TO lt_obj_all.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ls_res-obj_scan_cnt = lines( lt_obj_all ).

    " -----------------------------------------------------------------
    " 3. Identify Distinct Target Field(s) for this Role from CSV
    " -----------------------------------------------------------------
    LOOP AT gt_role_actvts INTO DATA(ls_ra) WHERE agr_name = ls_role-agr_name.
      READ TABLE lt_flds WITH KEY table_line = ls_ra-field TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND ls_ra-field TO lt_flds.
        IF lv_flds_str IS INITIAL.
          lv_flds_str = ls_ra-field.
        ELSE.
          lv_flds_str = |{ lv_flds_str }, { ls_ra-field }|.
        ENDIF.
      ENDIF.

      DATA(lv_val_item) = COND string(
        WHEN ls_ra-val_high IS NOT INITIAL
        THEN |{ ls_ra-val_low }-{ ls_ra-val_high }|
        ELSE |{ ls_ra-val_low }| ).
      IF NOT line_exists( lt_seen_vals[ table_line = lv_val_item ] ).
        INSERT lv_val_item INTO TABLE lt_seen_vals.
        IF lv_vals_str IS INITIAL.
          lv_vals_str = lv_val_item.
        ELSEIF strlen( lv_vals_str ) < 60.
          lv_vals_str = |{ lv_vals_str }, { lv_val_item }|.
        ENDIF.
      ENDIF.
    ENDLOOP.

    ls_res-field_names = lv_flds_str.
    ls_res-new_val_str = lv_vals_str.

    " -----------------------------------------------------------------
    " 4. Scan and Match: Strictly block Org-Level fields (USORG)
    " -----------------------------------------------------------------
    LOOP AT lt_flds INTO DATA(lv_target_field).
      IF line_exists( gt_usorg_map[ field = lv_target_field ] ).
        IF lv_org_skipped IS INITIAL.
          lv_org_skipped = lv_target_field.
        ELSE.
          lv_org_skipped = |{ lv_org_skipped }, { lv_target_field }|.
        ENDIF.
        CONTINUE.
      ENDIF.

      CLEAR lt_obj_auth.
      LOOP AT lt_pt1251 INTO DATA(ls_pt)
        WHERE field = lv_target_field AND deleted = space AND copied <> 'I'.
        IF NOT line_exists( lt_active_1250[ object = ls_pt-object auth = ls_pt-auth ] ).
          CONTINUE.
        ENDIF.
        READ TABLE lt_obj_auth WITH KEY object = ls_pt-object auth = ls_pt-auth TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          APPEND VALUE ty_obj_auth( object = ls_pt-object auth = ls_pt-auth ) TO lt_obj_auth.
        ENDIF.
        READ TABLE lt_matched_objs WITH KEY table_line = ls_pt-object TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          APPEND ls_pt-object TO lt_matched_objs.
        ENDIF.
      ENDLOOP.

      IF lt_obj_auth IS INITIAL.
        CONTINUE.
      ENDIF.

      DATA: lt_csv_vals TYPE STANDARD TABLE OF ty_role_actvt.
      CLEAR lt_csv_vals.
      LOOP AT gt_role_actvts INTO DATA(ls_tv)
        WHERE agr_name = ls_role-agr_name AND field = lv_target_field.
        READ TABLE lt_csv_vals WITH KEY val_low = ls_tv-val_low val_high = ls_tv-val_high TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          APPEND ls_tv TO lt_csv_vals.
        ENDIF.
      ENDLOOP.

      LOOP AT lt_obj_auth INTO DATA(ls_oa).
        DATA: lt_current_vals TYPE STANDARD TABLE OF pt1251,
              lt_target_vals  TYPE STANDARD TABLE OF ty_role_actvt.
        CLEAR: lt_current_vals, lt_target_vals.

        LOOP AT lt_pt1251 INTO DATA(ls_cur)
          WHERE object = ls_oa-object AND auth = ls_oa-auth AND field = lv_target_field
            AND deleted = space AND copied <> 'I'.
          APPEND ls_cur TO lt_current_vals.
        ENDLOOP.

        IF rb_app = abap_true.
          LOOP AT lt_current_vals INTO DATA(ls_cur_app)
            WHERE low IS NOT INITIAL OR high IS NOT INITIAL.
            READ TABLE lt_target_vals WITH KEY val_low = ls_cur_app-low val_high = ls_cur_app-high TRANSPORTING NO FIELDS.
            IF sy-subrc <> 0.
              APPEND VALUE ty_role_actvt(
                agr_name = ls_role-agr_name
                field    = lv_target_field
                val_low  = ls_cur_app-low
                val_high = ls_cur_app-high
              ) TO lt_target_vals.
            ENDIF.
          ENDLOOP.
        ENDIF.

        LOOP AT lt_csv_vals INTO DATA(ls_cv).
          READ TABLE lt_target_vals WITH KEY val_low = ls_cv-val_low val_high = ls_cv-val_high TRANSPORTING NO FIELDS.
          IF sy-subrc <> 0.
            APPEND ls_cv TO lt_target_vals.
          ENDIF.
        ENDLOOP.

        DATA(lv_obj_changed) = abap_false.
        IF lines( lt_current_vals ) <> lines( lt_target_vals ).
          lv_obj_changed = abap_true.
        ELSE.
          LOOP AT lt_target_vals INTO DATA(ls_nv).
            READ TABLE lt_current_vals WITH KEY low = ls_nv-val_low high = ls_nv-val_high TRANSPORTING NO FIELDS.
            IF sy-subrc <> 0.
              lv_obj_changed = abap_true.
              EXIT.
            ENDIF.
          ENDLOOP.
        ENDIF.

        IF lv_obj_changed = abap_true.
          lv_upd_cnt       = lv_upd_cnt + 1.
          lv_role_modified = abap_true.

          IF NOT line_exists( lt_seen_upd_objs[ table_line = ls_oa-object ] ).
            INSERT ls_oa-object INTO TABLE lt_seen_upd_objs.
            IF lv_upd_det IS INITIAL.
              lv_upd_det = |{ ls_oa-object }|.
            ELSEIF strlen( lv_upd_det ) < 150.
              lv_upd_det = |{ lv_upd_det }, { ls_oa-object }|.
            ENDIF.
          ENDIF.

          DATA(lv_fld_mod) = CONV char1( 'G' ).
          READ TABLE lt_pt1250 ASSIGNING FIELD-SYMBOL(<ls_a50>)
            WITH KEY object = ls_oa-object auth = ls_oa-auth deleted = space.
          IF sy-subrc = 0 AND <ls_a50>-copied <> 'I'.
            IF <ls_a50>-modified = 'U'.
              lv_fld_mod = 'U'.
            ELSEIF <ls_a50>-modified = 'S'.
              <ls_a50>-modified = 'G'.
              <ls_a50>-neu      = COND #( WHEN <ls_a50>-neu IS NOT INITIAL THEN <ls_a50>-neu ELSE 'O' ).
              lv_mod1250        = abap_true.
            ENDIF.
          ENDIF.

          READ TABLE lt_current_vals INTO DATA(ls_tmpl) INDEX 1.
          DATA(lv_variant) = ls_tmpl-variant.

          DELETE lt_pt1251 WHERE object = ls_oa-object AND auth = ls_oa-auth
                             AND field = lv_target_field
                             AND deleted = space AND copied <> 'I'.

          LOOP AT lt_target_vals INTO DATA(ls_ins).
            APPEND VALUE pt1251(
              object   = ls_oa-object
              auth     = ls_oa-auth
              variant  = lv_variant
              field    = lv_target_field
              low      = ls_ins-val_low
              high     = ls_ins-val_high
              modified = lv_fld_mod
              neu      = COND #( WHEN ls_tmpl-neu IS NOT INITIAL THEN ls_tmpl-neu ELSE 'O' )
              copied   = ls_tmpl-copied
            ) TO lt_pt1251.
          ENDLOOP.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    ls_res-obj_fld_cnt = lines( lt_matched_objs ).
    ls_res-obj_upd_cnt = lv_upd_cnt.
    ls_res-obj_upd_det = lv_upd_det.

    " -----------------------------------------------------------------
    " 5. Determine Result Status & Message
    " -----------------------------------------------------------------
    IF lines( lt_matched_objs ) = 0.
      ls_res-status = gc_status_warn.
      ls_res-action = 'NO-FIELD'.
      IF lv_org_skipped IS NOT INITIAL.
        ls_res-message = |Skipped Org Level field(s) [{ lv_org_skipped }] (use Z_ROLE_03A_UPDATE_ORG instead).|.
      ELSE.
        ls_res-message = |No objects in role contain target field '{ lv_flds_str }'. Kept unchanged.|.
      ENDIF.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    SELECT SINGLE profile FROM agr_1016 INTO @ls_res-profile
      WHERE agr_name = @ls_role-agr_name.

    IF lv_role_modified = abap_false.
      ls_res-status  = gc_status_ok.
      ls_res-action  = 'UP-TO-DATE'.
      ls_res-message = |All { lines( lt_matched_objs ) } object(s) with field '{ lv_flds_str }' already match target values.|.
      IF lv_org_skipped IS NOT INITIAL.
        ls_res-status  = gc_status_warn.
        ls_res-message = |{ ls_res-message } Org Level field(s) [{ lv_org_skipped }] skipped.|.
      ENDIF.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " 6. Simulation Mode Handling
    " -----------------------------------------------------------------
    IF p_test = abap_true.
      ls_res-status  = gc_status_ok.
      ls_res-action  = 'SIMULATE'.
      ls_res-message = |[Simulated] { lv_upd_cnt } auth instance(s) across { lines( lt_matched_objs ) } object(s) will be updated: { lv_vals_str }.|.
      IF lv_org_skipped IS NOT INITIAL.
        ls_res-status  = gc_status_warn.
        ls_res-message = |{ ls_res-message } Org Level field(s) [{ lv_org_skipped }] skipped.|.
      ENDIF.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " 7. Real Run: Enqueue -> Save -> Timestamp -> Commit -> Dequeue -> Gen
    " -----------------------------------------------------------------
    PERFORM normalize_1251_org_bindings CHANGING lt_pt1251.

    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
      EXPORTING
        activity_group          = ls_role-agr_name
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
        EXCEPTIONS
          OTHERS         = 0.
      COMMIT WORK AND WAIT.
    ELSE.
      ROLLBACK WORK.
    ENDIF.

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
      lv_gen_subrc = sy-subrc.

      LOOP AT lt_bapiret INTO DATA(ls_ret) WHERE type CA 'EAX'.
        IF lv_gen_err IS INITIAL.
          lv_gen_err = ls_ret-message.
        ELSE.
          lv_gen_err = |{ lv_gen_err }; { ls_ret-message }|.
        ENDIF.
      ENDLOOP.

      COMMIT WORK AND WAIT.

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

      IF lv_gen_subrc <> 0 OR lv_gen_err IS NOT INITIAL.
        ls_res-status  = gc_status_warn.
        ls_res-action  = 'UPDATED'.
        ls_res-message = |{ lv_upd_cnt } auth instance(s) updated. Profile warning: { lv_gen_err } { lv_chk_msg }|.
      ELSEIF lv_chk_color = 'GREEN'.
        ls_res-status  = gc_status_ok.
        ls_res-action  = 'UPDATED'.
        ls_res-message = |{ lv_upd_cnt } auth instance(s) updated. Profile '{ ls_res-profile }' is GREEN.|.
      ELSEIF lv_chk_color = 'YELLOW'.
        ls_res-status  = gc_status_warn.
        ls_res-action  = 'UPDATED'.
        ls_res-message = |{ lv_upd_cnt } auth instance(s) updated. Profile Yellow: { lv_chk_msg }|.
      ELSEIF lv_chk_color = 'RED'.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'WARNING'.
        ls_res-message = |{ lv_upd_cnt } auth instance(s) updated. Profile Red: { lv_chk_msg }|.
      ELSE.
        ls_res-status  = gc_status_ok.
        ls_res-action  = 'UPDATED'.
        ls_res-message = |{ lv_upd_cnt } auth instance(s) updated. Profile status: { lv_chk_color } { lv_chk_msg }|.
      ENDIF.
    ELSE.
      ls_res-status  = gc_status_ok.
      ls_res-action  = 'UPDATED'.
      ls_res-message = |{ lv_upd_cnt } auth instance(s) updated in role. Profile regeneration skipped.|.
    ENDIF.

    IF lv_org_skipped IS NOT INITIAL.
      ls_res-status  = gc_status_warn.
      ls_res-message = |{ ls_res-message } Org Level field(s) [{ lv_org_skipped }] skipped.|.
    ENDIF.

    APPEND ls_res TO gt_results.
  ENDLOOP.
ENDFORM.

*----------------------------------------------------------------------*
* 8. ALV EVENT HANDLER DEFINITION & IMPLEMENTATION
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
      lo_display->set_list_header( 'Batch Role Activity Fields (ACTVT / PS_ACTVT) Update Results' ).

      " Format Columns
      lo_cols = lo_alv->get_columns( ).
      lo_cols->set_optimize( abap_true ).

      " Format Column: STATUS
      lo_col ?= lo_cols->get_column( 'STATUS' ).
      lo_col->set_short_text( 'Status' ).
      lo_col->set_medium_text( 'Status' ).
      lo_col->set_long_text( 'Execution Status' ).
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

      " Format Column: FILE_ITEM_CNT
      lo_col ?= lo_cols->get_column( 'FILE_ITEM_CNT' ).
      lo_col->set_short_text( 'File Items' ).
      lo_col->set_medium_text( 'File Items Cnt' ).
      lo_col->set_long_text( 'Activity Rows in File' ).
      lo_col->set_alignment( if_salv_c_alignment=>right ).

      " Format Column: FIELD_NAMES
      lo_col ?= lo_cols->get_column( 'FIELD_NAMES' ).
      lo_col->set_short_text( 'Field' ).
      lo_col->set_medium_text( 'Field Name' ).
      lo_col->set_long_text( 'Target Activity Field(s)' ).

      " Format Column: OBJ_SCAN_CNT
      lo_col ?= lo_cols->get_column( 'OBJ_SCAN_CNT' ).
      lo_col->set_short_text( 'Role Objs' ).
      lo_col->set_medium_text( 'Total Role Objects' ).
      lo_col->set_long_text( 'Total Objects in Role' ).
      lo_col->set_alignment( if_salv_c_alignment=>right ).

      " Format Column: OBJ_FLD_CNT
      lo_col ?= lo_cols->get_column( 'OBJ_FLD_CNT' ).
      lo_col->set_short_text( 'Objs w/Fld' ).
      lo_col->set_medium_text( 'Objects with Field' ).
      lo_col->set_long_text( 'Objects Containing Target Field' ).
      lo_col->set_alignment( if_salv_c_alignment=>right ).

      " Format Column: OBJ_UPD_CNT
      lo_col ?= lo_cols->get_column( 'OBJ_UPD_CNT' ).
      lo_col->set_short_text( 'Upd Auth' ).
      lo_col->set_medium_text( 'Updated Auths' ).
      lo_col->set_long_text( 'Auth Instances Updated' ).
      lo_col->set_alignment( if_salv_c_alignment=>right ).

      " Format Column: NEW_VAL_STR
      lo_col ?= lo_cols->get_column( 'NEW_VAL_STR' ).
      lo_col->set_short_text( 'New Values' ).
      lo_col->set_medium_text( 'New Activity Values' ).
      lo_col->set_long_text( 'Target Activity Values' ).

      " Format Column: OBJ_UPD_DET
      lo_col ?= lo_cols->get_column( 'OBJ_UPD_DET' ).
      lo_col->set_short_text( 'Upd Objs' ).
      lo_col->set_medium_text( 'Updated Objects' ).
      lo_col->set_long_text( 'Summary of Updated Objects' ).

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
*& Form normalize_1251_org_bindings
*&---------------------------------------------------------------------*
* Ensures all active Org Level fields in lt_pt1251 remain strictly bound
* to $VARBL (MODIFIED = 'S', NEU = 'O') and deduplicated per (object, auth, field).
*&---------------------------------------------------------------------*
FORM normalize_1251_org_bindings CHANGING ct_pt1251 TYPE STANDARD TABLE.
  DATA: lt_clean    TYPE STANDARD TABLE OF pt1251,
        lt_seen_key TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line,
        ls_f51      TYPE pt1251,
        lv_key      TYPE string.

  IF gt_usorg_map IS INITIAL OR ct_pt1251 IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT ct_pt1251 INTO ls_f51.
    IF ls_f51-deleted = space AND ls_f51-copied <> 'I'.
      READ TABLE gt_usorg_map INTO DATA(ls_uo) WITH TABLE KEY field = ls_f51-field.
      IF sy-subrc = 0.
        lv_key = |{ ls_f51-object }:{ ls_f51-auth }:{ ls_f51-field }|.
        IF line_exists( lt_seen_key[ table_line = lv_key ] ).
          CONTINUE.
        ENDIF.
        INSERT lv_key INTO TABLE lt_seen_key.
        IF ls_f51-low <> ls_uo-varbl OR ls_f51-high IS NOT INITIAL
           OR ls_f51-modified <> 'S' OR ls_f51-neu <> 'O'.
          ls_f51-low      = ls_uo-varbl.
          ls_f51-high     = space.
          ls_f51-modified = 'S'.
          ls_f51-neu      = 'O'.
        ENDIF.
      ENDIF.
    ENDIF.
    APPEND ls_f51 TO lt_clean.
  ENDLOOP.
  ct_pt1251 = lt_clean.
ENDFORM.
