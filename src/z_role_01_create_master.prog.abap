*&---------------------------------------------------------------------*
*& Report Z_ROLE_01_CREATE_MASTER
*&---------------------------------------------------------------------*
*& Purpose: Batch Role Creation & Menu Structuring from CSV
*& Description:
*&   Uploads role definitions containing Role Name, Role Description,
*&   and Transaction Codes (TCodes). Groups multiple TCodes into single
*&   roles, creates a dedicated Menu Folder named after the Role
*&   Description, nests all assigned TCodes under this folder, and
*&   automatically generates the authorization profiles.
*&
*& File format (CSV .csv):
*&   Col 1: Role Name        (e.g., Z_FI_GL_ACCOUNTING)
*&   Col 2: Role Description (e.g., General Ledger Accounting Role)
*&   Col 3: TCode            (e.g., FB01, FS00, or N/A)
*&
*& Author: Antigravity AI (SAP Basis Engineering)
*& Package: $TMP (Local Object) or Custom Package
*&---------------------------------------------------------------------*
REPORT z_role_01_create_master.

*----------------------------------------------------------------------*
* 1. TYPES & DATA DEFINITIONS
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_raw_row,
         col1 TYPE string,
         col2 TYPE string,
         col3 TYPE string,
       END OF ty_raw_row.

TYPES: BEGIN OF ty_role_entry,
         agr_name  TYPE agr_name,
         role_desc TYPE agr_title,
         tcode_cnt TYPE i,
       END OF ty_role_entry.

TYPES: BEGIN OF ty_tcode_entry,
         agr_name TYPE agr_name,
         tcode    TYPE tcode,
         ttext    TYPE ttext_stct,
         is_valid TYPE abap_bool,
       END OF ty_tcode_entry.

TYPES: BEGIN OF ty_alv_result,
         status         TYPE char12,         " Status Icon & Code: @08@ [OK], @09@ [WARN], @0A@ [ERR]
         action         TYPE char12,         " Action: Created / Updated / Up-To-Date / Simulated / Skipped / Error
         agr_name       TYPE agr_name,       " Role ID (Hotspot to PFCG)
         role_desc      TYPE agr_title,      " Role Description
         folder_name    TYPE agr_title,      " Menu Folder Name (= Role Description)
         tcode_cnt      TYPE i,              " Count of TCodes in File
         tcodes         TYPE string,         " Comma-separated list of TCodes in File
         tcodes_add     TYPE string,         " TCodes Added (Synchronized)
         tcodes_del     TYPE string,         " TCodes Removed (Synchronized)
         invalid_tcodes TYPE string,         " Invalid TCodes (Not found in TSTC)
         derived_roles  TYPE string,         " Child Derived Roles Adjusted
         profile        TYPE xuprofile,      " Generated Profile Name
         message        TYPE string,         " Execution Status / BAPI Message
       END OF ty_alv_result.

CONSTANTS: gc_status_ok   TYPE char12 VALUE '@08@ [OK]',
           gc_status_warn TYPE char12 VALUE '@09@ [WARN]',
           gc_status_err  TYPE char12 VALUE '@0A@ [ERR]'.

DATA: gt_raw_rows        TYPE STANDARD TABLE OF ty_raw_row,
      gt_roles           TYPE STANDARD TABLE OF ty_role_entry,
      gt_tcodes          TYPE STANDARD TABLE OF ty_tcode_entry,
      gt_results         TYPE STANDARD TABLE OF ty_alv_result,
      gt_usorg_map       TYPE SORTED TABLE OF usorg
                           WITH NON-UNIQUE KEY field
                           WITH NON-UNIQUE SORTED KEY by_varbl COMPONENTS varbl,
      gt_oversized_roles TYPE STANDARD TABLE OF string.

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
              p_genprf TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_chktc  TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_adjder TYPE abap_bool AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b_opt.

*----------------------------------------------------------------------*
* 3. INITIALIZATION & SCREEN EVENTS
*----------------------------------------------------------------------*
INITIALIZATION.
  b_tit1 = 'Input CSV File (.csv)'(b01).
  b_tit2 = 'Execution & Authorization Options'(b02).

  %_p_file_%_app_%-text   = 'File Path'.
  %_p_test_%_app_%-text   = 'Simulation (Test Run)'.
  %_p_upd_%_app_%-text    = 'Update Existing Roles'.
  %_p_sync_%_app_%-text   = 'Two-Way Sync (Remove Surplus)'.
  %_p_genprf_%_app_%-text = 'Auto-Generate Auth Profiles'.
  %_p_chktc_%_app_%-text  = 'Validate TCodes in TSTC'.
  %_p_adjder_%_app_%-text = 'Adjust Child Derived Roles'.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  PERFORM f4_file_open CHANGING p_file.

AT SELECTION-SCREEN ON p_file.
  PERFORM validate_filename USING p_file.

*----------------------------------------------------------------------*
* 4. START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.
  PERFORM check_authority.
  CLEAR gt_usorg_map.
  SELECT * FROM usorg INTO TABLE @gt_usorg_map.
  PERFORM upload_and_parse_file.
  PERFORM process_role_generation.
  PERFORM display_alv_results.

*&---------------------------------------------------------------------*
*& Form f4_file_open
*&---------------------------------------------------------------------*
FORM f4_file_open CHANGING cv_file TYPE localfile.
  DATA: lt_file_table TYPE filetable,
        lv_rc         TYPE i.

  cl_gui_frontend_services=>file_open_dialog(
    EXPORTING
      window_title            = 'Select Master Role CSV File'
      file_filter             = 'Master Role CSV (*01_Master*.csv)|*01_Master*.csv|CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'
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
    MESSAGE |Invalid file '{ lv_fname }'. Expected CSV file (*_01_Master_converted.csv).| TYPE 'E'.
  ENDIF.

  IF NOT ( lv_up CS '01_MASTER' OR lv_up CS '_MASTER' )
     OR lv_up CS '02_DERIVE' OR lv_up CS '03A_ORG' OR lv_up CS '03B_AUTH'
     OR lv_up CS '03B_OBJECT' OR lv_up CS '03C_ACTIVITY' OR lv_up CS '04_COMPOSITE'
     OR lv_up CS '01_CREATE' OR lv_up CS '02_ASSIGN'.
    MESSAGE |Invalid file '{ lv_fname }' for Z_ROLE_01_CREATE_MASTER. Expected '*_01_Master_converted.csv'.| TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form check_authority
*&---------------------------------------------------------------------*
FORM check_authority.
  IF p_test = abap_true.
    AUTHORITY-CHECK OBJECT 'S_USER_AGR'
      ID 'ACT_GROUP' DUMMY
      ID 'ACTVT'     FIELD '03'.
    IF sy-subrc <> 0.
      MESSAGE 'Missing authorization to display roles (S_USER_AGR ACTVT 03).' TYPE 'E'.
    ENDIF.
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
      MESSAGE 'Missing authorization for role creation/change (S_USER_AGR ACTVT 01/02).' TYPE 'E'.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form upload_and_parse_file
*&---------------------------------------------------------------------*
FORM upload_and_parse_file.
  CLEAR: gt_raw_rows, gt_roles, gt_tcodes, gt_results.

  PERFORM read_csv_file USING p_file.

  IF gt_raw_rows IS INITIAL.
    MESSAGE 'No valid data found in the uploaded file.' TYPE 'S' DISPLAY LIKE 'E'.
    STOP.
  ENDIF.

  PERFORM aggregate_and_validate_data.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form read_csv_file
*&---------------------------------------------------------------------*
FORM read_csv_file USING iv_file TYPE localfile.
  DATA: lt_lines    TYPE TABLE OF string,
        lv_filepath TYPE string,
        ls_raw      TYPE ty_raw_row.

  lv_filepath = iv_file.

  cl_gui_frontend_services=>gui_upload(
    EXPORTING
      filename                = lv_filepath
      filetype                = 'ASC'
      codepage                = '4110'
    CHANGING
      data_tab                = lt_lines
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

  LOOP AT lt_lines INTO DATA(lv_line).
    DATA(lv_tabix) = sy-tabix.
    IF lv_tabix = 1 AND strlen( lv_line ) >= 1.
      IF lv_line(1) = cl_abap_char_utilities=>byte_order_mark_utf8.
        lv_line = substring( val = lv_line off = 1 ).
      ENDIF.
    ENDIF.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf(1) IN lv_line WITH ''.

    CLEAR ls_raw.
    PERFORM parse_csv_line USING lv_line
                           CHANGING ls_raw-col1 ls_raw-col2 ls_raw-col3.

    IF lv_tabix = 1.
      DATA(lv_c1_up) = to_upper( ls_raw-col1 ).
      DATA(lv_c2_up) = to_upper( ls_raw-col2 ).
      DATA(lv_c3_up) = to_upper( ls_raw-col3 ).
      IF lv_c2_up = 'DERIVED ROLE' OR lv_c2_up = 'ORG_LEVEL' OR lv_c2_up = 'OBJECT-FIELD'
         OR lv_c3_up = 'VALUE-LOW' OR lv_c1_up = 'COMPOSITE ROLE' OR lv_c1_up = 'COMPOSITE ROLE NAME'
         OR lv_c3_up = 'SINGLE ROLE' OR lv_c1_up = 'USERNAME'.
        MESSAGE 'Invalid CSV header for Z_ROLE_01_CREATE_MASTER. Expected: Role Name, Role Description, TCode.' TYPE 'E'.
      ENDIF.
      IF lv_c1_up = 'ROLE' OR lv_c1_up = 'ROLE NAME' OR lv_c1_up = 'ROLE_NAME' OR lv_c1_up = 'ROLE ID'.
        CONTINUE.
      ENDIF.
    ENDIF.

    IF ls_raw-col1 IS NOT INITIAL.
      IF ls_raw-col3 IS INITIAL.
        ls_raw-col3 = 'N/A'.
      ENDIF.
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
        lv_char   TYPE string,
        lv_next   TYPE string,
        lv_idx    TYPE i,
        lv_delim  TYPE c LENGTH 1.

  CLEAR: ev_col1, ev_col2, ev_col3.

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
    ev_col2 = lt_tokens[ 2 ]. " Keep exact spacing as in input file (no trim/condense)
  ENDIF.
  IF lines( lt_tokens ) >= 3.
    ev_col3 = lt_tokens[ 3 ].
    ev_col3 = to_upper( condense( ev_col3 ) ).
  ENDIF.
ENDFORM.


*&---------------------------------------------------------------------*
*& Form aggregate_and_validate_data
*&---------------------------------------------------------------------*
FORM aggregate_and_validate_data.
  DATA: ls_role     TYPE ty_role_entry,
        ls_tcode    TYPE ty_tcode_entry,
        lv_agr_raw  TYPE string,
        lv_agr_name TYPE agr_name,
        lv_role_dsc TYPE agr_title,
        lv_tcode    TYPE tcode.

  CLEAR gt_oversized_roles.

  LOOP AT gt_raw_rows INTO DATA(ls_raw).
    lv_agr_raw  = to_upper( condense( ls_raw-col1 ) ).
    lv_role_dsc = ls_raw-col2. " Keep exact spacing as in input file
    DATA(lv_raw_tc) = to_upper( condense( ls_raw-col3 ) ).

    IF lv_agr_raw IS INITIAL.
      CONTINUE.
    ENDIF.

    " Guard against silent >30-char truncation
    IF strlen( lv_agr_raw ) > 30.
      READ TABLE gt_oversized_roles WITH KEY table_line = lv_agr_raw TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND lv_agr_raw TO gt_oversized_roles.
      ENDIF.
      CONTINUE.
    ENDIF.

    lv_agr_name = lv_agr_raw.

    IF lv_role_dsc IS INITIAL.
      lv_role_dsc = lv_agr_name.
    ENDIF.

    " Maintain Role Header
    READ TABLE gt_roles ASSIGNING FIELD-SYMBOL(<ls_r>)
      WITH KEY agr_name = lv_agr_name.
    IF sy-subrc <> 0.
      CLEAR ls_role.
      ls_role-agr_name  = lv_agr_name.
      ls_role-role_desc = lv_role_dsc.
      ls_role-tcode_cnt = 0.
      APPEND ls_role TO gt_roles.
    ELSE.
      IF <ls_r>-role_desc IS INITIAL AND lv_role_dsc IS NOT INITIAL.
        <ls_r>-role_desc = lv_role_dsc.
      ENDIF.
    ENDIF.

    " Check if role explicitly has no TCodes (N/A)
    IF lv_raw_tc = 'N/A' OR lv_raw_tc = 'NA' OR lv_raw_tc = '-' OR lv_raw_tc = 'NONE' OR lv_raw_tc IS INITIAL.
      CONTINUE.
    ENDIF.

    lv_tcode = lv_raw_tc.

    " Maintain TCode Assignment (Prevent duplicates per role)
    READ TABLE gt_tcodes WITH KEY agr_name = lv_agr_name tcode = lv_tcode
      TRANSPORTING NO FIELDS.
    IF sy-subrc <> 0.
      CLEAR ls_tcode.
      ls_tcode-agr_name = lv_agr_name.
      ls_tcode-tcode    = lv_tcode.
      ls_tcode-is_valid = abap_true.
      APPEND ls_tcode TO gt_tcodes.

      " Increment count
      READ TABLE gt_roles ASSIGNING <ls_r> WITH KEY agr_name = lv_agr_name.
      IF sy-subrc = 0.
        <ls_r>-tcode_cnt = <ls_r>-tcode_cnt + 1.
      ENDIF.
    ENDIF.
  ENDLOOP.

  " Validate TCodes against TSTC and fetch descriptions
  IF gt_tcodes IS NOT INITIAL.
    SELECT tcode, ttext FROM tstct
      INTO TABLE @DATA(lt_tstct)
      FOR ALL ENTRIES IN @gt_tcodes
      WHERE sprsl = @sy-langu
        AND tcode = @gt_tcodes-tcode.

    IF p_chktc = abap_true.
      SELECT tcode FROM tstc
        INTO TABLE @DATA(lt_tstc)
        FOR ALL ENTRIES IN @gt_tcodes
        WHERE tcode = @gt_tcodes-tcode.
    ENDIF.

    LOOP AT gt_tcodes ASSIGNING FIELD-SYMBOL(<ls_tc>).
      " Read description
      READ TABLE lt_tstct INTO DATA(ls_txt) WITH KEY tcode = <ls_tc>-tcode.
      IF sy-subrc = 0.
        <ls_tc>-ttext = ls_txt-ttext.
      ELSE.
        <ls_tc>-ttext = <ls_tc>-tcode.
      ENDIF.

      " Validate existence in TSTC
      IF p_chktc = abap_true.
        READ TABLE lt_tstc WITH KEY tcode = <ls_tc>-tcode TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          <ls_tc>-is_valid = abap_false.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form process_role_generation
*&---------------------------------------------------------------------*
FORM process_role_generation.
  DATA: lt_nodes          TYPE TABLE OF smensapnew,
        lt_texts          TYPE TABLE OF smencust,
        lt_curr_nodes     TYPE TABLE OF agr_shier,
        lt_curr_texts     TYPE TABLE OF agr_shiert,
        lt_tcodes_to_add  TYPE TABLE OF ty_tcode_entry,
        lt_tcodes_to_del  TYPE TABLE OF tcode,
        lt_tcodes_to_keep TYPE TABLE OF tcode,
        lt_bapiret        TYPE TABLE OF bapiret2,
        ls_res            TYPE ty_alv_result,
        ls_stck           TYPE smen_stck,
        lv_obj_num        TYPE numc5,
        lv_exists         TYPE abap_bool,
        lv_dummy_agr      TYPE agr_name,
        lv_invalid_cnt    TYPE i,
        lv_valid_cnt      TYPE i,
        lv_invalid_list   TYPE string,
        lv_tcd_list       TYPE string,
        lv_str_add        TYPE string,
        lv_str_del        TYPE string,
        lv_str_keep       TYPE string,
        lv_target_folder  TYPE menu_num_8,
        lv_target_level   TYPE menu_num_8,
        lv_has_folder     TYPE abap_bool,
        lv_max_id         TYPE menu_num_8,
        lv_max_sort       TYPE menu_num_8,
        lv_err_flag       TYPE char01,
        lv_rc             TYPE sy-subrc,
        lv_parent_chk     TYPE agr_name,
        lv_coll_chk       TYPE char01,
        lv_adj_sum        TYPE string,
        lv_adj_roles      TYPE string.

  LOOP AT gt_oversized_roles INTO DATA(lv_bad_role).
    CLEAR ls_res.
    ls_res-status   = gc_status_err.
    ls_res-action   = 'ERROR'.
    ls_res-agr_name = lv_bad_role.
    ls_res-message  = |Role name exceeds SAP 30-character limit: '{ lv_bad_role }'.|.
    APPEND ls_res TO gt_results.
  ENDLOOP.

  LOOP AT gt_roles INTO DATA(ls_role).
    CLEAR: ls_res, lt_nodes, lt_texts, lt_bapiret, lv_tcd_list, lv_invalid_cnt,
           lv_invalid_list, lv_valid_cnt, lv_adj_sum, lv_adj_roles,
           lv_err_flag, lv_rc, lv_parent_chk, lv_coll_chk.

    ls_res-agr_name    = ls_role-agr_name.
    ls_res-role_desc   = ls_role-role_desc.
    ls_res-folder_name = ls_role-role_desc.

    " Categorize TCodes into valid vs invalid
    LOOP AT gt_tcodes INTO DATA(ls_tc) WHERE agr_name = ls_role-agr_name.
      IF lv_tcd_list IS INITIAL.
        lv_tcd_list = ls_tc-tcode.
      ELSE.
        CONCATENATE lv_tcd_list ',' ls_tc-tcode INTO lv_tcd_list SEPARATED BY space.
      ENDIF.
      IF ls_tc-is_valid = abap_false.
        lv_invalid_cnt = lv_invalid_cnt + 1.
        IF lv_invalid_list IS INITIAL.
          lv_invalid_list = ls_tc-tcode.
        ELSE.
          CONCATENATE lv_invalid_list ',' ls_tc-tcode INTO lv_invalid_list SEPARATED BY space.
        ENDIF.
      ELSE.
        lv_valid_cnt = lv_valid_cnt + 1.
      ENDIF.
    ENDLOOP.

    ls_res-invalid_tcodes = lv_invalid_list.

    " Set displayed TCodes & count
    IF lv_tcd_list IS INITIAL.
      ls_res-tcodes    = 'N/A'.
      ls_res-tcode_cnt = 0.
    ELSE.
      ls_res-tcodes    = lv_tcd_list.
      ls_res-tcode_cnt = lv_valid_cnt. " Number of VALID TCodes assigned to the role
    ENDIF.

    " Check if role already exists in SAP & guard against Composite / Derived roles
    CLEAR: lv_dummy_agr, lv_parent_chk, lv_coll_chk.
    SELECT SINGLE agr_name, parent_agr FROM agr_define
      INTO ( @lv_dummy_agr, @lv_parent_chk )
      WHERE agr_name = @ls_role-agr_name.
    IF sy-subrc = 0.
      lv_exists = abap_true.
      SELECT SINGLE flag_value FROM agr_flags INTO @lv_coll_chk
        WHERE agr_name = @ls_role-agr_name AND flag_type = 'COLL_AGR'.
      IF sy-subrc = 0 AND lv_coll_chk = 'X'.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'ERROR'.
        ls_res-message = |Role '{ ls_role-agr_name }' is a Composite Role; cannot maintain in Master Role tool.|.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.
      IF lv_parent_chk IS NOT INITIAL.
        ls_res-status  = gc_status_err.
        ls_res-action  = 'ERROR'.
        ls_res-message = |Role '{ ls_role-agr_name }' is a Derived Role (Parent: '{ lv_parent_chk }'); edit Master Role instead.|.
        APPEND ls_res TO gt_results.
        CONTINUE.
      ENDIF.
    ELSE.
      lv_exists = abap_false.
    ENDIF.

    " Per-role authority check
    DATA(lv_req_actvt) = COND activ_auth(
      WHEN p_test = abap_true THEN '03'
      WHEN lv_exists = abap_true THEN '02'
      ELSE '01' ).
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
    " Build Menu Hierarchy Nodes (ONLY with valid TCodes!)
    " Invalid TCodes are excluded to avoid aborting role/menu creation!
    " -----------------------------------------------------------------
    IF lv_valid_cnt > 0.
      DATA(ls_folder_node) = VALUE smensapnew(
        customized = 'X'
        object_id  = '00001'
        parent_id  = '00000'
        menu_level = 1
        reporttype = space
      ).
      APPEND ls_folder_node TO lt_nodes.

      DATA(ls_folder_txt) = VALUE smencust(
        spras     = sy-langu
        object_id = '00001'
        text      = ls_role-role_desc
      ).
      APPEND ls_folder_txt TO lt_texts.

      IF sy-langu NE 'E'.
        ls_folder_txt-spras = 'E'.
        APPEND ls_folder_txt TO lt_texts.
      ENDIF.

      lv_obj_num = 1.
      " Crucial: ONLY append VALID TCodes!
      LOOP AT gt_tcodes INTO ls_tc WHERE agr_name = ls_role-agr_name AND is_valid = abap_true.
        ADD 1 TO lv_obj_num.

        DATA(ls_tcode_node) = VALUE smensapnew(
          customized = 'X'
          object_id  = lv_obj_num
          parent_id  = '00001'     " Assigned strictly under the Folder!
          menu_level = 2
          reporttype = 'TR'
          report     = ls_tc-tcode
        ).
        APPEND ls_tcode_node TO lt_nodes.

        DATA(ls_tcode_txt) = VALUE smencust(
          spras     = sy-langu
          object_id = lv_obj_num
          text      = ls_tc-ttext
        ).
        APPEND ls_tcode_txt TO lt_texts.

        IF sy-langu NE 'E'.
          ls_tcode_txt-spras = 'E'.
          APPEND ls_tcode_txt TO lt_texts.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " -----------------------------------------------------------------
    " Branch 1: SIMULATION MODE (TEST RUN)
    " -----------------------------------------------------------------
    IF p_test = abap_true.
      ls_res-status = gc_status_ok.
      ls_res-action = 'SIMULATED'.

      IF lv_exists = abap_true.
        IF p_upd = abap_true.
          " Check existing TCodes in role from agr_tcodes
          SELECT tcode FROM agr_tcodes INTO TABLE @DATA(lt_sim_curr_tcds)
            WHERE agr_name = @ls_role-agr_name AND type = 'TR'.

          CLEAR: lt_tcodes_to_add, lt_tcodes_to_del, lt_tcodes_to_keep,
                 lv_str_add, lv_str_del, lv_str_keep.

          " 1. TCodes in CSV -> Add or Keep
          LOOP AT gt_tcodes INTO DATA(ls_sim_tc)
            WHERE agr_name = ls_role-agr_name AND is_valid = abap_true.
            READ TABLE lt_sim_curr_tcds WITH KEY tcode = ls_sim_tc-tcode TRANSPORTING NO FIELDS.
            IF sy-subrc = 0.
              APPEND ls_sim_tc-tcode TO lt_tcodes_to_keep.
              IF lv_str_keep IS INITIAL. lv_str_keep = ls_sim_tc-tcode.
              ELSE. CONCATENATE lv_str_keep ',' ls_sim_tc-tcode INTO lv_str_keep SEPARATED BY space. ENDIF.
            ELSE.
              APPEND ls_sim_tc TO lt_tcodes_to_add.
              IF lv_str_add IS INITIAL. lv_str_add = ls_sim_tc-tcode.
              ELSE. CONCATENATE lv_str_add ',' ls_sim_tc-tcode INTO lv_str_add SEPARATED BY space. ENDIF.
            ENDIF.
          ENDLOOP.

          " 2. TCodes in SAP not in CSV -> Del (Sync Mode) or Keep (Append Mode)
          IF p_sync = abap_true.
            LOOP AT lt_sim_curr_tcds INTO DATA(ls_sim_curr).
              READ TABLE gt_tcodes WITH KEY agr_name = ls_role-agr_name tcode = ls_sim_curr-tcode is_valid = abap_true TRANSPORTING NO FIELDS.
              IF sy-subrc <> 0.
                APPEND ls_sim_curr-tcode TO lt_tcodes_to_del.
                IF lv_str_del IS INITIAL. lv_str_del = ls_sim_curr-tcode.
                ELSE. CONCATENATE lv_str_del ',' ls_sim_curr-tcode INTO lv_str_del SEPARATED BY space. ENDIF.
              ENDIF.
            ENDLOOP.
          ELSE.
            LOOP AT lt_sim_curr_tcds INTO ls_sim_curr.
              READ TABLE gt_tcodes WITH KEY agr_name = ls_role-agr_name tcode = ls_sim_curr-tcode is_valid = abap_true TRANSPORTING NO FIELDS.
              IF sy-subrc <> 0.
                APPEND ls_sim_curr-tcode TO lt_tcodes_to_keep.
              ENDIF.
            ENDLOOP.
          ENDIF.

          ls_res-tcodes_add = lv_str_add.
          ls_res-tcodes_del = lv_str_del.

          IF lt_tcodes_to_add IS INITIAL AND lt_tcodes_to_del IS INITIAL.
            ls_res-status  = gc_status_ok.
            ls_res-action  = 'UP-TO-DATE'.
            ls_res-message = |Simulation: Role menu already up-to-date with { lines( lt_tcodes_to_keep ) } valid TCodes. No changes needed.|.
          ELSE.
            ls_res-status  = gc_status_ok.
            ls_res-action  = 'SIMULATED'.
            ls_res-message = |Simulation OK: Would add { lines( lt_tcodes_to_add ) } [{ lv_str_add }], remove { lines( lt_tcodes_to_del ) } [{ lv_str_del }], keep { lines( lt_tcodes_to_keep ) } TCode(s).|.
          ENDIF.

          IF p_adjder = abap_true.
            SELECT agr_name FROM agr_define INTO TABLE @DATA(lt_sim_der)
              WHERE parent_agr = @ls_role-agr_name
              ORDER BY agr_name.
            IF lt_sim_der IS NOT INITIAL.
              DATA(lv_sim_der_str) = ``.
              LOOP AT lt_sim_der INTO DATA(ls_sd).
                IF lv_sim_der_str IS INITIAL. lv_sim_der_str = ls_sd-agr_name.
                ELSE. CONCATENATE lv_sim_der_str ',' ls_sd-agr_name INTO lv_sim_der_str SEPARATED BY space. ENDIF.
              ENDLOOP.
              ls_res-derived_roles = lv_sim_der_str.
              ls_res-message = |{ ls_res-message } Would adjust { lines( lt_sim_der ) } child derived role(s) [{ lv_sim_der_str }] (preserving org levels).|.
            ENDIF.
          ENDIF.

          IF lv_invalid_cnt > 0.
            ls_res-status  = gc_status_warn.
            ls_res-message = |Warning: { lv_invalid_cnt } TCode(s) not in TSTC: [{ lv_invalid_list }] (excluded). { ls_res-message }|.
          ENDIF.

        ELSE.
          ls_res-status  = gc_status_warn.
          ls_res-action  = 'SKIPPED'.
          ls_res-message = |Role already exists. Skipping because Update Existing Roles is unchecked.|.
          IF lv_invalid_cnt > 0.
            ls_res-message = |Warning: { lv_invalid_cnt } TCode(s) not in TSTC: [{ lv_invalid_list }] (excluded). { ls_res-message }|.
          ENDIF.
        ENDIF.

      ELSE.
        " New role simulation
        IF lv_valid_cnt = 0.
          IF lv_invalid_cnt > 0.
            ls_res-status  = gc_status_warn.
            ls_res-action  = 'SIMULATED'.
            ls_res-message = |Warning: { lv_invalid_cnt } TCode(s) not in TSTC: [{ lv_invalid_list }] (excluded). Would create role without menu; Org levels defaulted to '-1'.|.
          ELSE.
            ls_res-status  = gc_status_warn.
            ls_res-action  = 'SIMULATED'.
            ls_res-message = |Warning: Role has no TCodes (N/A). Would create Master role without menu; Org levels defaulted to '-1'.|.
          ENDIF.
        ELSE.
          ls_res-action  = 'SIMULATED'.
          ls_res-message = |Simulation OK: Would create Master role with folder '{ ls_role-role_desc }' and { lv_valid_cnt } valid TCodes; Org levels defaulted to '-1'.|.
          IF lv_invalid_cnt > 0.
            ls_res-status  = gc_status_warn.
            ls_res-message = |Warning: { lv_invalid_cnt } TCode(s) not in TSTC: [{ lv_invalid_list }] (excluded). { ls_res-message }|.
          ENDIF.
        ENDIF.
      ENDIF.

      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " Branch 2: ACTUAL EXECUTION
    " -----------------------------------------------------------------
    IF lv_exists = abap_false.
      " 2A. CREATE NEW MASTER ROLE
      IF lv_valid_cnt = 0.
        " Role has no valid TCodes (e.g. N/A or all were invalid in TSTC)
        CALL FUNCTION 'PRGN_RFC_CREATE_AGR_MULTIPLE'
          EXPORTING
            activity_group      = ls_role-agr_name
            activity_group_text = ls_role-role_desc
            no_dialog           = 'X'
          TABLES
            return              = lt_bapiret
          EXCEPTIONS
            OTHERS              = 1.
        lv_rc = sy-subrc.

        IF lv_rc = 0.
          PERFORM set_org_levels_default USING ls_role-agr_name.

          PERFORM set_role_description USING ls_role-agr_name ls_role-role_desc.
          COMMIT WORK AND WAIT.

          ls_res-action = 'CREATED'.
          IF lv_invalid_cnt > 0.
            ls_res-status  = gc_status_warn.
            ls_res-message = |Warning: { lv_invalid_cnt } TCode(s) not in TSTC: [{ lv_invalid_list }] (excluded). Role created without menu; Org levels defaulted to '-1'.|.
          ELSE.
            ls_res-status  = gc_status_warn.
            ls_res-message = |Warning: Role created without TCodes (N/A); Org levels defaulted to '-1'.|.
          ENDIF.
        ELSE.
          ROLLBACK WORK.
          ls_res-status  = gc_status_err.
          ls_res-action  = 'ERROR'.
          PERFORM format_bapi_message USING lt_bapiret CHANGING ls_res-message.
          IF ls_res-message IS INITIAL.
            ls_res-message = |Failed to create role definition (sy-subrc = { lv_rc }).|.
          ENDIF.
        ENDIF.

      ELSE.
        " Role has at least 1 valid TCode -> Create role with folder and valid TCodes
        DATA: lv_only_tc TYPE char01 VALUE space.
        CLEAR lv_only_tc.
        IF p_genprf = abap_false.
          lv_only_tc = 'X'.
        ENDIF.

        CALL FUNCTION 'PRGN_RFC_CREATE_ACTIVITY_GROUP'
          EXPORTING
            activity_group                = ls_role-agr_name
            activity_group_text           = ls_role-role_desc
            org_levels_with_star          = space   " Master role: DO NOT fill orgs with '*'
            unmaintained_fields_with_star = 'X'
            only_tcode_assignment         = lv_only_tc
            no_dialog                     = 'X'
          TABLES
            hierarchy_nodes               = lt_nodes
            hierarchy_texts               = lt_texts
            return                        = lt_bapiret
          EXCEPTIONS
            activity_group_already_exists = 1
            activity_group_enqueued       = 2
            namespace_problem             = 3
            illegal_characters            = 4
            error_when_creating_actgroup  = 5
            profile_name_exists           = 6
            profile_not_in_namespace      = 7
            no_auth_data_selected         = 8
            illegal_tcodes                = 9
            not_authorized                = 10
            profgen_tables_not_updated    = 11
            error_when_generating_profile = 12
            OTHERS                        = 13.
        lv_rc = sy-subrc.

        IF lv_rc = 0 OR lv_rc = 11 OR lv_rc = 12.
          IF p_genprf = abap_true.
            PERFORM generate_master_role_profile USING ls_role-agr_name abap_false.
          ELSE.
            PERFORM set_org_levels_default USING ls_role-agr_name.
          ENDIF.

          PERFORM set_role_description USING ls_role-agr_name ls_role-role_desc.
          COMMIT WORK AND WAIT.

          ls_res-status  = gc_status_ok.
          ls_res-action  = 'CREATED'.
          ls_res-message = |Master role created. Folder '{ ls_role-role_desc }' populated with { lv_valid_cnt } valid TCodes; Org levels defaulted to '-1'.|.
          IF lv_invalid_cnt > 0.
            ls_res-status  = gc_status_warn.
            ls_res-message = |Warning: { lv_invalid_cnt } TCode(s) not in TSTC: [{ lv_invalid_list }] (excluded). { ls_res-message }|.
          ENDIF.
        ELSE.
          ROLLBACK WORK.
          ls_res-status  = gc_status_err.
          ls_res-action  = 'ERROR'.
          PERFORM format_bapi_message USING lt_bapiret CHANGING ls_res-message.
          IF ls_res-message IS INITIAL.
            ls_res-message = |Role creation failed with exception sy-subrc = { lv_rc }.|.
          ENDIF.
        ENDIF.
      ENDIF.

    ELSE.
      " 2B. ROLE ALREADY EXISTS
      IF p_upd = abap_false.
        ls_res-status  = gc_status_warn.
        ls_res-action  = 'SKIPPED'.
        ls_res-message = 'Role already exists. Skipping (Update option not enabled).'.
        IF lv_invalid_cnt > 0.
          ls_res-message = |Warning: { lv_invalid_cnt } TCode(s) not in TSTC: [{ lv_invalid_list }] (excluded). { ls_res-message }|.
        ENDIF.
      ELSE.
        " Read current menu nodes & current TCodes from agr_tcodes (strictly check load error!)
        CLEAR: lt_curr_nodes, lt_curr_texts, lt_tcodes_to_add, lt_tcodes_to_del, lt_tcodes_to_keep,
               lv_str_add, lv_str_del, lv_str_keep.

        CALL FUNCTION 'PRGN_STRU_LOAD_NODES'
          EXPORTING
            activity_group = ls_role-agr_name
          TABLES
            i_nodes_out    = lt_curr_nodes
            i_texts_out    = lt_curr_texts
          EXCEPTIONS
            OTHERS         = 1.
        lv_rc = sy-subrc.
        IF lv_rc <> 0.
          ls_res-status  = gc_status_err.
          ls_res-action  = 'ERROR'.
          ls_res-message = |Failed to load existing menu nodes for '{ ls_role-agr_name }' (sy-subrc = { lv_rc }); aborted to prevent overwrite.|.
          APPEND ls_res TO gt_results.
          CONTINUE.
        ENDIF.

        SELECT tcode FROM agr_tcodes INTO TABLE @DATA(lt_curr_tcds)
          WHERE agr_name = @ls_role-agr_name AND type = 'TR'.

        " 1. Identify TCodes to Add vs Keep from CSV
        LOOP AT gt_tcodes INTO DATA(ls_chk_tc) WHERE agr_name = ls_role-agr_name AND is_valid = abap_true.
          READ TABLE lt_curr_tcds WITH KEY tcode = ls_chk_tc-tcode TRANSPORTING NO FIELDS.
          IF sy-subrc = 0.
            APPEND ls_chk_tc-tcode TO lt_tcodes_to_keep.
            IF lv_str_keep IS INITIAL. lv_str_keep = ls_chk_tc-tcode.
            ELSE. CONCATENATE lv_str_keep ',' ls_chk_tc-tcode INTO lv_str_keep SEPARATED BY space. ENDIF.
          ELSE.
            APPEND ls_chk_tc TO lt_tcodes_to_add.
            IF lv_str_add IS INITIAL. lv_str_add = ls_chk_tc-tcode.
            ELSE. CONCATENATE lv_str_add ',' ls_chk_tc-tcode INTO lv_str_add SEPARATED BY space. ENDIF.
          ENDIF.
        ENDLOOP.

        " 2. Identify TCodes to Delete (exist in SAP role but NOT in incoming CSV) - Sync Mode only
        IF p_sync = abap_true.
          LOOP AT lt_curr_tcds INTO DATA(ls_c_tc).
            READ TABLE gt_tcodes WITH KEY agr_name = ls_role-agr_name tcode = ls_c_tc-tcode is_valid = abap_true TRANSPORTING NO FIELDS.
            IF sy-subrc <> 0.
              APPEND ls_c_tc-tcode TO lt_tcodes_to_del.
              IF lv_str_del IS INITIAL. lv_str_del = ls_c_tc-tcode.
              ELSE. CONCATENATE lv_str_del ',' ls_c_tc-tcode INTO lv_str_del SEPARATED BY space. ENDIF.
            ENDIF.
          ENDLOOP.
        ELSE.
          LOOP AT lt_curr_tcds INTO ls_c_tc.
            READ TABLE gt_tcodes WITH KEY agr_name = ls_role-agr_name tcode = ls_c_tc-tcode is_valid = abap_true TRANSPORTING NO FIELDS.
            IF sy-subrc <> 0.
              APPEND ls_c_tc-tcode TO lt_tcodes_to_keep.
            ENDIF.
          ENDLOOP.
        ENDIF.

        ls_res-tcodes_add = lv_str_add.
        ls_res-tcodes_del = lv_str_del.

        " 3. Case A: Role had no menu at all currently
        IF lt_curr_nodes IS INITIAL.
          IF lv_valid_cnt = 0.
            PERFORM set_org_levels_default USING ls_role-agr_name.
            COMMIT WORK AND WAIT.
            ls_res-status  = gc_status_warn.
            ls_res-action  = 'UP-TO-DATE'.
            ls_res-message = 'Role exists without menu and no valid TCodes in CSV. Up-to-date; Org levels defaulted to -1.'.
          ELSE.
            " Create initial menu
            CALL FUNCTION 'PRGN_RFC_CHANGE_TRANSACTIONS'
              EXPORTING
                activity_group          = ls_role-agr_name
                no_dialog               = 'X'
              TABLES
                hierarchy_nodes         = lt_nodes
                hierarchy_texts         = lt_texts
                return                  = lt_bapiret
              EXCEPTIONS
                OTHERS                  = 1.
            lv_rc = sy-subrc.

            IF lv_rc = 0.
              IF p_genprf = abap_true.
                PERFORM generate_master_role_profile USING ls_role-agr_name abap_true.
              ELSE.
                PERFORM set_org_levels_default USING ls_role-agr_name.
              ENDIF.
              PERFORM set_role_description USING ls_role-agr_name ls_role-role_desc.
              COMMIT WORK AND WAIT.

              IF p_adjder = abap_true.
                PERFORM adjust_derived_roles USING ls_role-agr_name CHANGING lv_adj_roles lv_adj_sum.
                ls_res-derived_roles = lv_adj_roles.
              ENDIF.

              ls_res-status  = gc_status_ok.
              ls_res-action  = 'UPDATED'.
              ls_res-message = |Role had no menu. Created menu folder '{ ls_role-role_desc }' with { lv_valid_cnt } valid TCodes; Org levels defaulted to '-1'.|.
              IF lv_adj_sum IS NOT INITIAL.
                CONCATENATE ls_res-message lv_adj_sum INTO ls_res-message SEPARATED BY space.
              ENDIF.
              IF lv_invalid_cnt > 0.
                ls_res-status  = gc_status_warn.
                ls_res-message = |Warning: { lv_invalid_cnt } TCode(s) not in TSTC: [{ lv_invalid_list }] (excluded). { ls_res-message }|.
              ENDIF.
            ELSE.
              ROLLBACK WORK.
              ls_res-status  = gc_status_err.
              ls_res-action  = 'ERROR'.
              PERFORM format_bapi_message USING lt_bapiret CHANGING ls_res-message.
              IF ls_res-message IS INITIAL.
                ls_res-message = |Failed to initialize role menu (sy-subrc = { lv_rc }).|.
              ENDIF.
            ENDIF.
          ENDIF.

        " 4. Case B: Role already has menu structure
        ELSE.
          IF lt_tcodes_to_add IS INITIAL AND lt_tcodes_to_del IS INITIAL.
            " Completely matched, nothing to change
            IF p_genprf = abap_true.
              PERFORM generate_master_role_profile USING ls_role-agr_name abap_false.
            ELSE.
              PERFORM set_org_levels_default USING ls_role-agr_name.
            ENDIF.
            PERFORM set_role_description USING ls_role-agr_name ls_role-role_desc.
            COMMIT WORK AND WAIT.

            IF p_adjder = abap_true.
              PERFORM adjust_derived_roles USING ls_role-agr_name CHANGING lv_adj_roles lv_adj_sum.
              ls_res-derived_roles = lv_adj_roles.
            ENDIF.

            ls_res-status  = gc_status_ok.
            ls_res-action  = 'UP-TO-DATE'.
            ls_res-message = |Role menu up-to-date. All { lines( lt_tcodes_to_keep ) } valid TCodes already match exactly. Org levels defaulted to '-1'.|.
            IF lv_adj_sum IS NOT INITIAL.
              CONCATENATE ls_res-message lv_adj_sum INTO ls_res-message SEPARATED BY space.
            ENDIF.
            IF lv_invalid_cnt > 0.
              ls_res-status  = gc_status_warn.
              ls_res-message = |Warning: { lv_invalid_cnt } TCode(s) not in TSTC: [{ lv_invalid_list }] (excluded). { ls_res-message }|.
            ENDIF.

          ELSE.
            " Changes exist: Add missing TCodes and/or Remove surplus TCodes!
            " A. Remove surplus TCodes
            IF lt_tcodes_to_del IS NOT INITIAL.
              DATA: lt_node_del_ids TYPE STANDARD TABLE OF menu_num_8.
              CLEAR lt_node_del_ids.
              LOOP AT lt_curr_nodes ASSIGNING FIELD-SYMBOL(<ls_cn_del>).
                CLEAR ls_stck.
                ls_stck = <ls_cn_del>-string1.
                IF ls_stck-reporttype = 'TR'.
                  DATA(lv_tr_del) = CONV tcode( ls_stck-report ).
                  READ TABLE lt_tcodes_to_del WITH KEY table_line = lv_tr_del TRANSPORTING NO FIELDS.
                  IF sy-subrc = 0.
                    APPEND <ls_cn_del>-object_id TO lt_node_del_ids.
                  ENDIF.
                ENDIF.
              ENDLOOP.

              LOOP AT lt_node_del_ids INTO DATA(lv_did).
                DELETE lt_curr_nodes WHERE object_id = lv_did.
                DELETE lt_curr_texts WHERE object_id = lv_did.
              ENDLOOP.
            ENDIF.

            " B. Add missing TCodes (safely handle roles without any folder node)
            IF lt_tcodes_to_add IS NOT INITIAL.
              lv_target_folder = 0.
              lv_target_level  = 1.
              lv_has_folder    = abap_false.
              lv_max_id        = 0.
              lv_max_sort      = 0.

              LOOP AT lt_curr_texts ASSIGNING FIELD-SYMBOL(<ls_ct>) WHERE text = ls_role-role_desc.
                READ TABLE lt_curr_nodes ASSIGNING FIELD-SYMBOL(<ls_cn>)
                  WITH KEY object_id = <ls_ct>-object_id folder = 'X'.
                IF sy-subrc = 0.
                  lv_target_folder = <ls_cn>-object_id.
                  lv_target_level  = <ls_cn>-menu_level + 1.
                  lv_has_folder    = abap_true.
                  EXIT.
                ENDIF.
              ENDLOOP.

              IF lv_has_folder = abap_false.
                READ TABLE lt_curr_nodes ASSIGNING <ls_cn> WITH KEY folder = 'X'.
                IF sy-subrc = 0.
                  lv_target_folder = <ls_cn>-object_id.
                  lv_target_level  = <ls_cn>-menu_level + 1.
                  lv_has_folder    = abap_true.
                ENDIF.
              ENDIF.

              LOOP AT lt_curr_nodes ASSIGNING <ls_cn>.
                IF <ls_cn>-object_id > lv_max_id.
                  lv_max_id = <ls_cn>-object_id.
                ENDIF.
                IF <ls_cn>-parent_id = lv_target_folder AND <ls_cn>-sort_order > lv_max_sort.
                  lv_max_sort = <ls_cn>-sort_order.
                ENDIF.
              ENDLOOP.

              LOOP AT lt_tcodes_to_add INTO DATA(ls_add_tc).
                lv_max_id   = lv_max_id + 1.
                lv_max_sort = lv_max_sort + 10.

                DATA(ls_new_node) = VALUE agr_shier(
                  object_id  = lv_max_id
                  parent_id  = lv_target_folder
                  menu_level = lv_target_level
                  sort_order = lv_max_sort
                ).
                CLEAR ls_stck.
                ls_stck-reporttype  = 'TR'.
                ls_stck-report      = ls_add_tc-tcode.
                ls_new_node-string1 = ls_stck.
                APPEND ls_new_node TO lt_curr_nodes.

                DATA(ls_new_txt) = VALUE agr_shiert(
                  object_id = lv_max_id
                  spras     = sy-langu
                  text      = ls_add_tc-ttext
                ).
                APPEND ls_new_txt TO lt_curr_texts.

                IF sy-langu NE 'E'.
                  ls_new_txt-spras = 'E'.
                  APPEND ls_new_txt TO lt_curr_texts.
                ENDIF.
              ENDLOOP.
            ENDIF.

            " C. Save modified menu nodes
            CLEAR: lv_err_flag, lt_bapiret.
            CALL FUNCTION 'PRGN_STRU_SAVE_NODES'
              EXPORTING
                activity_group    = ls_role-agr_name
                use_global_tables = space
                enqueue           = 'X'
              IMPORTING
                error_flag        = lv_err_flag
              TABLES
                menu_hierarchy    = lt_curr_nodes
                menu_texts        = lt_curr_texts
                return            = lt_bapiret
              EXCEPTIONS
                not_authorized          = 1
                activity_group_enqueued = 2
                OTHERS                  = 3.
            lv_rc = sy-subrc.

            IF lv_rc = 0 AND lv_err_flag IS INITIAL.
              " Rebuild auth data so deleted TCodes lose authorizations and added TCodes gain them
              IF p_genprf = abap_true.
                PERFORM generate_master_role_profile USING ls_role-agr_name abap_true.
              ELSE.
                PERFORM set_org_levels_default USING ls_role-agr_name.
              ENDIF.

              PERFORM set_role_description USING ls_role-agr_name ls_role-role_desc.
              COMMIT WORK AND WAIT.

              IF p_adjder = abap_true.
                PERFORM adjust_derived_roles USING ls_role-agr_name CHANGING lv_adj_roles lv_adj_sum.
                ls_res-derived_roles = lv_adj_roles.
              ENDIF.

              ls_res-status  = gc_status_ok.
              ls_res-action  = 'UPDATED'.
              ls_res-message = |Synchronized menu: Added { lines( lt_tcodes_to_add ) } [{ lv_str_add }], Removed { lines( lt_tcodes_to_del ) } [{ lv_str_del }], Kept { lines( lt_tcodes_to_keep ) }; Org levels defaulted to '-1'.|.
              IF lv_adj_sum IS NOT INITIAL.
                CONCATENATE ls_res-message lv_adj_sum INTO ls_res-message SEPARATED BY space.
              ENDIF.
              IF lv_invalid_cnt > 0.
                ls_res-status  = gc_status_warn.
                ls_res-message = |Warning: { lv_invalid_cnt } TCode(s) not in TSTC: [{ lv_invalid_list }] (excluded). { ls_res-message }|.
              ENDIF.
            ELSE.
              ROLLBACK WORK.
              ls_res-status  = gc_status_err.
              ls_res-action  = 'ERROR'.
              PERFORM format_bapi_message USING lt_bapiret CHANGING ls_res-message.
              IF ls_res-message IS INITIAL.
                ls_res-message = |Failed to save updated role menu (error_flag = { lv_err_flag }, sy-subrc = { lv_rc }).|.
              ENDIF.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.

    " Retrieve generated profile name from AGR_1016
    SELECT SINGLE profile FROM agr_1016 INTO ls_res-profile
      WHERE agr_name = ls_role-agr_name.

    APPEND ls_res TO gt_results.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form format_bapi_message
*&---------------------------------------------------------------------*
FORM format_bapi_message USING    it_bapiret TYPE bapiret2_t
                         CHANGING cv_msg     TYPE string.
  CLEAR cv_msg.
  LOOP AT it_bapiret INTO DATA(ls_bapi) WHERE type CA 'EAX'.
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
* Sets all Organizational Levels for Master Roles to '-1'
* (Used as template default for subsequent derived role specialization)
*&---------------------------------------------------------------------*
FORM set_org_levels_default USING iv_agr_name TYPE agr_name.
  DATA: lt_org_levels TYPE TABLE OF pt1252,
        lv_org_mod    TYPE abap_bool.

  CLEAR: lt_org_levels, lv_org_mod.
  CALL FUNCTION 'PRGN_1252_READ_ORG_LEVELS'
    EXPORTING
      activity_group    = iv_agr_name
    TABLES
      org_levels        = lt_org_levels
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.

  IF sy-subrc = 0 AND lt_org_levels IS NOT INITIAL.
    LOOP AT lt_org_levels ASSIGNING FIELD-SYMBOL(<ls_org>).
      IF <ls_org>-low <> '-1' OR <ls_org>-high IS NOT INITIAL.
        <ls_org>-low  = '-1'.
        <ls_org>-high = space.
        lv_org_mod    = abap_true.
      ENDIF.
    ENDLOOP.
  ELSEIF sy-subrc = 1 OR lt_org_levels IS INITIAL.
    " Fallback: Read Org variables directly from AGR_1251 (verified against cached gt_usorg_map)
    DATA: lt_auth_vars TYPE TABLE OF agval.
    SELECT DISTINCT low FROM agr_1251 INTO TABLE @lt_auth_vars
      WHERE agr_name = @iv_agr_name AND low LIKE '$%'
        AND deleted  = @space AND copied <> 'I'.
    LOOP AT lt_auth_vars INTO DATA(lv_var).
      IF line_exists( gt_usorg_map[ KEY by_varbl COMPONENTS varbl = lv_var ] ).
        APPEND VALUE pt1252( varbl = lv_var low = '-1' high = space ) TO lt_org_levels.
        lv_org_mod = abap_true.
      ENDIF.
    ENDLOOP.
  ENDIF.

  IF lv_org_mod = abap_true AND lt_org_levels IS NOT INITIAL.
    SORT lt_org_levels BY varbl low high.
    DELETE ADJACENT DUPLICATES FROM lt_org_levels COMPARING varbl low high.

    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
      EXPORTING
        activity_group = iv_agr_name
      EXCEPTIONS
        OTHERS         = 1.
    IF sy-subrc = 0.
      CALL FUNCTION 'PRGN_1252_SAVE_ORG_LEVELS'
        EXPORTING
          activity_group = iv_agr_name
        TABLES
          org_levels     = lt_org_levels
        EXCEPTIONS
          OTHERS         = 1.
      CALL FUNCTION 'PRGN_UPDATE_DATABASE'
        EXCEPTIONS
          OTHERS = 1.
      COMMIT WORK AND WAIT.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
        EXPORTING
          activity_group = iv_agr_name
        EXCEPTIONS
          OTHERS         = 0.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form generate_master_role_profile
*&---------------------------------------------------------------------*
* Generates authorization runtime profile for Master Role cleanly:
* 1. Rebuilds auth data if requested (merging menu changes)
* 2. Sets all org levels to '-1' in AGR_1252 so no open variables remain
* 3. Compiles runtime profile via SUPRN_DARK_MANIPULATE_PROFILE
* 4. Updates timestamps in AGR_FLAGS/TOST to ensure 100% GREEN status
*&---------------------------------------------------------------------*
FORM generate_master_role_profile USING iv_agr_name     TYPE agr_name
                                        iv_rebuild_auth TYPE abap_bool.
  DATA: lt_bapi TYPE bapiret2_t.

  " Step 1: Rebuild auth objects from menu if requested
  IF iv_rebuild_auth = abap_true.
    CALL FUNCTION 'SUPRN_DARK_MANIPULATE_PROFILE'
      EXPORTING
        activity_group        = iv_agr_name
        fill_orgs_with_star   = space
        fill_fields_with_star = 'X'
        no_dialog             = 'X'
        rebuild_auth_data     = 'X'
        generate_profile      = space
      IMPORTING
        return                = lt_bapi
      EXCEPTIONS
        OTHERS                = 1.
  ENDIF.

  " Step 2: Ensure ALL Org Levels in AGR_1252 have default value '-1'
  PERFORM set_org_levels_default USING iv_agr_name.

  " Step 3: Compile runtime authorization profile
  CLEAR lt_bapi.
  CALL FUNCTION 'SUPRN_DARK_MANIPULATE_PROFILE'
    EXPORTING
      activity_group        = iv_agr_name
      fill_orgs_with_star   = space
      fill_fields_with_star = 'X'
      no_dialog             = 'X'
      rebuild_auth_data     = space
      generate_profile      = 'X'
    IMPORTING
      return                = lt_bapi
    EXCEPTIONS
      OTHERS                = 1.

  " Step 3b: Restore Org Variable Bindings in AGR_1251 for Master Role
  " (Standard SAP template rule: Org fields in Master Role AGR_1251 MUST be bound to $VARBL with MODIFIED = 'S')
  PERFORM restore_1251_org_bindings USING iv_agr_name.

  " Step 4: Synchronize role and profile timestamp in PFCG
  CALL FUNCTION 'PRGN_SET_ACTGROUP_TIMESTAMP'
    EXPORTING
      activity_group = iv_agr_name
    EXCEPTIONS
      OTHERS         = 0.

  COMMIT WORK AND WAIT.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form adjust_derived_roles
*&---------------------------------------------------------------------*
* Automatically propagates updated authorization objects from Master Role
* down to all inheriting Derived Roles, strictly preserving their existing
* Org Levels (AGR_1252).
*&---------------------------------------------------------------------*
FORM adjust_derived_roles USING    iv_master_agr  TYPE agr_name
                          CHANGING cv_der_roles   TYPE string
                                   cv_der_summary TYPE string.
  DATA: lt_derived_roles   TYPE STANDARD TABLE OF agr_name,
        lt_child_bapi      TYPE bapiret2_t,
        lt_orig_orgs       TYPE TABLE OF agr_1252,
        lt_cur_child_orgs  TYPE TABLE OF pt1252,
        lt_dist_vars       TYPE STANDARD TABLE OF agval,
        lt_final_child_org TYPE TABLE OF pt1252,
        lv_new_req         TYPE trkorr,
        lv_drv_ok          TYPE char01,
        lv_adj_ok          TYPE char01,
        lv_prf_ok          TYPE char01,
        lv_rc              TYPE sy-subrc,
        lv_succ_cnt        TYPE i,
        lv_err_cnt         TYPE i,
        lv_role_list       TYPE string.

  CLEAR: cv_der_roles, cv_der_summary, lv_succ_cnt, lv_err_cnt, lv_role_list.

  SELECT agr_name FROM agr_define INTO TABLE @lt_derived_roles
    WHERE parent_agr = @iv_master_agr
    ORDER BY agr_name.

  IF lt_derived_roles IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT lt_derived_roles INTO DATA(lv_child_agr).
    IF lv_role_list IS INITIAL.
      lv_role_list = lv_child_agr.
    ELSE.
      CONCATENATE lv_role_list ',' lv_child_agr INTO lv_role_list SEPARATED BY space.
    ENDIF.

    " Per-child authority check
    AUTHORITY-CHECK OBJECT 'S_USER_AGR'
      ID 'ACT_GROUP' FIELD lv_child_agr
      ID 'ACTVT'     FIELD '02'.
    IF sy-subrc <> 0.
      lv_err_cnt = lv_err_cnt + 1.
      CONTINUE.
    ENDIF.

    " 1. Backup ALL existing Org Levels of this derived role
    CLEAR lt_orig_orgs.
    SELECT * FROM agr_1252 INTO TABLE @lt_orig_orgs
      WHERE agr_name = @lv_child_agr
      ORDER BY counter.

    " 2. Inherit authorization objects from Master Role via standard FM
    CLEAR: lt_child_bapi, lv_new_req, lv_drv_ok, lv_adj_ok, lv_prf_ok.
    CALL FUNCTION 'PRGN_RFC_CREATE_DERIVATION'
      EXPORTING
        role            = lv_child_agr
        parent_role     = iv_master_agr
        adjust_auths    = 'X'
        profile_gen     = space
        no_dialog       = 'X'
      IMPORTING
        new_request     = lv_new_req
        derivation_ok   = lv_drv_ok
        adjust_auths_ok = lv_adj_ok
        profile_gen_ok  = lv_prf_ok
      TABLES
        return          = lt_child_bapi
      EXCEPTIONS
        error_message   = 98
        OTHERS          = 99.
    lv_rc = sy-subrc.

    DATA(lv_has_der_err) = xsdbool( lv_rc <> 0 ).
    LOOP AT lt_child_bapi INTO DATA(ls_b_chk) WHERE type CA 'EAX'.
      lv_has_der_err = abap_true.
      EXIT.
    ENDLOOP.

    IF lv_has_der_err = abap_true.
      lv_err_cnt = lv_err_cnt + 1.
      CONTINUE.
    ENDIF.

    " 3. Restore and preserve ALL multi-value Child Org Levels (AGR_1252)
    CLEAR: lt_cur_child_orgs, lt_dist_vars, lt_final_child_org.
    CALL FUNCTION 'PRGN_1252_READ_ORG_LEVELS'
      EXPORTING
        activity_group    = lv_child_agr
      TABLES
        org_levels        = lt_cur_child_orgs
      EXCEPTIONS
        no_data_available = 1
        OTHERS            = 2.

    LOOP AT lt_cur_child_orgs INTO DATA(ls_cur_org).
      APPEND ls_cur_org-varbl TO lt_dist_vars.
    ENDLOOP.
    SORT lt_dist_vars.
    DELETE ADJACENT DUPLICATES FROM lt_dist_vars.
    DELETE lt_dist_vars WHERE table_line IS INITIAL.

    LOOP AT lt_dist_vars INTO DATA(lv_cvar).
      DATA(lv_found_orig) = abap_false.
      LOOP AT lt_orig_orgs INTO DATA(ls_orig)
        WHERE varbl = lv_cvar
          AND ( ( low IS NOT INITIAL AND low <> '-1' ) OR high IS NOT INITIAL ).
        lv_found_orig = abap_true.
        APPEND VALUE pt1252(
          varbl = ls_orig-varbl
          low   = ls_orig-low
          high  = ls_orig-high
        ) TO lt_final_child_org.
      ENDLOOP.

      IF lv_found_orig = abap_false.
        APPEND VALUE pt1252( varbl = lv_cvar low = space high = space ) TO lt_final_child_org.
      ENDIF.
    ENDLOOP.

    SORT lt_final_child_org BY varbl low high.
    DELETE ADJACENT DUPLICATES FROM lt_final_child_org COMPARING varbl low high.

    IF lt_final_child_org IS NOT INITIAL.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
        EXPORTING
          activity_group = lv_child_agr
        EXCEPTIONS
          OTHERS         = 1.
      IF sy-subrc = 0.
        CALL FUNCTION 'PRGN_1252_SAVE_ORG_LEVELS'
          EXPORTING
            activity_group = lv_child_agr
          TABLES
            org_levels     = lt_final_child_org
          EXCEPTIONS
            OTHERS         = 1.
        CALL FUNCTION 'PRGN_UPDATE_DATABASE'
          EXCEPTIONS
            OTHERS = 1.
        CALL FUNCTION 'PRGN_SET_ACTGROUP_TIMESTAMP'
          EXPORTING
            activity_group = lv_child_agr
          EXCEPTIONS
            OTHERS         = 0.
        COMMIT WORK AND WAIT.
        CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
          EXPORTING
            activity_group = lv_child_agr
          EXCEPTIONS
            OTHERS         = 0.
      ENDIF.
    ENDIF.

    " Restore Org Variable Bindings in AGR_1251/1250 BEFORE profile generation
    PERFORM restore_1251_org_bindings USING lv_child_agr.

    " 4. Regenerate derived role runtime profile if requested
    IF p_genprf = abap_true.
      CLEAR lt_child_bapi.
      CALL FUNCTION 'SUPRN_DARK_MANIPULATE_PROFILE'
        EXPORTING
          activity_group        = lv_child_agr
          fill_orgs_with_star   = space
          fill_fields_with_star = space
          no_dialog             = 'X'
          rebuild_auth_data     = space
          generate_profile      = 'X'
        IMPORTING
          return                = lt_child_bapi
        EXCEPTIONS
          OTHERS                = 1.
      COMMIT WORK AND WAIT.
    ENDIF.

    lv_succ_cnt = lv_succ_cnt + 1.
  ENDLOOP.

  cv_der_roles = lv_role_list.

  IF lv_err_cnt = 0.
    cv_der_summary = |Adjusted { lv_succ_cnt } child role(s) [{ lv_role_list }] (org levels preserved).|.
  ELSE.
    cv_der_summary = |Adjusted { lv_succ_cnt } child role(s) [{ lv_role_list }]; { lv_err_cnt } role(s) had errors.|.
  ENDIF.
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
    IF sy-subrc = 0 AND column = 'AGR_NAME' AND ls_row-agr_name IS NOT INITIAL.
      TRY.
          SET PARAMETER ID 'AGR' FIELD ls_row-agr_name.
          CALL TRANSACTION 'PFCG' WITH AUTHORITY-CHECK AND SKIP FIRST SCREEN.
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

      lo_functions = lo_alv->get_functions( ).
      lo_functions->set_all( abap_true ).

      lo_cols = lo_alv->get_columns( ).
      lo_cols->set_optimize( abap_true ).

      " Status column
      lo_col ?= lo_cols->get_column( 'STATUS' ).
      lo_col->set_short_text( 'Status' ).
      lo_col->set_medium_text( 'Status' ).
      lo_col->set_long_text( 'Status' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " Action column
      lo_col ?= lo_cols->get_column( 'ACTION' ).
      lo_col->set_short_text( 'Action' ).
      lo_col->set_medium_text( 'Execution Action' ).
      lo_col->set_long_text( 'Execution Action' ).

      " Role Name column (Hotspot to PFCG)
      lo_col ?= lo_cols->get_column( 'AGR_NAME' ).
      lo_col->set_short_text( 'Role ID' ).
      lo_col->set_medium_text( 'Role Name (PFCG)' ).
      lo_col->set_long_text( 'Role Name (Click to open PFCG)' ).
      lo_col->set_cell_type( if_salv_c_cell_type=>hotspot ).

      " Role Description
      lo_col ?= lo_cols->get_column( 'ROLE_DESC' ).
      lo_col->set_short_text( 'Role Desc' ).
      lo_col->set_medium_text( 'Role Description' ).
      lo_col->set_long_text( 'Role Description' ).

      " Menu Folder
      lo_col ?= lo_cols->get_column( 'FOLDER_NAME' ).
      lo_col->set_short_text( 'Folder' ).
      lo_col->set_medium_text( 'Menu Folder' ).
      lo_col->set_long_text( 'Menu Folder Name' ).

      " TCode Count
      lo_col ?= lo_cols->get_column( 'TCODE_CNT' ).
      lo_col->set_short_text( 'TC Cnt' ).
      lo_col->set_medium_text( 'TCode Count' ).
      lo_col->set_long_text( 'Assigned TCode Count' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      " TCodes List
      lo_col ?= lo_cols->get_column( 'TCODES' ).
      lo_col->set_short_text( 'TC List' ).
      lo_col->set_medium_text( 'TCodes in File' ).
      lo_col->set_long_text( 'Assigned Transaction Codes in File' ).
      lo_col->set_output_length( 40 ).

      " Added TCodes (Synchronized)
      TRY.
          lo_col ?= lo_cols->get_column( 'TCODES_ADD' ).
          lo_col->set_short_text( 'Added TC' ).
          lo_col->set_medium_text( 'Added TCodes' ).
          lo_col->set_long_text( 'TCodes Added to Menu' ).
          lo_col->set_output_length( 30 ).
        CATCH cx_salv_not_found.
      ENDTRY.

      " Removed TCodes (Synchronized)
      TRY.
          lo_col ?= lo_cols->get_column( 'TCODES_DEL' ).
          lo_col->set_short_text( 'Removed TC' ).
          lo_col->set_medium_text( 'Removed TCodes' ).
          lo_col->set_long_text( 'Surplus TCodes Removed from Role' ).
          lo_col->set_output_length( 30 ).
        CATCH cx_salv_not_found.
      ENDTRY.

      " Invalid TCodes (Not in TSTC)
      TRY.
          lo_col ?= lo_cols->get_column( 'INVALID_TCODES' ).
          lo_col->set_short_text( 'Invalid TC' ).
          lo_col->set_medium_text( 'Invalid TCodes' ).
          lo_col->set_long_text( 'Invalid TCodes (Not in TSTC)' ).
          lo_col->set_output_length( 40 ).
        CATCH cx_salv_not_found.
      ENDTRY.

      " Derived Roles
      TRY.
          lo_col ?= lo_cols->get_column( 'DERIVED_ROLES' ).
          lo_col->set_short_text( 'Derived' ).
          lo_col->set_medium_text( 'Derived Roles' ).
          lo_col->set_long_text( 'Adjusted Child Derived Roles' ).
          lo_col->set_output_length( 40 ).
        CATCH cx_salv_not_found.
      ENDTRY.

      " Auth Profile
      lo_col ?= lo_cols->get_column( 'PROFILE' ).
      lo_col->set_short_text( 'Profile' ).
      lo_col->set_medium_text( 'Auth Profile' ).
      lo_col->set_long_text( 'Generated Auth Profile' ).

      " Details Message
      lo_col ?= lo_cols->get_column( 'MESSAGE' ).
      lo_col->set_short_text( 'Message' ).
      lo_col->set_medium_text( 'Execution Details' ).
      lo_col->set_long_text( 'Execution Status & Details' ).
      lo_col->set_output_length( 255 ).

      " Register Hotspot Event Handler
      lo_events = lo_alv->get_event( ).
      SET HANDLER lcl_alv_event_handler=>on_link_click FOR lo_events.

      lo_alv->display( ).

    CATCH cx_salv_msg cx_salv_not_found INTO DATA(lx_salv).
      MESSAGE lx_salv->get_text( ) TYPE 'E'.
  ENDTRY.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form restore_1251_org_bindings
*&---------------------------------------------------------------------*
* Ensures all Org Level fields in AGR_1251 are bound to their respective
* Org Variable ($VARBL) with MODIFIED = 'S' and NEU = 'O', never left as '-1'
* or marked as Manual ('U').
*&---------------------------------------------------------------------*
FORM restore_1251_org_bindings USING iv_agr_name TYPE agr_name.
  DATA: lt_pt1251   TYPE STANDARD TABLE OF pt1251,
        lt_clean    TYPE STANDARD TABLE OF pt1251,
        lt_pt1250   TYPE STANDARD TABLE OF pt1250,
        lt_seen_key TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line,
        lv_key      TYPE string,
        lv_mod51    TYPE abap_bool,
        lv_mod50    TYPE abap_bool.

  CLEAR: lt_pt1251, lt_clean, lt_pt1250, lt_seen_key, lv_mod51, lv_mod50.

  IF gt_usorg_map IS INITIAL.
    RETURN.
  ENDIF.

  CALL FUNCTION 'PRGN_1251_READ_FIELD_VALUES'
    EXPORTING
      activity_group = iv_agr_name
    TABLES
      field_values   = lt_pt1251
    EXCEPTIONS
      OTHERS         = 1.

  IF sy-subrc <> 0 OR lt_pt1251 IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT lt_pt1251 INTO DATA(ls_f51).
    IF ls_f51-deleted = space AND ls_f51-copied <> 'I'.
      READ TABLE gt_usorg_map INTO DATA(ls_uo) WITH TABLE KEY field = ls_f51-field.
      IF sy-subrc = 0.
        lv_key = |{ ls_f51-object }:{ ls_f51-auth }:{ ls_f51-field }|.
        IF line_exists( lt_seen_key[ table_line = lv_key ] ).
          lv_mod51 = abap_true.
          CONTINUE.
        ENDIF.
        INSERT lv_key INTO TABLE lt_seen_key.
        IF ls_f51-low <> ls_uo-varbl OR ls_f51-high IS NOT INITIAL
           OR ls_f51-modified <> 'S' OR ls_f51-neu <> 'O'.
          ls_f51-low      = ls_uo-varbl.
          ls_f51-high     = space.
          ls_f51-modified = 'S'.
          ls_f51-neu      = 'O'.
          lv_mod51        = abap_true.
        ENDIF.
      ENDIF.
    ENDIF.
    APPEND ls_f51 TO lt_clean.
  ENDLOOP.
  lt_pt1251 = lt_clean.

  CALL FUNCTION 'PRGN_1250_READ_AUTH_DATA'
    EXPORTING
      activity_group = iv_agr_name
      no_texts       = 'X'
    TABLES
      auth_data      = lt_pt1250
    EXCEPTIONS
      OTHERS         = 1.

  IF sy-subrc = 0 AND lt_pt1250 IS NOT INITIAL.
    LOOP AT lt_pt1250 ASSIGNING FIELD-SYMBOL(<ls_a50>)
      WHERE deleted = space AND copied <> 'I' AND modified = 'U'.
      READ TABLE lt_pt1251 TRANSPORTING NO FIELDS
        WITH KEY object = <ls_a50>-object auth = <ls_a50>-auth
                 modified = 'U' deleted = space.
      IF sy-subrc <> 0.
        READ TABLE lt_pt1251 TRANSPORTING NO FIELDS
          WITH KEY object = <ls_a50>-object auth = <ls_a50>-auth
                   modified = 'G' deleted = space.
        IF sy-subrc = 0.
          <ls_a50>-modified = 'G'.
        ELSE.
          <ls_a50>-modified = 'S'.
        ENDIF.
        <ls_a50>-neu = 'O'.
        lv_mod50     = abap_true.
      ENDIF.
    ENDLOOP.
  ENDIF.

  IF lv_mod51 = abap_true OR lv_mod50 = abap_true.
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
      EXPORTING
        activity_group = iv_agr_name
      EXCEPTIONS
        OTHERS         = 1.
    IF sy-subrc = 0.
      IF lv_mod51 = abap_true.
        CALL FUNCTION 'PRGN_1251_SAVE_FIELD_VALUES'
          EXPORTING
            activity_group = iv_agr_name
          TABLES
            field_values   = lt_pt1251
          EXCEPTIONS
            OTHERS         = 1.
      ENDIF.
      IF lv_mod50 = abap_true.
        CALL FUNCTION 'PRGN_1250_SAVE_AUTH_DATA'
          EXPORTING
            activity_group = iv_agr_name
          TABLES
            auth_data      = lt_pt1250
          EXCEPTIONS
            OTHERS         = 1.
      ENDIF.
      CALL FUNCTION 'PRGN_UPDATE_DATABASE'
        EXCEPTIONS
          OTHERS = 1.
      COMMIT WORK AND WAIT.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
        EXPORTING
          activity_group = iv_agr_name
        EXCEPTIONS
          OTHERS         = 0.
    ENDIF.
  ENDIF.
ENDFORM.
