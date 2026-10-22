*&---------------------------------------------------------------------*
*& Report Z_ROLE_03A_UPDATE_ORG
*&---------------------------------------------------------------------*
*& Purpose: Batch Update Organizational Levels for PFCG Roles
*& Description:
*&   Reads a CSV (.csv) file containing Organizational
*&   Level values for roles (Role Name, Org Level Variable, Org Value),
*&   updates table AGR_1252 via standard PFCG function modules, restores
*&   Org Variable bindings in AGR_1251 if corrupted, regenerates authorization
*&   profiles, and displays execution results in an interactive ALV grid.
*&
*& File format (CSV .csv):
*&   Col 1: Role Name             (e.g., Z_FI_PERIOD_CONTROL_1000)
*&   Col 2: Org Level Variable    (e.g., $ERKRS or $BUKRS or BUKRS)
*&   Col 3: Org Value-Low         (e.g., 1000, 1000*, *)
*&   Col 4: Org Value-High        (e.g., 2000, optional)
*&
*& Author: Antigravity AI (SAP Basis Engineering)
*& Package: $TMP (Local Object) or Custom Package
*&---------------------------------------------------------------------*
REPORT z_role_03a_update_org.

TABLES: agr_define, agr_texts, agr_1252, agr_1251, agr_1016, usorg.

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
         org_cnt  TYPE i,
       END OF ty_role_entry.

TYPES: BEGIN OF ty_role_org,
         agr_name TYPE agr_name,
         varbl    TYPE agval,
         val_low  TYPE agval,
         val_high TYPE agval,
       END OF ty_role_org.

TYPES: BEGIN OF ty_alv_result,
         status        TYPE char12,    " Status Icon & Code: @08@ [OK], @09@ [WARN], @0A@ [ERR]
         action        TYPE char12,    " Action: UPDATED / UP-TO-DATE / SIMULATE / ERROR / WARNING
         agr_name      TYPE agr_name,  " Role ID (Hotspot to PFCG)
         role_desc     TYPE agr_title, " Role Description
         parent_agr    TYPE agr_name,  " Parent Master Role (Hotspot to PFCG)
         orgs_file_cnt TYPE i,         " Number of Org Levels in input file
         orgs_upd_cnt  TYPE i,         " Number of Org Levels updated in AGR_1252
         orgs_skip_cnt TYPE i,         " Number of Org Levels in file skipped (not in role)
         orgs_detail   TYPE string,    " Detail summary of updated Org Levels
         profile       TYPE xuprofile, " Generated Profile Name
         message       TYPE string,    " Status Message / Execution Log
       END OF ty_alv_result.

CONSTANTS: gc_status_ok   TYPE char12 VALUE '@08@ [OK]',
           gc_status_warn TYPE char12 VALUE '@09@ [WARN]',
           gc_status_err  TYPE char12 VALUE '@0A@ [ERR]'.

DATA: gt_raw_rows  TYPE STANDARD TABLE OF ty_raw_row,
      gt_roles     TYPE STANDARD TABLE OF ty_role_entry,
      gt_role_orgs TYPE STANDARD TABLE OF ty_role_org,
      gt_results   TYPE STANDARD TABLE OF ty_alv_result,
      gt_usorg_map TYPE STANDARD TABLE OF usorg.

*----------------------------------------------------------------------*
* 2. SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b_file WITH FRAME TITLE b_tit1.
  PARAMETERS: p_file TYPE localfile OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b_file.

SELECTION-SCREEN BEGIN OF BLOCK b_opt WITH FRAME TITLE b_tit2.
  PARAMETERS: p_test   TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_genprf TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_astnon TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_fix51  TYPE abap_bool AS CHECKBOX DEFAULT 'X'.
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
  %_p_astnon_%_app_%-text = 'Default Unlisted Org Levels to *'.
  %_p_fix51_%_app_%-text  = 'Restore Variables in AGR_1251'.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  PERFORM f4_file_open CHANGING p_file.

*----------------------------------------------------------------------*
* 4. START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.
  PERFORM check_authority.
  PERFORM upload_and_parse_file.
  PERFORM aggregate_input_data.
  PERFORM process_org_update.
  PERFORM display_alv_results.

*&---------------------------------------------------------------------*
*& Form f4_file_open
*&---------------------------------------------------------------------*
FORM f4_file_open CHANGING cv_file TYPE localfile.
  DATA: lt_file_table TYPE filetable,
        lv_rc         TYPE i.

  cl_gui_frontend_services=>file_open_dialog(
    EXPORTING
      window_title            = 'Select Role Org Levels CSV File'
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
    IF lv_line_idx = 1 AND ( lv_c1_up CS 'ROLE' OR lv_c2_up CS 'ORG' OR lv_c2_up CS 'VAR' ).
      CONTINUE.
    ENDIF.
    IF lv_c1_up = 'ROLE NAME' OR lv_c1_up = 'ROLE_NAME' OR lv_c1_up = 'ROLE'
       OR lv_c2_up = 'ORG LEVEL VARIABLE' OR lv_c2_up = 'ORG_LEVEL_VARIABLE' OR lv_c2_up = 'VARIABLE'.
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
    ev_col3 = condense( ev_col3 ).
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
        lv_var      TYPE agval,
        lv_low      TYPE agval,
        lv_high     TYPE agval,
        ls_role_ent TYPE ty_role_entry.

  CLEAR: gt_roles, gt_role_orgs.

  LOOP AT gt_raw_rows INTO DATA(ls_raw).
    lv_role = to_upper( condense( ls_raw-col1 ) ).
    lv_var  = to_upper( condense( ls_raw-col2 ) ).
    lv_low  = condense( ls_raw-col3 ).
    lv_high = condense( ls_raw-col4 ).

    IF lv_role IS INITIAL OR lv_var IS INITIAL.
      CONTINUE.
    ENDIF.

    " Ensure Org Variable has leading '$' (e.g. BUKRS -> $BUKRS)
    IF lv_var(1) NE '$'.
      lv_var = '$' && lv_var.
    ENDIF.

    " Strip surrounding quotes or Excel formula wrapping (e.g. ="00000000" -> 00000000)
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

    " Handle potential ranges (LOW - HIGH or LOW:HIGH) if col4 is initial (backwards compatibility)
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

    " Maintain Role Header count
    READ TABLE gt_roles ASSIGNING FIELD-SYMBOL(<ls_r>) WITH KEY agr_name = lv_role.
    IF sy-subrc = 0.
      <ls_r>-org_cnt = <ls_r>-org_cnt + 1.
    ELSE.
      CLEAR ls_role_ent.
      ls_role_ent-agr_name = lv_role.
      ls_role_ent-org_cnt  = 1.
      APPEND ls_role_ent TO gt_roles.
    ENDIF.

    " Maintain Role Org Variable entry
    APPEND VALUE ty_role_org(
      agr_name = lv_role
      varbl    = lv_var
      val_low  = lv_low
      val_high = lv_high
    ) TO gt_role_orgs.
  ENDLOOP.

  " Preload USORG mapping for field synchronization / variable restoration
  CLEAR gt_usorg_map.
  SELECT * FROM usorg INTO TABLE @gt_usorg_map.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form process_org_update
*&---------------------------------------------------------------------*
FORM process_org_update.
  DATA: ls_res         TYPE ty_alv_result,
        lt_curr_1252   TYPE STANDARD TABLE OF agr_1252,
        lt_parent_1252 TYPE STANDARD TABLE OF agr_1252,
        lt_auth_vars   TYPE STANDARD TABLE OF agval,
        lt_all_vars    TYPE STANDARD TABLE OF agval,
        lt_pt1252      TYPE STANDARD TABLE OF pt1252,
        lt_bapiret     TYPE STANDARD TABLE OF bapiret2,
        lv_agr_chk     TYPE agr_name,
        lv_parent_chk  TYPE agr_name,
        lv_chg_cnt     TYPE i,
        lv_match_cnt   TYPE i,
        lv_detail      TYPE string,
        lv_t_low       TYPE agval,
        lv_t_high      TYPE agval,
        lv_from_file   TYPE abap_bool.

  CLEAR gt_results.

  LOOP AT gt_roles INTO DATA(ls_role).
    CLEAR: ls_res, lt_curr_1252, lt_parent_1252, lt_auth_vars, lt_all_vars,
           lt_pt1252, lt_bapiret, lv_agr_chk, lv_parent_chk,
           lv_chg_cnt, lv_match_cnt, lv_detail.

    ls_res-agr_name      = ls_role-agr_name.
    ls_res-orgs_file_cnt = ls_role-org_cnt.

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
    " 2. Restore Org Variable Bindings in AGR_1251 (if corrupted with '-1')
    " -----------------------------------------------------------------
    IF p_fix51 = abap_true AND p_test = abap_false.
      DATA: lt_pt1251_fix TYPE STANDARD TABLE OF pt1251,
            lv_fix_needed TYPE abap_bool.
      CLEAR: lt_pt1251_fix, lv_fix_needed.

      CALL FUNCTION 'PRGN_1251_READ_FIELD_VALUES'
        EXPORTING
          activity_group    = ls_role-agr_name
        TABLES
          field_values      = lt_pt1251_fix
        EXCEPTIONS
          OTHERS            = 1.

      IF sy-subrc = 0 AND lt_pt1251_fix IS NOT INITIAL.
        LOOP AT gt_usorg_map INTO DATA(ls_um).
          LOOP AT lt_pt1251_fix ASSIGNING FIELD-SYMBOL(<ls_f51>)
            WHERE field = ls_um-field AND low = '-1'.
            <ls_f51>-low      = ls_um-varbl.
            <ls_f51>-modified = 'U'.
            lv_fix_needed     = abap_true.
          ENDLOOP.
        ENDLOOP.

        IF lv_fix_needed = abap_true.
          CALL FUNCTION 'PRGN_1251_SAVE_FIELD_VALUES'
            EXPORTING
              activity_group = ls_role-agr_name
            TABLES
              field_values   = lt_pt1251_fix.
          CALL FUNCTION 'PRGN_UPDATE_DATABASE'.
          COMMIT WORK AND WAIT.
        ENDIF.
      ENDIF.
    ENDIF.

    " -----------------------------------------------------------------
    " 3. Read Existing Org Levels in Role (AGR_1252)
    " -----------------------------------------------------------------
    SELECT * FROM agr_1252 INTO TABLE @lt_curr_1252
      WHERE agr_name = @ls_role-agr_name
      ORDER BY counter.

    " -----------------------------------------------------------------
    " 4. Read Org Levels in Parent Master Role (AGR_1252)
    " -----------------------------------------------------------------
    IF lv_parent_chk IS NOT INITIAL.
      SELECT * FROM agr_1252 INTO TABLE @lt_parent_1252
        WHERE agr_name = @lv_parent_chk
        ORDER BY counter.
    ENDIF.

    " -----------------------------------------------------------------
    " 5. Find Org Variables in Authorizations (AGR_1251)
    " -----------------------------------------------------------------
    SELECT DISTINCT low FROM agr_1251 INTO TABLE @lt_auth_vars
      WHERE agr_name = @ls_role-agr_name AND low LIKE '$%'.
    IF lv_parent_chk IS NOT INITIAL.
      SELECT DISTINCT low FROM agr_1251 APPENDING TABLE @lt_auth_vars
        WHERE agr_name = @lv_parent_chk AND low LIKE '$%'.
    ENDIF.
    SORT lt_auth_vars.
    DELETE ADJACENT DUPLICATES FROM lt_auth_vars.

    " -----------------------------------------------------------------
    " 6. Assemble Full Set of Required Org Variables for Role
    " -----------------------------------------------------------------
    " Rule: Only maintain Org Variables that legitimately belong to role:
    "  - Variables currently in role's AGR_1252
    "  - Variables in parent master role's AGR_1252
    "  - Variables in AGR_1251 authorizations ($...)
    " Do NOT blindly add unassigned Org Levels from input file!
    " a) Variables currently in role's AGR_1252
    LOOP AT lt_curr_1252 INTO DATA(ls_c1252).
      APPEND ls_c1252-varbl TO lt_all_vars.
    ENDLOOP.
    " b) Variables in parent role's AGR_1252
    LOOP AT lt_parent_1252 INTO DATA(ls_p1252).
      APPEND ls_p1252-varbl TO lt_all_vars.
    ENDLOOP.
    " c) Variables in AGR_1251 authorizations
    LOOP AT lt_auth_vars INTO DATA(lv_av).
      APPEND lv_av TO lt_all_vars.
    ENDLOOP.

    SORT lt_all_vars.
    DELETE ADJACENT DUPLICATES FROM lt_all_vars.
    DELETE lt_all_vars WHERE table_line IS INITIAL.

    " Count Org Levels in file that do NOT belong to this role
    DATA: lv_skip_file_cnt TYPE i.
    CLEAR lv_skip_file_cnt.
    LOOP AT gt_role_orgs INTO DATA(ls_chk_file) WHERE agr_name = ls_role-agr_name.
      READ TABLE lt_all_vars WITH KEY table_line = ls_chk_file-varbl TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        lv_skip_file_cnt = lv_skip_file_cnt + 1.
      ENDIF.
    ENDLOOP.
    ls_res-orgs_skip_cnt = lv_skip_file_cnt.

    " If role has NO Org Levels at all (e.g. only S_TCODE / non-org objects)
    IF lt_all_vars IS INITIAL.
      ls_res-status       = gc_status_ok.
      ls_res-action       = 'UP-TO-DATE'.
      ls_res-orgs_upd_cnt = 0.
      IF lv_skip_file_cnt > 0.
        ls_res-message = |Role contains no Org Levels in authorizations. { lv_skip_file_cnt } Org Level(s) in CSV skipped (not in role).|.
      ELSE.
        ls_res-message = 'Role contains no Org Levels in authorizations.'.
      ENDIF.
      SELECT SINGLE profile FROM agr_1016 INTO @ls_res-profile
        WHERE agr_name = @ls_role-agr_name.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " 7. Build Updated Org Levels Table (PT1252)
    " -----------------------------------------------------------------
    LOOP AT lt_all_vars INTO DATA(lv_varbl).
      CLEAR: lv_t_low, lv_t_high, lv_from_file.

      " Priority 1: Value from input file
      READ TABLE gt_role_orgs INTO DATA(ls_org_in)
        WITH KEY agr_name = ls_role-agr_name varbl = lv_varbl.
      IF sy-subrc = 0.
        lv_t_low     = ls_org_in-val_low.
        lv_t_high    = ls_org_in-val_high.
        lv_from_file = abap_true.
        lv_match_cnt = lv_match_cnt + 1.
      ELSE.
        " Priority 2: Keep existing value in AGR_1252 if maintained & valid (not empty, not $, not -1)
        READ TABLE lt_curr_1252 INTO DATA(ls_c_exist)
          WITH KEY varbl = lv_varbl.
        IF sy-subrc = 0 AND ls_c_exist-low IS NOT INITIAL
                        AND ls_c_exist-low <> '$'
                        AND ls_c_exist-low <> '-1'.
          lv_t_low  = ls_c_exist-low.
          lv_t_high = ls_c_exist-high.
        ELSEIF p_astnon = abap_true.
          " Priority 3: Default unlisted Org Levels to '*' to guarantee GREEN status
          lv_t_low = '*'.
          CLEAR lv_t_high.
        ELSE.
          " Priority 4: Inherit from parent role if available
          READ TABLE lt_parent_1252 INTO DATA(ls_p_exist)
            WITH KEY varbl = lv_varbl.
          IF sy-subrc = 0 AND ls_p_exist-low IS NOT INITIAL AND ls_p_exist-low <> '$'.
            lv_t_low  = ls_p_exist-low.
            lv_t_high = ls_p_exist-high.
          ELSE.
            lv_t_low = '*'.
          ENDIF.
        ENDIF.
      ENDIF.

      " Check if changed or newly added
      READ TABLE lt_curr_1252 INTO DATA(ls_old_chk) WITH KEY varbl = lv_varbl.
      IF sy-subrc <> 0 OR ls_old_chk-low <> lv_t_low OR ls_old_chk-high <> lv_t_high.
        lv_chg_cnt = lv_chg_cnt + 1.
      ENDIF.

      APPEND VALUE pt1252(
        varbl = lv_varbl
        low   = lv_t_low
        high  = lv_t_high
      ) TO lt_pt1252.

      IF lv_from_file = abap_true.
        IF lv_detail IS INITIAL.
          lv_detail = |{ lv_varbl }={ lv_t_low }|.
        ELSEIF strlen( lv_detail ) < 200.
          lv_detail = |{ lv_detail }, { lv_varbl }={ lv_t_low }|.
        ENDIF.
      ENDIF.
    ENDLOOP.

    ls_res-orgs_upd_cnt = lv_chg_cnt.
    ls_res-orgs_detail  = lv_detail.

    " -----------------------------------------------------------------
    " 8. Simulation Mode
    " -----------------------------------------------------------------
    IF p_test = abap_true.
      IF lv_chg_cnt > 0 OR lines( lt_curr_1252 ) <> lines( lt_pt1252 ).
        ls_res-status  = gc_status_ok.
        ls_res-action  = 'SIMULATE'.
        ls_res-message = |[Simulated] { lv_chg_cnt } Org Level(s) will be updated/maintained (Total: { lines( lt_pt1252 ) }).|.
      ELSE.
        ls_res-status  = gc_status_ok.
        ls_res-action  = 'SIMULATE'.
        ls_res-message = |[Simulated] All { lines( lt_pt1252 ) } Org Levels in role are already up-to-date.|.
      ENDIF.
      IF lv_skip_file_cnt > 0.
        ls_res-message = |{ ls_res-message } { lv_skip_file_cnt } Org Level(s) in CSV skipped (not in role).|.
      ENDIF.

      SELECT SINGLE profile FROM agr_1016 INTO @ls_res-profile
        WHERE agr_name = @ls_role-agr_name.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " 9. Real Execution
    " -----------------------------------------------------------------
    IF lv_chg_cnt > 0 OR lines( lt_curr_1252 ) <> lines( lt_pt1252 ).
      " Save via PFCG Function Module & PRGN_UPDATE_DATABASE
      CALL FUNCTION 'PRGN_1252_SAVE_ORG_LEVELS'
        EXPORTING
          activity_group = ls_role-agr_name
        TABLES
          org_levels     = lt_pt1252.

      CALL FUNCTION 'PRGN_UPDATE_DATABASE'.

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
      ENDIF.

      CALL FUNCTION 'PRGN_SET_ACTGROUP_TIMESTAMP'
        EXPORTING
          activity_group = ls_role-agr_name
        EXCEPTIONS
          OTHERS         = 0.

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
        ls_res-message = |Maintained { lines( lt_pt1252 ) } Org Level(s) ({ lv_chg_cnt } updated). Profile '{ ls_res-profile }' is GREEN (Current).|.
      ELSEIF lv_chk_color = 'YELLOW'.
        ls_res-status  = gc_status_warn.
        ls_res-action  = 'UPDATED'.
        ls_res-message = |Maintained { lines( lt_pt1252 ) } Org Level(s). Profile Yellow: { lv_chk_msg }|.
      ELSE.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'WARNING'.
        ls_res-message = |Profile Red: { lv_chk_msg }|.
      ENDIF.
      IF lv_skip_file_cnt > 0.
        ls_res-message = |{ ls_res-message } { lv_skip_file_cnt } Org Level(s) in CSV skipped (not in role).|.
      ENDIF.

    ELSE.
      SELECT SINGLE profile FROM agr_1016 INTO @ls_res-profile
        WHERE agr_name = @ls_role-agr_name.

      ls_res-status  = gc_status_ok.
      ls_res-action  = 'UP-TO-DATE'.
      ls_res-message = |All { lines( lt_pt1252 ) } Org Levels in role are already up-to-date.|.
      IF lv_skip_file_cnt > 0.
        ls_res-message = |{ ls_res-message } { lv_skip_file_cnt } Org Level(s) in CSV skipped (not in role).|.
      ENDIF.
    ENDIF.

    APPEND ls_res TO gt_results.
  ENDLOOP.
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

      " Format Column: ORGS_FILE_CNT
      lo_col ?= lo_cols->get_column( 'ORGS_FILE_CNT' ).
      lo_col->set_short_text( 'File Orgs' ).
      lo_col->set_medium_text( 'File Org Cnt' ).
      lo_col->set_long_text( 'Org Levels in Input File' ).
      lo_col->set_alignment( if_salv_c_alignment=>right ).

      " Format Column: ORGS_UPD_CNT
      lo_col ?= lo_cols->get_column( 'ORGS_UPD_CNT' ).
      lo_col->set_short_text( 'Upd Orgs' ).
      lo_col->set_medium_text( 'Updated Orgs' ).
      lo_col->set_long_text( 'Org Levels Updated' ).
      lo_col->set_alignment( if_salv_c_alignment=>right ).

      " Format Column: ORGS_SKIP_CNT
      lo_col ?= lo_cols->get_column( 'ORGS_SKIP_CNT' ).
      lo_col->set_short_text( 'Skip Orgs' ).
      lo_col->set_medium_text( 'Skipped Orgs' ).
      lo_col->set_long_text( 'Org Levels Skipped (Not in Role)' ).
      lo_col->set_alignment( if_salv_c_alignment=>right ).

      " Format Column: ORGS_DETAIL
      lo_col ?= lo_cols->get_column( 'ORGS_DETAIL' ).
      lo_col->set_short_text( 'Org Values' ).
      lo_col->set_medium_text( 'Updated Values' ).
      lo_col->set_long_text( 'Summary of Updated Org Values' ).

      " Format Column: PROFILE
      lo_col ?= lo_cols->get_column( 'PROFILE' ).
      lo_col->set_short_text( 'Profile' ).
      lo_col->set_medium_text( 'Auth Profile' ).
      lo_col->set_long_text( 'Generated Profile Name' ).

      " Format Column: MESSAGE
      lo_col ?= lo_cols->get_column( 'MESSAGE' ).
      lo_col->set_short_text( 'Log Msg' ).
      lo_col->set_medium_text( 'Status Message' ).
      lo_col->set_long_text( 'Execution Message / Result Log' ).

      " Attach Click Event Handler
      lo_events = lo_alv->get_event( ).
      SET HANDLER lcl_alv_event_handler=>on_link_click FOR lo_events.

      " Display ALV Fullscreen
      lo_alv->display( ).

    CATCH cx_root INTO DATA(lx_salv_err).
      DATA(lv_salv_msg) = lx_salv_err->get_text( ).
      MESSAGE |Error displaying ALV grid: { lv_salv_msg }| TYPE 'E'.
  ENDTRY.
ENDFORM.
