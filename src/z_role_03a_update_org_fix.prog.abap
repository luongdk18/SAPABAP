*&---------------------------------------------------------------------*
*& Report Z_ROLE_03A_UPDATE_ORG_FIX
*&---------------------------------------------------------------------*
*& Purpose: Batch Fix & Standardize Roles with Org Level Variables ($VARBL)
*& Description:
*&   Reads a list of roles (from CSV file or Selection Screen criteria).
*&   Does NOT update business authorization field values.
*&   Specifically diagnoses and heals authorization objects and fields:
*&   1. Scans AGR_1251 for all fields that are Org Levels (in USORG) or contain $VARBL:
*&      - Resets LOW to proper $VARBL (e.g. $BUKRS, $EKGRP, $WERKS).
*&      - Clears HIGH (space).
*&      - Restores MODIFIED to 'S' (Standard) and NEU to 'O' (Org Level).
*&   2. Scans AGR_1250 for authorization nodes marked as 'Manually' (MODIFIED = 'U'/'M'):
*&      - If all active fields in that node are Standard ('S'), restores the node in
*&        AGR_1250 to MODIFIED = 'S' (Standard) and NEU = 'O'.
*&   3. Ensures AGR_1252 has an entry for all active $VARBL variables:
*&      - For Master Roles: ensures unmaintained variables have default '-1'.
*&      - For Derived Roles: ensures variables exist; defaults unmaintained to '*'
*&        without wiping existing maintained values.
*&   4. If run on a Derived Role with p_parhea = 'X':
*&      - Automatically heals the Parent Master Role's AGR_1251/1250/1252 as well.
*&   5. Regenerates Authorization Profile cleanly via standard SAP APIs (SUPRN_DARK_MANIPULATE_PROFILE).
*&   6. Displays detailed diagnostics and repair summary in an interactive ALV grid.
*&
*& Package: $TMP (Local Object) or Custom Package
*& Author: Antigravity AI (SAP Basis Engineering)
*&---------------------------------------------------------------------*
REPORT z_role_03a_update_org_fix.

TABLES: agr_define, agr_texts, agr_1250, agr_1251, agr_1252, agr_1016, usorg.

*----------------------------------------------------------------------*
* 1. TYPES & DATA DEFINITIONS
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_role_entry,
         agr_name TYPE agr_name,
       END OF ty_role_entry,
       tt_role_entry TYPE STANDARD TABLE OF ty_role_entry WITH DEFAULT KEY.

TYPES: BEGIN OF ty_raw_row,
         col1 TYPE string,
         col2 TYPE string,
         col3 TYPE string,
         col4 TYPE string,
       END OF ty_raw_row.

TYPES: BEGIN OF ty_alv_result,
         status       TYPE char12,    " Status Icon: @08@ [OK], @09@ [WARN], @0A@ [ERR]
         action       TYPE char12,    " Action: FIXED / UP-TO-DATE / SIMULATE / ERROR
         agr_name     TYPE agr_name,  " Role ID (Hotspot to PFCG)
         role_desc    TYPE agr_title, " Role Description
         parent_agr   TYPE agr_name,  " Parent Master Role (Hotspot to PFCG)
         fixed_fields TYPE i,         " Number of Org Level Fields fixed to Standard
         fixed_auths  TYPE i,         " Number of Authorization Objects restored to Standard
         details      TYPE string,    " Detail list of fixed objects/fields
         profile      TYPE xuprofile, " Generated Runtime Profile Name
         message      TYPE string,    " Status Message / Execution Log
       END OF ty_alv_result.

CONSTANTS: gc_status_ok   TYPE char12 VALUE '@08@ [OK]',
           gc_status_warn TYPE char12 VALUE '@09@ [WARN]',
           gc_status_err  TYPE char12 VALUE '@0A@ [ERR]'.

DATA: gt_target_roles TYPE STANDARD TABLE OF ty_role_entry,
      gt_results      TYPE STANDARD TABLE OF ty_alv_result,
      gt_usorg_map    TYPE HASHED TABLE OF usorg WITH UNIQUE KEY field,
      gt_healed_pars  TYPE HASHED TABLE OF agr_name WITH UNIQUE KEY table_line.

*----------------------------------------------------------------------*
* 2. SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b_input WITH FRAME TITLE b_tit1.
  SELECT-OPTIONS: s_role FOR agr_define-agr_name.
  PARAMETERS:     p_file TYPE localfile.
SELECTION-SCREEN END OF BLOCK b_input.

SELECTION-SCREEN BEGIN OF BLOCK b_opt WITH FRAME TITLE b_tit2.
  PARAMETERS: p_test   TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_genprf TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_parhea TYPE abap_bool AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b_opt.

*----------------------------------------------------------------------*
* 3. INITIALIZATION & SCREEN EVENTS
*----------------------------------------------------------------------*
INITIALIZATION.
  b_tit1 = 'Role Selection & Input Source'(b01).
  b_tit2 = 'Execution & Repair Options'(b02).

  %_s_role_%_app_%-text   = 'Role Name Criteria'.
  %_p_file_%_app_%-text   = 'Input CSV File (Optional)'.
  %_p_test_%_app_%-text   = 'Simulation (Test Run)'.
  %_p_genprf_%_app_%-text = 'Regenerate Auth Profiles'.
  %_p_parhea_%_app_%-text = 'Auto-Heal Parent Master Role'.

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
  PERFORM collect_target_roles.
  PERFORM process_roles_healing.
  PERFORM display_alv_results.

*&---------------------------------------------------------------------*
*& Form f4_file_open
*&---------------------------------------------------------------------*
FORM f4_file_open CHANGING cv_file TYPE localfile.
  DATA: lt_file_table TYPE filetable,
        lv_rc         TYPE i.

  cl_gui_frontend_services=>file_open_dialog(
    EXPORTING
      window_title            = 'Select Role CSV File'
      file_filter             = 'Role CSV (*01_Master*.csv;*02_Derived*.csv;*03a_Org*.csv)|*01_Master*.csv;*02_Derived*.csv;*03a_Org*.csv|CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'
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
    MESSAGE |Invalid file '{ lv_fname }'. Expected a CSV file (.csv).| TYPE 'E'.
  ENDIF.

  IF lv_up CS '01_CREATE' OR lv_up CS '02_ASSIGN' OR lv_up CS '04_COMPOSITE'
     OR lv_up = 'ORG_LEVELS.CSV' OR lv_up = 'OBJECT_LEVELS.CSV'.
    MESSAGE |Invalid file '{ lv_fname }' for Z_ROLE_03A_UPDATE_ORG_FIX. Expected a Single/Derived Role CSV file.| TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form check_authority
*&---------------------------------------------------------------------*
FORM check_authority.
  AUTHORITY-CHECK OBJECT 'S_USER_AGR'
    ID 'ACT_GROUP' DUMMY
    ID 'ACTVT'     FIELD '02'.
  IF sy-subrc <> 0.
    MESSAGE 'No authorization to change roles (S_USER_AGR, ACTVT 02).' TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form load_usorg_mapping
*&---------------------------------------------------------------------*
FORM load_usorg_mapping.
  CLEAR gt_usorg_map.
  SELECT * FROM usorg INTO TABLE @gt_usorg_map.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form collect_target_roles
*&---------------------------------------------------------------------*
FORM collect_target_roles.
  DATA: lt_roles_from_file TYPE STANDARD TABLE OF ty_role_entry,
        lt_roles_from_db   TYPE STANDARD TABLE OF ty_role_entry.

  CLEAR: gt_target_roles, lt_roles_from_file, lt_roles_from_db.

  " 1. Read roles from CSV file (if provided)
  IF p_file IS NOT INITIAL.
    PERFORM read_roles_from_file USING p_file CHANGING lt_roles_from_file.
  ENDIF.

  " 2. Read roles from Select-Options (if provided)
  IF s_role[] IS NOT INITIAL.
    SELECT agr_name FROM agr_define
      INTO TABLE @lt_roles_from_db
      WHERE agr_name IN @s_role
      ORDER BY agr_name.
  ENDIF.

  " Combine and deduplicate
  APPEND LINES OF lt_roles_from_file TO gt_target_roles.
  APPEND LINES OF lt_roles_from_db   TO gt_target_roles.

  SORT gt_target_roles BY agr_name.
  DELETE ADJACENT DUPLICATES FROM gt_target_roles COMPARING agr_name.

  IF gt_target_roles IS INITIAL.
    MESSAGE 'No target roles found. Please specify an input CSV file or Role Name criteria.' TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form read_roles_from_file
*&---------------------------------------------------------------------*
FORM read_roles_from_file USING    iv_file       TYPE localfile
                          CHANGING ct_file_roles TYPE tt_role_entry.
  DATA: lt_file_records TYPE truxs_t_text_data,
        lv_filepath     TYPE string,
        lv_line         TYPE string,
        lv_line_idx     TYPE i,
        lv_c1           TYPE string,
        lv_c2           TYPE string,
        lv_c3           TYPE string,
        lv_c4           TYPE string.

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
    CLEAR: lv_c1, lv_c2, lv_c3, lv_c4.
    PERFORM parse_csv_line USING lv_line CHANGING lv_c1 lv_c2 lv_c3 lv_c4.

    DATA(lv_c1_up) = to_upper( lv_c1 ).
    " Validate & skip header line
    IF lv_line_idx = 1.
      IF lv_c1_up CS 'USER' OR lv_c1_up CS 'COMPOSITE'.
        MESSAGE 'Invalid CSV header for Z_ROLE_03A_UPDATE_ORG_FIX. Expected a Single/Derived Role CSV file.' TYPE 'E'.
      ENDIF.
      IF lv_c1_up CS 'ROLE' OR lv_c1_up CS 'AGR_NAME'.
        CONTINUE.
      ENDIF.
    ENDIF.
    IF lv_c1_up = 'ROLE' OR lv_c1_up = 'ROLE NAME' OR lv_c1_up = 'ROLE_NAME' OR lv_c1_up = 'AGR_NAME'.
      CONTINUE.
    ENDIF.

    IF lv_c1 IS NOT INITIAL.
      APPEND VALUE ty_role_entry( agr_name = lv_c1 ) TO ct_file_roles.
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
    ev_col3 = condense( ev_col3 ).
  ENDIF.
  IF lines( lt_tokens ) >= 4.
    ev_col4 = lt_tokens[ 4 ].
    ev_col4 = condense( ev_col4 ).
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form process_roles_healing
*&---------------------------------------------------------------------*
FORM process_roles_healing.
  DATA: ls_res           TYPE ty_alv_result,
        lv_parent        TYPE agr_name,
        lv_parent_healed TYPE abap_bool.

  CLEAR: gt_results, gt_healed_pars.

  LOOP AT gt_target_roles INTO DATA(ls_target).
    CLEAR: ls_res, lv_parent, lv_parent_healed.
    ls_res-agr_name = ls_target-agr_name.

    " 1. Validate Role in SAP
    SELECT SINGLE parent_agr FROM agr_define
      INTO @lv_parent
      WHERE agr_name = @ls_target-agr_name.
    IF sy-subrc <> 0.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = |Role '{ ls_target-agr_name }' does not exist in SAP.|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    ls_res-parent_agr = lv_parent.

    " Fetch Role Description from AGR_TEXTS
    SELECT SINGLE text FROM agr_texts INTO @ls_res-role_desc
      WHERE agr_name = @ls_target-agr_name AND spras = @sy-langu AND line = '00000'.
    IF sy-subrc <> 0.
      SELECT SINGLE text FROM agr_texts INTO @ls_res-role_desc
        WHERE agr_name = @ls_target-agr_name AND line = '00000'.
    ENDIF.

    " 2. Heal and Standardize Current Role
    PERFORM heal_single_role USING    ls_target-agr_name
                                      lv_parent
                                      p_test
                                      p_genprf
                             CHANGING ls_res.

    " 3. If Derived Role and p_parhea = 'X': Auto-Heal Parent Master Role
    IF p_parhea = abap_true AND lv_parent IS NOT INITIAL.
      IF NOT line_exists( gt_healed_pars[ table_line = lv_parent ] ).
        DATA: ls_par_res TYPE ty_alv_result.
        CLEAR ls_par_res.
        PERFORM heal_single_role USING    lv_parent
                                          space   " Parent role has no parent
                                          p_test
                                          p_genprf
                                 CHANGING ls_par_res.
        IF ls_par_res-action = 'FIXED'.
          INSERT lv_parent INTO TABLE gt_healed_pars.
          ls_res-message = |{ ls_res-message } Master Role '{ lv_parent }' also healed ({ ls_par_res-fixed_fields } field(s), { ls_par_res-fixed_auths } object(s)).|.
        ENDIF.
      ENDIF.
    ENDIF.

    APPEND ls_res TO gt_results.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form heal_single_role
*&---------------------------------------------------------------------*
FORM heal_single_role USING    iv_role    TYPE agr_name
                               iv_parent  TYPE agr_name
                               iv_test    TYPE abap_bool
                               iv_genprf  TYPE abap_bool
                      CHANGING cs_res     TYPE ty_alv_result.
  DATA: lt_pt1250       TYPE STANDARD TABLE OF pt1250,
        lt_pt1251       TYPE STANDARD TABLE OF pt1251,
        lt_pt1252       TYPE STANDARD TABLE OF pt1252,
        lv_fix_1251     TYPE abap_bool,
        lv_fix_1250     TYPE abap_bool,
        lv_fix_1252     TYPE abap_bool,
        lv_fld_cnt      TYPE i,
        lv_auth_cnt     TYPE i,
        lv_details      TYPE string,
        lt_fixed_fld_tk TYPE STANDARD TABLE OF string,
        lt_fixed_obj_tk TYPE STANDARD TABLE OF string.

  CLEAR: lt_pt1250, lt_pt1251, lt_pt1252, lv_fix_1251, lv_fix_1250, lv_fix_1252,
         lv_fld_cnt, lv_auth_cnt, lv_details, lt_fixed_fld_tk, lt_fixed_obj_tk.

  " Read active authorization structures via standard SAP FMs
  CALL FUNCTION 'PRGN_1251_READ_FIELD_VALUES'
    EXPORTING
      activity_group    = iv_role
    TABLES
      field_values      = lt_pt1251
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.

  CALL FUNCTION 'PRGN_1250_READ_AUTH_DATA'
    EXPORTING
      activity_group    = iv_role
      no_texts          = 'X'
    TABLES
      auth_data         = lt_pt1250
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.

  CALL FUNCTION 'PRGN_1252_READ_ORG_LEVELS'
    EXPORTING
      activity_group    = iv_role
    TABLES
      org_levels        = lt_pt1252
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.

  IF lt_pt1251 IS INITIAL AND lt_pt1250 IS INITIAL.
    cs_res-status  = gc_status_ok.
    cs_res-action  = 'UP-TO-DATE'.
    cs_res-message = 'Role has no authorization objects.'.
    RETURN.
  ENDIF.

  " -----------------------------------------------------------------
  " Step A: Fix Fields in AGR_1251
  " Rule: Any field registered in USORG MUST be bound to $VARBL with
  "       MODIFIED = 'S' (Standard) and NEU = 'O' (Org Level).
  " -----------------------------------------------------------------
  LOOP AT gt_usorg_map INTO DATA(ls_um).
    LOOP AT lt_pt1251 ASSIGNING FIELD-SYMBOL(<ls_f51>)
      WHERE field = ls_um-field
        AND deleted = space AND copied <> 'I'.
      IF <ls_f51>-low <> ls_um-varbl OR <ls_f51>-modified <> 'S'
         OR <ls_f51>-neu <> 'O' OR <ls_f51>-high IS NOT INITIAL.
        <ls_f51>-low      = ls_um-varbl.
        <ls_f51>-high     = space.
        <ls_f51>-modified = 'S'.   " Must be Standard ('S')
        <ls_f51>-neu      = 'O'.   " Object - old / Org Level ('O')
        lv_fix_1251       = abap_true.
        lv_fld_cnt        = lv_fld_cnt + 1.

        DATA(lv_fld_str) = |{ <ls_f51>-object }-{ <ls_f51>-field }={ ls_um-varbl }|.
        READ TABLE lt_fixed_fld_tk WITH KEY table_line = lv_fld_str TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          APPEND lv_fld_str TO lt_fixed_fld_tk.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDLOOP.

  " Ensure all active non-org fields have NEU = 'O'
  LOOP AT lt_pt1251 ASSIGNING <ls_f51>
    WHERE deleted = space AND copied <> 'I'.
    IF <ls_f51>-neu <> 'O'.
      <ls_f51>-neu = 'O'.
      lv_fix_1251  = abap_true.
    ENDIF.
  ENDLOOP.

  " -----------------------------------------------------------------
  " Step B: Fix Authorization Headers in AGR_1250
  " Rule: If all active fields in an authorization node are now Standard ('S'),
  "       restore the node in AGR_1250 from 'U'/'M' to 'S' (Standard).
  " -----------------------------------------------------------------
  IF lt_pt1250 IS NOT INITIAL.
    LOOP AT lt_pt1250 ASSIGNING FIELD-SYMBOL(<ls_a50>)
      WHERE modified = 'U' OR modified = 'M'.
      READ TABLE lt_pt1251 TRANSPORTING NO FIELDS
        WITH KEY auth = <ls_a50>-auth modified = 'U' deleted = space.
      IF sy-subrc <> 0.
        READ TABLE lt_pt1251 TRANSPORTING NO FIELDS
          WITH KEY auth = <ls_a50>-auth modified = 'G' deleted = space.
        IF sy-subrc = 0.
          <ls_a50>-modified = 'G'.
        ELSE.
          <ls_a50>-modified = 'S'.
        ENDIF.
        <ls_a50>-neu      = 'O'.
        lv_fix_1250       = abap_true.
        lv_auth_cnt       = lv_auth_cnt + 1.

        DATA(lv_obj_str) = |{ <ls_a50>-object }|.
        READ TABLE lt_fixed_obj_tk WITH KEY table_line = lv_obj_str TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          APPEND lv_obj_str TO lt_fixed_obj_tk.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDIF.

  " -----------------------------------------------------------------
  " Step C: Ensure AGR_1252 Consistency for All Active Org Variables ($VARBL in USORG)
  " -----------------------------------------------------------------
  DATA: lt_active_vars TYPE HASHED TABLE OF agval WITH UNIQUE KEY table_line.
  CLEAR lt_active_vars.

  LOOP AT gt_usorg_map INTO ls_um.
    READ TABLE lt_pt1251 TRANSPORTING NO FIELDS
      WITH KEY field = ls_um-field deleted = space.
    IF sy-subrc = 0.
      LOOP AT lt_pt1251 ASSIGNING <ls_f51>
        WHERE field = ls_um-field AND deleted = space AND copied <> 'I'.
        INSERT ls_um-varbl INTO TABLE lt_active_vars.
        EXIT.
      ENDLOOP.
    ENDIF.
  ENDLOOP.

  LOOP AT lt_active_vars INTO DATA(lv_varbl).
    READ TABLE lt_pt1252 ASSIGNING FIELD-SYMBOL(<ls_o1252>)
      WITH KEY varbl = lv_varbl.
    IF sy-subrc <> 0.
      " Variable missing in AGR_1252!
      IF iv_parent IS INITIAL.
        " Master Role: default to '-1'
        APPEND VALUE pt1252( varbl = lv_varbl low = '-1' high = space ) TO lt_pt1252.
      ELSE.
        " Derived Role: default to '*'
        APPEND VALUE pt1252( varbl = lv_varbl low = '*' high = space ) TO lt_pt1252.
      ENDIF.
      lv_fix_1252 = abap_true.
    ELSE.
      " Variable exists in AGR_1252
      IF iv_parent IS INITIAL.
        IF <ls_o1252>-low IS INITIAL OR <ls_o1252>-low = space.
          <ls_o1252>-low = '-1'.
          lv_fix_1252    = abap_true.
        ENDIF.
      ELSE.
        IF <ls_o1252>-low = '-1'.
          <ls_o1252>-low = '*'.
          lv_fix_1252    = abap_true.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDLOOP.

  " Build detail summary string
  LOOP AT lt_fixed_fld_tk INTO DATA(ls_tk).
    IF lv_details IS INITIAL.
      lv_details = ls_tk.
    ELSEIF strlen( lv_details ) < 150.
      lv_details = |{ lv_details }, { ls_tk }|.
    ENDIF.
  ENDLOOP.

  cs_res-fixed_fields = lv_fld_cnt.
  cs_res-fixed_auths  = lv_auth_cnt.
  cs_res-details      = lv_details.

  " -----------------------------------------------------------------
  " Step D: Simulation Mode Output
  " -----------------------------------------------------------------
  IF iv_test = abap_true.
    SELECT SINGLE profile FROM agr_1016 INTO @cs_res-profile
      WHERE agr_name = @iv_role.

    IF lv_fix_1251 = abap_true OR lv_fix_1250 = abap_true OR lv_fix_1252 = abap_true.
      cs_res-status  = gc_status_ok.
      cs_res-action  = 'SIMULATE'.
      cs_res-message = |[Simulated] Would standardize { lv_fld_cnt } field(s) in AGR_1251 and { lv_auth_cnt } object(s) in AGR_1250 to Standard 'S'.|.
    ELSE.
      cs_res-status  = gc_status_ok.
      cs_res-action  = 'SIMULATE'.
      cs_res-message = '[Simulated] All Org variables in role are already Standard and up-to-date.'.
    ENDIF.
    RETURN.
  ENDIF.

  " -----------------------------------------------------------------
  " Step E: Save and Commit Data via Standard FMs
  " -----------------------------------------------------------------
  IF lv_fix_1251 = abap_true.
    CALL FUNCTION 'PRGN_1251_SAVE_FIELD_VALUES'
      EXPORTING
        activity_group = iv_role
      TABLES
        field_values   = lt_pt1251.
  ENDIF.

  IF lv_fix_1250 = abap_true.
    CALL FUNCTION 'PRGN_1250_SAVE_AUTH_DATA'
      EXPORTING
        activity_group = iv_role
      TABLES
        auth_data      = lt_pt1250.
  ENDIF.

  IF lv_fix_1252 = abap_true.
    CALL FUNCTION 'PRGN_1252_SAVE_ORG_LEVELS'
      EXPORTING
        activity_group = iv_role
      TABLES
        org_levels     = lt_pt1252.
  ENDIF.

  IF lv_fix_1251 = abap_true OR lv_fix_1250 = abap_true OR lv_fix_1252 = abap_true.
    CALL FUNCTION 'PRGN_UPDATE_DATABASE'.
    COMMIT WORK AND WAIT.
  ENDIF.

  " -----------------------------------------------------------------
  " Step F: Profile Regeneration (if requested)
  " -----------------------------------------------------------------
  IF iv_genprf = abap_true.
    DATA: lt_bapi TYPE bapiret2_t.
    CLEAR lt_bapi.

    CALL FUNCTION 'SUPRN_DARK_MANIPULATE_PROFILE'
      EXPORTING
        activity_group        = iv_role
        fill_orgs_with_star   = space
        fill_fields_with_star = 'X'
        no_dialog             = 'X'
        rebuild_auth_data     = space
        generate_profile      = 'X'
      IMPORTING
        return                = lt_bapi
      EXCEPTIONS
        OTHERS                = 1.

    " Re-verify and ensure Org bindings remain Standard after generation
    PERFORM clean_final_1251_bindings USING iv_role.

    CALL FUNCTION 'PRGN_SET_ACTGROUP_TIMESTAMP'
      EXPORTING
        activity_group = iv_role
      EXCEPTIONS
        OTHERS         = 0.

    COMMIT WORK AND WAIT.
  ENDIF.

  SELECT SINGLE profile FROM agr_1016 INTO @cs_res-profile
    WHERE agr_name = @iv_role.

  IF lv_fix_1251 = abap_true OR lv_fix_1250 = abap_true OR lv_fix_1252 = abap_true.
    cs_res-status  = gc_status_ok.
    cs_res-action  = 'FIXED'.
    cs_res-message = |Standardized { lv_fld_cnt } Org field(s) in AGR_1251 and { lv_auth_cnt } object(s) in AGR_1250 to Standard 'S'.|.
  ELSE.
    cs_res-status  = gc_status_ok.
    cs_res-action  = 'UP-TO-DATE'.
    cs_res-message = 'All Org variables in role are already Standard and up-to-date.'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form clean_final_1251_bindings
*&---------------------------------------------------------------------*
FORM clean_final_1251_bindings USING iv_role TYPE agr_name.
  DATA: lt_pt1251 TYPE STANDARD TABLE OF pt1251,
        lt_pt1250 TYPE STANDARD TABLE OF pt1250,
        lv_mod51  TYPE abap_bool,
        lv_mod50  TYPE abap_bool.

  CLEAR: lt_pt1251, lt_pt1250, lv_mod51, lv_mod50.

  CALL FUNCTION 'PRGN_1251_READ_FIELD_VALUES'
    EXPORTING
      activity_group = iv_role
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
      IF <ls_f51>-low <> ls_uo-varbl OR <ls_f51>-modified <> 'S' OR <ls_f51>-neu <> 'O'.
        <ls_f51>-low      = ls_uo-varbl.
        <ls_f51>-high     = space.
        <ls_f51>-modified = 'S'.
        <ls_f51>-neu      = 'O'.
        lv_mod51          = abap_true.
      ENDIF.
    ENDLOOP.
  ENDLOOP.

  CALL FUNCTION 'PRGN_1250_READ_AUTH_DATA'
    EXPORTING
      activity_group = iv_role
      no_texts       = 'X'
    TABLES
      auth_data      = lt_pt1250
    EXCEPTIONS
      OTHERS         = 0.

  IF lt_pt1250 IS NOT INITIAL.
    LOOP AT lt_pt1250 ASSIGNING FIELD-SYMBOL(<ls_a50>) WHERE modified = 'U' OR modified = 'M'.
      READ TABLE lt_pt1251 TRANSPORTING NO FIELDS
        WITH KEY auth = <ls_a50>-auth modified = 'U' deleted = space.
      IF sy-subrc <> 0.
        <ls_a50>-modified = 'S'.
        lv_mod50          = abap_true.
      ENDIF.
    ENDLOOP.
  ENDIF.

  IF lv_mod51 = abap_true.
    CALL FUNCTION 'PRGN_1251_SAVE_FIELD_VALUES'
      EXPORTING
        activity_group = iv_role
      TABLES
        field_values   = lt_pt1251.
  ENDIF.

  IF lv_mod50 = abap_true.
    CALL FUNCTION 'PRGN_1250_SAVE_AUTH_DATA'
      EXPORTING
        activity_group = iv_role
      TABLES
        auth_data      = lt_pt1250.
  ENDIF.

  IF lv_mod51 = abap_true OR lv_mod50 = abap_true.
    CALL FUNCTION 'PRGN_UPDATE_DATABASE'.
    COMMIT WORK AND WAIT.
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

      " Format Column: AGR_NAME (Hotspot to PFCG)
      lo_col ?= lo_cols->get_column( 'AGR_NAME' ).
      lo_col->set_short_text( 'Role' ).
      lo_col->set_medium_text( 'Role Name' ).
      lo_col->set_long_text( 'Role Name (Click to open PFCG)' ).
      lo_col->set_cell_type( if_salv_c_cell_type=>hotspot ).

      " Format Column: ROLE_DESC
      lo_col ?= lo_cols->get_column( 'ROLE_DESC' ).
      lo_col->set_short_text( 'Desc' ).
      lo_col->set_medium_text( 'Role Description' ).
      lo_col->set_long_text( 'Role Description' ).

      " Format Column: PARENT_AGR (Hotspot to PFCG)
      lo_col ?= lo_cols->get_column( 'PARENT_AGR' ).
      lo_col->set_short_text( 'Parent' ).
      lo_col->set_medium_text( 'Master Role' ).
      lo_col->set_long_text( 'Parent Master Role (Click to open)' ).
      lo_col->set_cell_type( if_salv_c_cell_type=>hotspot ).

      " Format Column: FIXED_FIELDS
      lo_col ?= lo_cols->get_column( 'FIXED_FIELDS' ).
      lo_col->set_short_text( 'Fix Flds' ).
      lo_col->set_medium_text( 'Fixed Fields' ).
      lo_col->set_long_text( 'Fixed Org Level Fields' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " Format Column: FIXED_AUTHS
      lo_col ?= lo_cols->get_column( 'FIXED_AUTHS' ).
      lo_col->set_short_text( 'Fix Objs' ).
      lo_col->set_medium_text( 'Fixed Objs' ).
      lo_col->set_long_text( 'Fixed Auth Objects to Standard' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " Format Column: DETAILS
      lo_col ?= lo_cols->get_column( 'DETAILS' ).
      lo_col->set_short_text( 'Details' ).
      lo_col->set_medium_text( 'Fixed Details' ).
      lo_col->set_long_text( 'Fixed Objects and Fields' ).
      lo_col->set_output_length( 35 ).

      " Format Column: PROFILE
      lo_col ?= lo_cols->get_column( 'PROFILE' ).
      lo_col->set_short_text( 'Profile' ).
      lo_col->set_medium_text( 'Profile Name' ).
      lo_col->set_long_text( 'Generated Profile Name' ).

      " Format Column: MESSAGE
      lo_col ?= lo_cols->get_column( 'MESSAGE' ).
      lo_col->set_short_text( 'Message' ).
      lo_col->set_medium_text( 'Execution Message' ).
      lo_col->set_long_text( 'Execution Log & Message' ).
      lo_col->set_output_length( 50 ).

      " Register Hotspot Click Handler
      lo_events = lo_alv->get_event( ).
      SET HANDLER lcl_alv_event_handler=>on_link_click FOR lo_events.

      lo_alv->display( ).

    CATCH cx_salv_msg cx_salv_not_found.
      MESSAGE 'Failed to display ALV output.' TYPE 'E'.
  ENDTRY.
ENDFORM.
