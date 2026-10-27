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
*&     remains completely untouched ("Nếu không có thì giữ nguyên").
*&   - All other authorization fields under each object (e.g. BUKRS,
*&     WERKS, KOSTL, etc.) are strictly preserved.
*&   - Saves changes via standard PFCG FM PRGN_1251_SAVE_FIELD_VALUES
*&     (Zero direct database updates - 100% standard SAP API compliance).
*&   - Regenerates authorization profiles and displays detailed execution
*&     results in an interactive ALV grid with PFCG hotspots.
*&
*& File format (CSV .csv):
*&   Col 1: Role Name        (e.g., DRFI01_MASTERDATA_DISP_1100, LRFI01_MASTERDATA_DISP)
*&   Col 2: Field            (e.g., ACTVT, PS_ACTVT)
*&   Col 3: Value-Low        (e.g., 03, *, 08, F4)
*&   Col 4: Value-High       (optional high value)
*&
*& Author: Antigravity AI (SAP Basis Engineering)
*& Package: $TMP (Local Object) or Custom Package
*&---------------------------------------------------------------------*
REPORT z_role_03c_update_activity.

TABLES: agr_define, agr_texts, agr_1250, agr_1251, agr_1016.

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

DATA: gt_raw_rows   TYPE STANDARD TABLE OF ty_raw_row,
      gt_roles      TYPE STANDARD TABLE OF ty_role_entry,
      gt_role_actvts TYPE STANDARD TABLE OF ty_role_actvt,
      gt_results    TYPE STANDARD TABLE OF ty_alv_result.

*----------------------------------------------------------------------*
* 2. SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b_file WITH FRAME TITLE b_tit1.
  PARAMETERS: p_file TYPE localfile OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b_file.

SELECTION-SCREEN BEGIN OF BLOCK b_opt WITH FRAME TITLE b_tit2.
  PARAMETERS: p_test   TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_genprf TYPE abap_bool AS CHECKBOX DEFAULT 'X'.
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

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  PERFORM f4_file_open CHANGING p_file.

*----------------------------------------------------------------------*
* 4. START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.
  PERFORM check_authority.
  PERFORM upload_and_parse_file.
  PERFORM aggregate_input_data.
  PERFORM process_activity_update.
  PERFORM display_alv_results.

*&---------------------------------------------------------------------*
*& Form f4_file_open
*&---------------------------------------------------------------------*
FORM f4_file_open CHANGING cv_file TYPE localfile.
  DATA: lt_file_table TYPE filetable,
        lv_rc         TYPE i.

  cl_gui_frontend_services=>file_open_dialog(
    EXPORTING
      window_title            = 'Select Role Activity CSV File'
      file_filter             = 'CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'
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

    " Skip header row
    DATA(lv_c1_up) = to_upper( ls_raw-col1 ).
    DATA(lv_c2_up) = to_upper( ls_raw-col2 ).
    IF lv_line_idx = 1 AND ( lv_c1_up CS 'ROLE' OR lv_c2_up CS 'FIELD' OR lv_c2_up CS 'ACTVT' ).
      CONTINUE.
    ENDIF.
    IF lv_c1_up = 'ROLE' OR lv_c1_up = 'ROLE NAME' OR lv_c1_up = 'ROLE_NAME'
       OR lv_c2_up = 'FIELD' OR lv_c2_up = 'ACTIVITY' OR lv_c2_up = 'OBJECT-FIELD'.
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
    lv_char = iv_line+lv_idx(1).

    IF lv_char = '"'.
      IF lv_in_q = abap_true.
        lv_in_q = abap_false.
      ELSE.
        lv_in_q = abap_true.
      ENDIF.
      CONTINUE.
    ENDIF.

    IF ( lv_char = ',' OR lv_char = ';' ) AND lv_in_q = abap_false.
      APPEND lv_cur TO lt_tokens.
      CLEAR lv_cur.
    ELSE.
      CONCATENATE lv_cur lv_char INTO lv_cur.
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
        lv_field    TYPE xufield,
        lv_low      TYPE xuval,
        lv_high     TYPE xuval,
        ls_role_ent TYPE ty_role_entry.

  CLEAR: gt_roles, gt_role_actvts.

  LOOP AT gt_raw_rows INTO DATA(ls_raw).
    lv_role  = to_upper( condense( ls_raw-col1 ) ).
    lv_field = to_upper( condense( ls_raw-col2 ) ).
    lv_low   = condense( ls_raw-col3 ).
    lv_high  = condense( ls_raw-col4 ).

    IF lv_role IS INITIAL OR lv_field IS INITIAL.
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

    " Append role activity entry
    APPEND VALUE ty_role_actvt(
      agr_name = lv_role
      field    = lv_field
      val_low  = lv_low
      val_high = lv_high
    ) TO gt_role_actvts.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form process_activity_update
*&---------------------------------------------------------------------*
FORM process_activity_update.
  DATA: ls_res        TYPE ty_alv_result,
        lt_pt1251     TYPE STANDARD TABLE OF pt1251,
        lt_curr_1250  TYPE STANDARD TABLE OF agr_1250,
        lt_curr_1251  TYPE STANDARD TABLE OF agr_1251,
        lt_bapiret    TYPE STANDARD TABLE OF bapiret2,
        lv_agr_chk    TYPE agr_name,
        lv_parent_chk TYPE agr_name,
        lt_obj_auth   TYPE STANDARD TABLE OF ty_obj_auth,
        lt_flds       TYPE STANDARD TABLE OF xufield,
        lt_obj_all    TYPE STANDARD TABLE OF xuobject,
        lv_upd_cnt    TYPE i,
        lv_fld_obj_cnt TYPE i,
        lv_upd_det    TYPE string,
        lv_vals_str   TYPE string,
        lv_flds_str   TYPE string.

  CLEAR gt_results.

  LOOP AT gt_roles INTO DATA(ls_role).
    CLEAR: ls_res, lt_pt1251, lt_curr_1250, lt_curr_1251, lt_bapiret,
           lv_agr_chk, lv_parent_chk, lt_obj_auth, lt_flds, lt_obj_all,
           lv_upd_cnt, lv_fld_obj_cnt, lv_upd_det, lv_vals_str, lv_flds_str.

    ls_res-agr_name      = ls_role-agr_name.
    ls_res-file_item_cnt = ls_role-item_cnt.

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
    " 2. Read Existing Authorization Objects & Field Values via PFCG FM
    " -----------------------------------------------------------------
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

    " Count total distinct objects currently active in role
    SELECT object, auth FROM agr_1250
      INTO TABLE @DATA(lt_active_1250)
      WHERE agr_name = @ls_role-agr_name
        AND deleted  = @space
        AND copied  <> 'I'.

    LOOP AT lt_pt1251 INTO DATA(ls_p_scan) WHERE deleted = space AND copied <> 'I'.
      READ TABLE lt_active_1250 WITH KEY object = ls_p_scan-object auth = ls_p_scan-auth TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
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

      " Build summary string of new values
      DATA(lv_val_item) = ls_ra-val_low.
      IF ls_ra-val_high IS NOT INITIAL.
        lv_val_item = |{ lv_val_item }-{ ls_ra-val_high }|.
      ENDIF.
      IF lv_vals_str IS INITIAL.
        lv_vals_str = lv_val_item.
      ELSEIF NOT lv_vals_str CS lv_val_item.
        IF strlen( lv_vals_str ) < 60.
          lv_vals_str = |{ lv_vals_str }, { lv_val_item }|.
        ENDIF.
      ENDIF.
    ENDLOOP.

    ls_res-field_names = lv_flds_str.
    ls_res-new_val_str = lv_vals_str.

    " -----------------------------------------------------------------
    " 4. Scan and Match: For each target field, find objects in role
    "    Strict Rule: Only update objects that already contain the field!
    "                 Skip inactive/deactivated nodes (deleted='X' / copied='I')!
    "                 Objects without the field remain completely untouched.
    " -----------------------------------------------------------------
    DATA: lt_matched_objs TYPE STANDARD TABLE OF xuobject,
          lv_role_modified TYPE abap_bool VALUE abap_false.

    CLEAR: lt_matched_objs.

    LOOP AT lt_flds INTO DATA(lv_target_field).
      " Find all distinct (object, auth) ACTIVE instances in role containing this field
      CLEAR lt_obj_auth.
      LOOP AT lt_pt1251 INTO DATA(ls_pt)
        WHERE field = lv_target_field AND deleted = space AND copied <> 'I'.
        READ TABLE lt_active_1250 WITH KEY object = ls_pt-object auth = ls_pt-auth TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
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
        " No objects in role contain this field -> kept unchanged
        CONTINUE.
      ENDIF.

      " New values defined in CSV for this (role, field)
      DATA: lt_target_vals TYPE STANDARD TABLE OF ty_role_actvt.
      CLEAR lt_target_vals.
      LOOP AT gt_role_actvts INTO DATA(ls_tv)
        WHERE agr_name = ls_role-agr_name AND field = lv_target_field.
        APPEND ls_tv TO lt_target_vals.
      ENDLOOP.

      " For each (object, auth) instance, compare and update
      LOOP AT lt_obj_auth INTO DATA(ls_oa).
        DATA: lt_current_vals TYPE STANDARD TABLE OF pt1251.
        CLEAR lt_current_vals.

        LOOP AT lt_pt1251 INTO DATA(ls_cur)
          WHERE object = ls_oa-object AND auth = ls_oa-auth AND field = lv_target_field
            AND deleted = space AND copied <> 'I'.
          APPEND ls_cur TO lt_current_vals.
        ENDLOOP.

        " Compare current values with new values
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
          lv_upd_cnt = lv_upd_cnt + 1.
          lv_role_modified = abap_true.

          IF lv_upd_det IS INITIAL.
            lv_upd_det = |{ ls_oa-object }|.
          ELSEIF NOT lv_upd_det CS ls_oa-object.
            IF strlen( lv_upd_det ) < 150.
              lv_upd_det = |{ lv_upd_det }, { ls_oa-object }|.
            ENDIF.
          ENDIF.

          " Replace existing field values with new ones in lt_pt1251
          READ TABLE lt_current_vals INTO DATA(ls_tmpl) INDEX 1.
          DATA(lv_variant) = ls_tmpl-variant.

          DELETE lt_pt1251 WHERE object = ls_oa-object AND auth = ls_oa-auth AND field = lv_target_field.

          LOOP AT lt_target_vals INTO DATA(ls_ins).
            APPEND VALUE pt1251(
              object   = ls_oa-object
              auth     = ls_oa-auth
              variant  = lv_variant
              field    = lv_target_field
              low      = ls_ins-val_low
              high     = ls_ins-val_high
              modified = 'U'
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
      ls_res-status  = gc_status_warn.
      ls_res-action  = 'NO-FIELD'.
      ls_res-message = |No objects in role contain target field '{ lv_flds_str }'. Kept unchanged.|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " Fetch current auth profile from AGR_1016
    SELECT SINGLE profile FROM agr_1016 INTO @ls_res-profile
      WHERE agr_name = @ls_role-agr_name.

    IF lv_role_modified = abap_false.
      ls_res-status  = gc_status_ok.
      ls_res-action  = 'UP-TO-DATE'.
      ls_res-message = |All { lines( lt_matched_objs ) } object(s) with field '{ lv_flds_str }' already match target activity values.|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " 6. Simulation Mode Handling
    " -----------------------------------------------------------------
    IF p_test = abap_true.
      ls_res-status  = gc_status_ok.
      ls_res-action  = 'SIMULATE'.
      ls_res-message = |[Simulated] { lv_upd_cnt } auth instance(s) across { lines( lt_matched_objs ) } object(s) will be updated with values: { lv_vals_str }.|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " 7. Real Run: Save via standard PFCG FM & Regenerate Profile
    " -----------------------------------------------------------------
    CALL FUNCTION 'PRGN_1251_SAVE_FIELD_VALUES'
      EXPORTING
        activity_group = ls_role-agr_name
      TABLES
        field_values   = lt_pt1251.

    CALL FUNCTION 'PRGN_UPDATE_DATABASE'.
    COMMIT WORK AND WAIT.

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

      IF sy-subrc = 0.
        SELECT SINGLE profile FROM agr_1016 INTO @ls_res-profile
          WHERE agr_name = @ls_role-agr_name.
        ls_res-status  = gc_status_ok.
        ls_res-action  = 'UPDATED'.
        ls_res-message = |{ lv_upd_cnt } auth instance(s) updated. Profile '{ ls_res-profile }' regenerated successfully.|.
      ELSE.
        ls_res-status  = gc_status_warn.
        ls_res-action  = 'UPDATED'.
        ls_res-message = |{ lv_upd_cnt } auth instance(s) updated. Profile generation returned error/warning.|.
      ENDIF.
    ELSE.
      ls_res-status  = gc_status_ok.
      ls_res-action  = 'UPDATED'.
      ls_res-message = |{ lv_upd_cnt } auth instance(s) updated in role. Profile regeneration skipped.|.
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
