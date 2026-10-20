*&---------------------------------------------------------------------*
*& Report Z_AUTH_ROLE_UPDATE_ORG
*&---------------------------------------------------------------------*
*& Purpose: Batch Update Organizational Levels for PFCG Roles
*& Description:
*&   Reads an Excel (.xlsx) or CSV (.csv) file containing Organizational
*&   Level values for roles (Role Name, Org Level Variable, Org Value),
*&   updates table AGR_1252, synchronizes authorization fields in AGR_1251
*&   via the USORG mapping table, regenerates authorization profiles,
*&   and displays execution results in an interactive ALV grid cockpit.
*&
*& File format (Excel .xlsx or CSV .csv):
*&   Col 1: Role Name             (e.g., DRFI01_PERIOD_CONTROL_1100)
*&   Col 2: Org Level Variable    (e.g., $ERKRS or $BUKRS)
*&   Col 3: Org Value             (e.g., RG00, 1100, 1100*, *)
*&
*& Author: Antigravity AI (SAP Basis Engineering)
*& Package: $TMP
*&---------------------------------------------------------------------*
REPORT z_auth_role_update_org.

TABLES: agr_define, agr_texts, agr_1252, agr_1251, agr_1016, usorg.

*----------------------------------------------------------------------*
* 1. TYPES & DATA DEFINITIONS
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_raw_row,
         col1 TYPE string,
         col2 TYPE string,
         col3 TYPE string,
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
         status        TYPE char4,     " Icon (@08@ Green, @09@ Yellow, @0A@ Red)
         action        TYPE char12,    " Action: UPDATED / UP-TO-DATE / SIMULATED / SKIPPED / NO_ORGS / ERROR
         agr_name      TYPE agr_name,  " Role ID (Hotspot to PFCG)
         role_desc     TYPE agr_title, " Role Description
         parent_agr    TYPE agr_name,  " Parent Master Role (Hotspot to PFCG)
         orgs_file_cnt TYPE i,         " Number of Org Levels in input file
         orgs_upd_cnt  TYPE i,         " Number of Org Levels updated in AGR_1252
         orgs_detail   TYPE string,    " Detail summary of updated Org Levels
         profile       TYPE xuprofile, " Generated Profile Name
         message       TYPE string,    " Status Message / Execution Log
       END OF ty_alv_result.

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
              p_genprf TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_sync51 TYPE abap_bool AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b_opt.

*----------------------------------------------------------------------*
* 3. INITIALIZATION & SCREEN EVENTS
*----------------------------------------------------------------------*
INITIALIZATION.
  b_tit1 = 'Input File (Excel .xlsx / CSV)'(b01).
  b_tit2 = 'Execution & Profile Generation Options'(b02).
  c_auto = 'Auto Detect File'(t01).
  c_xlsx = 'Excel (.xlsx)'(t02).
  c_csv  = 'CSV / Text (.csv)'(t03).

  %_p_file_%_app_%-text   = 'File Path'.
  %_p_test_%_app_%-text   = 'Simulation (Test Run)'.
  %_p_genprf_%_app_%-text = 'Regenerate Auth Profiles'.
  %_p_sync51_%_app_%-text = 'Synchronize Fields in AGR_1251'.

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
      window_title            = 'Select Role Org Levels File'
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
    ID 'ACTVT'     FIELD '02'.
  IF sy-subrc <> 0.
    MESSAGE 'No authorization to change roles (S_USER_AGR, ACTVT 02).' TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form upload_and_parse_file
*&---------------------------------------------------------------------*
FORM upload_and_parse_file.
  DATA: lv_is_csv TYPE abap_bool,
        lv_len    TYPE i,
        lv_ext    TYPE string.

  CLEAR gt_raw_rows.

  IF p_file IS INITIAL.
    MESSAGE 'Please specify a file path.' TYPE 'E'.
  ENDIF.

  IF p_auto = abap_true.
    lv_len = strlen( p_file ).
    IF lv_len >= 4.
      DATA(lv_start) = lv_len - 4.
      lv_ext = substring( val = p_file off = lv_start len = 4 ).
      lv_ext = to_lower( lv_ext ).
      IF lv_ext = '.csv'.
        lv_is_csv = abap_true.
      ELSE.
        lv_is_csv = abap_false.
      ENDIF.
    ENDIF.
  ELSEIF p_csv = abap_true.
    lv_is_csv = abap_true.
  ELSE.
    lv_is_csv = abap_false.
  ENDIF.

  IF lv_is_csv = abap_true.
    PERFORM read_csv_file USING p_file.
  ELSE.
    PERFORM read_excel_file USING p_file.
  ENDIF.

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

    " Skip header row: only check line 1 or exact header column equality
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
    ev_col3 = lt_tokens[ 3 ].
    ev_col3 = condense( ev_col3 ).
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
        DATA: lv_row_idx TYPE i.
        CLEAR lv_row_idx.
        LOOP AT <lt_sheet_data> ASSIGNING <ls_sheet_row>.
          lv_row_idx = lv_row_idx + 1.
          CLEAR ls_raw.

          ASSIGN COMPONENT 1 OF STRUCTURE <ls_sheet_row> TO <lv_field>.
          IF sy-subrc = 0 AND <lv_field> IS ASSIGNED.
            ls_raw-col1 = <lv_field>.
            ls_raw-col1 = to_upper( condense( ls_raw-col1 ) ).
          ENDIF.

          ASSIGN COMPONENT 2 OF STRUCTURE <ls_sheet_row> TO <lv_field>.
          IF sy-subrc = 0 AND <lv_field> IS ASSIGNED.
            ls_raw-col2 = <lv_field>.
            ls_raw-col2 = to_upper( condense( ls_raw-col2 ) ).
          ENDIF.

          ASSIGN COMPONENT 3 OF STRUCTURE <ls_sheet_row> TO <lv_field>.
          IF sy-subrc = 0 AND <lv_field> IS ASSIGNED.
            ls_raw-col3 = <lv_field>.
            ls_raw-col3 = condense( ls_raw-col3 ).
          ENDIF.

          DATA(lv_c1_up) = to_upper( ls_raw-col1 ).
          DATA(lv_c2_up) = to_upper( ls_raw-col2 ).
          IF lv_row_idx = 1 AND ( lv_c1_up CS 'ROLE' OR lv_c2_up CS 'ORG' OR lv_c2_up CS 'VAR' ).
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
      ENDIF.

    CATCH cx_root INTO DATA(lx_err).
      DATA(lv_err_msg) = lx_err->get_text( ).
      MESSAGE |Error parsing Excel file: { lv_err_msg }| TYPE 'E'.
  ENDTRY.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form aggregate_input_data
*&---------------------------------------------------------------------*
FORM aggregate_input_data.
  DATA: lv_role     TYPE agr_name,
        lv_var      TYPE agval,
        lv_val      TYPE agval,
        lv_low      TYPE agval,
        lv_high     TYPE agval,
        ls_role_ent TYPE ty_role_entry.

  CLEAR: gt_roles, gt_role_orgs.

  LOOP AT gt_raw_rows INTO DATA(ls_raw).
    lv_role = to_upper( condense( ls_raw-col1 ) ).
    lv_var  = to_upper( condense( ls_raw-col2 ) ).
    lv_val  = condense( ls_raw-col3 ).

    IF lv_role IS INITIAL OR lv_var IS INITIAL.
      CONTINUE.
    ENDIF.

    " Ensure Org Variable has leading '$' (e.g. BUKRS -> $BUKRS)
    IF lv_var(1) NE '$'.
      lv_var = '$' && lv_var.
    ENDIF.

    " Handle potential ranges (LOW - HIGH or LOW:HIGH)
    CLEAR: lv_low, lv_high.
    IF lv_val CS ' - '.
      SPLIT lv_val AT ' - ' INTO lv_low lv_high.
      lv_low  = condense( lv_low ).
      lv_high = condense( lv_high ).
    ELSEIF lv_val CS ':'.
      SPLIT lv_val AT ':' INTO lv_low lv_high.
      lv_low  = condense( lv_low ).
      lv_high = condense( lv_high ).
    ELSE.
      lv_low = lv_val.
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

  " Preload USORG mapping for field synchronization
  CLEAR gt_usorg_map.
  SELECT * FROM usorg INTO TABLE @gt_usorg_map.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form process_org_update
*&---------------------------------------------------------------------*
FORM process_org_update.
  DATA: ls_res        TYPE ty_alv_result,
        lt_curr_1252  TYPE STANDARD TABLE OF agr_1252,
        lt_pt1252     TYPE STANDARD TABLE OF pt1252,
        lt_bapiret    TYPE STANDARD TABLE OF bapiret2,
        lv_agr_chk    TYPE agr_name,
        lv_parent_chk TYPE agr_name,
        lv_chg_cnt    TYPE i,
        lv_match_cnt  TYPE i,
        lv_detail     TYPE string.

  CLEAR gt_results.

  LOOP AT gt_roles INTO DATA(ls_role).
    CLEAR: ls_res, lt_curr_1252, lt_pt1252, lt_bapiret, lv_agr_chk,
           lv_parent_chk, lv_chg_cnt, lv_match_cnt, lv_detail.

    ls_res-agr_name      = ls_role-agr_name.
    ls_res-orgs_file_cnt = ls_role-org_cnt.

    " -----------------------------------------------------------------
    " 1. Validate Role in SAP
    " -----------------------------------------------------------------
    SELECT SINGLE agr_name, parent_agr FROM agr_define
      INTO ( @lv_agr_chk, @lv_parent_chk )
      WHERE agr_name = @ls_role-agr_name.
    IF sy-subrc <> 0 OR lv_agr_chk IS INITIAL.
      ls_res-status  = '@0A@'. " Red LED
      ls_res-action  = 'ERROR'.
      ls_res-message = |Role '{ ls_role-agr_name }' does not exist in SAP.|.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    ls_res-parent_agr = lv_parent_chk.

    " Fetch Role Description
    SELECT SINGLE text FROM agr_texts INTO @ls_res-role_desc
      WHERE agr_name = @ls_role-agr_name AND spras = @sy-langu AND line = '00000'.
    IF sy-subrc <> 0.
      SELECT SINGLE text FROM agr_texts INTO @ls_res-role_desc
        WHERE agr_name = @ls_role-agr_name AND line = '00000'.
    ENDIF.

    " -----------------------------------------------------------------
    " 2. Read Existing Org Levels in Role (AGR_1252)
    " -----------------------------------------------------------------
    SELECT * FROM agr_1252 INTO TABLE @lt_curr_1252
      WHERE agr_name = @ls_role-agr_name
      ORDER BY counter.

    IF lt_curr_1252 IS INITIAL.
      ls_res-status       = '@09@'. " Yellow LED
      ls_res-action       = 'NO_ORGS'.
      ls_res-orgs_upd_cnt = 0.
      ls_res-message      = 'Role contains no Org Levels in authorizations (0 entries in AGR_1252); skipped.'.
      SELECT SINGLE profile FROM agr_1016 INTO @ls_res-profile
        WHERE agr_name = @ls_role-agr_name.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " 3. Compare & Update Matching Org Levels
    " -----------------------------------------------------------------
    LOOP AT gt_role_orgs INTO DATA(ls_org) WHERE agr_name = ls_role-agr_name.
      READ TABLE lt_curr_1252 ASSIGNING FIELD-SYMBOL(<ls_1252>)
        WITH KEY varbl = ls_org-varbl.
      IF sy-subrc = 0.
        lv_match_cnt = lv_match_cnt + 1.
        IF <ls_1252>-low NE ls_org-val_low OR <ls_1252>-high NE ls_org-val_high.
          <ls_1252>-low  = ls_org-val_low.
          <ls_1252>-high = ls_org-val_high.
          lv_chg_cnt = lv_chg_cnt + 1.
        ENDIF.

        IF lv_detail IS INITIAL.
          lv_detail = |{ ls_org-varbl }={ ls_org-val_low }|.
        ELSE.
          lv_detail = |{ lv_detail }, { ls_org-varbl }={ ls_org-val_low }|.
        ENDIF.
      ENDIF.
    ENDLOOP.

    ls_res-orgs_upd_cnt = lv_chg_cnt.
    ls_res-orgs_detail  = lv_detail.

    " -----------------------------------------------------------------
    " 4. Simulation Mode
    " -----------------------------------------------------------------
    IF p_test = abap_true.
      IF lv_chg_cnt > 0.
        ls_res-status  = '@08@'. " Green LED
        ls_res-action  = 'SIMULATE'.
        ls_res-message = |[Simulated] { lv_chg_cnt } of { lines( lt_curr_1252 ) } Org Level(s) in role would be updated.|.
      ELSE.
        ls_res-status  = '@08@'. " Green LED
        ls_res-action  = 'SIMULATE'.
        ls_res-message = |[Simulated] Role is already up-to-date (no value change required).|.
      ENDIF.

      SELECT SINGLE profile FROM agr_1016 INTO @ls_res-profile
        WHERE agr_name = @ls_role-agr_name.
      APPEND ls_res TO gt_results.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " 5. Real Execution
    " -----------------------------------------------------------------
    IF lv_chg_cnt > 0.
      " Update AGR_1252 database table
      MODIFY agr_1252 FROM TABLE @lt_curr_1252.

      " Save via PFCG Function Module & PRGN_UPDATE_DATABASE
      CLEAR lt_pt1252.
      LOOP AT lt_curr_1252 INTO DATA(ls_c1252).
        APPEND VALUE pt1252(
          varbl = ls_c1252-varbl
          low   = ls_c1252-low
          high  = ls_c1252-high
        ) TO lt_pt1252.
      ENDLOOP.

      CALL FUNCTION 'PRGN_1252_SAVE_ORG_LEVELS'
        EXPORTING
          activity_group = ls_role-agr_name
        TABLES
          org_levels     = lt_pt1252.

      CALL FUNCTION 'PRGN_UPDATE_DATABASE'.

      " Synchronize into AGR_1251 for all fields mapped in USORG
      IF p_sync51 = abap_true.
        LOOP AT lt_curr_1252 INTO DATA(ls_org_entry).
          LOOP AT gt_usorg_map INTO DATA(ls_map) WHERE varbl = ls_org_entry-varbl.
            UPDATE agr_1251
              SET low  = @ls_org_entry-low,
                  high = @ls_org_entry-high
              WHERE agr_name = @ls_role-agr_name
                AND field    = @ls_map-field.
          ENDLOOP.
        ENDLOOP.
      ENDIF.

      " Regenerate Authorization Profile
      IF p_genprf = abap_true.
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

      " Check profile name
      SELECT SINGLE profile FROM agr_1016 INTO @ls_res-profile
        WHERE agr_name = @ls_role-agr_name.

      ls_res-status  = '@08@'. " Green LED
      ls_res-action  = 'UPDATED'.
      ls_res-message = |Updated { lv_chg_cnt } Org Level(s).|.
      IF p_genprf = abap_true AND ls_res-profile IS NOT INITIAL.
        ls_res-message = |{ ls_res-message } Profile '{ ls_res-profile }' regenerated.|.
      ENDIF.

    ELSE.
      SELECT SINGLE profile FROM agr_1016 INTO @ls_res-profile
        WHERE agr_name = @ls_role-agr_name.

      ls_res-status  = '@08@'. " Green LED
      ls_res-action  = 'UP-TO-DATE'.
      ls_res-message = |All { lv_match_cnt } Org Levels in role are already up-to-date.|.
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
      lo_col->set_short_text( 'Role' ).
      lo_col->set_medium_text( 'Role ID' ).
      lo_col->set_long_text( 'Role Name' ).
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
      lo_col->set_long_text( 'Parent Master Role' ).
      lo_col->set_cell_type( if_salv_c_cell_type=>hotspot ).

      " Format Column: ORGS_FILE_CNT
      lo_col ?= lo_cols->get_column( 'ORGS_FILE_CNT' ).
      lo_col->set_short_text( 'In File' ).
      lo_col->set_medium_text( 'Orgs in File' ).
      lo_col->set_long_text( 'Count of Orgs in File' ).

      " Format Column: ORGS_UPD_CNT
      lo_col ?= lo_cols->get_column( 'ORGS_UPD_CNT' ).
      lo_col->set_short_text( 'Updated' ).
      lo_col->set_medium_text( 'Orgs Updated' ).
      lo_col->set_long_text( 'Count of Orgs Updated' ).

      " Format Column: ORGS_DETAIL
      lo_col ?= lo_cols->get_column( 'ORGS_DETAIL' ).
      lo_col->set_short_text( 'Detail' ).
      lo_col->set_medium_text( 'Updated Org Detail' ).
      lo_col->set_long_text( 'Updated Org Levels Summary' ).

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
