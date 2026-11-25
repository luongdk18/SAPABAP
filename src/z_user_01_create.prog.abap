*&---------------------------------------------------------------------*
*& Report Z_USER_01_CREATE
*&---------------------------------------------------------------------*
*& Purpose: Batch SAP User Creation & Update from CSV file
*& Description:
*&   Reads a CSV (.csv) file containing user records (Username,
*&   Full Name, Email, Phone No., Department, Function),
*&   validates input fields, handles UTF-8 encoding (supporting Vietnamese
*&   and accented characters), maps 'Full Name' into SAP 'Last Name'
*&   (BAPIADDR3-LASTNAME), automatically generates secure initial passwords
*&   for new users (via SUSR_GENERATE_PASSWORD / SAP compliant generator),
*&   checks existing users in USR02, creates new users via BAPI_USER_CREATE1
*&   or updates existing ones via BAPI_USER_CHANGE, executes
*&   BAPI_TRANSACTION_COMMIT, and presents an interactive ALV cockpit with
*&   generated passwords and one-click navigation to transaction SU01.
*&
*& File format (CSV .csv):
*&   Col 1: Username         (e.g., JOHND, max 12 chars, uppercase)
*&   Col 2: Full Name        (e.g., John Doe - mapped to LASTNAME)
*&   Col 3: Email            (e.g., johnd@example.com)
*&   Col 4: Phone No.        (e.g., (84)999999999)
*&   Col 5: Department       (e.g., Finance & Accounting)
*&   Col 6: Function         (e.g., Finance Controller)
*&   Col 7: Initial Password (e.g., InitPass@2026 - optional, auto-generated if empty)
*&   (Note: Password is read from the last column; if provided, used directly; if empty, auto-generated)
*&
*& Author: Antigravity AI (SAP Basis Engineering)
*& Package: $TMP (Local Object) or Custom Package
*&---------------------------------------------------------------------*
REPORT z_user_01_create.

*----------------------------------------------------------------------*
* 1. TYPES & DATA DEFINITIONS
*----------------------------------------------------------------------*
TYPES: ty_bin_255      TYPE x LENGTH 255,
       ty_t_bapiparam1 TYPE STANDARD TABLE OF bapiparam1 WITH DEFAULT KEY.

TYPES: BEGIN OF ty_user_csv,
         raw_username  TYPE string,
         username      TYPE bapibname-bapibname,
         password      TYPE bapipwd-bapipwd,
         fullname      TYPE string,
         email         TYPE bapiaddr3-e_mail,
         email_invalid TYPE abap_bool,
         phone         TYPE bapiaddr3-tel1_numbr,
         department    TYPE bapiaddr3-department,
         function      TYPE bapiaddr3-function,
       END OF ty_user_csv.

TYPES: BEGIN OF ty_alv_result,
         status     TYPE char12,              " Status Icon & Code: @08@ [OK], @09@ [WARN], @0A@ [ERR]
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

CONSTANTS: gc_status_ok   TYPE char12 VALUE '@08@ [OK]',
           gc_status_warn TYPE char12 VALUE '@09@ [WARN]',
           gc_status_err  TYPE char12 VALUE '@0A@ [ERR]'.

DATA: gt_users        TYPE STANDARD TABLE OF ty_user_csv,
      gt_results      TYPE STANDARD TABLE OF ty_alv_result,
      gv_loaded_pfile TYPE localfile,
      gt_prev_pids    TYPE STANDARD TABLE OF bapiparam1-parid.

*----------------------------------------------------------------------*
* 2. SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b_file WITH FRAME TITLE b_tit1.
  PARAMETERS: p_file TYPE localfile OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b_file.

SELECTION-SCREEN BEGIN OF BLOCK b_proc WITH FRAME TITLE b_tit2.
  PARAMETERS: p_test TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_upd  TYPE abap_bool AS CHECKBOX DEFAULT ' ',
              p_sync TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_pwd  TYPE abap_bool AS CHECKBOX DEFAULT ' '.
SELECTION-SCREEN END OF BLOCK b_proc.

SELECTION-SCREEN BEGIN OF BLOCK b_def WITH FRAME TITLE b_tit3.
  PARAMETERS: p_ustyp  TYPE bapilogond-ustyp      DEFAULT 'A',
              p_gltgv  TYPE bapilogond-gltgv      DEFAULT sy-datum,
              p_gltgb  TYPE bapilogond-gltgb      DEFAULT '99991231',
              p_langu  TYPE bapidefaul-langu      DEFAULT sy-langu,
              p_tziana TYPE bapidefaul-tzone_iana,
              p_spld   TYPE bapidefaul-spld,
              p_prnow  TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_comp   TYPE bapiuscomp-company.
SELECTION-SCREEN END OF BLOCK b_def.

SELECTION-SCREEN BEGIN OF BLOCK b_param WITH FRAME TITLE b_tit4.
  PARAMETERS: p_uppar TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_pfile TYPE localfile.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(3)   c_hdr_no.
    SELECTION-SCREEN COMMENT 5(16)  c_hdr_id.
    SELECTION-SCREEN COMMENT 23(20) c_hdr_va.
    SELECTION-SCREEN COMMENT 45(33) c_hdr_ds.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(3) c_no01.
    SELECTION-SCREEN POSITION 5.
    PARAMETERS: p_pid01 TYPE bapiparam1-parid VISIBLE LENGTH 16.
    SELECTION-SCREEN POSITION 23.
    PARAMETERS: p_pva01 TYPE bapiparam1-parva VISIBLE LENGTH 20.
    SELECTION-SCREEN COMMENT 45(33) c_pds01.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(3) c_no02.
    SELECTION-SCREEN POSITION 5.
    PARAMETERS: p_pid02 TYPE bapiparam1-parid VISIBLE LENGTH 16.
    SELECTION-SCREEN POSITION 23.
    PARAMETERS: p_pva02 TYPE bapiparam1-parva VISIBLE LENGTH 20.
    SELECTION-SCREEN COMMENT 45(33) c_pds02.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(3) c_no03.
    SELECTION-SCREEN POSITION 5.
    PARAMETERS: p_pid03 TYPE bapiparam1-parid VISIBLE LENGTH 16.
    SELECTION-SCREEN POSITION 23.
    PARAMETERS: p_pva03 TYPE bapiparam1-parva VISIBLE LENGTH 20.
    SELECTION-SCREEN COMMENT 45(33) c_pds03.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(3) c_no04.
    SELECTION-SCREEN POSITION 5.
    PARAMETERS: p_pid04 TYPE bapiparam1-parid VISIBLE LENGTH 16.
    SELECTION-SCREEN POSITION 23.
    PARAMETERS: p_pva04 TYPE bapiparam1-parva VISIBLE LENGTH 20.
    SELECTION-SCREEN COMMENT 45(33) c_pds04.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(3) c_no05.
    SELECTION-SCREEN POSITION 5.
    PARAMETERS: p_pid05 TYPE bapiparam1-parid VISIBLE LENGTH 16.
    SELECTION-SCREEN POSITION 23.
    PARAMETERS: p_pva05 TYPE bapiparam1-parva VISIBLE LENGTH 20.
    SELECTION-SCREEN COMMENT 45(33) c_pds05.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(3) c_no06.
    SELECTION-SCREEN POSITION 5.
    PARAMETERS: p_pid06 TYPE bapiparam1-parid VISIBLE LENGTH 16.
    SELECTION-SCREEN POSITION 23.
    PARAMETERS: p_pva06 TYPE bapiparam1-parva VISIBLE LENGTH 20.
    SELECTION-SCREEN COMMENT 45(33) c_pds06.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(3) c_no07.
    SELECTION-SCREEN POSITION 5.
    PARAMETERS: p_pid07 TYPE bapiparam1-parid VISIBLE LENGTH 16.
    SELECTION-SCREEN POSITION 23.
    PARAMETERS: p_pva07 TYPE bapiparam1-parva VISIBLE LENGTH 20.
    SELECTION-SCREEN COMMENT 45(33) c_pds07.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(3) c_no08.
    SELECTION-SCREEN POSITION 5.
    PARAMETERS: p_pid08 TYPE bapiparam1-parid VISIBLE LENGTH 16.
    SELECTION-SCREEN POSITION 23.
    PARAMETERS: p_pva08 TYPE bapiparam1-parva VISIBLE LENGTH 20.
    SELECTION-SCREEN COMMENT 45(33) c_pds08.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(3) c_no09.
    SELECTION-SCREEN POSITION 5.
    PARAMETERS: p_pid09 TYPE bapiparam1-parid VISIBLE LENGTH 16.
    SELECTION-SCREEN POSITION 23.
    PARAMETERS: p_pva09 TYPE bapiparam1-parva VISIBLE LENGTH 20.
    SELECTION-SCREEN COMMENT 45(33) c_pds09.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(3) c_no10.
    SELECTION-SCREEN POSITION 5.
    PARAMETERS: p_pid10 TYPE bapiparam1-parid VISIBLE LENGTH 16.
    SELECTION-SCREEN POSITION 23.
    PARAMETERS: p_pva10 TYPE bapiparam1-parva VISIBLE LENGTH 20.
    SELECTION-SCREEN COMMENT 45(33) c_pds10.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b_param.

*----------------------------------------------------------------------*
* 3. INITIALIZATION & SCREEN EVENTS
*----------------------------------------------------------------------*
INITIALIZATION.
  b_tit1 = 'Input CSV File (.csv)'(b01).
  b_tit2 = 'Execution & Update Options'(b02).
  b_tit3 = 'User Defaults (Logon & Defaults)'(b03).
  b_tit4 = 'User Parameters (SU01 Parameters)'(b04).

  %_p_file_%_app_%-text   = 'File Path'.
  %_p_test_%_app_%-text   = 'Simulation (Test Run)'.
  %_p_upd_%_app_%-text    = 'Update Existing Users'.
  %_p_sync_%_app_%-text   = 'Two-Way Sync (Clear Blank CSV)'.
  %_p_pwd_%_app_%-text    = 'Reset Password on Update'.
  %_p_ustyp_%_app_%-text  = 'User Type (A=Dialog)'.
  %_p_gltgv_%_app_%-text  = 'Valid From'.
  %_p_gltgb_%_app_%-text  = 'Valid To'.
  %_p_langu_%_app_%-text  = 'Logon Language'.
  %_p_tziana_%_app_%-text = 'Time Zone (IANA)'.
  %_p_spld_%_app_%-text   = 'Default Output Device'.
  %_p_prnow_%_app_%-text  = 'Print Immediately (Print Now)'.
  %_p_comp_%_app_%-text   = 'Company Address'.
  %_p_uppar_%_app_%-text  = 'Create/Overwrite Parameters'.
  %_p_pfile_%_app_%-text  = 'Parameter CSV File'.

  c_hdr_no = 'No.'.
  c_hdr_id = 'Parameter ID'.
  c_hdr_va = 'Parameter Value'.
  c_hdr_ds = 'Description'.

  c_no01 = '01.'.
  c_no02 = '02.'.
  c_no03 = '03.'.
  c_no04 = '04.'.
  c_no05 = '05.'.
  c_no06 = '06.'.
  c_no07 = '07.'.
  c_no08 = '08.'.
  c_no09 = '09.'.
  c_no10 = '10.'.

  PERFORM refresh_param_descriptions USING abap_false.

AT SELECTION-SCREEN OUTPUT.
  PERFORM refresh_param_descriptions USING abap_false.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  PERFORM f4_file_open CHANGING p_file.

AT SELECTION-SCREEN ON p_file.
  PERFORM validate_filename USING p_file.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_pfile.
  PERFORM f4_param_file_open CHANGING p_pfile.

AT SELECTION-SCREEN ON p_pfile.
  PERFORM validate_param_filename USING p_pfile.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_comp.
  PERFORM f4_company CHANGING p_comp.

AT SELECTION-SCREEN.
  IF p_gltgv IS NOT INITIAL AND p_gltgb IS NOT INITIAL AND p_gltgv > p_gltgb.
    MESSAGE 'Valid From date cannot be later than Valid To date.' TYPE 'E'.
  ENDIF.
  IF p_pfile IS INITIAL.
    CLEAR gv_loaded_pfile.
  ELSEIF p_pfile <> gv_loaded_pfile OR ( p_pid01 IS INITIAL AND p_pid02 IS INITIAL ).
    PERFORM load_param_file_to_screen USING p_pfile abap_false.
  ENDIF.
  PERFORM validate_screen_params.

*----------------------------------------------------------------------*
* 4. START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.
  PERFORM check_authority.
  PERFORM upload_and_parse_file USING p_file.
  PERFORM process_users.
  PERFORM display_alv_results.

*&---------------------------------------------------------------------*
*& Form open_csv_dialog
*&---------------------------------------------------------------------*
FORM open_csv_dialog USING    iv_title  TYPE string
                              iv_filter TYPE string
                     CHANGING cv_file   TYPE localfile.
  DATA: lt_filetable TYPE filetable,
        ls_file      TYPE file_table,
        lv_rc        TYPE i.

  cl_gui_frontend_services=>file_open_dialog(
    EXPORTING
      window_title            = iv_title
      file_filter             = iv_filter
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
*& Form f4_file_open
*&---------------------------------------------------------------------*
FORM f4_file_open CHANGING cv_file TYPE localfile.
  DATA: lv_picked    TYPE localfile,
        lv_cand      TYPE string,
        lv_off       TYPE i,
        lv_exists_pf TYPE abap_bool.

  PERFORM open_csv_dialog
    USING    'Select Users CSV File (.csv)'
             'User Creation CSV (*01_Create*.csv)|*01_Create*.csv|CSV files (*.csv)|*.csv|All files (*.*)|*.*'
    CHANGING lv_picked.

  IF lv_picked IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM validate_filename USING lv_picked.
  cv_file = lv_picked.

  IF p_pfile IS INITIAL.
    lv_cand = lv_picked.
    FIND '_01_Create_converted.csv' IN lv_cand IGNORING CASE MATCH OFFSET lv_off.
    IF sy-subrc = 0.
      lv_cand = lv_cand(lv_off) && '_Create_Parameter_converted.csv'.
    ELSE.
      FIND '_01_Create.csv' IN lv_cand IGNORING CASE MATCH OFFSET lv_off.
      IF sy-subrc = 0.
        lv_cand = lv_cand(lv_off) && '_Create_Parameter_converted.csv'.
      ELSE.
        CLEAR lv_cand.
      ENDIF.
    ENDIF.

    IF lv_cand IS NOT INITIAL.
      CLEAR lv_exists_pf.
      cl_gui_frontend_services=>file_exist(
        EXPORTING
          file   = lv_cand
        RECEIVING
          result = lv_exists_pf
        EXCEPTIONS
          OTHERS = 1 ).
      IF sy-subrc = 0 AND lv_exists_pf = abap_true.
        p_pfile = lv_cand.
        PERFORM load_param_file_to_screen USING p_pfile abap_true.
      ENDIF.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form f4_param_file_open
*&---------------------------------------------------------------------*
FORM f4_param_file_open CHANGING cv_file TYPE localfile.
  DATA: lv_picked TYPE localfile.

  PERFORM open_csv_dialog
    USING    'Select User Parameter CSV File (.csv)'
             'Parameter CSV (*Create_Parameter*.csv)|*Create_Parameter*.csv|CSV files (*.csv)|*.csv|All files (*.*)|*.*'
    CHANGING lv_picked.

  IF lv_picked IS NOT INITIAL.
    PERFORM validate_param_filename USING lv_picked.
    PERFORM load_param_file_to_screen USING lv_picked abap_true.
    cv_file = lv_picked.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form extract_file_basename
*&---------------------------------------------------------------------*
FORM extract_file_basename USING    iv_file TYPE localfile
                           CHANGING ev_name TYPE string.
  DATA: lv_path  TYPE string,
        lt_parts TYPE STANDARD TABLE OF string.

  CLEAR ev_name.
  IF iv_file IS INITIAL.
    RETURN.
  ENDIF.

  lv_path = iv_file.
  REPLACE ALL OCCURRENCES OF '/' IN lv_path WITH '\'.
  SPLIT lv_path AT '\' INTO TABLE lt_parts.
  IF lines( lt_parts ) > 0.
    ev_name = lt_parts[ lines( lt_parts ) ].
  ELSE.
    ev_name = lv_path.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form validate_filename
*&---------------------------------------------------------------------*
FORM validate_filename USING iv_file TYPE localfile.
  DATA: lv_fname TYPE string.

  IF iv_file IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM extract_file_basename USING iv_file CHANGING lv_fname.

  DATA(lv_up) = to_upper( condense( lv_fname ) ).
  IF strlen( lv_up ) <= 4 OR NOT ( lv_up CP '*.CSV' ).
    MESSAGE |Invalid file '{ lv_fname }'. Expected CSV file (*_01_Create_converted.csv).| TYPE 'E'.
  ENDIF.

  DATA(lv_name_ok) = abap_false.
  IF lv_up CS '01_CREATE'.
    lv_name_ok = abap_true.
  ELSEIF lv_up CS 'USER_01'.
    lv_name_ok = abap_true.
  ENDIF.
  IF lv_up CS '01_MASTER' OR lv_up CS '02_DERIVE' OR lv_up CS '03A_ORG'
     OR lv_up CS '03B_AUTH' OR lv_up CS '03B_OBJECT' OR lv_up CS '03C_ACTIVITY'
     OR lv_up CS '04_COMPOSITE' OR lv_up CS '02_ASSIGN' OR lv_up CS 'PARAMETER'.
    lv_name_ok = abap_false.
  ENDIF.
  IF lv_name_ok = abap_false.
    MESSAGE |Invalid file '{ lv_fname }' for Z_USER_01_CREATE. Expected '*_01_Create_converted.csv'.| TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form validate_param_filename
*&---------------------------------------------------------------------*
FORM validate_param_filename USING iv_file TYPE localfile.
  DATA: lv_fname TYPE string.

  IF iv_file IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM extract_file_basename USING iv_file CHANGING lv_fname.

  DATA(lv_up) = to_upper( condense( lv_fname ) ).
  IF strlen( lv_up ) <= 4 OR NOT ( lv_up CP '*.CSV' ).
    MESSAGE |Invalid file '{ lv_fname }'. Expected Parameter CSV (*_Create_Parameter_converted.csv).| TYPE 'E'.
  ENDIF.

  DATA(lv_name_ok) = abap_false.
  IF lv_up CS 'PARAMETER'.
    lv_name_ok = abap_true.
  ENDIF.
  IF lv_up CS '01_MASTER' OR lv_up CS '02_DERIVE' OR lv_up CS '03A_ORG'
     OR lv_up CS '03B_AUTH' OR lv_up CS '03B_OBJECT' OR lv_up CS '03C_ACTIVITY'
     OR lv_up CS '04_COMPOSITE' OR lv_up CS '02_ASSIGN'.
    lv_name_ok = abap_false.
  ENDIF.
  IF lv_name_ok = abap_false.
    MESSAGE |Invalid file '{ lv_fname }' for Parameter upload. Expected '*_Create_Parameter_converted.csv'.| TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form f4_company
*&---------------------------------------------------------------------*
FORM f4_company CHANGING cv_comp TYPE bapiuscomp-company.
  TYPES: BEGIN OF ty_comp_f4,
           company    TYPE uscompany-company,
           addrnumber TYPE uscompany-addrnumber,
         END OF ty_comp_f4.

  DATA: lt_comp TYPE STANDARD TABLE OF ty_comp_f4.

  SELECT company, addrnumber FROM uscompany
    INTO TABLE @lt_comp.

  IF lt_comp IS INITIAL.
    RETURN.
  ENDIF.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield        = 'COMPANY'
      dynpprog        = sy-repid
      dynpnr          = sy-dynnr
      dynprofield     = 'P_COMP'
      value_org       = 'S'
    TABLES
      value_tab       = lt_comp
    EXCEPTIONS
      parameter_error = 1
      no_values_found = 2
      OTHERS          = 3.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form check_authority
*&---------------------------------------------------------------------*
FORM check_authority.
  " Check authorization for user administration (S_USER_GRP)
  IF p_test = abap_true.
    AUTHORITY-CHECK OBJECT 'S_USER_GRP'
      ID 'CLASS' DUMMY
      ID 'ACTVT' FIELD '03'. " Display
    IF sy-subrc <> 0.
      MESSAGE 'No display authorization for SAP user administration (S_USER_GRP ACTVT 03).' TYPE 'E'.
    ENDIF.
    RETURN.
  ENDIF.

  AUTHORITY-CHECK OBJECT 'S_USER_GRP'
    ID 'CLASS' DUMMY
    ID 'ACTVT' FIELD '01'. " Create
  IF sy-subrc <> 0.
    AUTHORITY-CHECK OBJECT 'S_USER_GRP'
      ID 'CLASS' DUMMY
      ID 'ACTVT' FIELD '02'. " Change
    IF sy-subrc <> 0.
      MESSAGE 'No authorization to create or modify SAP users (object S_USER_GRP).' TYPE 'E'.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form read_local_csv_lines
*&---------------------------------------------------------------------*
FORM read_local_csv_lines USING    iv_file  TYPE localfile
                          CHANGING et_lines TYPE string_table.
  DATA: lv_filepath   TYPE string,
        lt_binary_tab TYPE STANDARD TABLE OF ty_bin_255,
        lv_length     TYPE i,
        lv_content    TYPE string.

  CLEAR et_lines.
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
    IF sy-subrc <> 0.
      MESSAGE 'Failed to decode CSV file content (check UTF-8 encoding).' TYPE 'E'.
    ENDIF.
  ENDIF.

  " Strip Byte Order Mark (BOM U+FEFF) if present
  DATA(lv_bom) = cl_abap_conv_in_ce=>uccp( 'FEFF' ).
  IF strlen( lv_content ) > 0 AND lv_content(1) = lv_bom.
    lv_content = lv_content+1.
  ENDIF.

  " Normalize mixed line endings (CRLF / CR -> LF) before splitting
  REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf
    IN lv_content WITH cl_abap_char_utilities=>newline.
  REPLACE ALL OCCURRENCES OF |\r|
    IN lv_content WITH cl_abap_char_utilities=>newline.
  SPLIT lv_content AT cl_abap_char_utilities=>newline INTO TABLE et_lines.

  LOOP AT et_lines ASSIGNING FIELD-SYMBOL(<lv_line>).
    IF sy-tabix = 1 AND strlen( <lv_line> ) > 0 AND <lv_line>(1) = lv_bom.
      <lv_line> = <lv_line>+1.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form upload_and_parse_file
*&---------------------------------------------------------------------*
FORM upload_and_parse_file USING iv_file TYPE localfile.
  DATA: lt_lines       TYPE STANDARD TABLE OF string,
        lv_line        TYPE string,
        lv_line_idx    TYPE i,
        ls_user        TYPE ty_user_csv,
        lt_tokens      TYPE string_table,
        lv_c1          TYPE string,
        lv_pwd_col_idx TYPE i.

  PERFORM read_local_csv_lines USING iv_file CHANGING lt_lines.

  CLEAR: lv_line_idx, lv_pwd_col_idx.

  LOOP AT lt_lines INTO lv_line.
    lv_line_idx = lv_line_idx + 1.
    IF lv_line IS INITIAL.
      CONTINUE.
    ENDIF.

    PERFORM parse_csv_line USING lv_line
                           CHANGING lt_tokens.

    IF lt_tokens IS INITIAL.
      CONTINUE.
    ENDIF.

    READ TABLE lt_tokens INTO lv_c1 INDEX 1.
    DATA(lv_c1_up) = to_upper( lv_c1 ).

    " Validate header row against wrong CSV types
    IF lv_line_idx = 1.
      DATA(lv_hdr_line) = to_upper( lv_line ).
      IF lv_hdr_line CS 'ROLE' OR lv_hdr_line CS 'TCODE'
         OR lv_hdr_line CS 'ORG_LEVEL' OR lv_hdr_line CS 'OBJECT-FIELD'
         OR lv_hdr_line CS 'VALUE-LOW'
         OR lv_hdr_line CS 'PARAMETER ID' OR lv_hdr_line CS 'PARAMATER ID'.
        MESSAGE 'Invalid CSV header for Z_USER_01_CREATE. Expected: Username, Full Name, Email, Phone No., Department, Function.' TYPE 'E'.
      ENDIF.
    ENDIF.

    " Check and skip header row
    IF lv_line_idx = 1 AND ( lv_c1_up CS 'USER' OR lv_c1_up CS 'NAME' OR lv_c1_up CS 'BNAME' ).
      LOOP AT lt_tokens INTO DATA(lv_hdr_tok).
        DATA(lv_hdr_up) = to_upper( lv_hdr_tok ).
        IF lv_hdr_up CS 'PASS' OR lv_hdr_up CS 'PWD' OR lv_hdr_up CS 'MẬT' OR lv_hdr_up CS 'MAT'.
          lv_pwd_col_idx = sy-tabix.
        ENDIF.
      ENDLOOP.
      CONTINUE.
    ENDIF.
    IF lv_c1_up = 'USERNAME' OR lv_c1_up = 'USER' OR lv_c1_up = 'BNAME'.
      CONTINUE.
    ENDIF.

    IF lv_c1 IS NOT INITIAL.
      DATA: lv_raw_user TYPE string,
            lv_pwd_val  TYPE string,
            lv_last_tok TYPE string,
            lv_num_tok  TYPE i.

      CLEAR: ls_user, lv_raw_user, lv_pwd_val, lv_last_tok, lv_num_tok.
      lv_raw_user = lv_c1_up.
      CONDENSE lv_raw_user NO-GAPS.
      ls_user-raw_username = lv_raw_user.
      IF strlen( lv_raw_user ) <= 12.
        ls_user-username = lv_raw_user.
      ENDIF.

      READ TABLE lt_tokens INTO ls_user-fullname   INDEX 2.
      READ TABLE lt_tokens INTO ls_user-email      INDEX 3.
      READ TABLE lt_tokens INTO ls_user-phone      INDEX 4.
      READ TABLE lt_tokens INTO ls_user-department INDEX 5.
      READ TABLE lt_tokens INTO ls_user-function   INDEX 6.

      " Read Initial Password from the mapped or last column (strictly check sy-subrc)
      lv_num_tok = lines( lt_tokens ).
      IF lv_pwd_col_idx > 0.
        READ TABLE lt_tokens INTO lv_pwd_val INDEX lv_pwd_col_idx.
        IF sy-subrc = 0.
          CONDENSE lv_pwd_val NO-GAPS.
          ls_user-password = lv_pwd_val.
        ENDIF.
      ELSEIF lv_num_tok >= 7.
        " No explicit header: read last column (Col 7 or final non-empty token >= 7)
        READ TABLE lt_tokens INTO lv_last_tok INDEX lv_num_tok.
        IF sy-subrc = 0.
          CONDENSE lv_last_tok NO-GAPS.
        ELSE.
          CLEAR lv_last_tok.
        ENDIF.
        IF lv_last_tok IS INITIAL AND lv_num_tok > 7.
          READ TABLE lt_tokens INTO lv_last_tok INDEX 7.
          IF sy-subrc = 0.
            CONDENSE lv_last_tok NO-GAPS.
          ELSE.
            CLEAR lv_last_tok.
          ENDIF.
        ENDIF.
        ls_user-password = lv_last_tok.
      ENDIF.

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
FORM parse_csv_line USING    iv_line   TYPE string
                    CHANGING et_tokens TYPE string_table.
  DATA: lv_len      TYPE i,
        lv_pos      TYPE i,
        lv_in_q     TYPE abap_bool VALUE abap_false,
        lv_cur      TYPE string,
        lv_char     TYPE string,
        lv_next     TYPE string,
        lv_delim    TYPE c LENGTH 1,
        lv_cnt_tab  TYPE i,
        lv_cnt_semi TYPE i,
        lv_cnt_com  TYPE i.

  CLEAR et_tokens.

  lv_len = strlen( iv_line ).

  " Pass 1: Detect primary delimiter outside quotes (TAB > ';' > ',')
  lv_pos = 0.
  lv_in_q = abap_false.
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
    lv_delim = cl_abap_char_utilities=>horizontal_tab.
  ELSEIF lv_cnt_semi > 0 AND lv_cnt_semi >= lv_cnt_com.
    lv_delim = ';'.
  ELSE.
    lv_delim = ','.
  ENDIF.

  " Pass 2: Tokenize with RFC 4180 escaped-quote support and space preservation
  lv_pos = 0.
  lv_in_q = abap_false.
  CLEAR lv_cur.
  WHILE lv_pos < lv_len.
    lv_char = substring( val = iv_line off = lv_pos len = 1 ).
    IF lv_char = '"'.
      IF lv_in_q = abap_true AND lv_pos + 1 < lv_len.
        lv_next = substring( val = iv_line off = lv_pos + 1 len = 1 ).
        IF lv_next = '"'.
          lv_cur = lv_cur && '"'.
          lv_pos = lv_pos + 2.
          CONTINUE.
        ENDIF.
      ENDIF.
      lv_in_q = xsdbool( lv_in_q = abap_false ).
    ELSEIF lv_char = lv_delim AND lv_in_q = abap_false.
      APPEND lv_cur TO et_tokens.
      CLEAR lv_cur.
    ELSE.
      lv_cur = lv_cur && lv_char.
    ENDIF.
    lv_pos = lv_pos + 1.
  ENDWHILE.
  APPEND lv_cur TO et_tokens.

  " Clean quotes and trim outer spaces for each token
  LOOP AT et_tokens ASSIGNING FIELD-SYMBOL(<lv_tok>).
    PERFORM clean_cell CHANGING <lv_tok>.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form clean_cell
*&---------------------------------------------------------------------*
FORM clean_cell CHANGING cv_val TYPE string.
  CONDENSE cv_val.
  DATA(lv_len) = strlen( cv_val ).
  IF lv_len >= 2.
    DATA(lv_last_off) = lv_len - 1.
    IF cv_val(1) = '"' AND substring( val = cv_val off = lv_last_off len = 1 ) = '"'.
      DATA(lv_inner_len) = lv_len - 2.
      IF lv_inner_len > 0.
        cv_val = substring( val = cv_val off = 1 len = lv_inner_len ).
      ELSE.
        CLEAR cv_val.
      ENDIF.
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
    DATA: lv_clean_email TYPE bapiaddr3-e_mail,
          lv_email_valid TYPE abap_bool,
          lv_email_note  TYPE string,
          lv_pwd_from_file TYPE abap_bool,
          lv_usr02_bname TYPE usr02-bname.

    CLEAR: ls_res, lt_return, lv_errmsg, lv_has_err, lv_exists,
           lv_clean_email, lv_email_valid, lv_email_note,
           lv_pwd_from_file, lv_usr02_bname.

    " Validation 1: Username must not be initial
    IF ls_user-raw_username IS INITIAL.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = 'Username is empty or missing.'.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " Validation 2: Username max 12 characters (checked on raw string BEFORE CHAR12 truncation)
    IF strlen( ls_user-raw_username ) > 12.
      ls_res-status     = gc_status_err.
      ls_res-action     = 'ERROR'.
      ls_res-username   = ls_user-raw_username(12).
      ls_res-fullname   = ls_user-fullname.
      ls_res-email      = ls_user-email.
      ls_res-phone      = ls_user-phone.
      ls_res-department = ls_user-department.
      ls_res-function   = ls_user-function.
      ls_res-message    = 'Username exceeds SAP 12-character limit: ' && ls_user-raw_username.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " Validate email: if invalid, ignore it without overwriting existing SAP email
    IF ls_user-email IS NOT INITIAL.
      PERFORM validate_email USING ls_user-email
                             CHANGING lv_clean_email lv_email_valid.
      IF lv_email_valid = abap_false.
        lv_email_note = | [WARN: Invalid email '{ ls_user-email }' ignored]|.
        ls_user-email_invalid = abap_true.
        CLEAR ls_user-email.
      ELSE.
        ls_user-email = lv_clean_email.
      ENDIF.
    ENDIF.

    " Check user existence in USR02
    SELECT SINGLE bname FROM usr02 INTO @lv_usr02_bname
      WHERE bname = @ls_user-username.
    IF sy-subrc = 0.
      lv_exists = abap_true.
    ELSE.
      lv_exists = abap_false.
    ENDIF.

    " Track whether initial password was supplied in the input file
    IF ls_user-password IS NOT INITIAL.
      lv_pwd_from_file = abap_true.
    ELSE.
      lv_pwd_from_file = abap_false.
    ENDIF.

    " Generate Initial Password if empty (for new user or when password reset is requested)
    IF lv_exists = abap_false.
      IF ls_user-password IS INITIAL.
        PERFORM generate_initial_password CHANGING ls_user-password.
      ENDIF.
      ls_res-password = ls_user-password.
    ELSE.
      IF p_upd = abap_true AND p_pwd = abap_true.
        IF ls_user-password IS INITIAL.
          PERFORM generate_initial_password CHANGING ls_user-password.
        ENDIF.
        ls_res-password = ls_user-password.
      ELSE.
        CLEAR ls_user-password.
        ls_res-password = '(Unchanged)'.
      ENDIF.
    ENDIF.

    ls_res-username   = ls_user-username.
    ls_res-fullname   = ls_user-fullname.
    ls_res-email      = ls_user-email.
    ls_res-phone      = ls_user-phone.
    ls_res-department = ls_user-department.
    ls_res-function   = ls_user-function.

    " Validation 3: Full Name must not be initial (BAPIADDR3-LASTNAME is mandatory)
    IF ls_user-fullname IS INITIAL.
      ls_res-status  = gc_status_err.
      ls_res-action  = 'ERROR'.
      ls_res-message = 'Full Name is empty (SAP Last Name is mandatory).'.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " Case A: User does NOT exist in SAP
    IF lv_exists = abap_false.
      IF p_test = abap_true.
        " Simulation Mode: New user creation
        ls_res-status  = COND #( WHEN lv_email_note IS NOT INITIAL THEN gc_status_warn ELSE gc_status_ok ).
        ls_res-action  = 'SIM_NEW'.
        IF lv_pwd_from_file = abap_true.
          ls_res-message = 'Simulated: User will be created with initial password from file (' &&
                           'Type: ' && p_ustyp && ', Valid: ' && p_gltgv && ' to ' && p_gltgb && ').' && lv_email_note.
        ELSE.
          ls_res-message = 'Simulated: User will be created with auto-generated initial password (' &&
                           'Type: ' && p_ustyp && ', Valid: ' && p_gltgv && ' to ' && p_gltgb && ').' && lv_email_note.
        ENDIF.
        APPEND ls_res TO gt_results.
      ELSE.
        " Real Execution: Call BAPI_USER_CREATE1
        PERFORM create_single_user USING ls_user
                                   CHANGING lt_return.

        PERFORM format_return_messages USING lt_return
                                       CHANGING lv_errmsg lv_has_err.

        IF lv_has_err = abap_true.
          CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
          ls_res-status  = gc_status_err.
          ls_res-action  = 'ERROR'.
          ls_res-message = lv_errmsg && lv_email_note.
        ELSE.
          CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
            EXPORTING
              wait = 'X'.

          ls_res-status  = COND #( WHEN lv_email_note IS NOT INITIAL THEN gc_status_warn ELSE gc_status_ok ).
          ls_res-action  = 'CREATED'.
          IF lv_errmsg IS NOT INITIAL.
            ls_res-message = 'User created successfully: ' && lv_errmsg && lv_email_note.
          ELSE.
            IF lv_pwd_from_file = abap_true.
              ls_res-message = 'User created successfully with initial password from file & details.' && lv_email_note.
            ELSE.
              ls_res-message = 'User created successfully with auto-generated initial password & details.' && lv_email_note.
            ENDIF.
          ENDIF.
        ENDIF.
        APPEND ls_res TO gt_results.
      ENDIF.

    " Case B: User ALREADY EXISTS in SAP
    ELSE.
      IF p_upd = abap_false.
        " User exists, but update flag is not selected -> Skip with Yellow warning
        ls_res-status  = gc_status_warn.
        ls_res-action  = 'SKIPPED'.
        ls_res-message = 'User already exists in SAP. Check "Update Existing Users" to modify.' && lv_email_note.
        APPEND ls_res TO gt_results.
      ELSE.
        " Check if existing user details already match CSV (when password reset is not requested)
        DATA: ls_cur_addr   TYPE bapiaddr3,
              ls_cur_comp   TYPE bapiuscomp,
              ls_cur_def    TYPE bapidefaul,
              lt_cur_params TYPE ty_t_bapiparam1,
              lt_scr_params TYPE ty_t_bapiparam1,
              lv_tgt_spdb   TYPE bapidefaul-spdb,
              lt_cur_ret    TYPE STANDARD TABLE OF bapiret2,
              lv_cur_err    TYPE abap_bool,
              lv_cur_msg    TYPE string,
              lv_usr_same   TYPE abap_bool,
              lv_tgt_last   TYPE bapiaddr3-lastname.
        CLEAR: ls_cur_addr, ls_cur_comp, ls_cur_def, lt_cur_params,
               lt_scr_params, lv_tgt_spdb, lt_cur_ret, lv_cur_err,
               lv_cur_msg, lv_usr_same, lv_tgt_last.

        IF strlen( ls_user-fullname ) > 40.
          lv_tgt_last = ls_user-fullname(40).
        ELSE.
          lv_tgt_last = ls_user-fullname.
        ENDIF.

        IF p_pwd = abap_false.
          PERFORM collect_screen_parameters CHANGING lt_scr_params.
          lv_tgt_spdb = COND #( WHEN p_prnow = abap_true THEN 'G' ELSE 'H' ).

          CALL FUNCTION 'BAPI_USER_GET_DETAIL'
            EXPORTING
              username   = ls_user-username
            IMPORTING
              defaults   = ls_cur_def
              address    = ls_cur_addr
              company    = ls_cur_comp
            TABLES
              parameter1 = lt_cur_params
              return     = lt_cur_ret.

          PERFORM format_return_messages USING lt_cur_ret
                                         CHANGING lv_cur_msg lv_cur_err.
          IF lv_cur_err = abap_true.
            ls_res-status  = gc_status_err.
            ls_res-action  = 'ERROR'.
            ls_res-message = 'Failed to read existing user details: ' && lv_cur_msg.
            APPEND ls_res TO gt_results.
            CONTINUE.
          ENDIF.

          lv_usr_same = abap_true.
          IF ls_cur_addr-lastname <> lv_tgt_last.
            lv_usr_same = abap_false.
          ENDIF.
          IF ls_user-email_invalid = abap_false
             AND ( p_sync = abap_true OR ls_user-email IS NOT INITIAL )
             AND ls_cur_addr-e_mail <> ls_user-email.
            lv_usr_same = abap_false.
          ENDIF.
          IF ( p_sync = abap_true OR ls_user-phone IS NOT INITIAL ) AND ls_cur_addr-tel1_numbr <> ls_user-phone.
            lv_usr_same = abap_false.
          ENDIF.
          IF ( p_sync = abap_true OR ls_user-department IS NOT INITIAL ) AND ls_cur_addr-department <> ls_user-department.
            lv_usr_same = abap_false.
          ENDIF.
          IF ( p_sync = abap_true OR ls_user-function IS NOT INITIAL ) AND ls_cur_addr-function <> ls_user-function.
            lv_usr_same = abap_false.
          ENDIF.
          IF p_comp IS NOT INITIAL AND ls_cur_comp-company <> p_comp.
            lv_usr_same = abap_false.
          ENDIF.
          IF ls_cur_def-spdb <> lv_tgt_spdb.
            lv_usr_same = abap_false.
          ENDIF.
          IF p_spld IS NOT INITIAL AND ls_cur_def-spld <> p_spld.
            lv_usr_same = abap_false.
          ENDIF.
          IF p_tziana IS NOT INITIAL AND ls_cur_def-tzone_iana <> p_tziana.
            lv_usr_same = abap_false.
          ENDIF.
          IF p_uppar = abap_true AND lt_scr_params IS NOT INITIAL AND lv_usr_same = abap_true.
            LOOP AT lt_scr_params INTO DATA(ls_scr_par).
              READ TABLE lt_cur_params INTO DATA(ls_cur_par)
                WITH KEY parid = ls_scr_par-parid.
              IF sy-subrc <> 0 OR ls_cur_par-parva <> ls_scr_par-parva.
                lv_usr_same = abap_false.
                EXIT.
              ENDIF.
            ENDLOOP.
          ENDIF.
        ENDIF.

        IF lv_usr_same = abap_true.
          ls_res-status  = COND #( WHEN lv_email_note IS NOT INITIAL THEN gc_status_warn ELSE gc_status_ok ).
          ls_res-action  = 'UP-TO-DATE'.
          IF p_test = abap_true.
            ls_res-message = 'Simulated: User details, defaults & parameters match. No changes needed.' && lv_email_note.
          ELSE.
            ls_res-message = 'User details, defaults & parameters match. No changes needed.' && lv_email_note.
          ENDIF.
          APPEND ls_res TO gt_results.

        " Subcase B1: Simulation Mode
        ELSEIF p_test = abap_true.
          ls_res-status  = COND #( WHEN lv_email_note IS NOT INITIAL THEN gc_status_warn ELSE gc_status_ok ).
          ls_res-action  = 'SIM_UPD'.
          IF p_pwd = abap_true.
            IF lv_pwd_from_file = abap_true.
              ls_res-message = 'Simulated: User details, defaults, parameters & password will be updated.' && lv_email_note.
            ELSE.
              ls_res-message = 'Simulated: User details, defaults, parameters & auto password will be updated.' && lv_email_note.
            ENDIF.
          ELSE.
            ls_res-message = 'Simulated: User details, defaults & parameters will be updated (Pwd unchanged).' && lv_email_note.
          ENDIF.
          APPEND ls_res TO gt_results.

        " Subcase B2: Real Execution
        ELSE.
          " Call BAPI_USER_CHANGE to update user address, defaults & parameters
          PERFORM update_single_user USING ls_user
                                     CHANGING lt_return.

          PERFORM format_return_messages USING lt_return
                                         CHANGING lv_errmsg lv_has_err.

          IF lv_has_err = abap_true.
            CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
            ls_res-status  = gc_status_err.
            ls_res-action  = 'ERROR'.
            ls_res-message = lv_errmsg && lv_email_note.
          ELSE.
            CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
              EXPORTING
                wait = 'X'.

            ls_res-status  = COND #( WHEN lv_email_note IS NOT INITIAL THEN gc_status_warn ELSE gc_status_ok ).
            ls_res-action  = 'UPDATED'.
            IF lv_errmsg IS NOT INITIAL.
              ls_res-message = 'User updated successfully: ' && lv_errmsg && lv_email_note.
            ELSE.
              IF p_pwd = abap_true.
                IF lv_pwd_from_file = abap_true.
                  ls_res-message = 'User updated successfully with password from file.' && lv_email_note.
                ELSE.
                  ls_res-message = 'User updated successfully with auto-generated password.' && lv_email_note.
                ENDIF.
              ELSE.
                ls_res-message = 'User updated successfully (password unchanged).' && lv_email_note.
              ENDIF.
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
        ls_address   TYPE bapiaddr3,
        ls_company   TYPE bapiuscomp,
        lt_param1    TYPE ty_t_bapiparam1.

  CLEAR: et_return, ls_logondata, ls_password, ls_defaults, ls_address, ls_company, lt_param1.

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
  ls_defaults-spdb  = COND #( WHEN p_prnow = abap_true THEN 'G' ELSE 'H' ).
  IF p_tziana IS NOT INITIAL.
    ls_defaults-tzone_iana = p_tziana.
  ENDIF.

  " 4. Company Address (Ensures user is created as Normal Dialog user, not Technical)
  IF p_comp IS NOT INITIAL.
    ls_company-company = p_comp.
  ENDIF.

  " 5. Address - Full Name mapped entirely into Last Name (BAPIADDR3-LASTNAME)
  IF strlen( is_user-fullname ) > 40.
    ls_address-lastname = is_user-fullname(40).
  ELSE.
    ls_address-lastname = is_user-fullname.
  ENDIF.
  ls_address-e_mail     = is_user-email.
  ls_address-tel1_numbr = is_user-phone.
  ls_address-department = is_user-department.
  ls_address-function   = is_user-function.

  " 6. User Parameters (SU01 Parameters)
  PERFORM collect_screen_parameters CHANGING lt_param1.

  CALL FUNCTION 'BAPI_USER_CREATE1'
    EXPORTING
      username   = lv_username
      logondata  = ls_logondata
      password   = ls_password
      defaults   = ls_defaults
      company    = ls_company
      address    = ls_address
    TABLES
      parameter1 = lt_param1
      return     = et_return.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form update_single_user
*&---------------------------------------------------------------------*
FORM update_single_user USING    is_user   TYPE ty_user_csv
                        CHANGING et_return TYPE bapiret2_t.
  DATA: lv_username   TYPE bapibname-bapibname,
        ls_defaults   TYPE bapidefaul,
        ls_defaultsx  TYPE bapidefax,
        ls_address    TYPE bapiaddr3,
        ls_addressx   TYPE bapiaddr3x,
        ls_company    TYPE bapiuscomp,
        ls_companyx   TYPE bapiuscomx,
        ls_password   TYPE bapipwd,
        ls_pwd_x      TYPE bapipwdx,
        ls_paramx     TYPE bapiparamx,
        lt_scr_params TYPE ty_t_bapiparam1,
        lt_cur_params TYPE ty_t_bapiparam1,
        lt_get_ret    TYPE STANDARD TABLE OF bapiret2.

  CLEAR: et_return, ls_defaults, ls_defaultsx, ls_address, ls_addressx,
         ls_company, ls_companyx, ls_password, ls_pwd_x, ls_paramx,
         lt_scr_params, lt_cur_params, lt_get_ret.

  lv_username = is_user-username.

  " Defaults: Output Device, Print Now, IANA Time Zone
  ls_defaults-spdb  = COND #( WHEN p_prnow = abap_true THEN 'G' ELSE 'H' ).
  ls_defaultsx-spdb = 'X'.

  IF p_spld IS NOT INITIAL.
    ls_defaults-spld  = p_spld.
    ls_defaultsx-spld = 'X'.
  ENDIF.

  IF p_tziana IS NOT INITIAL.
    ls_defaults-tzone_iana  = p_tziana.
    ls_defaultsx-tzone_iana = 'X'.
  ENDIF.

  " Assign Company if p_comp is specified
  IF p_comp IS NOT INITIAL.
    ls_company-company  = p_comp.
    ls_companyx-company = 'X'.
  ENDIF.

  " Update Address - Full Name mapped into Last Name
  IF strlen( is_user-fullname ) > 40.
    ls_address-lastname = is_user-fullname(40).
  ELSE.
    ls_address-lastname = is_user-fullname.
  ENDIF.
  ls_addressx-lastname = 'X'.

  IF is_user-email_invalid = abap_false
     AND ( p_sync = abap_true OR is_user-email IS NOT INITIAL ).
    ls_address-e_mail  = is_user-email.
    ls_addressx-e_mail = 'X'.
  ENDIF.

  IF p_sync = abap_true OR is_user-phone IS NOT INITIAL.
    ls_address-tel1_numbr  = is_user-phone.
    ls_addressx-tel1_numbr = 'X'.
  ENDIF.

  IF p_sync = abap_true OR is_user-department IS NOT INITIAL.
    ls_address-department  = is_user-department.
    ls_addressx-department = 'X'.
  ENDIF.

  IF p_sync = abap_true OR is_user-function IS NOT INITIAL.
    ls_address-function  = is_user-function.
    ls_addressx-function = 'X'.
  ENDIF.

  " Reset password ONLY if p_pwd is set and password is not '(Unchanged)'
  IF p_pwd = abap_true AND is_user-password IS NOT INITIAL AND is_user-password <> '(Unchanged)'.
    ls_password-bapipwd = is_user-password.
    ls_pwd_x-bapipwd    = 'X'.
  ENDIF.

  " Merge configured parameters into existing user parameters (create or overwrite)
  IF p_uppar = abap_true.
    PERFORM collect_screen_parameters CHANGING lt_scr_params.
    IF lt_scr_params IS NOT INITIAL.
      CALL FUNCTION 'BAPI_USER_GET_DETAIL'
        EXPORTING
          username   = lv_username
        TABLES
          parameter1 = lt_cur_params
          return     = lt_get_ret.

      LOOP AT lt_get_ret INTO DATA(ls_get_ret) WHERE type CA 'EA'.
        et_return = lt_get_ret.
        RETURN.
      ENDLOOP.

      LOOP AT lt_scr_params INTO DATA(ls_scr_par).
        READ TABLE lt_cur_params ASSIGNING FIELD-SYMBOL(<ls_cur_par>)
          WITH KEY parid = ls_scr_par-parid.
        IF sy-subrc = 0.
          <ls_cur_par>-parva = ls_scr_par-parva.
        ELSE.
          APPEND ls_scr_par TO lt_cur_params.
        ENDIF.
      ENDLOOP.

      ls_paramx-parid = 'X'.
      ls_paramx-parva = 'X'.
    ENDIF.
  ENDIF.

  CALL FUNCTION 'BAPI_USER_CHANGE'
    EXPORTING
      username   = lv_username
      defaults   = ls_defaults
      defaultsx  = ls_defaultsx
      company    = ls_company
      companyx   = ls_companyx
      address    = ls_address
      addressx   = ls_addressx
      password   = ls_password
      passwordx  = ls_pwd_x
      parameterx = ls_paramx
    TABLES
      parameter1 = lt_cur_params
      return     = et_return.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form refresh_param_descriptions
*&---------------------------------------------------------------------*
FORM refresh_param_descriptions USING iv_only_blank TYPE abap_bool.
  TYPES: BEGIN OF ty_pid_key,
           paramid TYPE tpara-paramid,
         END OF ty_pid_key,
         BEGIN OF ty_pid_txt,
           paramid TYPE tparat-paramid,
           partext TYPE tparat-partext,
         END OF ty_pid_txt.

  DATA: lt_keys     TYPE STANDARD TABLE OF ty_pid_key,
        lt_cur_pids TYPE STANDARD TABLE OF bapiparam1-parid,
        lt_refresh  TYPE STANDARD TABLE OF abap_bool,
        lt_txt_l    TYPE STANDARD TABLE OF ty_pid_txt,
        lt_txt_e    TYPE STANDARD TABLE OF ty_pid_txt,
        lt_txt_b    TYPE STANDARD TABLE OF ty_pid_txt,
        lv_idx_c    TYPE n LENGTH 2,
        lv_f_pid    TYPE string,
        lv_f_pds    TYPE string,
        lv_pid      TYPE bapiparam1-parid,
        lv_prev_pid TYPE bapiparam1-parid,
        lv_need_ref TYPE abap_bool.

  FIELD-SYMBOLS: <lv_pid> TYPE bapiparam1-parid,
                 <lv_pds> TYPE csequence.

  DO 10 TIMES.
    lv_idx_c = sy-index.
    lv_f_pid = |P_PID{ lv_idx_c }|.
    lv_f_pds = |C_PDS{ lv_idx_c }|.
    ASSIGN (lv_f_pid) TO <lv_pid>.
    ASSIGN (lv_f_pds) TO <lv_pds>.

    CLEAR: lv_pid, lv_prev_pid, lv_need_ref.
    READ TABLE gt_prev_pids INTO lv_prev_pid INDEX sy-index.

    IF <lv_pid> IS ASSIGNED AND <lv_pds> IS ASSIGNED.
      IF <lv_pid> IS INITIAL.
        CLEAR <lv_pds>.
      ELSE.
        lv_pid = to_upper( <lv_pid> ).
        IF <lv_pds> IS INITIAL OR ( iv_only_blank = abap_false AND lv_pid <> lv_prev_pid ).
          lv_need_ref = abap_true.
          APPEND VALUE ty_pid_key( paramid = lv_pid ) TO lt_keys.
        ENDIF.
      ENDIF.
    ENDIF.

    APPEND lv_pid TO lt_cur_pids.
    APPEND lv_need_ref TO lt_refresh.
    UNASSIGN: <lv_pid>, <lv_pds>.
  ENDDO.

  gt_prev_pids = lt_cur_pids.

  IF lt_keys IS INITIAL.
    RETURN.
  ENDIF.

  SORT lt_keys BY paramid.
  DELETE ADJACENT DUPLICATES FROM lt_keys COMPARING paramid.

  SELECT paramid, partext FROM tparat
    FOR ALL ENTRIES IN @lt_keys
    WHERE paramid = @lt_keys-paramid
      AND sprache = @sy-langu
    INTO TABLE @lt_txt_l.

  IF sy-langu <> 'E'.
    SELECT paramid, partext FROM tparat
      FOR ALL ENTRIES IN @lt_keys
      WHERE paramid = @lt_keys-paramid
        AND sprache = 'E'
      INTO TABLE @lt_txt_e.
  ENDIF.

  SELECT paramid, partext FROM tpara
    FOR ALL ENTRIES IN @lt_keys
    WHERE paramid = @lt_keys-paramid
    INTO TABLE @lt_txt_b.

  SORT lt_txt_l BY paramid.
  SORT lt_txt_e BY paramid.
  SORT lt_txt_b BY paramid.

  DO 10 TIMES.
    lv_idx_c = sy-index.
    CLEAR lv_need_ref.
    READ TABLE lt_refresh INTO lv_need_ref INDEX sy-index.
    IF lv_need_ref = abap_false.
      CONTINUE.
    ENDIF.

    lv_f_pid = |P_PID{ lv_idx_c }|.
    lv_f_pds = |C_PDS{ lv_idx_c }|.
    ASSIGN (lv_f_pid) TO <lv_pid>.
    ASSIGN (lv_f_pds) TO <lv_pds>.
    IF <lv_pid> IS ASSIGNED AND <lv_pds> IS ASSIGNED AND <lv_pid> IS NOT INITIAL.
      lv_pid = to_upper( <lv_pid> ).
      READ TABLE lt_txt_l INTO DATA(ls_txt) WITH KEY paramid = lv_pid BINARY SEARCH.
      IF sy-subrc = 0 AND ls_txt-partext IS NOT INITIAL.
        <lv_pds> = ls_txt-partext.
      ELSE.
        READ TABLE lt_txt_e INTO ls_txt WITH KEY paramid = lv_pid BINARY SEARCH.
        IF sy-subrc = 0 AND ls_txt-partext IS NOT INITIAL.
          <lv_pds> = ls_txt-partext.
        ELSE.
          READ TABLE lt_txt_b INTO ls_txt WITH KEY paramid = lv_pid BINARY SEARCH.
          IF sy-subrc = 0.
            IF ls_txt-partext IS NOT INITIAL.
              <lv_pds> = ls_txt-partext.
            ELSE.
              <lv_pds> = '(No description)'.
            ENDIF.
          ELSE.
            <lv_pds> = '(Unknown Parameter ID)'.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.
    UNASSIGN: <lv_pid>, <lv_pds>.
  ENDDO.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form load_param_file_to_screen
*&---------------------------------------------------------------------*
FORM load_param_file_to_screen USING iv_file          TYPE localfile
                                     iv_update_dynpro TYPE abap_bool.
  TYPES: BEGIN OF ty_par_row,
           parid TYPE bapiparam1-parid,
           parva TYPE bapiparam1-parva,
           partx TYPE c LENGTH 33,
         END OF ty_par_row.

  DATA: lt_lines   TYPE STANDARD TABLE OF string,
        lt_tokens  TYPE string_table,
        lt_rows    TYPE STANDARD TABLE OF ty_par_row,
        ls_row     TYPE ty_par_row,
        lv_line    TYPE string,
        lv_lidx    TYPE i,
        lv_c1      TYPE string,
        lv_c2      TYPE string,
        lv_c3      TYPE string,
        lv_idx_c   TYPE n LENGTH 2,
        lv_f_pid   TYPE string,
        lv_f_pva   TYPE string,
        lv_f_pds   TYPE string,
        lt_dynp    TYPE STANDARD TABLE OF dynpread,
        lv_cur_pid TYPE bapiparam1-parid.

  FIELD-SYMBOLS: <lv_pid> TYPE bapiparam1-parid,
                 <lv_pva> TYPE bapiparam1-parva,
                 <lv_pds> TYPE csequence.

  IF iv_file IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM read_local_csv_lines USING iv_file CHANGING lt_lines.

  LOOP AT lt_lines INTO lv_line.
    lv_lidx = lv_lidx + 1.
    IF lv_line IS INITIAL.
      CONTINUE.
    ENDIF.

    PERFORM parse_csv_line USING lv_line CHANGING lt_tokens.
    IF lt_tokens IS INITIAL.
      CONTINUE.
    ENDIF.

    CLEAR: lv_c1, lv_c2, lv_c3.
    READ TABLE lt_tokens INTO lv_c1 INDEX 1.
    READ TABLE lt_tokens INTO lv_c2 INDEX 2.
    READ TABLE lt_tokens INTO lv_c3 INDEX 3.

    DATA(lv_c1_up) = to_upper( condense( lv_c1 ) ).
    DATA(lv_c2_up) = to_upper( condense( lv_c2 ) ).

    IF lv_lidx = 1.
      DATA(lv_hdr_up) = to_upper( lv_line ).
      IF lv_hdr_up CS 'USERNAME' OR lv_hdr_up CS 'FULL NAME' OR lv_hdr_up CS 'ROLE'
         OR lv_hdr_up CS 'TCODE' OR lv_hdr_up CS 'ORG_LEVEL' OR lv_hdr_up CS 'OBJECT-FIELD'
         OR lv_hdr_up CS 'VALUE-LOW'.
        MESSAGE 'Invalid CSV header for Parameter CSV. Expected: Parameter ID, Parameter Value, Description.' TYPE 'E'.
      ENDIF.
      IF lv_c1_up = 'PARAMETER ID' OR lv_c1_up = 'PARAMATER ID' OR lv_c1_up = 'PARID'
         OR ( lv_c1_up CS 'PARAM' AND ( lv_c2_up CS 'VAL' OR lv_c2_up CS 'PARVA' ) ).
        CONTINUE.
      ENDIF.
    ENDIF.

    IF lv_c1_up = 'PARAMETER ID' OR lv_c1_up = 'PARAMATER ID' OR lv_c1_up = 'PARID'.
      CONTINUE.
    ENDIF.

    IF lv_c1_up IS NOT INITIAL.
      CLEAR ls_row.
      ls_row-parid = lv_c1_up.
      CONDENSE ls_row-parid NO-GAPS.
      ls_row-parva = lv_c2.
      ls_row-partx = lv_c3.
      READ TABLE lt_rows ASSIGNING FIELD-SYMBOL(<ls_existing>) WITH KEY parid = ls_row-parid.
      IF sy-subrc = 0.
        <ls_existing>-parva = ls_row-parva.
        <ls_existing>-partx = ls_row-partx.
      ELSE.
        APPEND ls_row TO lt_rows.
      ENDIF.
    ENDIF.
  ENDLOOP.

  IF lt_rows IS INITIAL.
    MESSAGE 'No parameter rows found in the selected Parameter CSV file.' TYPE 'E'.
  ENDIF.

  IF lines( lt_rows ) > 10.
    MESSAGE |Loaded first 10 of { lines( lt_rows ) } parameters onto screen.| TYPE 'S' DISPLAY LIKE 'W'.
  ENDIF.

  CLEAR gt_prev_pids.
  DO 10 TIMES.
    lv_idx_c = sy-index.
    lv_f_pid = |P_PID{ lv_idx_c }|.
    lv_f_pva = |P_PVA{ lv_idx_c }|.
    lv_f_pds = |C_PDS{ lv_idx_c }|.
    ASSIGN (lv_f_pid) TO <lv_pid>.
    ASSIGN (lv_f_pva) TO <lv_pva>.
    ASSIGN (lv_f_pds) TO <lv_pds>.
    CLEAR ls_row.
    READ TABLE lt_rows INTO ls_row INDEX sy-index.
    IF <lv_pid> IS ASSIGNED.
      <lv_pid> = ls_row-parid.
    ENDIF.
    IF <lv_pva> IS ASSIGNED.
      <lv_pva> = ls_row-parva.
    ENDIF.
    IF <lv_pds> IS ASSIGNED.
      <lv_pds> = ls_row-partx.
    ENDIF.
    lv_cur_pid = ls_row-parid.
    APPEND lv_cur_pid TO gt_prev_pids.
    UNASSIGN: <lv_pid>, <lv_pva>, <lv_pds>.
  ENDDO.

  PERFORM refresh_param_descriptions USING abap_true.
  gv_loaded_pfile = iv_file.

  IF iv_update_dynpro = abap_true AND sy-batch IS INITIAL.
    CLEAR lt_dynp.
    IF p_file IS NOT INITIAL.
      APPEND VALUE dynpread( fieldname = 'P_FILE' fieldvalue = p_file ) TO lt_dynp.
    ENDIF.
    APPEND VALUE dynpread( fieldname = 'P_PFILE' fieldvalue = iv_file ) TO lt_dynp.
    DO 10 TIMES.
      lv_idx_c = sy-index.
      lv_f_pid = |P_PID{ lv_idx_c }|.
      lv_f_pva = |P_PVA{ lv_idx_c }|.
      lv_f_pds = |C_PDS{ lv_idx_c }|.
      ASSIGN (lv_f_pid) TO <lv_pid>.
      ASSIGN (lv_f_pva) TO <lv_pva>.
      ASSIGN (lv_f_pds) TO <lv_pds>.
      IF <lv_pid> IS ASSIGNED.
        APPEND VALUE dynpread( fieldname = lv_f_pid fieldvalue = <lv_pid> ) TO lt_dynp.
      ENDIF.
      IF <lv_pva> IS ASSIGNED.
        APPEND VALUE dynpread( fieldname = lv_f_pva fieldvalue = <lv_pva> ) TO lt_dynp.
      ENDIF.
      IF <lv_pds> IS ASSIGNED.
        APPEND VALUE dynpread( fieldname = lv_f_pds fieldvalue = <lv_pds> ) TO lt_dynp.
      ENDIF.
      UNASSIGN: <lv_pid>, <lv_pva>, <lv_pds>.
    ENDDO.

    CALL FUNCTION 'DYNP_VALUES_UPDATE'
      EXPORTING
        dyname               = sy-repid
        dynumb               = sy-dynnr
      TABLES
        dynpfields           = lt_dynp
      EXCEPTIONS
        invalid_abapworkarea = 1
        invalid_dynprofield  = 2
        invalid_dynproname   = 3
        invalid_dynpronummer = 4
        invalid_request      = 5
        no_fielddescription  = 6
        undefind_error       = 7
        OTHERS               = 8.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form validate_screen_params
*&---------------------------------------------------------------------*
FORM validate_screen_params.
  TYPES: BEGIN OF ty_pid_key,
           paramid TYPE tpara-paramid,
         END OF ty_pid_key.

  DATA: lt_check TYPE STANDARD TABLE OF ty_pid_key,
        lt_found TYPE STANDARD TABLE OF ty_pid_key,
        lv_idx_c TYPE n LENGTH 2,
        lv_f_pid TYPE string,
        lv_pid   TYPE bapiparam1-parid.

  FIELD-SYMBOLS: <lv_pid> TYPE bapiparam1-parid.

  IF p_uppar = abap_false.
    RETURN.
  ENDIF.

  DO 10 TIMES.
    lv_idx_c = sy-index.
    lv_f_pid = |P_PID{ lv_idx_c }|.
    ASSIGN (lv_f_pid) TO <lv_pid>.
    IF <lv_pid> IS ASSIGNED AND <lv_pid> IS NOT INITIAL.
      lv_pid = to_upper( condense( <lv_pid> ) ).
      <lv_pid> = lv_pid.
      APPEND VALUE ty_pid_key( paramid = lv_pid ) TO lt_check.
    ENDIF.
    UNASSIGN <lv_pid>.
  ENDDO.

  IF lt_check IS INITIAL.
    RETURN.
  ENDIF.

  SORT lt_check BY paramid.
  DELETE ADJACENT DUPLICATES FROM lt_check COMPARING paramid.

  SELECT paramid FROM tpara
    FOR ALL ENTRIES IN @lt_check
    WHERE paramid = @lt_check-paramid
    INTO TABLE @lt_found.

  SORT lt_found BY paramid.

  LOOP AT lt_check INTO DATA(ls_chk).
    READ TABLE lt_found WITH KEY paramid = ls_chk-paramid
      TRANSPORTING NO FIELDS BINARY SEARCH.
    IF sy-subrc <> 0.
      MESSAGE |Invalid SAP Parameter ID '{ ls_chk-paramid }' (not found in TPARA).| TYPE 'E'.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form collect_screen_parameters
*&---------------------------------------------------------------------*
FORM collect_screen_parameters CHANGING et_params TYPE ty_t_bapiparam1.
  DATA: lv_idx_c TYPE n LENGTH 2,
        lv_f_pid TYPE string,
        lv_f_pva TYPE string,
        lv_pid   TYPE bapiparam1-parid.

  FIELD-SYMBOLS: <lv_pid> TYPE bapiparam1-parid,
                 <lv_pva> TYPE bapiparam1-parva.

  CLEAR et_params.

  IF p_uppar = abap_false.
    RETURN.
  ENDIF.

  DO 10 TIMES.
    lv_idx_c = sy-index.
    lv_f_pid = |P_PID{ lv_idx_c }|.
    lv_f_pva = |P_PVA{ lv_idx_c }|.
    ASSIGN (lv_f_pid) TO <lv_pid>.
    ASSIGN (lv_f_pva) TO <lv_pva>.
    IF <lv_pid> IS ASSIGNED AND <lv_pid> IS NOT INITIAL.
      lv_pid = to_upper( <lv_pid> ).
      READ TABLE et_params ASSIGNING FIELD-SYMBOL(<ls_par>)
        WITH KEY parid = lv_pid.
      IF sy-subrc = 0.
        IF <lv_pva> IS ASSIGNED.
          <ls_par>-parva = <lv_pva>.
        ENDIF.
      ELSE.
        APPEND INITIAL LINE TO et_params ASSIGNING <ls_par>.
        <ls_par>-parid = lv_pid.
        IF <lv_pva> IS ASSIGNED.
          <ls_par>-parva = <lv_pva>.
        ENDIF.
      ENDIF.
    ENDIF.
    UNASSIGN: <lv_pid>, <lv_pva>.
  ENDDO.
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
      TRY.
          CALL TRANSACTION 'SU01' WITH AUTHORITY-CHECK AND SKIP FIRST SCREEN.
        CATCH cx_sy_authorization_error.
          MESSAGE 'No authorization to launch transaction SU01.' TYPE 'S' DISPLAY LIKE 'E'.
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

*&---------------------------------------------------------------------*
*& Form generate_initial_password
*&---------------------------------------------------------------------*
FORM generate_initial_password CHANGING cv_password TYPE bapipwd-bapipwd.
  DATA: lv_gen_pwd TYPE xubcode.

  CLEAR cv_password.

  " Attempt 1: Standard SAP password generation function
  CALL FUNCTION 'SUSR_GENERATE_PASSWORD'
    IMPORTING
      password        = lv_gen_pwd
    EXCEPTIONS
      generator_error = 1
      OTHERS          = 2.

  IF sy-subrc = 0 AND lv_gen_pwd IS NOT INITIAL AND strlen( lv_gen_pwd ) >= 8.
    cv_password = lv_gen_pwd.
    RETURN.
  ENDIF.

  " Attempt 2: CSPRNG-backed SAP-compliant fallback generator (12 characters)
  DATA: lv_uppers   TYPE string VALUE 'ABCDEFGHJKLMNPQRSTUVWXYZ',
        lv_lowers   TYPE string VALUE 'abcdefghijkmnpqrstuvwxyz',
        lv_digits   TYPE string VALUE '23456789',
        lv_spec     TYPE string VALUE '!@#$%*-_=+',
        lv_all      TYPE string,
        lv_res      TYPE string,
        lv_char     TYPE c LENGTH 1,
        lv_sec_x    TYPE xstring,
        lv_sec_pos  TYPE i,
        lo_rnd      TYPE REF TO cl_abap_random_int,
        lv_shuffled TYPE string,
        lv_rem_len  TYPE i,
        lv_pick_pos TYPE i,
        lv_rval     TYPE i.

  lv_all = lv_uppers && lv_lowers && lv_digits && lv_spec.

  CALL FUNCTION 'GENERATE_SEC_RANDOM'
    EXPORTING
      length         = 32
    IMPORTING
      random         = lv_sec_x
    EXCEPTIONS
      invalid_length = 1
      no_memory      = 2
      internal_error = 3
      OTHERS         = 4.
  IF sy-subrc <> 0.
    CLEAR lv_sec_x.
  ENDIF.

  IF xstrlen( lv_sec_x ) < 24.
    TRY.
        lo_rnd = cl_abap_random_int=>create(
                   seed = cl_abap_random=>seed( )
                   min  = 0
                   max  = 999999 ).
      CATCH cx_root.
    ENDTRY.
  ENDIF.

  " Ensure at least 1 of each required character category
  PERFORM pick_random_char USING lv_uppers lv_sec_x lo_rnd CHANGING lv_sec_pos lv_char.
  lv_res = lv_res && lv_char.

  PERFORM pick_random_char USING lv_lowers lv_sec_x lo_rnd CHANGING lv_sec_pos lv_char.
  lv_res = lv_res && lv_char.

  PERFORM pick_random_char USING lv_digits lv_sec_x lo_rnd CHANGING lv_sec_pos lv_char.
  lv_res = lv_res && lv_char.

  PERFORM pick_random_char USING lv_spec lv_sec_x lo_rnd CHANGING lv_sec_pos lv_char.
  lv_res = lv_res && lv_char.

  " Fill remaining 8 characters
  DO 8 TIMES.
    PERFORM pick_random_char USING lv_all lv_sec_x lo_rnd CHANGING lv_sec_pos lv_char.
    lv_res = lv_res && lv_char.
  ENDDO.

  " Shuffle characters for randomness
  DO 12 TIMES.
    lv_rem_len = strlen( lv_res ).
    IF lv_rem_len <= 1.
      lv_shuffled = lv_shuffled && lv_res.
      EXIT.
    ENDIF.
    PERFORM next_random_int USING lv_sec_x lo_rnd lv_rem_len CHANGING lv_sec_pos lv_rval.
    lv_pick_pos = lv_rval.
    lv_char = substring( val = lv_res off = lv_pick_pos len = 1 ).
    lv_shuffled = lv_shuffled && lv_char.
    IF lv_pick_pos = 0.
      lv_res = substring( val = lv_res off = 1 ).
    ELSEIF lv_pick_pos = lv_rem_len - 1.
      lv_res = substring( val = lv_res off = 0 len = lv_pick_pos ).
    ELSE.
      lv_res = substring( val = lv_res off = 0 len = lv_pick_pos ) &&
               substring( val = lv_res off = lv_pick_pos + 1 ).
    ENDIF.
  ENDDO.

  cv_password = lv_shuffled.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form next_random_int
*&---------------------------------------------------------------------*
FORM next_random_int USING    iv_sec_x  TYPE xstring
                              io_rnd    TYPE REF TO cl_abap_random_int
                              iv_mod    TYPE i
                     CHANGING cv_pos    TYPE i
                              ev_val    TYPE i.
  DATA: lv_byte TYPE x LENGTH 1,
        lv_int  TYPE i.

  CLEAR ev_val.
  IF iv_mod <= 1.
    RETURN.
  ENDIF.

  IF xstrlen( iv_sec_x ) > cv_pos.
    lv_byte = iv_sec_x+cv_pos(1).
    cv_pos  = cv_pos + 1.
    lv_int  = lv_byte.
    ev_val  = lv_int MOD iv_mod.
  ELSEIF io_rnd IS BOUND.
    ev_val = io_rnd->get_next( ) MOD iv_mod.
  ELSE.
    MESSAGE 'Cryptographic random password generator unavailable.' TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form pick_random_char
*&---------------------------------------------------------------------*
FORM pick_random_char USING    iv_pool  TYPE string
                               iv_sec_x TYPE xstring
                               io_rnd   TYPE REF TO cl_abap_random_int
                      CHANGING cv_pos   TYPE i
                               cv_char  TYPE c.
  DATA: lv_pool_len TYPE i,
        lv_off      TYPE i.

  lv_pool_len = strlen( iv_pool ).
  IF lv_pool_len = 0.
    cv_char = 'A'.
    RETURN.
  ENDIF.

  PERFORM next_random_int USING iv_sec_x io_rnd lv_pool_len CHANGING cv_pos lv_off.
  cv_char = substring( val = iv_pool off = lv_off len = 1 ).
ENDFORM.
