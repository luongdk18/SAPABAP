*&---------------------------------------------------------------------*
*& Report Z_ROLE_04_COMPOSITE
*&---------------------------------------------------------------------*
*& Purpose: Batch PFCG Composite Role Creation & Single Role Assignment
*& Description:
*&   Reads a CSV (.csv) file containing composite role definitions and
*&   single/derived role assignments (Composite Role Name, Composite Role
*&   Description, Single/Derived Role), validates single roles in SAP,
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
*&   Col 3: Single / Derived Role      (e.g., Z_FI_PERIOD_CONTROL_1000 or N/A)
*&
*& Author: Antigravity AI (SAP Basis Engineering)
*& Package: $TMP
*&---------------------------------------------------------------------*
REPORT z_role_04_composite.

TABLES: agr_define, agr_texts, agr_flags, agr_agrs.

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
         status         TYPE char4,      " Icon (@08@ Green, @09@ Yellow, @0A@ Red)
         action         TYPE char12,     " Action: CREATED / UPDATED / SIMULATE / SKIPPED / WARNING / ERROR
         composite_role TYPE agr_name,   " Composite Role ID (Hotspot to PFCG)
         role_desc      TYPE agr_title,  " Composite Role Description
         roles_cnt      TYPE i,          " Total Single Roles in CSV
         valid_cnt      TYPE i,          " Valid Single Roles in SAP
         assigned_cnt   TYPE i,          " Successfully Assigned Single Roles
         missing_roles  TYPE string,     " Single Roles missing from SAP
         message        TYPE string,     " Status Message / Execution Log
       END OF ty_alv_result.

DATA: gt_raw_rows        TYPE STANDARD TABLE OF ty_raw_row,
      gt_composite_roles TYPE STANDARD TABLE OF ty_composite_role,
      gt_results         TYPE STANDARD TABLE OF ty_alv_result.

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
  %_p_upd_%_app_%-text    = 'Update Existing Composite Roles'.
  %_p_sync_%_app_%-text   = 'Synchronize Single Roles'.
  %_p_chksgl_%_app_%-text = 'Validate Single Roles in SAP'.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  PERFORM f4_file_open CHANGING p_file.

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
    IF lv_line IS INITIAL.
      CONTINUE.
    ENDIF.

    CLEAR: lv_c1, lv_c2, lv_c3.
    PERFORM parse_csv_line USING lv_line
                           CHANGING lv_c1 lv_c2 lv_c3.

    " Skip header row
    DATA(lv_c1_up) = to_upper( lv_c1 ).
    DATA(lv_c2_up) = to_upper( lv_c2 ).
    DATA(lv_c3_up) = to_upper( lv_c3 ).

    IF lv_line_idx = 1 AND ( lv_c1_up CS 'COMPOSITE' OR lv_c1_up CS 'ROLE' ).
      CONTINUE.
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
  DATA: lv_c_role TYPE agr_name,
        lv_c_desc TYPE agr_title,
        lv_s_role TYPE agr_name.

  CLEAR gt_composite_roles.

  LOOP AT gt_raw_rows INTO DATA(ls_raw).
    lv_c_role = to_upper( condense( ls_raw-col1 ) ).
    lv_c_desc = ls_raw-col2. " Exact spacing preserved
    lv_s_role = to_upper( condense( ls_raw-col3 ) ).

    IF lv_c_role IS INITIAL.
      CONTINUE.
    ENDIF.

    READ TABLE gt_composite_roles ASSIGNING FIELD-SYMBOL(<ls_comp>)
      WITH KEY role_name = lv_c_role.
    IF sy-subrc <> 0.
      APPEND VALUE ty_composite_role(
        role_name = lv_c_role
        role_desc = lv_c_desc
      ) TO gt_composite_roles ASSIGNING <ls_comp>.
    ENDIF.

    " Populate description if previously initial
    IF <ls_comp>-role_desc IS INITIAL AND lv_c_desc IS NOT INITIAL.
      <ls_comp>-role_desc = lv_c_desc.
    ENDIF.

    " Handle empty single role indicators (N/A, NA, -, NONE, space)
    IF lv_s_role = 'N/A' OR lv_s_role = 'NA' OR lv_s_role = '-' OR lv_s_role = 'NONE' OR lv_s_role IS INITIAL.
      <ls_comp>-has_na = abap_true.
    ELSE.
      " Prevent duplicate single roles for the same composite role
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
        lv_missing_str  TYPE string.

  CLEAR gt_results.

  LOOP AT gt_composite_roles INTO DATA(ls_comp).
    CLEAR: ls_res, lt_bapiret, lv_exists, lv_coll_flag, lv_dummy,
           lt_valid_sgl, lt_missing_sgl, lt_colls_sgl, lt_add_txt, lt_del_txt,
           lt_curr_agrs, lv_new_req, lv_missing_str.

    ls_res-composite_role = ls_comp-role_name.
    ls_res-role_desc      = ls_comp-role_desc.
    ls_res-roles_cnt      = lines( ls_comp-single_roles ).

    " -----------------------------------------------------------------
    " 1. Validate Composite Role Name Length (SAP Max 30 chars)
    " -----------------------------------------------------------------
    IF strlen( ls_comp-role_name ) > 30.
      ls_res-status  = '@0A@'. " Red LED
      ls_res-action  = 'ERROR'.
      ls_res-message = 'Composite role name exceeds maximum allowed length of 30 characters.'.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " 2. Validate Existing Role Type in SAP
    " -----------------------------------------------------------------
    CLEAR lv_dummy.
    SELECT SINGLE agr_name FROM agr_define INTO lv_dummy
      WHERE agr_name = ls_comp-role_name.
    IF sy-subrc = 0.
      lv_exists = abap_true.

      " Ensure the existing role is a composite role (COLL_AGR = 'X')
      SELECT SINGLE flag_value FROM agr_flags INTO lv_coll_flag
        WHERE agr_name = ls_comp-role_name AND flag_type = 'COLL_AGR'.
      IF sy-subrc <> 0 OR lv_coll_flag <> 'X'.
        ls_res-status  = '@0A@'. " Red LED
        ls_res-action  = 'ERROR'.
        ls_res-message = |Role '{ ls_comp-role_name }' exists in SAP as a SINGLE role; cannot overwrite single role as composite role.|.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.
    ELSE.
      lv_exists = abap_false.
    ENDIF.

    " -----------------------------------------------------------------
    " 3. Validate Single Roles in SAP (AGR_DEFINE & AGR_FLAGS)
    " -----------------------------------------------------------------
    IF ls_comp-single_roles IS NOT INITIAL AND p_chksgl = abap_true.
      LOOP AT ls_comp-single_roles INTO DATA(lv_chk_role).
        CLEAR lv_dummy.
        SELECT SINGLE agr_name FROM agr_define INTO lv_dummy
          WHERE agr_name = lv_chk_role.
        IF sy-subrc <> 0.
          APPEND lv_chk_role TO lt_missing_sgl.
        ELSE.
          " Ensure assigned role is NOT itself a composite role (SAP restriction)
          CLEAR lv_coll_flag.
          SELECT SINGLE flag_value FROM agr_flags INTO lv_coll_flag
            WHERE agr_name = lv_chk_role AND flag_type = 'COLL_AGR'.
          IF sy-subrc = 0 AND lv_coll_flag = 'X'.
            APPEND lv_chk_role TO lt_colls_sgl.
            APPEND lv_chk_role TO lt_missing_sgl.
          ELSE.
            APPEND lv_chk_role TO lt_valid_sgl.
          ENDIF.
        ENDIF.
      ENDLOOP.

      ls_res-valid_cnt = lines( lt_valid_sgl ).

      " Build missing roles string
      IF lt_missing_sgl IS NOT INITIAL.
        LOOP AT lt_missing_sgl INTO DATA(lv_m).
          IF lv_missing_str IS INITIAL.
            lv_missing_str = lv_m.
          ELSE.
            CONCATENATE lv_missing_str ',' lv_m INTO lv_missing_str SEPARATED BY space.
          ENDIF.
        ENDLOOP.
        ls_res-missing_roles = lv_missing_str.
      ENDIF.

    ELSEIF ls_comp-single_roles IS NOT INITIAL.
      " If check is disabled, assume all single roles are valid
      lt_valid_sgl = ls_comp-single_roles.
      ls_res-valid_cnt = lines( lt_valid_sgl ).
    ELSE.
      ls_res-valid_cnt = 0.
    ENDIF.

    " -----------------------------------------------------------------
    " 4. Simulation Mode (Test Run)
    " -----------------------------------------------------------------
    IF p_test = abap_true.
      IF lv_exists = abap_true.
        IF p_upd = abap_true.
          IF lt_missing_sgl IS NOT INITIAL.
            ls_res-status  = '@09@'. " Yellow LED
            ls_res-action  = 'SIMULATE'.
            ls_res-message = |[Simulated] Role exists; would update assignments ({ lines( lt_valid_sgl ) } valid, { lines( lt_missing_sgl ) } missing).|.
          ELSE.
            ls_res-status  = '@08@'. " Green LED
            ls_res-action  = 'SIMULATE'.
            ls_res-message = |[Simulated] Role exists; would update assignments ({ lines( lt_valid_sgl ) } single roles).|.
          ENDIF.
        ELSE.
          ls_res-status  = '@09@'. " Yellow LED
          ls_res-action  = 'SIMULATE'.
          ls_res-message = '[Simulated] Composite role already exists; would be skipped (Update option unselected).'.
        ENDIF.
      ELSE.
        IF ls_comp-single_roles IS INITIAL AND ls_comp-has_na = abap_true.
          ls_res-status  = '@09@'. " Yellow LED
          ls_res-action  = 'SIMULATE'.
          ls_res-message = '[Simulated] Role does not exist; would be created without single roles (N/A).'.
        ELSEIF lt_missing_sgl IS NOT INITIAL.
          ls_res-status  = '@09@'. " Yellow LED
          ls_res-action  = 'SIMULATE'.
          ls_res-message = |[Simulated] Role does not exist; would be created ({ lines( lt_valid_sgl ) } valid, { lines( lt_missing_sgl ) } missing).|.
        ELSE.
          ls_res-status  = '@08@'. " Green LED
          ls_res-action  = 'SIMULATE'.
          ls_res-message = |[Simulated] Role does not exist; would be created as Composite Role with { lines( lt_valid_sgl ) } single roles.|.
        ENDIF.
      ENDIF.

      " Read currently assigned count for simulation review
      SELECT COUNT(*) FROM agr_agrs INTO @ls_res-assigned_cnt
        WHERE agr_name = @ls_comp-role_name.

      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " 5. Real Execution: Role Shell Creation / Updating
    " -----------------------------------------------------------------
    IF lv_exists = abap_true.
      " Composite Role Already Exists
      IF p_upd = abap_false.
        ls_res-status  = '@09@'. " Yellow LED
        ls_res-action  = 'SKIPPED'.
        ls_res-message = 'Composite role already exists in SAP; skipped (Update option unselected).'.
        SELECT COUNT(*) FROM agr_agrs INTO @ls_res-assigned_cnt
          WHERE agr_name = @ls_comp-role_name.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.

      " Update Description in AGR_TEXTS (preserving exact spacing)
      UPDATE agr_texts SET text = @ls_comp-role_desc
        WHERE agr_name = @ls_comp-role_name AND line = '00000'.
      IF sy-subrc <> 0.
        DATA(ls_txt_upd) = VALUE agr_texts(
          mandt    = sy-mandt
          agr_name = ls_comp-role_name
          spras    = sy-langu
          line     = '00000'
          text     = ls_comp-role_desc
        ).
        MODIFY agr_texts FROM @ls_txt_upd.
      ENDIF.

      " Strip automatic comments from AGR_TEXTS
      DELETE FROM agr_texts
        WHERE agr_name = @ls_comp-role_name AND line > '00000'.

      ls_res-action = 'UPDATED'.

    ELSE.
      " Create New Composite Role via PRGN_RFC_CREATE_AGR_MULTIPLE
      CALL FUNCTION 'PRGN_RFC_CREATE_AGR_MULTIPLE'
        EXPORTING
          activity_group                = ls_comp-role_name
          activity_group_text           = ls_comp-role_desc
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

      IF sy-subrc <> 0.
        ls_res-status = '@0A@'. " Red LED
        ls_res-action = 'ERROR'.
        PERFORM format_bapi_message USING lt_bapiret CHANGING ls_res-message.
        IF ls_res-message IS INITIAL.
          ls_res-message = |Failed to create composite role shell (sy-subrc = { sy-subrc }).|.
        ENDIF.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.

      " Ensure clean description in AGR_TEXTS (exact spacing, remove comment lines)
      UPDATE agr_texts SET text = @ls_comp-role_desc
        WHERE agr_name = @ls_comp-role_name AND line = '00000'.
      DELETE FROM agr_texts
        WHERE agr_name = @ls_comp-role_name AND line > '00000'.
      COMMIT WORK AND WAIT.

      ls_res-action = 'CREATED'.
    ENDIF.

    " -----------------------------------------------------------------
    " 6. Assign / Synchronize Single Roles
    " -----------------------------------------------------------------
    IF ls_comp-single_roles IS INITIAL AND ls_comp-has_na = abap_true.
      ls_res-status       = '@09@'. " Yellow LED
      ls_res-assigned_cnt = 0.
      ls_res-message      = 'Composite role created without single roles (N/A).'.

    ELSEIF lt_valid_sgl IS INITIAL.
      ls_res-status       = '@09@'. " Yellow LED
      ls_res-assigned_cnt = 0.
      ls_res-message      = 'No valid single roles found in SAP to assign.'.

    ELSE.
      " Read current single role assignments in AGR_AGRS
      SELECT * FROM agr_agrs INTO TABLE @lt_curr_agrs
        WHERE agr_name = @ls_comp-role_name.

      " If Synchronize is active, identify roles to delete (roles in SAP but no longer in CSV)
      IF p_sync = abap_true AND lt_curr_agrs IS NOT INITIAL.
        LOOP AT lt_curr_agrs INTO DATA(ls_curr).
          READ TABLE lt_valid_sgl WITH KEY table_line = ls_curr-child_agr
            TRANSPORTING NO FIELDS.
          IF sy-subrc <> 0.
            APPEND VALUE agr_txt( agr_name = ls_curr-child_agr ) TO lt_del_txt.
          ENDIF.
        ENDLOOP.

        IF lt_del_txt IS NOT INITIAL.
          CLEAR lt_bapiret.
          CALL FUNCTION 'PRGN_RFC_DEL_AGRS_IN_COLL_AGR'
            EXPORTING
              activity_group              = ls_comp-role_name
              profile_comparison          = 'X'
              no_dialog                   = 'X'
            TABLES
              activity_groups             = lt_del_txt
              return                      = lt_bapiret
            EXCEPTIONS
              OTHERS                      = 0.
        ENDIF.
      ENDIF.

      " Determine single roles to add (valid single roles not yet assigned in AGR_AGRS)
      LOOP AT lt_valid_sgl INTO DATA(lv_sgl_add).
        READ TABLE lt_curr_agrs WITH KEY child_agr = lv_sgl_add
          TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0 OR p_sync = abap_false.
          APPEND VALUE agr_txt( agr_name = lv_sgl_add ) TO lt_add_txt.
        ENDIF.
      ENDLOOP.

      IF lt_add_txt IS NOT INITIAL.
        CLEAR lt_bapiret.
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
      ENDIF.

      " Update role timestamp in AGR_DEFINE
      CALL FUNCTION 'PRGN_SET_ACTGROUP_TIMESTAMP'
        EXPORTING
          activity_group = ls_comp-role_name
        EXCEPTIONS
          OTHERS         = 0.
      COMMIT WORK AND WAIT.

      " Count final assigned single roles
      SELECT COUNT(*) FROM agr_agrs INTO @ls_res-assigned_cnt
        WHERE agr_name = @ls_comp-role_name.

      " Set execution status
      IF lt_missing_sgl IS NOT INITIAL.
        ls_res-status  = '@09@'. " Yellow LED
        ls_res-message = |{ ls_res-action }: { ls_res-assigned_cnt } single roles assigned ({ lines( lt_missing_sgl ) } missing in SAP).|.
      ELSE.
        ls_res-status  = '@08@'. " Green LED
        ls_res-message = |{ ls_res-action }: { ls_res-assigned_cnt } single roles successfully assigned.|.
      ENDIF.
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
      SET PARAMETER ID 'AGR' FIELD ls_row-composite_role.
      CALL TRANSACTION 'PFCG' AND SKIP FIRST SCREEN.
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

      " Assigned Roles Count
      lo_col ?= lo_cols->get_column( 'ASSIGNED_CNT' ).
      lo_col->set_short_text( 'Assign Cnt' ).
      lo_col->set_medium_text( 'Assigned Roles' ).
      lo_col->set_long_text( 'Successfully Assigned Roles' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " Missing Roles
      lo_col ?= lo_cols->get_column( 'MISSING_ROLES' ).
      lo_col->set_short_text( 'Missing' ).
      lo_col->set_medium_text( 'Missing Roles' ).
      lo_col->set_long_text( 'Single Roles Missing from SAP' ).
      lo_col->set_output_length( 40 ).

      " Message Column
      lo_col ?= lo_cols->get_column( 'MESSAGE' ).
      lo_col->set_short_text( 'Message' ).
      lo_col->set_medium_text( 'Execution Message' ).
      lo_col->set_long_text( 'Execution Message / Details' ).

      " Register Hotspot Event Handler
      lo_events = lo_alv->get_event( ).
      SET HANDLER lcl_alv_event_handler=>on_link_click FOR lo_events.

      lo_alv->display( ).

    CATCH cx_salv_msg cx_salv_not_found.
      MESSAGE 'Error rendering ALV report display.' TYPE 'E'.
  ENDTRY.
ENDFORM.
