*&---------------------------------------------------------------------*
*& Report Z_USER_01_CREATE
*&---------------------------------------------------------------------*
*& Purpose: Batch SAP User Creation & Update from CSV file
*& Description:
*&   Reads a CSV (.csv) file containing user records (Username, Initial
*&   Password, Full Name, Email, Phone No., Department, Function),
*&   validates input fields, handles UTF-8 encoding (supporting Vietnamese
*&   and accented characters), maps 'Full Name' into SAP 'Last Name'
*&   (BAPIADDR3-LASTNAME), checks existing users in USR02, creates new
*&   users via BAPI_USER_CREATE1 or updates existing ones via
*&   BAPI_USER_CHANGE, executes BAPI_TRANSACTION_COMMIT, and presents an
*&   interactive ALV cockpit with one-click navigation to transaction SU01.
*&
*& File format (CSV .csv):
*&   Col 1: Username         (e.g., JOHND, max 12 chars, uppercase)
*&   Col 2: Initial Password (e.g., N8l0%GO_UVkK, SAP-compliant password)
*&   Col 3: Full Name        (e.g., John Doe - mapped to LASTNAME)
*&   Col 4: Email            (e.g., johnd@company.com)
*&   Col 5: Phone No.        (e.g., (+84)981234567)
*&   Col 6: Department       (e.g., Finance & Accounting)
*&   Col 7: Function         (e.g., Finance Controller)
*&
*& Author: Antigravity AI (SAP Basis Engineering)
*& Package: ZBC_UT
*& Transport: SKDK900253 / SKDK900254$TMP
*&---------------------------------------------------------------------*
REPORT z_user_01_create.

TABLES: usr02.

*----------------------------------------------------------------------*
* 1. TYPES & DATA DEFINITIONS
*----------------------------------------------------------------------*
TYPES: ty_bin_255 TYPE x LENGTH 255.

TYPES: BEGIN OF ty_user_csv,
         username   TYPE bapibname-bapibname,
         password   TYPE bapipwd-bapipwd,
         fullname   TYPE string,
         email      TYPE bapiaddr3-e_mail,
         phone      TYPE bapiaddr3-tel1_numbr,
         department TYPE bapiaddr3-department,
         function   TYPE bapiaddr3-function,
       END OF ty_user_csv.

TYPES: BEGIN OF ty_alv_result,
         status     TYPE char4,               " Icon (@08@ Green, @09@ Yellow, @0A@ Red)
         action     TYPE char12,              " CREATED / UPDATED / SIM_NEW / SIM_UPD / SKIPPED / ERROR
         username   TYPE bapibname-bapibname, " SAP User ID (Hotspot to SU01)
         password   TYPE bapipwd-bapipwd,     " Initial Password
         fullname   TYPE string,              " Last Name (Full Name)
         email      TYPE bapiaddr3-e_mail,
         phone      TYPE bapiaddr3-tel1_numbr,
         department TYPE bapiaddr3-department,
         function   TYPE bapiaddr3-function,
         message    TYPE string,              " Status Message / Execution Log
       END OF ty_alv_result.

DATA: gt_users   TYPE STANDARD TABLE OF ty_user_csv,
      gt_results TYPE STANDARD TABLE OF ty_alv_result.

*----------------------------------------------------------------------*
* 2. SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b_file WITH FRAME TITLE b_tit1.
  PARAMETERS: p_file TYPE localfile OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b_file.

SELECTION-SCREEN BEGIN OF BLOCK b_proc WITH FRAME TITLE b_tit2.
  PARAMETERS: p_test TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_upd  TYPE abap_bool AS CHECKBOX DEFAULT ' ',
              p_pwd  TYPE abap_bool AS CHECKBOX DEFAULT ' '.
SELECTION-SCREEN END OF BLOCK b_proc.

SELECTION-SCREEN BEGIN OF BLOCK b_def WITH FRAME TITLE b_tit3.
  PARAMETERS: p_ustyp TYPE bapilogond-ustyp DEFAULT 'A',
              p_gltgv TYPE bapilogond-gltgv DEFAULT sy-datum,
              p_gltgb TYPE bapilogond-gltgb DEFAULT '99991231',
              p_langu TYPE bapidefaul-langu DEFAULT sy-langu,
              p_spld  TYPE bapidefaul-spld  DEFAULT 'LP01'.
SELECTION-SCREEN END OF BLOCK b_def.

*----------------------------------------------------------------------*
* 3. INITIALIZATION & SCREEN EVENTS
*----------------------------------------------------------------------*
INITIALIZATION.
  b_tit1 = 'Input CSV File (.csv)'(b01).
  b_tit2 = 'Execution & Update Options'(b02).
  b_tit3 = 'User Defaults (Logon & Defaults)'(b03).

  %_p_file_%_app_%-text  = 'File Path'.
  %_p_test_%_app_%-text  = 'Simulation (Test Run)'.
  %_p_upd_%_app_%-text   = 'Update Existing Users'.
  %_p_pwd_%_app_%-text   = 'Reset Password on Update'.
  %_p_ustyp_%_app_%-text = 'User Type (A=Dialog)'.
  %_p_gltgv_%_app_%-text = 'Valid From'.
  %_p_gltgb_%_app_%-text = 'Valid To'.
  %_p_langu_%_app_%-text = 'Logon Language'.
  %_p_spld_%_app_%-text  = 'Default Output Device'.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  PERFORM f4_file_open CHANGING p_file.

*----------------------------------------------------------------------*
* 4. START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.
  PERFORM check_authority.
  PERFORM upload_and_parse_file USING p_file.
  PERFORM process_users.
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
      window_title            = 'Select Users CSV File (.csv)'
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
  " Check authorization for user administration (S_USER_GRP)
  AUTHORITY-CHECK OBJECT 'S_USER_GRP'
    ID 'CLASS' DUMMY
    ID 'ACTVT' FIELD '01'. " Create
  IF sy-subrc <> 0.
    AUTHORITY-CHECK OBJECT 'S_USER_GRP'
      ID 'CLASS' DUMMY
      ID 'ACTVT' FIELD '02'. " Change
    IF sy-subrc <> 0 AND p_test = abap_false.
      MESSAGE 'No authorization to create or modify SAP users (object S_USER_GRP).' TYPE 'E'.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form upload_and_parse_file
*&---------------------------------------------------------------------*
FORM upload_and_parse_file USING iv_file TYPE localfile.
  DATA: lv_filepath     TYPE string,
        lt_binary_tab   TYPE STANDARD TABLE OF ty_bin_255,
        lv_length       TYPE i,
        lv_content      TYPE string,
        lt_lines        TYPE STANDARD TABLE OF string,
        lv_line         TYPE string,
        lv_line_idx     TYPE i,
        ls_user         TYPE ty_user_csv,
        lv_c1           TYPE string,
        lv_c2           TYPE string,
        lv_c3           TYPE string,
        lv_c4           TYPE string,
        lv_c5           TYPE string,
        lv_c6           TYPE string,
        lv_c7           TYPE string.

  lv_filepath = iv_file.

  " Upload file in BIN mode to preserve raw UTF-8 bytes (Vietnamese diacritics)
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

  CLEAR lv_line_idx.
  LOOP AT lt_lines INTO lv_line.
    lv_line_idx = lv_line_idx + 1.
    IF lv_line IS INITIAL.
      CONTINUE.
    ENDIF.

    " Strip BOM from first line if still lingering
    IF lv_line_idx = 1 AND strlen( lv_line ) > 0 AND lv_line(1) = lv_bom.
      lv_line = lv_line+1.
    ENDIF.

    CLEAR: lv_c1, lv_c2, lv_c3, lv_c4, lv_c5, lv_c6, lv_c7.
    PERFORM parse_csv_line USING lv_line
                           CHANGING lv_c1 lv_c2 lv_c3 lv_c4 lv_c5 lv_c6 lv_c7.

    " Check and skip header row
    DATA(lv_c1_up) = to_upper( lv_c1 ).
    DATA(lv_c3_up) = to_upper( lv_c3 ).
    IF lv_line_idx = 1 AND ( lv_c1_up CS 'USER' OR lv_c1_up CS 'NAME' OR lv_c3_up CS 'FULL' ).
      CONTINUE.
    ENDIF.
    IF lv_c1_up = 'USERNAME' OR lv_c1_up = 'USER' OR lv_c1_up = 'BNAME'
       OR lv_c3_up = 'FULL NAME' OR lv_c3_up = 'FULLNAME'.
      CONTINUE.
    ENDIF.

    IF lv_c1 IS NOT INITIAL.
      CLEAR ls_user.
      ls_user-username   = to_upper( lv_c1 ).
      CONDENSE ls_user-username NO-GAPS.
      ls_user-password   = lv_c2.
      ls_user-fullname   = lv_c3. " Full Name -> will be mapped to LASTNAME
      ls_user-email      = lv_c4.
      ls_user-phone      = lv_c5.
      ls_user-department = lv_c6.
      ls_user-function   = lv_c7.
      APPEND ls_user TO gt_users.
    ENDIF.
  ENDLOOP.

  IF gt_users IS INITIAL.
    MESSAGE 'No valid user records found in the CSV file.' TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form parse_csv_line
*&---------------------------------------------------------------------*
FORM parse_csv_line USING    iv_line TYPE string
                    CHANGING ev_col1 TYPE string
                             ev_col2 TYPE string
                             ev_col3 TYPE string
                             ev_col4 TYPE string
                             ev_col5 TYPE string
                             ev_col6 TYPE string
                             ev_col7 TYPE string.
  DATA: lt_tokens TYPE STANDARD TABLE OF string,
        lv_len    TYPE i,
        lv_in_q   TYPE abap_bool VALUE abap_false,
        lv_cur    TYPE string,
        lv_char   TYPE string.

  CLEAR: ev_col1, ev_col2, ev_col3, ev_col4, ev_col5, ev_col6, ev_col7.

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

  " Extract tokens into corresponding columns
  READ TABLE lt_tokens INTO ev_col1 INDEX 1.
  READ TABLE lt_tokens INTO ev_col2 INDEX 2.
  READ TABLE lt_tokens INTO ev_col3 INDEX 3.
  READ TABLE lt_tokens INTO ev_col4 INDEX 4.
  READ TABLE lt_tokens INTO ev_col5 INDEX 5.
  READ TABLE lt_tokens INTO ev_col6 INDEX 6.
  READ TABLE lt_tokens INTO ev_col7 INDEX 7.

  " Clean quotes and trim outer spaces
  PERFORM clean_cell CHANGING ev_col1.
  PERFORM clean_cell CHANGING ev_col2.
  PERFORM clean_cell CHANGING ev_col3.
  PERFORM clean_cell CHANGING ev_col4.
  PERFORM clean_cell CHANGING ev_col5.
  PERFORM clean_cell CHANGING ev_col6.
  PERFORM clean_cell CHANGING ev_col7.
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
*& Form process_users
*&---------------------------------------------------------------------*
FORM process_users.
  DATA: ls_res     TYPE ty_alv_result,
        lv_exists  TYPE abap_bool,
        lt_return  TYPE STANDARD TABLE OF bapiret2,
        lv_errmsg  TYPE string,
        lv_has_err TYPE abap_bool.

  CLEAR gt_results.

  LOOP AT gt_users INTO DATA(ls_user).
    CLEAR: ls_res, lt_return, lv_errmsg, lv_has_err.

    " Validate email: if invalid, automatically clear it
    DATA: lv_clean_email TYPE bapiaddr3-e_mail,
          lv_email_valid TYPE abap_bool.

    IF ls_user-email IS NOT INITIAL.
      PERFORM validate_email USING ls_user-email
                             CHANGING lv_clean_email lv_email_valid.
      IF lv_email_valid = abap_false.
        CLEAR ls_user-email.
      ELSE.
        ls_user-email = lv_clean_email.
      ENDIF.
    ENDIF.

    ls_res-username   = ls_user-username.
    ls_res-password   = ls_user-password.
    ls_res-fullname   = ls_user-fullname.
    ls_res-email      = ls_user-email.
    ls_res-phone      = ls_user-phone.
    ls_res-department = ls_user-department.
    ls_res-function   = ls_user-function.

    " Validation 1: Username must not be initial
    IF ls_user-username IS INITIAL.
      ls_res-status  = '@0A@'.
      ls_res-action  = 'ERROR'.
      ls_res-message = 'Username is empty or missing.'.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " Validation 2: Username max 12 characters (SAP User ID limit)
    IF strlen( ls_user-username ) > 12.
      ls_res-status  = '@0A@'.
      ls_res-action  = 'ERROR'.
      ls_res-message = 'Username exceeds SAP 12-character limit: ' && ls_user-username.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " Validation 3: Full Name must not be initial (BAPIADDR3-LASTNAME is mandatory)
    IF ls_user-fullname IS INITIAL.
      ls_res-status  = '@0A@'.
      ls_res-action  = 'ERROR'.
      ls_res-message = 'Full Name is empty (SAP Last Name is mandatory).'.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " Check user existence in USR02
    SELECT SINGLE bname FROM usr02 INTO @DATA(lv_usr02_bname)
      WHERE bname = @ls_user-username.
    IF sy-subrc = 0.
      lv_exists = abap_true.
    ELSE.
      lv_exists = abap_false.
    ENDIF.

    " Case A: User does NOT exist in SAP
    IF lv_exists = abap_false.
      " Initial password check for new user creation
      IF ls_user-password IS INITIAL.
        ls_res-status  = '@0A@'.
        ls_res-action  = 'ERROR'.
        ls_res-message = 'Initial Password is required for new user creation.'.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.

      IF p_test = abap_true.
        " Simulation Mode: New user creation
        ls_res-status  = '@08@'.
        ls_res-action  = 'SIM_NEW'.
        ls_res-message = 'Simulated: User will be created (' &&
                         'Type: ' && p_ustyp && ', Valid: ' && p_gltgv && ' to ' && p_gltgb && ').'.
        APPEND ls_res TO gt_results.
      ELSE.
        " Real Execution: Call BAPI_USER_CREATE1
        PERFORM create_single_user USING ls_user
                                   CHANGING lt_return.

        PERFORM format_return_messages USING lt_return
                                       CHANGING lv_errmsg lv_has_err.

        IF lv_has_err = abap_true.
          ls_res-status  = '@0A@'.
          ls_res-action  = 'ERROR'.
          ls_res-message = lv_errmsg.
        ELSE.
          CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
            EXPORTING
              wait = 'X'.

          ls_res-status  = '@08@'.
          ls_res-action  = 'CREATED'.
          IF lv_errmsg IS NOT INITIAL.
            ls_res-message = 'User created successfully: ' && lv_errmsg.
          ELSE.
            ls_res-message = 'User created successfully with initial password and address details.'.
          ENDIF.
        ENDIF.
        APPEND ls_res TO gt_results.
      ENDIF.

    " Case B: User ALREADY EXISTS in SAP
    ELSE.
      IF p_upd = abap_false.
        " User exists, but update flag is not selected -> Skip with Yellow warning
        ls_res-status  = '@09@'.
        ls_res-action  = 'SKIPPED'.
        ls_res-message = 'User already exists in SAP. Check "Update Existing Users" to modify.'.
        APPEND ls_res TO gt_results.
      ELSE.
        IF p_test = abap_true.
          " Simulation Mode: Existing user update
          ls_res-status  = '@08@'.
          ls_res-action  = 'SIM_UPD'.
          IF p_pwd = abap_true AND ls_user-password IS NOT INITIAL.
            ls_res-message = 'Simulated: User details and password will be updated.'.
          ELSE.
            ls_res-message = 'Simulated: User details (Last name, email, phone, dept, function) will be updated.'.
          ENDIF.
          APPEND ls_res TO gt_results.
        ELSE.
          " Real Execution: Call BAPI_USER_CHANGE
          PERFORM update_single_user USING ls_user
                                     CHANGING lt_return.

          PERFORM format_return_messages USING lt_return
                                         CHANGING lv_errmsg lv_has_err.

          IF lv_has_err = abap_true.
            ls_res-status  = '@0A@'.
            ls_res-action  = 'ERROR'.
            ls_res-message = lv_errmsg.
          ELSE.
            CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
              EXPORTING
                wait = 'X'.

            ls_res-status  = '@08@'.
            ls_res-action  = 'UPDATED'.
            IF lv_errmsg IS NOT INITIAL.
              ls_res-message = 'User updated successfully: ' && lv_errmsg.
            ELSE.
              ls_res-message = 'User updated successfully.'.
            ENDIF.
          ENDIF.
          APPEND ls_res TO gt_results.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form create_single_user
*&---------------------------------------------------------------------*
FORM create_single_user USING    is_user   TYPE ty_user_csv
                        CHANGING et_return TYPE bapiret2_t.
  DATA: lv_username  TYPE bapibname-bapibname,
        ls_logondata TYPE bapilogond,
        ls_password  TYPE bapipwd,
        ls_defaults  TYPE bapidefaul,
        ls_address   TYPE bapiaddr3.

  CLEAR: et_return, ls_logondata, ls_password, ls_defaults, ls_address.

  lv_username = is_user-username.

  " 1. Logon Data
  ls_logondata-ustyp = p_ustyp.
  ls_logondata-gltgv = p_gltgv.
  ls_logondata-gltgb = p_gltgb.

  " 2. Password
  ls_password-bapipwd = is_user-password.

  " 3. Defaults
  ls_defaults-langu = p_langu.
  ls_defaults-spld  = p_spld.

  " 4. Address - Full Name mapped entirely into Last Name (BAPIADDR3-LASTNAME)
  IF strlen( is_user-fullname ) > 40.
    ls_address-lastname = is_user-fullname(40).
  ELSE.
    ls_address-lastname = is_user-fullname.
  ENDIF.
  ls_address-e_mail     = is_user-email.
  ls_address-tel1_numbr = is_user-phone.
  ls_address-department = is_user-department.
  ls_address-function   = is_user-function.

  CALL FUNCTION 'BAPI_USER_CREATE1'
    EXPORTING
      username  = lv_username
      logondata = ls_logondata
      password  = ls_password
      defaults  = ls_defaults
      address   = ls_address
    TABLES
      return    = et_return.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form update_single_user
*&---------------------------------------------------------------------*
FORM update_single_user USING    is_user   TYPE ty_user_csv
                        CHANGING et_return TYPE bapiret2_t.
  DATA: lv_username TYPE bapibname-bapibname,
        ls_address  TYPE bapiaddr3,
        ls_addressx TYPE bapiaddr3x,
        ls_password TYPE bapipwd,
        ls_pwd_x    TYPE bapipwdx.

  CLEAR: et_return, ls_address, ls_addressx, ls_password, ls_pwd_x.

  lv_username = is_user-username.

  " Update Address - Full Name mapped into Last Name
  IF strlen( is_user-fullname ) > 40.
    ls_address-lastname = is_user-fullname(40).
  ELSE.
    ls_address-lastname = is_user-fullname.
  ENDIF.
  ls_addressx-lastname = 'X'.

  IF is_user-email IS NOT INITIAL.
    ls_address-e_mail  = is_user-email.
    ls_addressx-e_mail = 'X'.
  ENDIF.

  IF is_user-phone IS NOT INITIAL.
    ls_address-tel1_numbr  = is_user-phone.
    ls_addressx-tel1_numbr = 'X'.
  ENDIF.

  IF is_user-department IS NOT INITIAL.
    ls_address-department  = is_user-department.
    ls_addressx-department = 'X'.
  ENDIF.

  IF is_user-function IS NOT INITIAL.
    ls_address-function  = is_user-function.
    ls_addressx-function = 'X'.
  ENDIF.

  " Optionally reset password if p_pwd is set
  IF p_pwd = abap_true AND is_user-password IS NOT INITIAL.
    ls_password-bapipwd = is_user-password.
    ls_pwd_x-bapipwd    = 'X'.
  ENDIF.

  CALL FUNCTION 'BAPI_USER_CHANGE'
    EXPORTING
      username  = lv_username
      address   = ls_address
      addressx  = ls_addressx
      password  = ls_password
      passwordx = ls_pwd_x
    TABLES
      return    = et_return.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form format_return_messages
*&---------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*& Form validate_email
*&---------------------------------------------------------------------*
FORM validate_email USING    iv_email    TYPE bapiaddr3-e_mail
                    CHANGING cv_email    TYPE bapiaddr3-e_mail
                             ev_is_valid TYPE abap_bool.
  DATA: ls_addr_in TYPE sx_address.
  CLEAR: cv_email, ev_is_valid.

  IF iv_email IS INITIAL.
    RETURN.
  ENDIF.

  " Syntactic basic checks: must contain '@' and domain must contain '.'
  IF iv_email NA '@' OR iv_email NA '.'.
    RETURN.
  ENDIF.

  ls_addr_in-type    = 'INT'.
  ls_addr_in-address = iv_email.

  CALL FUNCTION 'SX_INTERNET_ADDRESS_TO_NORMAL'
    EXPORTING
      address_unstruct    = ls_addr_in
    EXCEPTIONS
      error_address_type  = 1
      error_address       = 2
      error_group_address = 3
      OTHERS              = 4.

  IF sy-subrc = 0.
    cv_email    = iv_email.
    ev_is_valid = abap_true.
  ELSE.
    CLEAR cv_email.
    ev_is_valid = abap_false.
  ENDIF.
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
    MESSAGE 'No user records were processed.' TYPE 'S' DISPLAY LIKE 'W'.
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
      lo_col->set_long_text( 'SAP User (Click to open SU01)' ).
      lo_col->set_cell_type( if_salv_c_cell_type=>hotspot ).

      " Initial Password Column
      lo_col ?= lo_cols->get_column( 'PASSWORD' ).
      lo_col->set_short_text( 'Password' ).
      lo_col->set_medium_text( 'Initial Password' ).
      lo_col->set_long_text( 'Initial Logon Password' ).

      " Full Name (Last Name)
      lo_col ?= lo_cols->get_column( 'FULLNAME' ).
      lo_col->set_short_text( 'Full Name' ).
      lo_col->set_medium_text( 'Full Name (Last)' ).
      lo_col->set_long_text( 'User Full Name (Mapped to Last Name)' ).

      " Email
      lo_col ?= lo_cols->get_column( 'EMAIL' ).
      lo_col->set_short_text( 'Email' ).
      lo_col->set_medium_text( 'E-Mail Address' ).
      lo_col->set_long_text( 'E-Mail Address' ).

      " Phone
      lo_col ?= lo_cols->get_column( 'PHONE' ).
      lo_col->set_short_text( 'Phone' ).
      lo_col->set_medium_text( 'Telephone No.' ).
      lo_col->set_long_text( 'Telephone Number' ).

      " Department
      lo_col ?= lo_cols->get_column( 'DEPARTMENT' ).
      lo_col->set_short_text( 'Department' ).
      lo_col->set_medium_text( 'Department' ).
      lo_col->set_long_text( 'Department' ).

      " Function
      lo_col ?= lo_cols->get_column( 'FUNCTION' ).
      lo_col->set_short_text( 'Function' ).
      lo_col->set_medium_text( 'Job Function' ).
      lo_col->set_long_text( 'Job Function / Title' ).

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
