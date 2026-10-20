*&---------------------------------------------------------------------*
*& Report Z_AUTH_ROLE_CREATE
*&---------------------------------------------------------------------*
*& Purpose: Batch Role Creation & Menu Structuring from Excel / CSV
*& Description:
*&   Uploads role definitions containing Role Name, Role Description,
*&   and Transaction Codes (TCodes). Groups multiple TCodes into single
*&   roles, creates a dedicated Menu Folder named after the Role
*&   Description, nests all assigned TCodes under this folder, and
*&   automatically generates the authorization profiles.
*&
*& File format (Excel .xlsx or CSV .csv):
*&   Col 1: Role Name        (e.g., LRFI01_PERIOD_CONTROL)
*&   Col 2: Role Description (e.g., GL Period Control)
*&   Col 3: TCode            (e.g., S_ALR_87003642)
*&
*& Author: Antigravity AI (SAP Basis Engineering)
*& Package: $TMP
*&---------------------------------------------------------------------*
REPORT z_auth_role_create.

TABLES: agr_define, agr_texts, tstc.

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
         status         TYPE char4,          " Icon (@08@ Green, @09@ Yellow, @0A@ Red)
         action         TYPE char12,         " Action: Created / Updated / Up-To-Date / Simulated / Skipped / Error
         agr_name       TYPE agr_name,       " Role ID (Hotspot to PFCG)
         role_desc      TYPE agr_title,      " Role Description
         folder_name    TYPE agr_title,      " Menu Folder Name (= Role Description)
         tcode_cnt      TYPE i,              " Count of TCodes
         tcodes         TYPE string,         " Comma-separated list of TCodes
         invalid_tcodes TYPE string,         " Invalid TCodes (Not found in TSTC)
         profile        TYPE xuprofile,      " Generated Profile Name
         message        TYPE string,         " Execution Status / BAPI Message
       END OF ty_alv_result.

DATA: gt_raw_rows TYPE STANDARD TABLE OF ty_raw_row,
      gt_roles    TYPE STANDARD TABLE OF ty_role_entry,
      gt_tcodes   TYPE STANDARD TABLE OF ty_tcode_entry,
      gt_results  TYPE STANDARD TABLE OF ty_alv_result.

*----------------------------------------------------------------------*
* 2. SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b_file WITH FRAME TITLE b_tit1.
  PARAMETERS: p_file TYPE localfile OBLIGATORY.
  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_auto RADIOBUTTON GROUP grp1 DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 3(20) c_auto FOR FIELD p_auto.
    PARAMETERS: p_xlsx RADIOBUTTON GROUP grp1.
    SELECTION-SCREEN COMMENT 26(15) c_xlsx FOR FIELD p_xlsx.
    PARAMETERS: p_csv  RADIOBUTTON GROUP grp1.
    SELECTION-SCREEN COMMENT 44(15) c_csv FOR FIELD p_csv.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b_file.

SELECTION-SCREEN BEGIN OF BLOCK b_opt WITH FRAME TITLE b_tit2.
  PARAMETERS: p_test   TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_upd    TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_genprf TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_chktc  TYPE abap_bool AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b_opt.

*----------------------------------------------------------------------*
* 3. INITIALIZATION & SCREEN EVENTS
*----------------------------------------------------------------------*
INITIALIZATION.
  b_tit1 = 'Input File (Excel .xlsx / CSV)'(b01).
  b_tit2 = 'Execution & Authorization Options'(b02).
  c_auto = 'Auto Detect File'(t01).
  c_xlsx = 'Excel (.xlsx)'(t02).
  c_csv  = 'CSV / Text (.csv)'(t03).

  %_p_file_%_app_%-text   = 'File Path'.
  %_p_test_%_app_%-text   = 'Simulation (Test Run)'.
  %_p_upd_%_app_%-text    = 'Update Existing Roles'.
  %_p_genprf_%_app_%-text = 'Auto-Generate Auth Profiles'.
  %_p_chktc_%_app_%-text  = 'Validate TCodes in TSTC'.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  PERFORM f4_file_open CHANGING p_file.

*----------------------------------------------------------------------*
* 4. START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.
  PERFORM check_authority.
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
      window_title            = 'Select Role Mapping File'
      file_filter             = 'All Supported (*.xlsx;*.csv)|*.xlsx;*.csv|Excel Files (*.xlsx)|*.xlsx|CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'
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
    MESSAGE 'Missing authorization for role creation (S_USER_AGR ACTVT 01)' TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form upload_and_parse_file
*&---------------------------------------------------------------------*
FORM upload_and_parse_file.
  DATA: lv_ext       TYPE string,
        lv_file_str  TYPE string,
        lv_is_xlsx   TYPE abap_bool VALUE abap_false.

  CLEAR: gt_raw_rows, gt_roles, gt_tcodes, gt_results.

  lv_file_str = p_file.
  TRANSLATE lv_file_str TO UPPER CASE.

  " Determine file format
  IF p_xlsx = abap_true.
    lv_is_xlsx = abap_true.
  ELSEIF p_csv = abap_true.
    lv_is_xlsx = abap_false.
  ELSE.
    " Auto detection
    IF lv_file_str CP '*.XLSX'.
      lv_is_xlsx = abap_true.
    ELSE.
      lv_is_xlsx = abap_false.
    ENDIF.
  ENDIF.

  IF lv_is_xlsx = abap_true.
    PERFORM read_excel_file USING p_file.
  ELSE.
    PERFORM read_csv_file USING p_file.
  ENDIF.

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
    IF sy-tabix = 1.
      " Check if line is header and skip
      DATA(lv_check) = to_upper( lv_line ).
      IF lv_check CS 'ROLE NAME' OR lv_check CS 'ROLE_NAME' OR lv_check CS 'ROLE ID'.
        CONTINUE.
      ENDIF.
    ENDIF.

    CLEAR ls_raw.
    PERFORM parse_csv_line USING lv_line
                           CHANGING ls_raw-col1 ls_raw-col2 ls_raw-col3.

    IF ls_raw-col1 IS NOT INITIAL AND ls_raw-col3 IS NOT INITIAL.
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
*& Form read_excel_file
*&---------------------------------------------------------------------*
FORM read_excel_file USING iv_file TYPE localfile.
  DATA: lt_bin_data    TYPE solix_tab,
        lv_filelen     TYPE i,
        lv_filepath    TYPE string,
        lv_xstring     TYPE xstring,
        lo_excel       TYPE REF TO cl_fdt_xl_spreadsheet,
        lt_sheet_names TYPE if_fdt_doc_spreadsheet=>t_worksheet_names,
        lv_sheet_name  TYPE string,
        lr_data        TYPE REF TO data,
        ls_raw         TYPE ty_raw_row.

  FIELD-SYMBOLS: <lt_sheet_data> TYPE STANDARD TABLE,
                 <ls_sheet_row>  TYPE any,
                 <lv_field>      TYPE any.

  lv_filepath = iv_file.

  cl_gui_frontend_services=>gui_upload(
    EXPORTING
      filename                = lv_filepath
      filetype                = 'BIN'
    IMPORTING
      filelength              = lv_filelen
    CHANGING
      data_tab                = lt_bin_data
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
    MESSAGE 'Failed to read Excel (.xlsx) file from client workstation.' TYPE 'E'.
  ENDIF.

  CALL FUNCTION 'SCMS_BINARY_TO_XSTRING'
    EXPORTING
      input_length = lv_filelen
    IMPORTING
      buffer       = lv_xstring
    TABLES
      binary_tab   = lt_bin_data
    EXCEPTIONS
      failed       = 1
      OTHERS       = 2.

  IF sy-subrc <> 0 OR lv_xstring IS INITIAL.
    MESSAGE 'Failed to convert binary Excel data to xstring.' TYPE 'E'.
  ENDIF.

  TRY.
      CREATE OBJECT lo_excel
        EXPORTING
          document_name = lv_filepath
          xdocument     = lv_xstring.

      lo_excel->if_fdt_doc_spreadsheet~get_worksheet_names(
        IMPORTING
          worksheet_names = lt_sheet_names
      ).

      READ TABLE lt_sheet_names INTO lv_sheet_name INDEX 1.
      IF sy-subrc <> 0.
        MESSAGE 'No worksheet found in Excel file.' TYPE 'E'.
      ENDIF.

      lr_data = lo_excel->if_fdt_doc_spreadsheet~get_itab_from_worksheet( lv_sheet_name ).
      ASSIGN lr_data->* TO <lt_sheet_data>.

      IF <lt_sheet_data> IS ASSIGNED.
        LOOP AT <lt_sheet_data> ASSIGNING <ls_sheet_row>.
          CLEAR ls_raw.

          ASSIGN COMPONENT 1 OF STRUCTURE <ls_sheet_row> TO <lv_field>.
          IF sy-subrc = 0 AND <lv_field> IS ASSIGNED.
            ls_raw-col1 = <lv_field>.
            ls_raw-col1 = condense( ls_raw-col1 ).
          ENDIF.

          ASSIGN COMPONENT 2 OF STRUCTURE <ls_sheet_row> TO <lv_field>.
          IF sy-subrc = 0 AND <lv_field> IS ASSIGNED.
            ls_raw-col2 = <lv_field>. " Keep exact spacing as in input file (no trim/condense)
          ENDIF.

          ASSIGN COMPONENT 3 OF STRUCTURE <ls_sheet_row> TO <lv_field>.
          IF sy-subrc = 0 AND <lv_field> IS ASSIGNED.
            ls_raw-col3 = <lv_field>.
            ls_raw-col3 = condense( ls_raw-col3 ).
          ENDIF.

          DATA(lv_c1_up) = to_upper( ls_raw-col1 ).
          IF lv_c1_up = 'ROLE NAME' OR lv_c1_up = 'ROLE_NAME' OR lv_c1_up = 'ROLE ID'.
            CONTINUE.
          ENDIF.

          IF ls_raw-col1 IS NOT INITIAL AND ls_raw-col3 IS NOT INITIAL.
            APPEND ls_raw TO gt_raw_rows.
          ENDIF.
        ENDLOOP.
      ENDIF.

    CATCH cx_root INTO DATA(lx_err).
      DATA(lv_msg) = lx_err->get_text( ).
      MESSAGE lv_msg TYPE 'E'.
  ENDTRY.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form aggregate_and_validate_data
*&---------------------------------------------------------------------*
FORM aggregate_and_validate_data.
  DATA: ls_role     TYPE ty_role_entry,
        ls_tcode    TYPE ty_tcode_entry,
        lv_agr_name TYPE agr_name,
        lv_role_dsc TYPE agr_title,
        lv_tcode    TYPE tcode.

  LOOP AT gt_raw_rows INTO DATA(ls_raw).
    lv_agr_name = to_upper( condense( ls_raw-col1 ) ).
    lv_role_dsc = ls_raw-col2. " Keep exact spacing as in input file (no trim/condense)
    lv_tcode    = to_upper( condense( ls_raw-col3 ) ).

    IF lv_agr_name IS INITIAL OR lv_tcode IS INITIAL.
      CONTINUE.
    ENDIF.

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
  DATA: lt_nodes         TYPE TABLE OF smensapnew,
        lt_texts         TYPE TABLE OF smencust,
        lt_curr_nodes    TYPE TABLE OF agr_shier,
        lt_curr_texts    TYPE TABLE OF agr_shiert,
        lt_tcodes_to_add TYPE TABLE OF ty_tcode_entry,
        lt_bapiret       TYPE TABLE OF bapiret2,
        ls_res           TYPE ty_alv_result,
        ls_stck          TYPE smen_stck,
        lv_obj_num       TYPE numc5,
        lv_exists        TYPE abap_bool,
        lv_dummy_agr     TYPE agr_name,
        lv_invalid_cnt   TYPE i,
        lv_invalid_list  TYPE string,
        lv_tcd_list      TYPE string,
        lv_target_folder TYPE menu_num_8,
        lv_max_id        TYPE menu_num_8,
        lv_max_sort      TYPE menu_num_8,
        lv_err_flag      TYPE char01,
        lv_skipped_cnt   TYPE i,
        lv_added_cnt     TYPE i,
        lv_sim_exist_cnt TYPE i,
        lv_sim_add_cnt   TYPE i.

  LOOP AT gt_roles INTO DATA(ls_role).
    CLEAR: ls_res, lt_nodes, lt_texts, lt_bapiret, lv_tcd_list, lv_invalid_cnt, lv_invalid_list.

    ls_res-agr_name    = ls_role-agr_name.
    ls_res-role_desc   = ls_role-role_desc.
    ls_res-folder_name = ls_role-role_desc.
    ls_res-tcode_cnt   = ls_role-tcode_cnt.

    " Build TCode comma-delimited string & count invalid TCodes
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
      ENDIF.
    ENDLOOP.
    ls_res-tcodes         = lv_tcd_list.
    ls_res-invalid_tcodes = lv_invalid_list.

    " Check if role already exists in SAP
    CLEAR lv_dummy_agr.
    SELECT SINGLE agr_name FROM agr_define INTO lv_dummy_agr
      WHERE agr_name = ls_role-agr_name.
    IF sy-subrc = 0.
      lv_exists = abap_true.
    ELSE.
      lv_exists = abap_false.
    ENDIF.

    " -----------------------------------------------------------------
    " Build Menu Hierarchy Nodes (used for new role creation / empty menu)
    " Node 1: Folder = Role Description (parent_id = '00000', menu_level = 1)
    " Nodes 2..N: TCodes (parent_id = '00001', menu_level = 2)
    " -----------------------------------------------------------------
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
    LOOP AT gt_tcodes INTO ls_tc WHERE agr_name = ls_role-agr_name.
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

    " -----------------------------------------------------------------
    " Branch 1: SIMULATION MODE (TEST RUN)
    " -----------------------------------------------------------------
    IF p_test = abap_true.
      ls_res-status = '@08@'. " Green LED
      ls_res-action = 'SIMULATED'.

      IF lv_exists = abap_true.
        IF p_upd = abap_true.
          " Check existing TCodes in role
          SELECT tcode FROM agr_tcodes INTO TABLE @DATA(lt_sim_tcodes)
            WHERE agr_name = @ls_role-agr_name AND type = 'TR'.

          CLEAR: lv_sim_exist_cnt, lv_sim_add_cnt.
          LOOP AT gt_tcodes INTO DATA(ls_sim_chk) WHERE agr_name = ls_role-agr_name.
            READ TABLE lt_sim_tcodes WITH KEY tcode = ls_sim_chk-tcode TRANSPORTING NO FIELDS.
            IF sy-subrc = 0.
              lv_sim_exist_cnt = lv_sim_exist_cnt + 1.
            ELSE.
              lv_sim_add_cnt = lv_sim_add_cnt + 1.
            ENDIF.
          ENDLOOP.

          IF lv_sim_add_cnt = 0.
            ls_res-action  = 'UP-TO-DATE'.
            ls_res-message = |Simulation: Role already exists with all { ls_role-tcode_cnt } TCodes in menu. Up-to-date (no changes needed).|.
          ELSE.
            ls_res-action  = 'SIMULATED'.
            ls_res-message = |Simulation OK: Role exists ({ lv_sim_exist_cnt } existing TCodes). Would add { lv_sim_add_cnt } missing TCode(s) under existing folder '{ ls_role-role_desc }'.|.
          ENDIF.
        ELSE.
          ls_res-status  = '@09@'. " Yellow LED
          ls_res-action  = 'SKIPPED'.
          ls_res-message = |Role already exists. Skipping because Update Existing Roles is unchecked.|.
        ENDIF.
      ELSE.
        ls_res-action  = 'SIMULATED'.
        ls_res-message = |Simulation OK: Would create new Master role with folder '{ ls_role-role_desc }' and { ls_role-tcode_cnt } TCodes; Org levels defaulted to '-1'.|.
      ENDIF.

      IF lv_invalid_cnt > 0.
        ls_res-status  = '@09@'.
        ls_res-message = |Warning: { lv_invalid_cnt } TCode(s) not in TSTC: [{ lv_invalid_list }]. { ls_res-message }|.
      ENDIF.

      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " Branch 2: ACTUAL EXECUTION
    " -----------------------------------------------------------------
    IF lv_exists = abap_false.
      " 2A. CREATE NEW MASTER ROLE
      DATA: lv_only_tc TYPE char01 VALUE space.
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

      IF sy-subrc = 0 OR sy-subrc = 11 OR sy-subrc = 12.
        " Ensure Org Levels are defaulted to '-1' for Master Role derivation
        PERFORM set_org_levels_default USING ls_role-agr_name.

        " Regenerate profile with '-1' org values if requested
        IF p_genprf = abap_true.
          CALL FUNCTION 'SUPRN_DARK_MANIPULATE_PROFILE'
            EXPORTING
              activity_group        = ls_role-agr_name
              fill_orgs_with_star   = space
              fill_fields_with_star = 'X'
              no_dialog             = 'X'
              rebuild_auth_data     = space
              generate_profile      = 'X'
            IMPORTING
              return                = lt_bapiret
            EXCEPTIONS
              OTHERS                = 1.
          PERFORM set_org_levels_default USING ls_role-agr_name.
        ENDIF.

        " Clean Description tab: Keep ONLY exact Role Description, remove auto-comments
        UPDATE agr_texts SET text = @ls_role-role_desc
          WHERE agr_name = @ls_role-agr_name AND line = '00000'.
        DELETE FROM agr_texts
          WHERE agr_name = @ls_role-agr_name AND line > '00000'.
        COMMIT WORK AND WAIT.

        ls_res-status  = '@08@'. " Green
        ls_res-action  = 'CREATED'.
        ls_res-message = |Master role created. Folder '{ ls_role-role_desc }' populated with { ls_role-tcode_cnt } TCodes; Org levels defaulted to '-1'.|.
      ELSE.
        ROLLBACK WORK.
        ls_res-status  = '@0A@'. " Red
        ls_res-action  = 'ERROR'.
        PERFORM format_bapi_message USING lt_bapiret CHANGING ls_res-message.
        IF ls_res-message IS INITIAL.
          IF sy-subrc = 9.
            ls_res-message = |Role creation failed: Illegal transaction code(s) (sy-subrc = 9). Invalid: [{ lv_invalid_list }].|.
          ELSE.
            ls_res-message = |Role creation failed with exception sy-subrc = { sy-subrc }.|.
          ENDIF.
        ENDIF.
      ENDIF.

    ELSE.
      " 2B. ROLE ALREADY EXISTS
      IF p_upd = abap_false.
        ls_res-status  = '@09@'. " Yellow
        ls_res-action  = 'SKIPPED'.
        ls_res-message = 'Role already exists. Skipping (Update option not enabled).'.
      ELSE.
        " Update role description & remove auto comments
        UPDATE agr_texts SET text = @ls_role-role_desc
          WHERE agr_name = @ls_role-agr_name AND line = '00000'.
        IF sy-subrc <> 0.
          INSERT agr_texts FROM @( VALUE #( mandt    = sy-mandt
                                            agr_name = ls_role-agr_name
                                            spras    = sy-langu
                                            line     = '00000'
                                            text     = ls_role-role_desc ) ).
        ENDIF.
        DELETE FROM agr_texts
          WHERE agr_name = @ls_role-agr_name AND line > '00000'.

        " Load existing menu hierarchy
        CLEAR: lt_curr_nodes, lt_curr_texts.
        CALL FUNCTION 'PRGN_STRU_LOAD_NODES'
          EXPORTING
            activity_group = ls_role-agr_name
          TABLES
            i_nodes_out    = lt_curr_nodes
            i_texts_out    = lt_curr_texts
          EXCEPTIONS
            OTHERS         = 0.

        " Query existing TCodes in role
        SELECT tcode FROM agr_tcodes INTO TABLE @DATA(lt_curr_tcds)
          WHERE agr_name = @ls_role-agr_name AND type = 'TR'.

        " Filter: determine missing TCodes to add vs existing to skip
        CLEAR: lt_tcodes_to_add, lv_skipped_cnt.
        LOOP AT gt_tcodes INTO DATA(ls_chk_tc) WHERE agr_name = ls_role-agr_name.
          READ TABLE lt_curr_tcds WITH KEY tcode = ls_chk_tc-tcode TRANSPORTING NO FIELDS.
          IF sy-subrc = 0.
            lv_skipped_cnt = lv_skipped_cnt + 1.
          ELSE.
            APPEND ls_chk_tc TO lt_tcodes_to_add.
          ENDIF.
        ENDLOOP.

        IF lt_curr_nodes IS INITIAL.
          " Case A: Role currently has NO menu at all -> Create menu with Folder + TCodes
          CALL FUNCTION 'PRGN_RFC_CHANGE_TRANSACTIONS'
            EXPORTING
              activity_group          = ls_role-agr_name
              no_dialog               = 'X'
            TABLES
              hierarchy_nodes         = lt_nodes
              hierarchy_texts         = lt_texts
              return                  = lt_bapiret
            EXCEPTIONS
              activity_group_enqueued = 1
              activity_group_does_not_exist = 2
              tcodes_inherited_from_parent = 3
              illegal_tcodes          = 4
              not_authorized          = 5
              no_data_selected        = 6
              profgen_tables_not_updated = 7
              OTHERS                  = 8.

          IF sy-subrc = 0.
            PERFORM set_org_levels_default USING ls_role-agr_name.

            IF p_genprf = abap_true.
              CALL FUNCTION 'SUPRN_DARK_MANIPULATE_PROFILE'
                EXPORTING
                  activity_group        = ls_role-agr_name
                  fill_orgs_with_star   = space
                  fill_fields_with_star = 'X'
                  no_dialog             = 'X'
                  rebuild_auth_data     = 'X'
                  generate_profile      = 'X'
                IMPORTING
                  return                = lt_bapiret
                EXCEPTIONS
                  OTHERS                = 1.
              PERFORM set_org_levels_default USING ls_role-agr_name.
            ENDIF.

            DELETE FROM agr_texts
              WHERE agr_name = @ls_role-agr_name AND line > '00000'.
            COMMIT WORK AND WAIT.

            ls_res-status  = '@08@'.
            ls_res-action  = 'UPDATED'.
            ls_res-message = |Role had no menu. Created menu folder '{ ls_role-role_desc }' with { ls_role-tcode_cnt } TCodes; Org levels defaulted to '-1'.|.
          ELSE.
            ROLLBACK WORK.
            ls_res-status  = '@0A@'.
            ls_res-action  = 'ERROR'.
            PERFORM format_bapi_message USING lt_bapiret CHANGING ls_res-message.
            IF ls_res-message IS INITIAL.
              ls_res-message = |Failed to initialize role menu (sy-subrc = { sy-subrc }).|.
            ENDIF.
          ENDIF.

        ELSE.
          " Case B: Role ALREADY has a menu structure!
          IF lt_tcodes_to_add IS INITIAL.
            " All TCodes already exist! Skip menu modifications (idempotent, no duplicate folders/nodes)
            PERFORM set_org_levels_default USING ls_role-agr_name.

            IF p_genprf = abap_true.
              CALL FUNCTION 'SUPRN_DARK_MANIPULATE_PROFILE'
                EXPORTING
                  activity_group        = ls_role-agr_name
                  fill_orgs_with_star   = space
                  fill_fields_with_star = 'X'
                  no_dialog             = 'X'
                  rebuild_auth_data     = space
                  generate_profile      = 'X'
                IMPORTING
                  return                = lt_bapiret
                EXCEPTIONS
                  OTHERS                = 1.
              PERFORM set_org_levels_default USING ls_role-agr_name.
            ENDIF.

            DELETE FROM agr_texts
              WHERE agr_name = @ls_role-agr_name AND line > '00000'.
            COMMIT WORK AND WAIT.

            ls_res-status  = '@08@'.
            ls_res-action  = 'UP-TO-DATE'.
            ls_res-message = |Role menu up-to-date. All { ls_role-tcode_cnt } TCodes already exist. No duplicates added; Org levels defaulted to '-1'.|.

          ELSE.
            " Missing TCodes exist -> Append ONLY missing TCodes under existing folder
            lv_target_folder = 1.
            lv_max_id        = 1.
            lv_max_sort      = 0.
            CLEAR lv_err_flag.

            " Locate existing folder node matching role description
            LOOP AT lt_curr_texts ASSIGNING FIELD-SYMBOL(<ls_ct>) WHERE text = ls_role-role_desc.
              READ TABLE lt_curr_nodes ASSIGNING FIELD-SYMBOL(<ls_cn>)
                WITH KEY object_id = <ls_ct>-object_id folder = 'X'.
              IF sy-subrc = 0.
                lv_target_folder = <ls_cn>-object_id.
                EXIT.
              ENDIF.
            ENDLOOP.

            IF lv_target_folder = 1.
              READ TABLE lt_curr_nodes ASSIGNING <ls_cn> WITH KEY folder = 'X'.
              IF sy-subrc = 0.
                lv_target_folder = <ls_cn>-object_id.
              ENDIF.
            ENDIF.

            " Find max object_id and max sort_order
            LOOP AT lt_curr_nodes ASSIGNING <ls_cn>.
              IF <ls_cn>-object_id > lv_max_id.
                lv_max_id = <ls_cn>-object_id.
              ENDIF.
              IF <ls_cn>-parent_id = lv_target_folder AND <ls_cn>-sort_order > lv_max_sort.
                lv_max_sort = <ls_cn>-sort_order.
              ENDIF.
            ENDLOOP.

            " Append each missing TCode under the existing folder
            LOOP AT lt_tcodes_to_add INTO DATA(ls_add_tc).
              lv_max_id   = lv_max_id + 1.
              lv_max_sort = lv_max_sort + 10.

              DATA(ls_new_node) = VALUE agr_shier(
                object_id  = lv_max_id
                parent_id  = lv_target_folder
                menu_level = 2
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

            " Save updated menu hierarchy directly
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

            IF sy-subrc = 0 AND lv_err_flag IS INITIAL.
              PERFORM set_org_levels_default USING ls_role-agr_name.

              IF p_genprf = abap_true.
                CALL FUNCTION 'SUPRN_DARK_MANIPULATE_PROFILE'
                  EXPORTING
                    activity_group        = ls_role-agr_name
                    fill_orgs_with_star   = space
                    fill_fields_with_star = 'X'
                    no_dialog             = 'X'
                    rebuild_auth_data     = 'X'
                    generate_profile      = 'X'
                  IMPORTING
                    return                = lt_bapiret
                  EXCEPTIONS
                    OTHERS                = 1.
                PERFORM set_org_levels_default USING ls_role-agr_name.
              ENDIF.

              DELETE FROM agr_texts
                WHERE agr_name = @ls_role-agr_name AND line > '00000'.
              COMMIT WORK AND WAIT.

              lv_added_cnt = lines( lt_tcodes_to_add ).
              ls_res-status  = '@08@'.
              ls_res-action  = 'UPDATED'.
              ls_res-message = |Added { lv_added_cnt } new TCode(s) under existing folder '{ ls_role-role_desc }'; Skipped { lv_skipped_cnt } existing TCode(s); Org levels defaulted to '-1'.|.
            ELSE.
              ROLLBACK WORK.
              ls_res-status  = '@0A@'.
              ls_res-action  = 'ERROR'.
              PERFORM format_bapi_message USING lt_bapiret CHANGING ls_res-message.
              IF ls_res-message IS INITIAL.
                ls_res-message = |Failed to save updated role menu (error_flag = { lv_err_flag }, sy-subrc = { sy-subrc }).|.
              ENDIF.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.

    " Retrieve generated profile name from AGR_1016
    SELECT SINGLE profile FROM agr_1016 INTO ls_res-profile
      WHERE agr_name = ls_role-agr_name.

    IF lv_invalid_cnt > 0.
      IF ls_res-status = '@08@'.
        ls_res-status  = '@09@'.
      ENDIF.
      ls_res-message = |Warning: { lv_invalid_cnt } TCode(s) not in TSTC: [{ lv_invalid_list }]. { ls_res-message }|.
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
      <ls_org>-low = '-1'.
      lv_org_mod   = abap_true.
    ENDLOOP.

    IF lv_org_mod = abap_true.
      CALL FUNCTION 'PRGN_1252_SAVE_ORG_LEVELS'
        EXPORTING
          activity_group = iv_agr_name
        TABLES
          org_levels     = lt_org_levels.
      CALL FUNCTION 'PRGN_UPDATE_DATABASE'.
    ENDIF.
  ENDIF.

  " Directly ensure database table AGR_1252 has low = '-1'
  UPDATE agr_1252 SET low = '-1'
    WHERE agr_name = @iv_agr_name.

  " Propagate '-1' into AGR_1251 for all fields mapped to Org Levels in USORG
  SELECT varbl, field FROM usorg INTO TABLE @DATA(lt_usorg_map).
  IF sy-subrc = 0 AND lt_usorg_map IS NOT INITIAL.
    LOOP AT lt_usorg_map INTO DATA(ls_um).
      SELECT SINGLE varbl FROM agr_1252 INTO @DATA(lv_chk_var)
        WHERE agr_name = @iv_agr_name AND varbl = @ls_um-varbl.
      IF sy-subrc = 0.
        UPDATE agr_1251 SET low = '-1'
          WHERE agr_name = @iv_agr_name
            AND field    = @ls_um-field.
      ENDIF.
    ENDLOOP.
  ENDIF.

  COMMIT WORK AND WAIT.
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
      SET PARAMETER ID 'AGR' FIELD ls_row-agr_name.
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
      lo_col->set_medium_text( 'TCodes List' ).
      lo_col->set_long_text( 'Assigned Transaction Codes' ).
      lo_col->set_output_length( 50 ).

      " Invalid TCodes (Not in TSTC)
      TRY.
          lo_col ?= lo_cols->get_column( 'INVALID_TCODES' ).
          lo_col->set_short_text( 'Invalid TC' ).
          lo_col->set_medium_text( 'Invalid TCodes' ).
          lo_col->set_long_text( 'Invalid TCodes (Not in TSTC)' ).
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
