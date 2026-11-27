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
         username  TYPE bapibname-bapibname,
         has_na    TYPE abap_bool,
         roles     TYPE STANDARD TABLE OF agr_name WITH DEFAULT KEY,
         bad_roles TYPE string_table,
       END OF ty_user_assignment.

TYPES: BEGIN OF ty_alv_result,
         status         TYPE char12,              " Status Icon & Code: @08@ [OK], @09@ [WARN], @0A@ [ERR]
         action         TYPE char12,              " SYNCHRONIZED / APPENDED / DEDUPLICATED / SIMULATED / UP-TO-DATE / WARNING / ERROR
         username       TYPE bapibname-bapibname, " SAP User ID (Hotspot to SU01)
         roles_cnt      TYPE i,                   " Total Roles in CSV
         valid_cnt      TYPE i,                   " Valid Roles in SAP
         assigned_cnt   TYPE i,                   " Total Resulting Roles in SAP
         roles_add_cnt  TYPE i,                   " Roles Added (Count)
         roles_del_cnt  TYPE i,                   " Roles Removed (Count)
         roles_keep_cnt TYPE i,                   " Roles Retained (Count)
         dup_del_cnt    TYPE i,                   " Duplicate Role Periods Cleared (Count)
         roles_add      TYPE string,              " List of Added Roles
         roles_del      TYPE string,              " List of Removed Roles
         roles_keep     TYPE string,              " List of Retained Roles
         dup_roles      TYPE string,              " List of Deduplicated Roles
         missing_roles  TYPE string,              " Roles Missing in SAP
         message        TYPE string,              " Execution Log / BAPI Message
       END OF ty_alv_result.

CONSTANTS: gc_status_ok   TYPE char12 VALUE '@08@ [OK]',
           gc_status_warn TYPE char12 VALUE '@09@ [WARN]',
           gc_status_err  TYPE char12 VALUE '@0A@ [ERR]'.

DATA: gt_raw_rows        TYPE STANDARD TABLE OF ty_raw_row,
      gt_assignments     TYPE STANDARD TABLE OF ty_user_assignment,
      gt_results         TYPE STANDARD TABLE OF ty_alv_result,
      gt_oversized_users TYPE STANDARD TABLE OF string.

*----------------------------------------------------------------------*
* 2. SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b_file WITH FRAME TITLE b_tit1.
  PARAMETERS: p_file TYPE localfile OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b_file.

SELECTION-SCREEN BEGIN OF BLOCK b_proc WITH FRAME TITLE b_tit2.
  PARAMETERS: p_test   TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_chkrol TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_dedup  TYPE abap_bool AS CHECKBOX DEFAULT ' '.
  SELECTION-SCREEN ULINE.
  PARAMETERS: rb_sync  RADIOBUTTON GROUP rmod DEFAULT 'X',
              rb_app   RADIOBUTTON GROUP rmod.
SELECTION-SCREEN END OF BLOCK b_proc.

SELECTION-SCREEN BEGIN OF BLOCK b_date WITH FRAME TITLE b_tit3.
  PARAMETERS: p_from TYPE bapiagr-from_dat DEFAULT sy-datum OBLIGATORY,
              p_to   TYPE bapiagr-to_dat   DEFAULT '99991231' OBLIGATORY.
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
  %_p_chkrol_%_app_%-text = 'Validate Roles in SAP'.
  %_p_dedup_%_app_%-text  = 'Clear Duplicate Role Periods'.
  %_rb_sync_%_app_%-text  = 'Two-Way Sync (Add & Remove)'.
  %_rb_app_%_app_%-text   = 'Append Only (Keep Existing)'.
  %_p_from_%_app_%-text   = 'Valid From Date'.
  %_p_to_%_app_%-text     = 'Valid To Date'.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  PERFORM f4_file_open CHANGING p_file.

AT SELECTION-SCREEN ON p_file.
  DATA lv_file_ok TYPE abap_bool.
  PERFORM validate_filename USING p_file abap_false CHANGING lv_file_ok.

AT SELECTION-SCREEN.
  IF p_from IS NOT INITIAL AND p_to IS NOT INITIAL AND p_from > p_to.
    MESSAGE 'Valid From Date cannot be later than Valid To Date.' TYPE 'E'.
  ENDIF.

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
        lv_rc        TYPE i,
        lv_ok        TYPE abap_bool.

  cl_gui_frontend_services=>file_open_dialog(
    EXPORTING
      window_title            = 'Select User-Role Assignment CSV File (.csv)'
      file_filter             = 'User Role Assign CSV (*02_Assign*.csv)|*02_Assign*.csv|CSV files (*.csv)|*.csv|All files (*.*)|*.*'
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
      DATA lv_picked TYPE localfile.
      lv_picked = ls_file-filename.
      PERFORM validate_filename USING lv_picked abap_true CHANGING lv_ok.
      IF lv_ok = abap_true.
        cv_file = lv_picked.
      ENDIF.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form validate_filename
*&---------------------------------------------------------------------*
FORM validate_filename USING    iv_file   TYPE localfile
                                iv_in_pov TYPE abap_bool
                       CHANGING ev_ok     TYPE abap_bool.
  DATA: lv_fname TYPE string,
        lv_msg   TYPE string,
        lt_parts TYPE STANDARD TABLE OF string.

  ev_ok = abap_true.
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
    ev_ok  = abap_false.
    lv_msg = |Invalid file '{ lv_fname }'. Expected CSV file (*_02_Assign_converted.csv).|.
    IF iv_in_pov = abap_true.
      MESSAGE lv_msg TYPE 'S' DISPLAY LIKE 'E'.
    ELSE.
      MESSAGE lv_msg TYPE 'E'.
    ENDIF.
    RETURN.
  ENDIF.

  IF NOT ( lv_up CS '02_ASSIGN' OR lv_up CS 'USER_02' OR lv_up CS 'ASSIGN_ROLE' OR lv_up CS '_ASSIGN' )
     OR lv_up CS '01_MASTER' OR lv_up CS '02_DERIVE' OR lv_up CS '03A_ORG'
     OR lv_up CS '03B_AUTH' OR lv_up CS '03B_OBJECT' OR lv_up CS '03C_ACTIVITY'
     OR lv_up CS '04_COMPOSITE' OR lv_up CS '01_CREATE'.
    ev_ok  = abap_false.
    lv_msg = |Invalid file '{ lv_fname }' for Z_USER_02_ASSIGN_ROLE. Expected '*_02_Assign_converted.csv'.|.
    IF iv_in_pov = abap_true.
      MESSAGE lv_msg TYPE 'S' DISPLAY LIKE 'E'.
    ELSE.
      MESSAGE lv_msg TYPE 'E'.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form check_authority
*&---------------------------------------------------------------------*
FORM check_authority.
  IF p_test = abap_true.
    AUTHORITY-CHECK OBJECT 'S_USER_GRP'
      ID 'CLASS' DUMMY
      ID 'ACTVT' FIELD '03'.
    IF sy-subrc <> 0.
      MESSAGE 'No authorization to display users (S_USER_GRP, ACTVT 03).' TYPE 'E'.
    ENDIF.
    AUTHORITY-CHECK OBJECT 'S_USER_AGR'
      ID 'ACT_GROUP' DUMMY
      ID 'ACTVT'     FIELD '03'.
    IF sy-subrc <> 0.
      MESSAGE 'No authorization to display roles (S_USER_AGR, ACTVT 03).' TYPE 'E'.
    ENDIF.
    RETURN.
  ENDIF.

  " Live execution requires both role assignment (S_USER_AGR 22/02) and user group maintenance (S_USER_GRP 22/02)
  AUTHORITY-CHECK OBJECT 'S_USER_AGR'
    ID 'ACT_GROUP' DUMMY
    ID 'ACTVT'     FIELD '22'.
  IF sy-subrc <> 0.
    AUTHORITY-CHECK OBJECT 'S_USER_AGR'
      ID 'ACT_GROUP' DUMMY
      ID 'ACTVT'     FIELD '02'.
    IF sy-subrc <> 0.
      MESSAGE 'No authorization to assign roles (S_USER_AGR, ACTVT 22/02).' TYPE 'E'.
    ENDIF.
  ENDIF.

  AUTHORITY-CHECK OBJECT 'S_USER_GRP'
    ID 'CLASS' DUMMY
    ID 'ACTVT' FIELD '22'.
  IF sy-subrc <> 0.
    AUTHORITY-CHECK OBJECT 'S_USER_GRP'
      ID 'CLASS' DUMMY
      ID 'ACTVT' FIELD '02'.
    IF sy-subrc <> 0.
      MESSAGE 'No authorization to maintain user role assignments (S_USER_GRP, ACTVT 22/02).' TYPE 'E'.
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
    IF sy-subrc <> 0.
      MESSAGE 'Failed to decode CSV binary content.' TYPE 'E'.
    ENDIF.
  ENDIF.

  " Strip Byte Order Mark (BOM U+FEFF) if present
  DATA(lv_bom) = cl_abap_conv_in_ce=>uccp( 'FEFF' ).
  IF strlen( lv_content ) > 0 AND lv_content(1) = lv_bom.
    lv_content = lv_content+1.
  ENDIF.

  " Normalize mixed CRLF/CR/LF line endings cleanly
  REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_content
    WITH cl_abap_char_utilities=>newline.
  REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf(1) IN lv_content
    WITH cl_abap_char_utilities=>newline.
  SPLIT lv_content AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.

  DATA: lv_file_delim TYPE c LENGTH 1 VALUE ',',
        lv_delim_set  TYPE abap_bool VALUE abap_false.
  CLEAR: gt_raw_rows, lv_line_idx.

  LOOP AT lt_lines INTO lv_line.
    " Strip BOM from line 1 before empty-line check
    IF sy-tabix = 1 AND strlen( lv_line ) > 0 AND lv_line(1) = lv_bom.
      lv_line = lv_line+1.
    ENDIF.
    IF lv_line IS INITIAL.
      CONTINUE.
    ENDIF.
    lv_line_idx = lv_line_idx + 1.

    IF lv_delim_set = abap_false.
      PERFORM detect_csv_delimiter USING lv_line CHANGING lv_file_delim.
      lv_delim_set = abap_true.
    ENDIF.

    CLEAR: lv_c1, lv_c2.
    PERFORM parse_csv_line USING lv_line lv_file_delim
                           CHANGING lv_c1 lv_c2.

    " Validate & skip header row (strict tokens so headerless rows like USER01,Z_ROLE_MM_1000 are NOT skipped!)
    DATA(lv_c1_up) = to_upper( lv_c1 ).
    DATA(lv_c2_up) = to_upper( lv_c2 ).
    IF lv_line_idx = 1.
      DATA(lv_hdr_line) = to_upper( lv_line ).
      IF lv_hdr_line CS 'FULL NAME' OR lv_hdr_line CS 'EMAIL' OR lv_hdr_line CS 'DEPARTMENT'
         OR lv_hdr_line CS 'TCODE' OR lv_hdr_line CS 'ORG_LEVEL' OR lv_hdr_line CS 'OBJECT-FIELD'
         OR lv_hdr_line CS 'VALUE-LOW' OR lv_hdr_line CS 'COMPOSITE ROLE' OR lv_hdr_line CS 'MASTER ROLE'.
        MESSAGE 'Invalid CSV header for Z_USER_02_ASSIGN_ROLE. Expected: Username, Role.' TYPE 'E'.
      ENDIF.
      IF lv_c1_up = 'USERNAME' OR lv_c1_up = 'USER NAME' OR lv_c1_up = 'USER'
         OR lv_c1_up = 'USER ID' OR lv_c1_up = 'BNAME'
         OR lv_c2_up = 'ROLE' OR lv_c2_up = 'ROLE NAME' OR lv_c2_up = 'ROLE_NAME'
         OR lv_c2_up = 'AGR_NAME'.
        CONTINUE.
      ENDIF.
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
                             ev_col2  TYPE string.
  DATA: lt_tokens TYPE STANDARD TABLE OF string,
        lv_len    TYPE i,
        lv_in_q   TYPE abap_bool VALUE abap_false,
        lv_cur    TYPE string,
        lv_char   TYPE string,
        lv_next   TYPE string,
        lv_idx    TYPE i,
        lv_delim  TYPE c LENGTH 1.

  CLEAR: ev_col1, ev_col2.

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
ENDFORM.

*&---------------------------------------------------------------------*
*& Form aggregate_input_data
*&---------------------------------------------------------------------*
FORM aggregate_input_data.
  DATA: ls_assign    TYPE ty_user_assignment,
        lv_uname_raw TYPE string,
        lv_role_raw  TYPE string,
        lv_uname     TYPE bapibname-bapibname,
        lv_role      TYPE agr_name.

  CLEAR: gt_assignments, gt_oversized_users.

  LOOP AT gt_raw_rows INTO DATA(ls_raw).
    CLEAR: lv_uname_raw, lv_role_raw, lv_uname, lv_role.

    lv_uname_raw = to_upper( ls_raw-username ).
    CONDENSE lv_uname_raw NO-GAPS.

    lv_role_raw = to_upper( ls_raw-role ).
    CONDENSE lv_role_raw NO-GAPS.

    IF lv_uname_raw IS INITIAL.
      CONTINUE.
    ENDIF.

    " Guard against silent >12-char truncation (which would hit wrong user in Two-Way Sync!)
    IF strlen( lv_uname_raw ) > 12.
      READ TABLE gt_oversized_users WITH KEY table_line = lv_uname_raw TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND lv_uname_raw TO gt_oversized_users.
      ENDIF.
      CONTINUE.
    ENDIF.

    lv_uname = lv_uname_raw.

    READ TABLE gt_assignments ASSIGNING FIELD-SYMBOL(<fs_assign>)
      WITH KEY username = lv_uname.

    IF sy-subrc = 0.
      IF lv_role_raw = 'N/A'.
        <fs_assign>-has_na = abap_true.
      ELSEIF lv_role_raw IS INITIAL.
        " Blank role cell must NEVER set has_na (avoid accidental mass revocation in Sync mode)
      ELSEIF strlen( lv_role_raw ) > 30.
        READ TABLE <fs_assign>-bad_roles TRANSPORTING NO FIELDS WITH KEY table_line = lv_role_raw.
        IF sy-subrc <> 0.
          APPEND lv_role_raw TO <fs_assign>-bad_roles.
        ENDIF.
      ELSE.
        lv_role = lv_role_raw.
        READ TABLE <fs_assign>-roles TRANSPORTING NO FIELDS
          WITH KEY table_line = lv_role.
        IF sy-subrc <> 0.
          APPEND lv_role TO <fs_assign>-roles.
        ENDIF.
      ENDIF.
    ELSE.
      CLEAR ls_assign.
      ls_assign-username = lv_uname.
      IF lv_role_raw = 'N/A'.
        ls_assign-has_na = abap_true.
      ELSEIF lv_role_raw IS INITIAL.
        " Blank role cell kept empty without setting has_na
      ELSEIF strlen( lv_role_raw ) > 30.
        APPEND lv_role_raw TO ls_assign-bad_roles.
      ELSE.
        lv_role = lv_role_raw.
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
        lt_dedup_act    TYPE STANDARD TABLE OF bapiagr,
        ls_actgroup     TYPE bapiagr,
        lt_return       TYPE STANDARD TABLE OF bapiret2,
        lv_errmsg       TYPE string,
        lv_has_err      TYPE abap_bool,
        lt_roles_to_add TYPE STANDARD TABLE OF agr_name,
        lt_roles_to_del TYPE STANDARD TABLE OF agr_name,
        lt_roles_keep   TYPE STANDARD TABLE OF agr_name,
        lt_roles_dedup  TYPE STANDARD TABLE OF agr_name,
        lv_dedup_cnt    TYPE i,
        lv_prev_agr     TYPE agr_name,
        lv_str_add      TYPE string,
        lv_str_del      TYPE string,
        lv_str_keep     TYPE string,
        lv_str_dedup    TYPE string,
        lv_str_missing  TYPE string.

  CLEAR gt_results.

  " Report oversized (>12 char) CSV usernames explicitly without touching truncated SAP accounts
  LOOP AT gt_oversized_users INTO DATA(lv_bad_user).
    CLEAR ls_res.
    ls_res-status   = gc_status_err.
    ls_res-action   = 'ERROR'.
    ls_res-username = lv_bad_user.
    ls_res-message  = |Username exceeds SAP 12-character limit: { lv_bad_user }|.
    APPEND ls_res TO gt_results.
  ENDLOOP.

  LOOP AT gt_assignments INTO DATA(ls_assign).
    CLEAR: ls_res, lt_valid_roles, lt_miss_roles, lt_actgroups, lt_dedup_act,
           lt_return, lv_errmsg, lv_has_err,
           lt_roles_to_add, lt_roles_to_del, lt_roles_keep, lt_roles_dedup,
           lv_dedup_cnt, lv_prev_agr,
           lv_str_add, lv_str_del, lv_str_keep, lv_str_dedup, lv_str_missing.

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

    " Validation 3b: Abort if any CSV role exceeds SAP 30-char limit (prevents silent drop / Sync wipe)
    IF ls_assign-bad_roles IS NOT INITIAL.
      DATA(lv_bad_r_str) = REDUCE string(
        INIT s = `` FOR br IN ls_assign-bad_roles
        NEXT s = COND #( WHEN s IS INITIAL THEN br ELSE |{ s }, { br }| ) ).
      ls_res-status        = gc_status_err.
      ls_res-action        = 'ERROR'.
      ls_res-missing_roles = lv_bad_r_str.
      ls_res-message       = |Aborted: Role name(s) exceed SAP 30-char limit: [{ lv_bad_r_str }].|.
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

    " Check empty role list or missing in SAP
    IF ls_assign-roles IS INITIAL.
      IF ls_assign-has_na = abap_false.
        ls_res-status  = gc_status_warn.
        ls_res-action  = 'WARNING'.
        ls_res-message = 'No valid role entries found for this user (blank cell ignored; use explicit "N/A" to revoke all in Sync mode).'.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.
      " If has_na = abap_true, user explicitly marked as N/A (remove all direct roles in Sync mode)
    ELSEIF lt_valid_roles IS INITIAL.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = 'All specified roles are missing from SAP repository (AGR_DEFINE).'.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ELSEIF rb_sync = abap_true AND p_chkrol = abap_true AND lt_miss_roles IS NOT INITIAL.
      " Sync Safety: Never execute Two-Way Sync if any CSV role is missing in SAP (avoids unintended revocations)
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = |Two-Way Sync aborted: { lines( lt_miss_roles ) } role(s) missing in SAP [{ lv_str_missing }]. Existing assignments preserved.|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " Read current direct, non-HR-Org, non-excluded roles from AGR_USERS
    SELECT agr_name, from_dat, to_dat FROM agr_users
      INTO TABLE @DATA(lt_existing_roles)
      WHERE uname    = @ls_assign-username
        AND col_flag = @space
        AND org_flag = @space
        AND exclude  = @space.

    " Calculate Diff: ADD, DEL, KEEP (require FULL coverage of [p_from, p_to])
    " 1. Roles to Add: in CSV valid list, with NO existing period fully covering [p_from, p_to]
    DATA: lv_has_valid_period TYPE abap_bool.
    LOOP AT lt_valid_roles INTO DATA(lv_vrole).
      lv_has_valid_period = abap_false.
      LOOP AT lt_existing_roles INTO DATA(ls_ex_chk) WHERE agr_name = lv_vrole.
        IF ls_ex_chk-from_dat <= p_from AND ls_ex_chk-to_dat >= p_to.
          lv_has_valid_period = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.
      IF lv_has_valid_period = abap_false.
        APPEND lv_vrole TO lt_roles_to_add.
      ENDIF.
    ENDLOOP.

    " 2. Roles to Delete: in SAP currently, but not in CSV valid list (Sync mode only)
    IF rb_sync = abap_true.
      LOOP AT lt_existing_roles INTO DATA(ls_exist_del).
        READ TABLE lt_valid_roles TRANSPORTING NO FIELDS
          WITH KEY table_line = ls_exist_del-agr_name.
        IF sy-subrc <> 0.
          READ TABLE lt_roles_to_del TRANSPORTING NO FIELDS
            WITH KEY table_line = ls_exist_del-agr_name.
          IF sy-subrc <> 0.
            APPEND ls_exist_del-agr_name TO lt_roles_to_del.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " 3. Roles to Keep (deduplicated; preserves existing covering periods and future renewals)
    IF rb_sync = abap_true.
      " In Sync mode: keep roles present in both SAP (covering [p_from, p_to] OR disjoint future > p_to) and CSV
      LOOP AT lt_existing_roles INTO DATA(ls_exist_keep).
        READ TABLE lt_valid_roles TRANSPORTING NO FIELDS
          WITH KEY table_line = ls_exist_keep-agr_name.
        IF sy-subrc = 0 AND ( ( ls_exist_keep-from_dat <= p_from AND ls_exist_keep-to_dat >= p_to )
                              OR ls_exist_keep-from_dat > p_to ).
          READ TABLE lt_roles_keep TRANSPORTING NO FIELDS
            WITH KEY table_line = ls_exist_keep-agr_name.
          IF sy-subrc <> 0.
            APPEND ls_exist_keep-agr_name TO lt_roles_keep.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ELSE.
      " In Append mode: keep all existing roles (excluding those being extended/re-added)
      LOOP AT lt_existing_roles INTO DATA(ls_exist_app).
        READ TABLE lt_roles_to_add TRANSPORTING NO FIELDS
          WITH KEY table_line = ls_exist_app-agr_name.
        IF sy-subrc <> 0.
          READ TABLE lt_roles_keep TRANSPORTING NO FIELDS
            WITH KEY table_line = ls_exist_app-agr_name.
          IF sy-subrc <> 0.
            APPEND ls_exist_app-agr_name TO lt_roles_keep.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " Build target lt_actgroups table for standard BAPI
    " CRITICAL: Always preserve original (from_dat, to_dat) of existing covering periods and
    " future renewals so pre-approved future validity periods are never wiped in Sync!
    IF rb_sync = abap_true.
      LOOP AT lt_existing_roles INTO DATA(ls_sync_row).
        READ TABLE lt_valid_roles TRANSPORTING NO FIELDS
          WITH KEY table_line = ls_sync_row-agr_name.
        IF sy-subrc = 0 AND ( ( ls_sync_row-from_dat <= p_from AND ls_sync_row-to_dat >= p_to )
                              OR ls_sync_row-from_dat > p_to ).
          CLEAR ls_actgroup.
          ls_actgroup-agr_name = ls_sync_row-agr_name.
          ls_actgroup-from_dat = ls_sync_row-from_dat.
          ls_actgroup-to_dat   = ls_sync_row-to_dat.
          APPEND ls_actgroup TO lt_actgroups.
        ENDIF.
      ENDLOOP.
      LOOP AT lt_roles_to_add INTO DATA(lv_arole).
        CLEAR ls_actgroup.
        ls_actgroup-agr_name = lv_arole.
        ls_actgroup-from_dat = p_from.
        ls_actgroup-to_dat   = p_to.
        APPEND ls_actgroup TO lt_actgroups.
      ENDLOOP.
    ELSE.
      " Append Mode: preserve every existing assignment with its original validity period untouched
      LOOP AT lt_existing_roles INTO DATA(ls_exist_row).
        CLEAR ls_actgroup.
        ls_actgroup-agr_name = ls_exist_row-agr_name.
        ls_actgroup-from_dat = ls_exist_row-from_dat.
        ls_actgroup-to_dat   = ls_exist_row-to_dat.
        APPEND ls_actgroup TO lt_actgroups.
      ENDLOOP.
      " Only append roles that do NOT already fully cover [p_from, p_to]
      LOOP AT lt_roles_to_add INTO DATA(lv_add_app).
        CLEAR ls_actgroup.
        ls_actgroup-agr_name = lv_add_app.
        ls_actgroup-from_dat = p_from.
        ls_actgroup-to_dat   = p_to.
        APPEND ls_actgroup TO lt_actgroups.
      ENDLOOP.
    ENDIF.

    SORT lt_actgroups BY agr_name from_dat to_dat.
    DELETE ADJACENT DUPLICATES FROM lt_actgroups COMPARING agr_name from_dat to_dat.

    " Optional Deduplication: Coalesce overlapping/adjacent? -> strictly overlapping periods
    " into [min(from_dat)..max(to_dat)] per role while preserving disjoint future renewals!
    IF p_dedup = abap_true.
      SORT lt_actgroups BY agr_name ASCENDING from_dat ASCENDING to_dat ASCENDING.
      CLEAR lt_dedup_act.
      LOOP AT lt_actgroups INTO DATA(ls_in_ag).
        DATA(lv_d_cnt) = lines( lt_dedup_act ).
        IF lv_d_cnt > 0.
          ASSIGN lt_dedup_act[ lv_d_cnt ] TO FIELD-SYMBOL(<ls_last_ag>).
          IF <ls_last_ag>-agr_name = ls_in_ag-agr_name
             AND ls_in_ag-from_dat <= <ls_last_ag>-to_dat.
            IF ls_in_ag-to_dat > <ls_last_ag>-to_dat.
              <ls_last_ag>-to_dat = ls_in_ag-to_dat.
            ENDIF.
            lv_dedup_cnt = lv_dedup_cnt + 1.
            READ TABLE lt_roles_dedup TRANSPORTING NO FIELDS
              WITH KEY table_line = ls_in_ag-agr_name.
            IF sy-subrc <> 0.
              APPEND ls_in_ag-agr_name TO lt_roles_dedup.
            ENDIF.
            CONTINUE.
          ENDIF.
        ENDIF.
        APPEND ls_in_ag TO lt_dedup_act.
      ENDLOOP.
      lt_actgroups = lt_dedup_act.
    ENDIF.

    SORT lt_actgroups BY agr_name from_dat to_dat.
    DELETE ADJACENT DUPLICATES FROM lt_actgroups COMPARING agr_name from_dat to_dat.

    " Format counts and string summaries
    ls_res-roles_add_cnt  = lines( lt_roles_to_add ).
    ls_res-roles_del_cnt  = lines( lt_roles_to_del ).
    ls_res-roles_keep_cnt = lines( lt_roles_keep ).
    ls_res-dup_del_cnt    = lv_dedup_cnt.
    ls_res-assigned_cnt   = lines( lt_actgroups ).

    LOOP AT lt_roles_to_add INTO DATA(lv_s_add).
      IF lv_str_add IS INITIAL.
        lv_str_add = lv_s_add.
      ELSE.
        lv_str_add = lv_str_add && ', ' && lv_s_add.
      ENDIF.
    ENDLOOP.
    ls_res-roles_add = lv_str_add.

    LOOP AT lt_roles_to_del INTO DATA(lv_s_del).
      IF lv_str_del IS INITIAL.
        lv_str_del = lv_s_del.
      ELSE.
        lv_str_del = lv_str_del && ', ' && lv_s_del.
      ENDIF.
    ENDLOOP.
    ls_res-roles_del = lv_str_del.

    LOOP AT lt_roles_keep INTO DATA(lv_s_keep).
      IF lv_str_keep IS INITIAL.
        lv_str_keep = lv_s_keep.
      ELSE.
        lv_str_keep = lv_str_keep && ', ' && lv_s_keep.
      ENDIF.
    ENDLOOP.
    ls_res-roles_keep = lv_str_keep.

    LOOP AT lt_roles_dedup INTO DATA(lv_s_dedup).
      IF lv_str_dedup IS INITIAL.
        lv_str_dedup = lv_s_dedup.
      ELSE.
        lv_str_dedup = lv_str_dedup && ', ' && lv_s_dedup.
      ENDIF.
    ENDLOOP.
    ls_res-dup_roles = lv_str_dedup.

    " Exact set equality check between final lt_actgroups and existing AGR_USERS rows
    " (prevents redundant no-op BAPI writes and false 'Added' reports when deduplicated away)
    SORT lt_existing_roles BY agr_name from_dat to_dat.
    DELETE ADJACENT DUPLICATES FROM lt_existing_roles COMPARING agr_name from_dat to_dat.

    DATA: lv_is_up_to_date TYPE abap_bool.
    IF lines( lt_actgroups ) = lines( lt_existing_roles ).
      lv_is_up_to_date = abap_true.
      LOOP AT lt_actgroups INTO DATA(ls_cmp_a).
        READ TABLE lt_existing_roles TRANSPORTING NO FIELDS
          WITH KEY agr_name = ls_cmp_a-agr_name
                   from_dat = ls_cmp_a-from_dat
                   to_dat   = ls_cmp_a-to_dat
          BINARY SEARCH.
        IF sy-subrc <> 0.
          lv_is_up_to_date = abap_false.
          EXIT.
        ENDIF.
      ENDLOOP.
    ELSE.
      lv_is_up_to_date = abap_false.
    ENDIF.

    IF lv_is_up_to_date = abap_true.
      ls_res-roles_add_cnt = 0.
      ls_res-roles_del_cnt = 0.
      ls_res-dup_del_cnt   = 0.
      CLEAR: ls_res-roles_add, ls_res-roles_del, ls_res-dup_roles.
    ENDIF.

    " Simulation Mode (Test Run)
    IF p_test = abap_true.
      IF lv_is_up_to_date = abap_true.
        ls_res-status  = gc_status_ok.
        ls_res-action  = 'UP-TO-DATE'.
        ls_res-message = |Simulation: Roles already synchronized. All { ls_res-roles_keep_cnt } roles match CSV.|.
      ELSE.
        ls_res-status  = gc_status_ok.
        ls_res-action  = 'SIMULATED'.
        IF lv_dedup_cnt > 0.
          ls_res-message = |Simulation OK: Would add { ls_res-roles_add_cnt } [{ lv_str_add }], |
                        && |remove { ls_res-roles_del_cnt } [{ lv_str_del }], |
                        && |clear { lv_dedup_cnt } dup period(s) [{ lv_str_dedup }], |
                        && |keep { ls_res-roles_keep_cnt }. Total active: { ls_res-assigned_cnt }.|.
        ELSE.
          ls_res-message = |Simulation OK: Would add { ls_res-roles_add_cnt } [{ lv_str_add }], |
                        && |remove { ls_res-roles_del_cnt } [{ lv_str_del }], |
                        && |keep { ls_res-roles_keep_cnt }. Total active: { ls_res-assigned_cnt }.|.
        ENDIF.
      ENDIF.

      IF lt_miss_roles IS NOT INITIAL.
        ls_res-status  = gc_status_warn.
        ls_res-message = |Warning: { lines( lt_miss_roles ) } role(s) missing in SAP: [{ lv_str_missing }]. { ls_res-message }|.
      ENDIF.
      APPEND ls_res TO gt_results.

    " Live Execution Mode
    ELSE.
      IF lv_is_up_to_date = abap_true.
        ls_res-status  = gc_status_ok.
        ls_res-action  = 'UP-TO-DATE'.
        ls_res-message = |User roles up-to-date. All { ls_res-roles_keep_cnt } roles match CSV.|.
        IF lt_miss_roles IS NOT INITIAL.
          ls_res-status  = gc_status_warn.
          ls_res-message = |Warning: { lines( lt_miss_roles ) } role(s) missing from SAP: [{ lv_str_missing }]. { ls_res-message }|.
        ENDIF.
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
          CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
          ls_res-status  = gc_status_err.
          ls_res-action  = 'ERROR'.
          ls_res-message = lv_errmsg.
        ELSE.
          CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
            EXPORTING
              wait = 'X'.

          ls_res-status  = gc_status_ok.
          IF ls_res-roles_add_cnt = 0 AND ls_res-roles_del_cnt = 0 AND lv_dedup_cnt > 0.
            ls_res-action = 'DEDUPLICATED'.
          ELSE.
            ls_res-action = COND #( WHEN rb_sync = abap_true THEN 'SYNCHRONIZED' ELSE 'APPENDED' ).
          ENDIF.
          IF lv_dedup_cnt > 0.
            ls_res-message = |Success: Added { ls_res-roles_add_cnt } [{ lv_str_add }], |
                          && |Removed { ls_res-roles_del_cnt } [{ lv_str_del }], |
                          && |Cleared { lv_dedup_cnt } dup period(s) [{ lv_str_dedup }], |
                          && |Kept { ls_res-roles_keep_cnt }. Total active: { ls_res-assigned_cnt }.|.
          ELSE.
            ls_res-message = |Success: Added { ls_res-roles_add_cnt } [{ lv_str_add }], |
                          && |Removed { ls_res-roles_del_cnt } [{ lv_str_del }], |
                          && |Kept { ls_res-roles_keep_cnt }. Total active: { ls_res-assigned_cnt }.|.
          ENDIF.

          IF lt_miss_roles IS NOT INITIAL.
            ls_res-status  = gc_status_warn.
            ls_res-message = |Warning: { lines( lt_miss_roles ) } role(s) missing from SAP: [{ lv_str_missing }]. { ls_res-message }|.
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
    IF sy-subrc = 0 AND column = 'USERNAME'
       AND ls_row-username IS NOT INITIAL AND ls_row-action <> 'ERROR'.
      TRY.
          SET PARAMETER ID 'USR' FIELD ls_row-username.
          CALL TRANSACTION 'SU01' WITH AUTHORITY-CHECK AND SKIP FIRST SCREEN.
        CATCH cx_sy_authorization_error.
          MESSAGE 'No authorization to open transaction SU01.' TYPE 'S' DISPLAY LIKE 'E'.
      ENDTRY.
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

      " Roles Added Count
      lo_col ?= lo_cols->get_column( 'ROLES_ADD_CNT' ).
      lo_col->set_short_text( 'Add Cnt' ).
      lo_col->set_medium_text( 'Roles Added' ).
      lo_col->set_long_text( 'Roles Added (Count)' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " Roles Removed Count
      lo_col ?= lo_cols->get_column( 'ROLES_DEL_CNT' ).
      lo_col->set_short_text( 'Del Cnt' ).
      lo_col->set_medium_text( 'Roles Removed' ).
      lo_col->set_long_text( 'Roles Removed (Count)' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " Roles Retained Count
      lo_col ?= lo_cols->get_column( 'ROLES_KEEP_CNT' ).
      lo_col->set_short_text( 'Keep Cnt' ).
      lo_col->set_medium_text( 'Roles Kept' ).
      lo_col->set_long_text( 'Roles Retained (Count)' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " Duplicate Role Periods Cleared Count
      lo_col ?= lo_cols->get_column( 'DUP_DEL_CNT' ).
      lo_col->set_short_text( 'Dup Cnt' ).
      lo_col->set_medium_text( 'Dups Cleared' ).
      lo_col->set_long_text( 'Duplicate Periods Cleared' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " Total Resulting Assigned Roles Count
      lo_col ?= lo_cols->get_column( 'ASSIGNED_CNT' ).
      lo_col->set_short_text( 'Active' ).
      lo_col->set_medium_text( 'Active Roles' ).
      lo_col->set_long_text( 'Total Active Roles in SAP' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " Added Roles List
      lo_col ?= lo_cols->get_column( 'ROLES_ADD' ).
      lo_col->set_short_text( 'Added' ).
      lo_col->set_medium_text( 'Added Roles' ).
      lo_col->set_long_text( 'List of Roles Added' ).
      lo_col->set_output_length( 30 ).

      " Removed Roles List
      lo_col ?= lo_cols->get_column( 'ROLES_DEL' ).
      lo_col->set_short_text( 'Removed' ).
      lo_col->set_medium_text( 'Removed Roles' ).
      lo_col->set_long_text( 'List of Roles Removed' ).
      lo_col->set_output_length( 30 ).

      " Retained Roles List
      lo_col ?= lo_cols->get_column( 'ROLES_KEEP' ).
      lo_col->set_short_text( 'Retained' ).
      lo_col->set_medium_text( 'Retained Roles' ).
      lo_col->set_long_text( 'List of Roles Retained' ).
      lo_col->set_output_length( 30 ).

      " Deduplicated Roles List
      lo_col ?= lo_cols->get_column( 'DUP_ROLES' ).
      lo_col->set_short_text( 'Dedup' ).
      lo_col->set_medium_text( 'Deduplicated Roles' ).
      lo_col->set_long_text( 'Roles with Duplicate Periods Cleared' ).
      lo_col->set_output_length( 30 ).

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
