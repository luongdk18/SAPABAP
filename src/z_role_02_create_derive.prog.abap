*&---------------------------------------------------------------------*
*& Report Z_ROLE_02_CREATE_DERIVE
*&---------------------------------------------------------------------*
*& Purpose: Batch PFCG Derived Role Creation & Inheritance Synchronization
*& Description:
*&   Reads a CSV (.csv) file containing role derivation
*&   mappings (Master Role, Derived Role, Derived Role Description), validates
*&   the Master Roles in SAP, creates the Derived Single Roles linked to the
*&   Master Role (PARENT_AGR), inherits authorization data, defaults
*&   unmaintained Organizational Levels to '-1', and generates authorization
*&   profiles automatically.
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

TABLES: agr_define, agr_texts, agr_1252, agr_1016.

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

DATA: gt_raw_rows     TYPE STANDARD TABLE OF ty_raw_row,
      gt_derive_roles TYPE STANDARD TABLE OF ty_derive_entry,
      gt_results      TYPE STANDARD TABLE OF ty_alv_result.

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
              p_orgdef TYPE abap_bool AS CHECKBOX DEFAULT 'X'.
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
  %_p_adjust_%_app_%-text = 'Inherit / Adjust Auth from Master'.
  %_p_genprf_%_app_%-text = 'Auto-Generate Auth Profiles'.
  %_p_orgdef_%_app_%-text = 'Default Org Levels to "-1"'.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  PERFORM f4_file_open CHANGING p_file.

*----------------------------------------------------------------------*
* 4. START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.
  PERFORM check_authority.
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
    ID 'ACTVT'     FIELD '01'.
  IF sy-subrc <> 0.
    MESSAGE 'No authorization to create/maintain roles (S_USER_AGR, ACTVT 01).' TYPE 'E'.
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
                           CHANGING ls_raw-col1 ls_raw-col2 ls_raw-col3.

    " Skip Header row: only check line 1 or exact header title equality
    DATA(lv_c1_up) = to_upper( ls_raw-col1 ).
    DATA(lv_c2_up) = to_upper( ls_raw-col2 ).
    IF lv_line_idx = 1 AND ( lv_c1_up CS 'MASTER' OR lv_c1_up CS 'ROLE' ).
      CONTINUE.
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
        lv_char   TYPE string.

  CLEAR: ev_col1, ev_col2, ev_col3.

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
    ev_col3 = lt_tokens[ 3 ]. " Keep exact spacing as in input file (no trim/condense)
  ENDIF.
ENDFORM.


*&---------------------------------------------------------------------*
*& Form aggregate_input_data
*&---------------------------------------------------------------------*
FORM aggregate_input_data.
  DATA: lv_m_role TYPE agr_name,
        lv_d_role TYPE agr_name,
        lv_d_desc TYPE agr_title.

  CLEAR gt_derive_roles.

  LOOP AT gt_raw_rows INTO DATA(ls_raw).
    lv_m_role = to_upper( condense( ls_raw-col1 ) ).
    lv_d_role = to_upper( condense( ls_raw-col2 ) ).
    lv_d_desc = ls_raw-col3. " Keep exact spacing

    IF lv_m_role IS INITIAL OR lv_d_role IS INITIAL.
      CONTINUE.
    ENDIF.

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
  DATA: ls_res          TYPE ty_alv_result,
        lt_bapiret      TYPE STANDARD TABLE OF bapiret2,
        lv_master_chk   TYPE agr_name,
        lv_master_coll  TYPE char01,
        lv_exists       TYPE abap_bool,
        lv_curr_par     TYPE agr_name,
        lv_new_req      TYPE trkorr,
        lv_drv_ok       TYPE char01,
        lv_adj_ok       TYPE char01,
        lv_prf_ok       TYPE char01.

  CLEAR gt_results.

  LOOP AT gt_derive_roles INTO DATA(ls_drv).
    CLEAR: ls_res, lt_bapiret, lv_master_chk, lv_master_coll, lv_exists,
           lv_curr_par, lv_new_req, lv_drv_ok, lv_adj_ok, lv_prf_ok.

    ls_res-derived_role = ls_drv-derived_role.
    ls_res-derived_desc = ls_drv-derived_desc.
    ls_res-master_role  = ls_drv-master_role.

    " -----------------------------------------------------------------
    " 1. Validate Master Role in SAP
    " -----------------------------------------------------------------
    CLEAR lv_master_chk.
    SELECT SINGLE agr_name FROM agr_define INTO lv_master_chk
      WHERE agr_name = ls_drv-master_role.
    IF sy-subrc <> 0 OR lv_master_chk IS INITIAL.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = |Master role '{ ls_drv-master_role }' does not exist in SAP.|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " Fetch Master Role Description from AGR_TEXTS
    CLEAR ls_res-master_desc.
    SELECT SINGLE text FROM agr_texts INTO ls_res-master_desc
      WHERE agr_name = ls_drv-master_role AND spras = sy-langu AND line = '00000'.
    IF sy-subrc <> 0.
      SELECT SINGLE text FROM agr_texts INTO ls_res-master_desc
        WHERE agr_name = ls_drv-master_role AND line = '00000'.
    ENDIF.

    " Verify Master Role is not a collective role
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
    " 2. Validate Derived Role Name
    " -----------------------------------------------------------------
    IF strlen( ls_drv-derived_role ) > 30.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = |Derived role name exceeds maximum allowed length of 30 characters.|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    IF ls_drv-derived_role = ls_drv-master_role.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = 'Derived role name cannot be identical to master role.'.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " 3. Check Derived Role Existence in SAP
    " -----------------------------------------------------------------
    CLEAR lv_curr_par.
    SELECT SINGLE parent_agr FROM agr_define INTO lv_curr_par
      WHERE agr_name = ls_drv-derived_role.
    IF sy-subrc = 0.
      lv_exists = abap_true.
    ELSE.
      lv_exists = abap_false.
    ENDIF.

    " -----------------------------------------------------------------
    " 4. Simulation Mode (Test Run)
    " -----------------------------------------------------------------
    IF p_test = abap_true.
      IF lv_exists = abap_true.
        IF p_upd = abap_true.
          ls_res-status  = gc_status_ok.
          ls_res-action  = 'SIMULATE'.
          ls_res-message = |[Simulated] Role exists (Parent: '{ lv_curr_par }'); would be updated & synchronized from master '{ ls_drv-master_role }'.|.
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
      " Role already exists
      IF p_upd = abap_false.
        ls_res-status  = gc_status_warn.
        ls_res-action  = 'SKIPPED'.
        ls_res-message = |Derived role already exists in SAP; skipped (Update option unselected).|.
        SELECT SINGLE profile FROM agr_1016 INTO ls_res-profile
          WHERE agr_name = ls_drv-derived_role.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.

      " --- Update Existing Derived Role ---
      " Update PARENT_AGR link in AGR_DEFINE if different via standard FM
      IF lv_curr_par NE ls_drv-master_role.
        DATA: lt_def_upd TYPE STANDARD TABLE OF agr_define.
        CLEAR lt_def_upd.
        APPEND VALUE agr_define(
          agr_name   = ls_drv-derived_role
          parent_agr = ls_drv-master_role
        ) TO lt_def_upd.
        CALL FUNCTION 'PRGN_STRU_SAVE_DEFINITION'
          EXPORTING
            enqueue        = 'X'
            message_output = space
          TABLES
            i_definition   = lt_def_upd
            return         = lt_bapiret
          EXCEPTIONS
            OTHERS         = 0.
      ENDIF.

      " Update Role Description and remove comment lines via standard FM
      PERFORM set_role_description USING ls_drv-derived_role ls_drv-derived_desc.

      " Synchronize / Adjust Auth data from master role
      CALL FUNCTION 'PRGN_RFC_CREATE_DERIVATION'
        EXPORTING
          role            = ls_drv-derived_role
          parent_role     = ls_drv-master_role
          adjust_auths    = p_adjust
          profile_gen     = space " Deferred until Org Levels are initialized
          no_dialog       = 'X'
        IMPORTING
          new_request     = lv_new_req
          derivation_ok   = lv_drv_ok
          adjust_auths_ok = lv_adj_ok
          profile_gen_ok  = lv_prf_ok
        TABLES
          return          = lt_bapiret.

      " Check for fatal errors in BAPI return
      DATA(lv_has_err) = abap_false.
      LOOP AT lt_bapiret INTO DATA(ls_bapi_chk) WHERE type CA 'EAX'.
        lv_has_err = abap_true.
        EXIT.
      ENDLOOP.

      IF lv_has_err = abap_true.
        ls_res-status = gc_status_err.
        ls_res-action = 'ERROR'.
        PERFORM format_bapi_message USING lt_bapiret CHANGING ls_res-message.
        IF ls_res-message IS INITIAL.
          ls_res-message = 'Error occurred during role synchronization.'.
        ENDIF.
      ELSE.
        " Ensure Org Levels are populated from master role and defaulted to '-1'
        IF p_orgdef = abap_true.
          PERFORM set_org_levels_default USING ls_drv-derived_role ls_drv-master_role.
        ENDIF.

        " Regenerate profile after Org Levels are properly initialized
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
              OTHERS                = 1.
          CALL FUNCTION 'PRGN_SET_ACTGROUP_TIMESTAMP'
            EXPORTING
              activity_group = ls_drv-derived_role
            EXCEPTIONS
              OTHERS         = 0.
          COMMIT WORK AND WAIT.
        ENDIF.

        ls_res-status  = gc_status_ok.
        ls_res-action  = 'UPDATED'.
        ls_res-message = |Derived role updated & synchronized from master '{ ls_drv-master_role }'.|.
        IF p_orgdef = abap_true.
          ls_res-message = |{ ls_res-message } Org levels defaulted to '-1'.|.
        ENDIF.
      ENDIF.

    ELSE.
      " --- Create New Derived Role ---
      " Step 1: Create Role Definition with parent link via PRGN_RFC_CREATE_AGR_MULTIPLE
      CALL FUNCTION 'PRGN_RFC_CREATE_AGR_MULTIPLE'
        EXPORTING
          activity_group                = ls_drv-derived_role
          parent_role                   = ls_drv-master_role
          activity_group_text           = ls_drv-derived_desc
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

      IF sy-subrc <> 0.
        ls_res-status = gc_status_err.
        ls_res-action = 'ERROR'.
        PERFORM format_bapi_message USING lt_bapiret CHANGING ls_res-message.
        IF ls_res-message IS INITIAL.
          ls_res-message = |Failed to create derived role definition (sy-subrc = { sy-subrc }).|.
        ENDIF.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.

      " Step 2: Clean automatic comments from AGR_TEXTS via standard FM
      PERFORM set_role_description USING ls_drv-derived_role ls_drv-derived_desc.
      COMMIT WORK AND WAIT.

      " Step 3: Inherit auths from Master Role
      CLEAR lt_bapiret.
      CALL FUNCTION 'PRGN_RFC_CREATE_DERIVATION'
        EXPORTING
          role            = ls_drv-derived_role
          parent_role     = ls_drv-master_role
          adjust_auths    = p_adjust
          profile_gen     = space " Deferred until Org Levels are initialized
          no_dialog       = 'X'
        IMPORTING
          new_request     = lv_new_req
          derivation_ok   = lv_drv_ok
          adjust_auths_ok = lv_adj_ok
          profile_gen_ok  = lv_prf_ok
        TABLES
          return          = lt_bapiret.

      CLEAR lv_has_err.
      LOOP AT lt_bapiret INTO ls_bapi_chk WHERE type CA 'EAX'.
        lv_has_err = abap_true.
        EXIT.
      ENDLOOP.

      IF lv_has_err = abap_true.
        ls_res-status = gc_status_err.
        ls_res-action = 'ERROR'.
        PERFORM format_bapi_message USING lt_bapiret CHANGING ls_res-message.
        IF ls_res-message IS INITIAL.
          ls_res-message = 'Error occurred during auth transfer from master role.'.
        ENDIF.
      ELSE.
        " Step 4: Populate Org Levels from Master Role and default to '-1'
        IF p_orgdef = abap_true.
          PERFORM set_org_levels_default USING ls_drv-derived_role ls_drv-master_role.
        ENDIF.

        " Step 5: Regenerate profile after Org Levels are initialized
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
              OTHERS                = 1.
          CALL FUNCTION 'PRGN_SET_ACTGROUP_TIMESTAMP'
            EXPORTING
              activity_group = ls_drv-derived_role
            EXCEPTIONS
              OTHERS         = 0.
          COMMIT WORK AND WAIT.
        ENDIF.

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
*& Form set_org_levels_default
*&---------------------------------------------------------------------*
* Sets all Organizational Levels for Derived Roles to '-1'
* (Copies required Org Variables from Master Role or Authorizations)
*&---------------------------------------------------------------------*
FORM set_org_levels_default USING iv_agr_name    TYPE agr_name
                                  iv_master_name TYPE agr_name.
  DATA: lt_pt1252      TYPE TABLE OF pt1252,
        lt_master_1252 TYPE TABLE OF agr_1252,
        lt_auth_vars   TYPE TABLE OF agval.

  CLEAR: lt_pt1252, lt_master_1252, lt_auth_vars.

  " 1. Read Master Role's AGR_1252
  SELECT * FROM agr_1252 INTO TABLE @lt_master_1252
    WHERE agr_name = @iv_master_name
    ORDER BY counter.

  IF lt_master_1252 IS NOT INITIAL.
    LOOP AT lt_master_1252 INTO DATA(ls_m).
      APPEND VALUE pt1252(
        varbl = ls_m-varbl
        low   = '-1'
        high  = space
      ) TO lt_pt1252.
    ENDLOOP.
  ELSE.
    " Fallback: Read Org variables from authorizations in AGR_1251
    SELECT DISTINCT low FROM agr_1251 INTO TABLE @lt_auth_vars
      WHERE agr_name = @iv_agr_name AND low LIKE '$%'.
    IF lt_auth_vars IS INITIAL.
      SELECT DISTINCT low FROM agr_1251 INTO TABLE @lt_auth_vars
        WHERE agr_name = @iv_master_name AND low LIKE '$%'.
    ENDIF.

    LOOP AT lt_auth_vars INTO DATA(lv_var).
      APPEND VALUE pt1252(
        varbl = lv_var
        low   = '-1'
        high  = space
      ) TO lt_pt1252.
    ENDLOOP.
  ENDIF.

  IF lt_pt1252 IS NOT INITIAL.
    CALL FUNCTION 'PRGN_1252_SAVE_ORG_LEVELS'
      EXPORTING
        activity_group = iv_agr_name
      TABLES
        org_levels     = lt_pt1252.
    CALL FUNCTION 'PRGN_UPDATE_DATABASE'.
  ENDIF.

  COMMIT WORK AND WAIT.
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
      IF column = 'DERIVED_ROLE' AND ls_row-derived_role IS NOT INITIAL.
        SET PARAMETER ID 'AGR' FIELD ls_row-derived_role.
        CALL TRANSACTION 'PFCG' AND SKIP FIRST SCREEN.
      ELSEIF column = 'MASTER_ROLE' AND ls_row-master_role IS NOT INITIAL.
        SET PARAMETER ID 'AGR' FIELD ls_row-master_role.
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
