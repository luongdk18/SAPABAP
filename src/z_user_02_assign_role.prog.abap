*&---------------------------------------------------------------------*
*& Report Z_USER_02_ASSIGN_ROLE
*&---------------------------------------------------------------------*
*& Purpose: Batch User-Role Assignment Cockpit from CSV file
*& Description:
*&   Reads a CSV (.csv) file containing user-to-role assignments (Username,
*&   Role), aggregates multiple roles per user, validates user existence
*&   in table USR02, validates role existence in AGR_DEFINE (handling single,
*&   derived, and composite roles), assigns roles via standard BAPI
*&   (BAPI_USER_ACTGROUPS_ASSIGN), supports simulation mode (Test Run),
*&   preserves existing user assignments via Append mode, and displays
*&   results in an interactive ALV cockpit with one-click navigation to
*&   transaction SU01.
*&
*& File format (CSV .csv):
*&   Col 1: Username (e.g., JOHND, max 12 chars, uppercase)
*&   Col 2: Role     (e.g., CR_COMMON, Z_FI_COMP_CFO_1000, or N/A)
*&
*& Author: Antigravity AI (SAP Basis Engineering)
*& Package: $TMP (Local Object) or Custom Package
*&---------------------------------------------------------------------*
REPORT z_user_02_assign_role.

TABLES: usr02, agr_define, agr_users.

*----------------------------------------------------------------------*
* 1. TYPES & DATA DEFINITIONS
*----------------------------------------------------------------------*
TYPES: ty_bin_255 TYPE x LENGTH 255.

TYPES: BEGIN OF ty_raw_row,
         username TYPE string,
         role     TYPE string,
       END OF ty_raw_row.

TYPES: BEGIN OF ty_user_assignment,
         username TYPE bapibname-bapibname,
         has_na   TYPE abap_bool,
         roles    TYPE STANDARD TABLE OF agr_name WITH DEFAULT KEY,
       END OF ty_user_assignment.

TYPES: BEGIN OF ty_alv_result,
         status         TYPE char12,              " Status Icon & Code: @08@ [OK], @09@ [WARN], @0A@ [ERR]
         action         TYPE char12,              " ASSIGNED / SIMULATED / SKIPPED / WARNING / ERROR
         username       TYPE bapibname-bapibname, " SAP User ID (Hotspot to SU01)
         roles_cnt      TYPE i,                   " Total Roles in CSV
         valid_cnt      TYPE i,                   " Valid Roles in SAP
         assigned_cnt   TYPE i,                   " Successfully Assigned Roles
         assigned_roles TYPE string,              " List of Assigned Roles
         missing_roles  TYPE string,              " Roles Missing in SAP
         message        TYPE string,              " Execution Log / BAPI Message
       END OF ty_alv_result.

CONSTANTS: gc_status_ok   TYPE char12 VALUE '@08@ [OK]',
           gc_status_warn TYPE char12 VALUE '@09@ [WARN]',
           gc_status_err  TYPE char12 VALUE '@0A@ [ERR]'.

DATA: gt_raw_rows    TYPE STANDARD TABLE OF ty_raw_row,
      gt_assignments TYPE STANDARD TABLE OF ty_user_assignment,
      gt_results     TYPE STANDARD TABLE OF ty_alv_result.

*----------------------------------------------------------------------*
* 2. SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b_file WITH FRAME TITLE b_tit1.
  PARAMETERS: p_file TYPE localfile OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b_file.

SELECTION-SCREEN BEGIN OF BLOCK b_proc WITH FRAME TITLE b_tit2.
  PARAMETERS: p_test   TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_append TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_chkrol TYPE abap_bool AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b_proc.

SELECTION-SCREEN BEGIN OF BLOCK b_date WITH FRAME TITLE b_tit3.
  PARAMETERS: p_from TYPE bapiagr-from_dat DEFAULT sy-datum,
              p_to   TYPE bapiagr-to_dat   DEFAULT '99991231'.
SELECTION-SCREEN END OF BLOCK b_date.

*----------------------------------------------------------------------*
* 3. INITIALIZATION & SCREEN EVENTS
*----------------------------------------------------------------------*
INITIALIZATION.
  b_tit1 = 'Input CSV File (.csv)'(b01).
  b_tit2 = 'Execution & Assignment Options'(b02).
  b_tit3 = 'Assignment Validity Period'(b03).

  %_p_file_%_app_%-text   = 'File Path'.
  %_p_test_%_app_%-text   = 'Simulation (Test Run)'.
  %_p_append_%_app_%-text = 'Append to Existing Roles'.
  %_p_chkrol_%_app_%-text = 'Validate Roles in SAP'.
  %_p_from_%_app_%-text   = 'Valid From Date'.
  %_p_to_%_app_%-text     = 'Valid To Date'.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  PERFORM f4_file_open CHANGING p_file.

*----------------------------------------------------------------------*
* 4. START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.
  PERFORM check_authority.
  PERFORM upload_and_parse_file USING p_file.
  PERFORM aggregate_input_data.
  PERFORM process_assignments.
  PERFORM display_alv_results.

*&---------------------------------------------------------------------*
*& Form f4_file_open
*&---------------------------------------------------------------------*
FORM f4_file_open CHANGING cv_file TYPE localfile.
  DATA: lt_filetable TYPE filetable,
        ls_file      TYPE file_table,
        lv_rc        TYPE i.

  cl_gui_frontend_services=>file_open_dialog(
    EXPORTING
      window_title            = 'Select User-Role Assignment CSV File (.csv)'
      default_extension       = 'csv'
      file_filter             = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'
    CHANGING
      file_table              = lt_filetable
      rc                      = lv_rc
    EXCEPTIONS
      file_open_dialog_failed = 1
      cntl_error              = 2
      error_no_gui            = 3
      not_supported_by_gui    = 4
      OTHERS                  = 5 ).

  IF sy-subrc = 0 AND lv_rc > 0.
    READ TABLE lt_filetable INTO ls_file INDEX 1.
    IF sy-subrc = 0.
      cv_file = ls_file-filename.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form check_authority
*&---------------------------------------------------------------------*
FORM check_authority.
  " Check authorization for role assignment to users (S_USER_AGR / S_USER_GRP)
  AUTHORITY-CHECK OBJECT 'S_USER_AGR'
    ID 'ACT_GROUP' DUMMY
    ID 'ACTVT'     FIELD '22'. " Assign
  IF sy-subrc <> 0.
    AUTHORITY-CHECK OBJECT 'S_USER_AGR'
      ID 'ACT_GROUP' DUMMY
      ID 'ACTVT'     FIELD '02'. " Change
    IF sy-subrc <> 0.
      AUTHORITY-CHECK OBJECT 'S_USER_GRP'
        ID 'CLASS' DUMMY
        ID 'ACTVT' FIELD '02'.
      IF sy-subrc <> 0 AND p_test = abap_false.
        MESSAGE 'No authorization to assign roles to users (S_USER_AGR / S_USER_GRP).' TYPE 'E'.
      ENDIF.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form upload_and_parse_file
*&---------------------------------------------------------------------*
FORM upload_and_parse_file USING iv_file TYPE localfile.
  DATA: lv_filepath   TYPE string,
        lt_binary_tab TYPE STANDARD TABLE OF ty_bin_255,
        lv_length     TYPE i,
        lv_content    TYPE string,
        lt_lines      TYPE STANDARD TABLE OF string,
        lv_line       TYPE string,
        lv_line_idx   TYPE i,
        ls_raw        TYPE ty_raw_row,
        lv_c1         TYPE string,
        lv_c2         TYPE string.

  lv_filepath = iv_file.

  cl_gui_frontend_services=>gui_upload(
    EXPORTING
      filename                = lv_filepath
      filetype                = 'BIN'
    IMPORTING
      filelength              = lv_length
    CHANGING
      data_tab                = lt_binary_tab
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

  IF lv_length <= 0.
    MESSAGE 'Selected file is empty.' TYPE 'E'.
  ENDIF.

  " Convert binary buffer to UTF-8 string
  CALL FUNCTION 'SCMS_BINARY_TO_STRING'
    EXPORTING
      input_length = lv_length
      encoding     = '4110' " UTF-8
    IMPORTING
      text_buffer  = lv_content
    TABLES
      binary_tab   = lt_binary_tab
    EXCEPTIONS
      failed       = 1
      OTHERS       = 2.

  IF sy-subrc <> 0.
    CALL FUNCTION 'SCMS_BINARY_TO_STRING'
      EXPORTING
        input_length = lv_length
      IMPORTING
        text_buffer  = lv_content
      TABLES
        binary_tab   = lt_binary_tab
      EXCEPTIONS
        OTHERS       = 1.
  ENDIF.

  " Strip Byte Order Mark (BOM U+FEFF) if present
  DATA(lv_bom) = cl_abap_conv_in_ce=>uccp( 'FEFF' ).
  IF strlen( lv_content ) > 0 AND lv_content(1) = lv_bom.
    lv_content = lv_content+1.
  ENDIF.

  " Split by CR/LF or Newline
  SPLIT lv_content AT cl_abap_char_utilities=>cr_lf INTO TABLE lt_lines.
  IF lines( lt_lines ) <= 1.
    SPLIT lv_content AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.
  ENDIF.

  CLEAR: gt_raw_rows, lv_line_idx.

  LOOP AT lt_lines INTO lv_line.
    lv_line_idx = lv_line_idx + 1.
    IF lv_line IS INITIAL.
      CONTINUE.
    ENDIF.

    " Strip BOM from line 1 if still present
    IF lv_line_idx = 1 AND strlen( lv_line ) > 0 AND lv_line(1) = lv_bom.
      lv_line = lv_line+1.
    ENDIF.

    CLEAR: lv_c1, lv_c2.
    PERFORM parse_csv_line USING lv_line
                           CHANGING lv_c1 lv_c2.

    " Skip header row
    DATA(lv_c1_up) = to_upper( lv_c1 ).
    DATA(lv_c2_up) = to_upper( lv_c2 ).
    IF lv_line_idx = 1 AND ( lv_c1_up CS 'USER' OR lv_c2_up CS 'ROLE' ).
      CONTINUE.
    ENDIF.
    IF lv_c1_up = 'USERNAME' OR lv_c1_up = 'USER' OR lv_c1_up = 'BNAME'
       OR lv_c2_up = 'ROLE' OR lv_c2_up = 'ROLE NAME' OR lv_c2_up = 'AGR_NAME'.
      CONTINUE.
    ENDIF.

    IF lv_c1 IS NOT INITIAL.
      CLEAR ls_raw.
      ls_raw-username = lv_c1.
      ls_raw-role     = lv_c2.
      APPEND ls_raw TO gt_raw_rows.
    ENDIF.
  ENDLOOP.

  IF gt_raw_rows IS INITIAL.
    MESSAGE 'No valid assignment records found in CSV file.' TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form parse_csv_line
*&---------------------------------------------------------------------*
FORM parse_csv_line USING    iv_line TYPE string
                    CHANGING ev_col1 TYPE string
                             ev_col2 TYPE string.
  DATA: lt_tokens TYPE STANDARD TABLE OF string,
        lv_len    TYPE i,
        lv_in_q   TYPE abap_bool VALUE abap_false,
        lv_cur    TYPE string,
        lv_char   TYPE string.

  CLEAR: ev_col1, ev_col2.

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
      CONCATENATE lv_cur lv_char INTO lv_cur.
    ENDIF.
  ENDDO.
  APPEND lv_cur TO lt_tokens.

  READ TABLE lt_tokens INTO ev_col1 INDEX 1.
  READ TABLE lt_tokens INTO ev_col2 INDEX 2.

  PERFORM clean_cell CHANGING ev_col1.
  PERFORM clean_cell CHANGING ev_col2.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form clean_cell
*&---------------------------------------------------------------------*
FORM clean_cell CHANGING cv_val TYPE string.
  CONDENSE cv_val.
  IF strlen( cv_val ) >= 2 AND cv_val(1) = '"' AND cv_val+sy-fdpos(1) = '"'.
    DATA(lv_inner_len) = strlen( cv_val ) - 2.
    IF lv_inner_len > 0.
      cv_val = cv_val+1(lv_inner_len).
    ELSE.
      CLEAR cv_val.
    ENDIF.
  ENDIF.
  CONDENSE cv_val.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form aggregate_input_data
*&---------------------------------------------------------------------*
FORM aggregate_input_data.
  DATA: ls_assign TYPE ty_user_assignment,
        lv_uname  TYPE bapibname-bapibname,
        lv_role   TYPE agr_name.

  CLEAR gt_assignments.

  LOOP AT gt_raw_rows INTO DATA(ls_raw).
    CLEAR: lv_uname, lv_role.

    lv_uname = to_upper( ls_raw-username ).
    CONDENSE lv_uname NO-GAPS.

    lv_role = to_upper( ls_raw-role ).
    CONDENSE lv_role NO-GAPS.

    IF lv_uname IS INITIAL.
      CONTINUE.
    ENDIF.

    READ TABLE gt_assignments ASSIGNING FIELD-SYMBOL(<fs_assign>)
      WITH KEY username = lv_uname.

    IF sy-subrc = 0.
      IF lv_role = 'N/A' OR lv_role IS INITIAL.
        <fs_assign>-has_na = abap_true.
      ELSE.
        READ TABLE <fs_assign>-roles TRANSPORTING NO FIELDS
          WITH KEY table_line = lv_role.
        IF sy-subrc <> 0.
          APPEND lv_role TO <fs_assign>-roles.
        ENDIF.
      ENDIF.
    ELSE.
      CLEAR ls_assign.
      ls_assign-username = lv_uname.
      IF lv_role = 'N/A' OR lv_role IS INITIAL.
        ls_assign-has_na = abap_true.
      ELSE.
        APPEND lv_role TO ls_assign-roles.
      ENDIF.
      APPEND ls_assign TO gt_assignments.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form process_assignments
*&---------------------------------------------------------------------*
FORM process_assignments.
  DATA: ls_res          TYPE ty_alv_result,
        lt_valid_roles  TYPE STANDARD TABLE OF agr_name,
        lt_miss_roles   TYPE STANDARD TABLE OF agr_name,
        lt_actgroups    TYPE STANDARD TABLE OF bapiagr,
        ls_actgroup     TYPE bapiagr,
        lt_return       TYPE STANDARD TABLE OF bapiret2,
        lv_errmsg       TYPE string,
        lv_has_err      TYPE abap_bool,
        lv_str_assigned TYPE string,
        lv_str_missing  TYPE string.

  CLEAR gt_results.

  LOOP AT gt_assignments INTO DATA(ls_assign).
    CLEAR: ls_res, lt_valid_roles, lt_miss_roles, lt_actgroups,
           lt_return, lv_errmsg, lv_has_err, lv_str_assigned, lv_str_missing.

    ls_res-username  = ls_assign-username.
    ls_res-roles_cnt = lines( ls_assign-roles ).

    " Validation 1: Username must not be initial
    IF ls_assign-username IS INITIAL.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = 'Username is empty or missing.'.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " Validation 2: Username length <= 12 characters (SAP limit)
    IF strlen( ls_assign-username ) > 12.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = 'Username exceeds SAP 12-character limit: ' && ls_assign-username.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " Validation 3: Check user existence in USR02
    SELECT SINGLE bname FROM usr02 INTO @DATA(lv_exist_uname)
      WHERE bname = @ls_assign-username.
    IF sy-subrc <> 0.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = 'User does not exist in SAP (table USR02).'.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " Handle user with empty roles (N/A)
    IF ls_assign-roles IS INITIAL.
      IF ls_assign-has_na = abap_true.
        ls_res-status  = gc_status_warn.
        ls_res-action  = 'WARNING'.
        ls_res-message = 'No roles to assign for this user (marked as N/A in CSV).'.
      ELSE.
        ls_res-status  = gc_status_warn.
        ls_res-action  = 'WARNING'.
        ls_res-message = 'No role entries found for this user in the CSV file.'.
      ENDIF.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " Validate roles existence in AGR_DEFINE (if p_chkrol is active)
    IF p_chkrol = abap_true.
      LOOP AT ls_assign-roles INTO DATA(lv_role).
        SELECT SINGLE agr_name FROM agr_define INTO @DATA(lv_exist_agr)
          WHERE agr_name = @lv_role.
        IF sy-subrc = 0.
          APPEND lv_role TO lt_valid_roles.
        ELSE.
          APPEND lv_role TO lt_miss_roles.
        ENDIF.
      ENDLOOP.
    ELSE.
      lt_valid_roles = ls_assign-roles.
    ENDIF.

    ls_res-valid_cnt = lines( lt_valid_roles ).

    " Build missing roles string
    LOOP AT lt_miss_roles INTO DATA(lv_mrole).
      IF lv_str_missing IS INITIAL.
        lv_str_missing = lv_mrole.
      ELSE.
        lv_str_missing = lv_str_missing && ', ' && lv_mrole.
      ENDIF.
    ENDLOOP.
    ls_res-missing_roles = lv_str_missing.

    " If all roles in CSV are missing from SAP
    IF lt_valid_roles IS INITIAL.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = 'All specified roles are missing from SAP repository (AGR_DEFINE).'.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " Build list of target roles to assign
    " If p_append = 'X', preserve existing roles from AGR_USERS (direct assignments only)
    IF p_append = abap_true.
      SELECT agr_name, from_dat, to_dat FROM agr_users
        INTO TABLE @DATA(lt_existing_roles)
        WHERE uname = @ls_assign-username
          AND col_flag = @space.

      LOOP AT lt_existing_roles INTO DATA(ls_exist).
        CLEAR ls_actgroup.
        ls_actgroup-agr_name = ls_exist-agr_name.
        ls_actgroup-from_dat = ls_exist-from_dat.
        ls_actgroup-to_dat   = ls_exist-to_dat.
        APPEND ls_actgroup TO lt_actgroups.
      ENDLOOP.
    ENDIF.

    " Merge new valid roles from CSV
    LOOP AT lt_valid_roles INTO DATA(lv_vrole).
      READ TABLE lt_actgroups ASSIGNING FIELD-SYMBOL(<fs_act>)
        WITH KEY agr_name = lv_vrole.
      IF sy-subrc = 0.
        " Update validity if already present
        <fs_act>-from_dat = p_from.
        <fs_act>-to_dat   = p_to.
      ELSE.
        CLEAR ls_actgroup.
        ls_actgroup-agr_name = lv_vrole.
        ls_actgroup-from_dat = p_from.
        ls_actgroup-to_dat   = p_to.
        APPEND ls_actgroup TO lt_actgroups.
      ENDIF.
    ENDLOOP.

    ls_res-assigned_cnt = lines( lt_actgroups ).

    " Build assigned roles string
    LOOP AT lt_actgroups INTO DATA(ls_grp).
      IF lv_str_assigned IS INITIAL.
        lv_str_assigned = ls_grp-agr_name.
      ELSE.
        lv_str_assigned = lv_str_assigned && ', ' && ls_grp-agr_name.
      ENDIF.
    ENDLOOP.
    ls_res-assigned_roles = lv_str_assigned.

    " Simulation Mode (Test Run)
    IF p_test = abap_true.
      IF lt_miss_roles IS NOT INITIAL.
        ls_res-status  = gc_status_warn.
        ls_res-action  = 'WARNING'.
        ls_res-message = 'Simulated: ' && |{ lines( lt_valid_roles ) }| && ' new roles will be assigned. ' &&
                         |{ lines( lt_miss_roles ) }| && ' roles are missing in SAP.'.
      ELSE.
        ls_res-status  = gc_status_ok.
        ls_res-action  = 'SIMULATED'.
        ls_res-message = 'Simulated: Total ' && |{ lines( lt_actgroups ) }| && ' roles will be assigned (Valid ' &&
                         p_from && ' to ' && p_to && ').'.
      ENDIF.
      APPEND ls_res TO gt_results.

    " Live Execution Mode
    ELSE.
      CALL FUNCTION 'BAPI_USER_ACTGROUPS_ASSIGN'
        EXPORTING
          username       = ls_assign-username
        TABLES
          activitygroups = lt_actgroups
          return         = lt_return.

      PERFORM format_return_messages USING lt_return
                                     CHANGING lv_errmsg lv_has_err.

      IF lv_has_err = abap_true.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'ERROR'.
        ls_res-message = lv_errmsg.
      ELSE.
        CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
          EXPORTING
            wait = 'X'.

        IF lt_miss_roles IS NOT INITIAL.
          ls_res-status  = gc_status_warn.
          ls_res-action  = 'WARNING'.
          ls_res-message = 'Roles assigned successfully, but ' && |{ lines( lt_miss_roles ) }| &&
                           ' roles are missing from SAP.'.
        ELSE.
          ls_res-status  = gc_status_ok.
          ls_res-action  = 'ASSIGNED'.
          IF lv_errmsg IS NOT INITIAL.
            ls_res-message = 'Roles assigned successfully: ' && lv_errmsg.
          ELSE.
            ls_res-message = 'Total ' && |{ lines( lt_actgroups ) }| && ' roles assigned successfully to user.'.
          ENDIF.
        ENDIF.
      ENDIF.
      APPEND ls_res TO gt_results.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form format_return_messages
*&---------------------------------------------------------------------*
FORM format_return_messages USING    it_return  TYPE bapiret2_t
                            CHANGING ev_message TYPE string
                                     ev_error   TYPE abap_bool.
  DATA: ls_ret TYPE bapiret2,
        lv_txt TYPE string.

  CLEAR: ev_message, ev_error.

  LOOP AT it_return INTO ls_ret.
    IF ls_ret-type = 'E' OR ls_ret-type = 'A'.
      ev_error = abap_true.
    ENDIF.

    lv_txt = ls_ret-message.
    IF lv_txt IS INITIAL AND ls_ret-id IS NOT INITIAL.
      MESSAGE ID ls_ret-id TYPE ls_ret-type NUMBER ls_ret-number
        WITH ls_ret-message_v1 ls_ret-message_v2 ls_ret-message_v3 ls_ret-message_v4
        INTO lv_txt.
    ENDIF.

    IF lv_txt IS NOT INITIAL.
      IF ev_message IS INITIAL.
        ev_message = lv_txt.
      ELSE.
        ev_message = ev_message && ' | ' && lv_txt.
      ENDIF.
    ENDIF.
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
    IF sy-subrc = 0 AND column = 'USERNAME' AND ls_row-username IS NOT INITIAL.
      SET PARAMETER ID 'USR' FIELD ls_row-username.
      CALL TRANSACTION 'SU01' AND SKIP FIRST SCREEN.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

*&---------------------------------------------------------------------*
*& Form display_alv_results
*&---------------------------------------------------------------------*
FORM display_alv_results.
  DATA: lo_alv       TYPE REF TO cl_salv_table,
        lo_functions TYPE REF TO cl_salv_functions_list,
        lo_cols      TYPE REF TO cl_salv_columns_table,
        lo_col       TYPE REF TO cl_salv_column_table,
        lo_events    TYPE REF TO cl_salv_events_table.

  IF gt_results IS INITIAL.
    MESSAGE 'No user assignment records were processed.' TYPE 'S' DISPLAY LIKE 'W'.
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

      " Username Column (Hotspot link to SU01)
      lo_col ?= lo_cols->get_column( 'USERNAME' ).
      lo_col->set_short_text( 'User' ).
      lo_col->set_medium_text( 'SAP User' ).
      lo_col->set_long_text( 'SAP User ID (Click to open SU01)' ).
      lo_col->set_cell_type( if_salv_c_cell_type=>hotspot ).

      " Roles Count (in CSV)
      lo_col ?= lo_cols->get_column( 'ROLES_CNT' ).
      lo_col->set_short_text( 'CSV Roles' ).
      lo_col->set_medium_text( 'CSV Role Count' ).
      lo_col->set_long_text( 'Total Roles in CSV' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " Valid Roles Count (in SAP)
      lo_col ?= lo_cols->get_column( 'VALID_CNT' ).
      lo_col->set_short_text( 'Valid' ).
      lo_col->set_medium_text( 'Valid in SAP' ).
      lo_col->set_long_text( 'Valid Roles in SAP' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " Total Assigned Roles Count
      lo_col ?= lo_cols->get_column( 'ASSIGNED_CNT' ).
      lo_col->set_short_text( 'Assigned' ).
      lo_col->set_medium_text( 'Assigned Count' ).
      lo_col->set_long_text( 'Total Assigned Roles' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " Assigned Roles Summary
      lo_col ?= lo_cols->get_column( 'ASSIGNED_ROLES' ).
      lo_col->set_short_text( 'Roles' ).
      lo_col->set_medium_text( 'Assigned Roles' ).
      lo_col->set_long_text( 'List of Assigned Roles' ).
      lo_col->set_output_length( 40 ).

      " Missing Roles
      lo_col ?= lo_cols->get_column( 'MISSING_ROLES' ).
      lo_col->set_short_text( 'Missing' ).
      lo_col->set_medium_text( 'Missing Roles' ).
      lo_col->set_long_text( 'Roles Missing from SAP' ).
      lo_col->set_output_length( 30 ).

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
