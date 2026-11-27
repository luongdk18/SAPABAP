*&---------------------------------------------------------------------*
*& Report Z_USER_03_SSPR_ADMIN
*&---------------------------------------------------------------------*
*& Purpose: Centralized Management & Audit Cockpit for SAP SSPR & Unlock
*& Description:
*&   Monitors Self-Service Password Reset & Account Unlock security tokens,
*&   displays request statuses (Pending, Used, Expired, Invalid) with status
*&   indicators, tracks client IP addresses and expiration timestamps,
*&   enables one-click navigation to SU01, provides simulation-safe token
*&   cleanup, and displays the SICF web service endpoint info.
*&
*& Author: Antigravity AI (SAP Basis Engineering)
*& Package: $TMP (Local Object) or Custom Package
*&---------------------------------------------------------------------*
REPORT z_user_03_sspr_admin.

TABLES: zsspr_tokens.

*----------------------------------------------------------------------*
* 1. TYPES & DATA DEFINITIONS
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_alv_token,
         status_icon  TYPE char16,
         status       TYPE char10,
         action_type  TYPE char10,
         action_desc  TYPE char30,
         bname        TYPE bapibname-bapibname,
         email        TYPE ad_smtpadr,
         created_date TYPE dats,
         created_time TYPE tims,
         expires_date TYPE dats,
         expires_time TYPE tims,
         used_date    TYPE dats,
         used_time    TYPE tims,
         ip_address   TYPE char45,
         token_short  TYPE char20,
         token_full   TYPE char64,
       END OF ty_alv_token.

CONSTANTS: gc_status_used TYPE char16 VALUE '@08@ [USED]',
           gc_status_pend TYPE char16 VALUE '@09@ [PENDING]',
           gc_status_exp  TYPE char16 VALUE '@0A@ [EXPIRED]',
           gc_status_inv  TYPE char16 VALUE '@0A@ [INVALID]'.

DATA: gt_alv_data TYPE STANDARD TABLE OF ty_alv_token,
      go_alv      TYPE REF TO cl_salv_table.

*----------------------------------------------------------------------*
* 2. SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b_filt WITH FRAME TITLE b_tit1.
  SELECT-OPTIONS: s_date FOR zsspr_tokens-created_date DEFAULT sy-datum,
                  s_user FOR zsspr_tokens-bname.
  PARAMETERS: p_act  TYPE char10 AS LISTBOX VISIBLE LENGTH 25 DEFAULT 'ALL',
              p_stat TYPE char10 AS LISTBOX VISIBLE LENGTH 25 DEFAULT 'ALL'.
SELECTION-SCREEN END OF BLOCK b_filt.

SELECTION-SCREEN BEGIN OF BLOCK b_maint WITH FRAME TITLE b_tit2.
  PARAMETERS: p_test  TYPE abap_bool AS CHECKBOX DEFAULT 'X',
              p_clean TYPE abap_bool AS CHECKBOX DEFAULT ' ',
              p_days  TYPE i DEFAULT 7.
SELECTION-SCREEN END OF BLOCK b_maint.

SELECTION-SCREEN BEGIN OF BLOCK b_info WITH FRAME TITLE b_tit3.
  SELECTION-SCREEN COMMENT 1(70) c_url.
  SELECTION-SCREEN COMMENT /1(70) c_note.
SELECTION-SCREEN END OF BLOCK b_info.

*----------------------------------------------------------------------*
* 3. INITIALIZATION & SCREEN EVENTS
*----------------------------------------------------------------------*
INITIALIZATION.
  b_tit1 = 'Security Token Filter'(b01).
  b_tit2 = 'Maintenance & Cleanup'(b02).
  b_tit3 = 'Web Service Information'(b03).

  %_s_date_%_app_%-text  = 'Created Date'.
  %_s_user_%_app_%-text  = 'SAP Username'.
  %_p_act_%_app_%-text   = 'Action Type'.
  %_p_stat_%_app_%-text  = 'Token Status'.
  %_p_test_%_app_%-text  = 'Simulation (Test Run)'.
  %_p_clean_%_app_%-text = 'Cleanup Expired Tokens'.
  %_p_days_%_app_%-text  = 'Retention Days'.

  c_url  = 'SICF Service Endpoint: /sap/bc/z_sspr'.
  c_note = 'Handler Class: ZCL_SSPR_HTTP_HANDLER (Active)'.

AT SELECTION-SCREEN OUTPUT.
  PERFORM populate_dropdowns.

AT SELECTION-SCREEN.
  IF p_clean = abap_true AND ( p_days < 1 OR p_days > 3650 ).
    MESSAGE 'Retention Days must be between 1 and 3650 when Cleanup is enabled.' TYPE 'E'.
  ENDIF.

*----------------------------------------------------------------------*
* 4. START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.
  PERFORM check_authority.

  IF p_clean = abap_true.
    PERFORM cleanup_expired_tokens.
  ENDIF.

  PERFORM load_tokens_data.
  PERFORM display_alv.

*&---------------------------------------------------------------------*
*& Form populate_dropdowns
*&---------------------------------------------------------------------*
FORM populate_dropdowns.
  DATA: lt_values TYPE vrm_values,
        ls_value  TYPE vrm_value.

  " Action Type dropdown
  CLEAR lt_values.
  ls_value-key = 'ALL'.       ls_value-text = 'All Actions'.     APPEND ls_value TO lt_values.
  ls_value-key = 'RESET_PWD'. ls_value-text = 'Reset Password'.  APPEND ls_value TO lt_values.
  ls_value-key = 'UNLOCK'.    ls_value-text = 'Unlock Account'.  APPEND ls_value TO lt_values.
  CALL FUNCTION 'VRM_SET_VALUES'
    EXPORTING
      id              = 'P_ACT'
      values          = lt_values
    EXCEPTIONS
      id_illegal_name = 1
      OTHERS          = 2.

  " Status dropdown
  CLEAR lt_values.
  ls_value-key = 'ALL'.     ls_value-text = 'All Statuses'. APPEND ls_value TO lt_values.
  ls_value-key = 'PENDING'. ls_value-text = 'Pending'.      APPEND ls_value TO lt_values.
  ls_value-key = 'USED'.    ls_value-text = 'Used'.         APPEND ls_value TO lt_values.
  ls_value-key = 'EXPIRED'. ls_value-text = 'Expired'.      APPEND ls_value TO lt_values.
  ls_value-key = 'INVALID'. ls_value-text = 'Invalid'.      APPEND ls_value TO lt_values.
  CALL FUNCTION 'VRM_SET_VALUES'
    EXPORTING
      id              = 'P_STAT'
      values          = lt_values
    EXCEPTIONS
      id_illegal_name = 1
      OTHERS          = 2.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form check_authority
*&---------------------------------------------------------------------*
FORM check_authority.
  AUTHORITY-CHECK OBJECT 'S_USER_GRP'
    ID 'CLASS' DUMMY
    ID 'ACTVT' FIELD '03'.
  IF sy-subrc <> 0.
    MESSAGE 'You are not authorized to view user administration data (S_USER_GRP 03).' TYPE 'E'.
  ENDIF.

  " Require global delete authorization (S_USER_GRP CLASS='*' ACTVT='06') before purging audit logs
  IF p_clean = abap_true AND p_test = abap_false.
    AUTHORITY-CHECK OBJECT 'S_USER_GRP'
      ID 'CLASS' FIELD '*'
      ID 'ACTVT' FIELD '06'.
    IF sy-subrc <> 0.
      MESSAGE 'No global delete authorization to purge SSPR audit tokens (S_USER_GRP CLASS=* ACTVT=06).' TYPE 'E'.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form cleanup_expired_tokens
*&---------------------------------------------------------------------*
FORM cleanup_expired_tokens.
  DATA: lv_del_date TYPE dats,
        lv_del_cnt  TYPE i.

  lv_del_date = sy-datum - p_days.

  IF p_test = abap_true.
    SELECT COUNT(*) FROM zsspr_tokens
      INTO @lv_del_cnt
      WHERE created_date < @lv_del_date
        AND ( status = 'EXPIRED' OR status = 'USED' OR status = 'INVALID'
              OR ( status = 'PENDING'
                   AND ( expires_date < @sy-datum
                         OR ( expires_date = @sy-datum AND expires_time < @sy-uzeit ) ) ) ).
    MESSAGE |[Simulated] { lv_del_cnt } expired/used/invalid token(s) older than { p_days } day(s) would be deleted.| TYPE 'S'.
    RETURN.
  ENDIF.

  DELETE FROM zsspr_tokens
    WHERE created_date < @lv_del_date
      AND ( status = 'EXPIRED' OR status = 'USED' OR status = 'INVALID'
            OR ( status = 'PENDING'
                 AND ( expires_date < @sy-datum
                       OR ( expires_date = @sy-datum AND expires_time < @sy-uzeit ) ) ) ).

  lv_del_cnt = sy-dbcnt.
  COMMIT WORK AND WAIT.

  IF lv_del_cnt > 0.
    MESSAGE |Successfully cleaned up { lv_del_cnt } token(s) older than { p_days } day(s).| TYPE 'S'.
  ELSE.
    MESSAGE 'No expired, used, or invalid tokens found to clean up.' TYPE 'S'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form load_tokens_data
*&---------------------------------------------------------------------*
FORM load_tokens_data.
  DATA: lt_tokens   TYPE STANDARD TABLE OF zsspr_tokens,
        ls_alv      TYPE ty_alv_token,
        lv_eff_stat TYPE char10.

  CLEAR gt_alv_data.

  IF p_act = 'ALL'.
    SELECT * FROM zsspr_tokens
      WHERE created_date IN @s_date
        AND bname        IN @s_user
      ORDER BY created_date DESCENDING, created_time DESCENDING
      INTO TABLE @lt_tokens.
  ELSE.
    SELECT * FROM zsspr_tokens
      WHERE created_date IN @s_date
        AND bname        IN @s_user
        AND action_type  =  @p_act
      ORDER BY created_date DESCENDING, created_time DESCENDING
      INTO TABLE @lt_tokens.
  ENDIF.

  LOOP AT lt_tokens INTO DATA(ls_tok).
    CLEAR: ls_alv, lv_eff_stat.

    " Compute effective status BEFORE applying p_stat filter
    lv_eff_stat = ls_tok-status.
    CASE ls_tok-status.
      WHEN 'USED'.
        ls_alv-status_icon = gc_status_used.
      WHEN 'PENDING'.
        IF ls_tok-expires_date < sy-datum
           OR ( ls_tok-expires_date = sy-datum AND ls_tok-expires_time < sy-uzeit ).
          ls_alv-status_icon = gc_status_exp.
          lv_eff_stat        = 'EXPIRED'.
        ELSE.
          ls_alv-status_icon = gc_status_pend.
        ENDIF.
      WHEN 'EXPIRED'.
        ls_alv-status_icon = gc_status_exp.
      WHEN 'INVALID'.
        ls_alv-status_icon = gc_status_inv.
      WHEN OTHERS.
        ls_alv-status_icon = '@0A@ [ERR]'.
    ENDCASE.

    " Filter by effective status
    IF p_stat <> 'ALL' AND lv_eff_stat <> p_stat.
      CONTINUE.
    ENDIF.

    ls_alv-status       = lv_eff_stat.
    ls_alv-action_type  = ls_tok-action_type.
    ls_alv-bname        = ls_tok-bname.
    ls_alv-email        = ls_tok-email.
    ls_alv-created_date = ls_tok-created_date.
    ls_alv-created_time = ls_tok-created_time.
    ls_alv-expires_date = ls_tok-expires_date.
    ls_alv-expires_time = ls_tok-expires_time.
    ls_alv-used_date    = ls_tok-used_date.
    ls_alv-used_time    = ls_tok-used_time.
    ls_alv-ip_address   = ls_tok-ip_address.
    ls_alv-token_full   = ls_tok-token.
    ls_alv-token_short  = ls_tok-token(16) && '...'.

    IF ls_tok-action_type = 'UNLOCK'.
      ls_alv-action_desc = 'Unlock Account'.
    ELSE.
      ls_alv-action_desc = 'Reset Password'.
    ENDIF.

    APPEND ls_alv TO gt_alv_data.
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
    READ TABLE gt_alv_data INTO DATA(ls_row) INDEX row.
    IF sy-subrc = 0.
      IF column = 'BNAME' AND ls_row-bname IS NOT INITIAL.
        TRY.
            SET PARAMETER ID 'USR' FIELD ls_row-bname.
            CALL TRANSACTION 'SU01' WITH AUTHORITY-CHECK AND SKIP FIRST SCREEN.
          CATCH cx_sy_authorization_error.
            MESSAGE 'No authorization to open transaction SU01.' TYPE 'S' DISPLAY LIKE 'E'.
        ENDTRY.
      ELSEIF column = 'TOKEN_SHORT'.
        CALL FUNCTION 'POPUP_TO_INFORM'
          EXPORTING
            titel = 'Token SHA-256 Hash & Client IP'
            txt1  = 'SHA-256 Hash (1-32):'
            txt2  = ls_row-token_full(32)
            txt3  = |Hash (33-64): { ls_row-token_full+32(32) }|
            txt4  = |Client IP: { ls_row-ip_address }|.
      ENDIF.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

*&---------------------------------------------------------------------*
*& Form display_alv
*&---------------------------------------------------------------------*
FORM display_alv.
  DATA: lo_functions TYPE REF TO cl_salv_functions_list,
        lo_cols      TYPE REF TO cl_salv_columns_table,
        lo_col       TYPE REF TO cl_salv_column_table,
        lo_events    TYPE REF TO cl_salv_events_table.

  IF gt_alv_data IS INITIAL.
    MESSAGE 'No security tokens match the selection criteria.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  TRY.
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = go_alv
        CHANGING
          t_table      = gt_alv_data ).

      lo_functions = go_alv->get_functions( ).
      lo_functions->set_all( abap_true ).

      lo_cols = go_alv->get_columns( ).
      lo_cols->set_optimize( abap_true ).

      lo_col ?= lo_cols->get_column( 'STATUS_ICON' ).
      lo_col->set_short_text( 'Status' ).
      lo_col->set_medium_text( 'Token Status' ).
      lo_col->set_long_text( 'Security Token Status' ).
      lo_col->set_alignment( if_salv_c_alignment=>centered ).

      lo_col ?= lo_cols->get_column( 'ACTION_DESC' ).
      lo_col->set_short_text( 'Action' ).
      lo_col->set_medium_text( 'Action Type' ).
      lo_col->set_long_text( 'Request Action Type' ).

      lo_col ?= lo_cols->get_column( 'BNAME' ).
      lo_col->set_short_text( 'User' ).
      lo_col->set_medium_text( 'SAP Username' ).
      lo_col->set_long_text( 'Username (Click to open SU01)' ).
      lo_col->set_cell_type( if_salv_c_cell_type=>hotspot ).

      lo_col ?= lo_cols->get_column( 'EMAIL' ).
      lo_col->set_short_text( 'Email' ).
      lo_col->set_medium_text( 'Email Address' ).
      lo_col->set_long_text( 'User Email Address' ).

      lo_col ?= lo_cols->get_column( 'TOKEN_SHORT' ).
      lo_col->set_short_text( 'Token' ).
      lo_col->set_medium_text( 'Token Hash' ).
      lo_col->set_long_text( 'Token SHA-256 Hash (Click for full)' ).
      lo_col->set_cell_type( if_salv_c_cell_type=>hotspot ).

      lo_col ?= lo_cols->get_column( 'IP_ADDRESS' ).
      lo_col->set_short_text( 'Client IP' ).
      lo_col->set_medium_text( 'Client IP Address' ).
      lo_col->set_long_text( 'Client IP Address' ).

      lo_col ?= lo_cols->get_column( 'CREATED_DATE' ).
      lo_col->set_short_text( 'Created' ).
      lo_col->set_medium_text( 'Created Date' ).
      lo_col->set_long_text( 'Token Creation Date' ).

      lo_col ?= lo_cols->get_column( 'CREATED_TIME' ).
      lo_col->set_short_text( 'Time' ).
      lo_col->set_medium_text( 'Created Time' ).
      lo_col->set_long_text( 'Token Creation Time' ).

      lo_col ?= lo_cols->get_column( 'EXPIRES_DATE' ).
      lo_col->set_short_text( 'Expires' ).
      lo_col->set_medium_text( 'Expiry Date' ).
      lo_col->set_long_text( 'Token Expiration Date' ).

      lo_col ?= lo_cols->get_column( 'EXPIRES_TIME' ).
      lo_col->set_short_text( 'Exp Time' ).
      lo_col->set_medium_text( 'Expiry Time' ).
      lo_col->set_long_text( 'Token Expiration Time' ).

      lo_col ?= lo_cols->get_column( 'USED_DATE' ).
      lo_col->set_short_text( 'Used Date' ).
      lo_col->set_medium_text( 'Used Date' ).
      lo_col->set_long_text( 'Token Usage Date' ).

      lo_col ?= lo_cols->get_column( 'USED_TIME' ).
      lo_col->set_short_text( 'Used Time' ).
      lo_col->set_medium_text( 'Used Time' ).
      lo_col->set_long_text( 'Token Usage Time' ).

      lo_col ?= lo_cols->get_column( 'STATUS' ).
      lo_col->set_visible( abap_false ).
      lo_col ?= lo_cols->get_column( 'ACTION_TYPE' ).
      lo_col->set_visible( abap_false ).
      lo_col ?= lo_cols->get_column( 'TOKEN_FULL' ).
      lo_col->set_visible( abap_false ).

      lo_events = go_alv->get_event( ).
      SET HANDLER lcl_alv_event_handler=>on_link_click FOR lo_events.

      go_alv->display( ).

    CATCH cx_salv_msg cx_salv_not_found INTO DATA(lx_salv).
      MESSAGE lx_salv->get_text( ) TYPE 'E'.
  ENDTRY.
ENDFORM.
