*&---------------------------------------------------------------------*
*& Report Z_AUTH_TEST_N
*&---------------------------------------------------------------------*
*& Advanced SU53 Authorization Trace & Role Diagnostics Analyzer
*& Execute independently via SE38: Z_AUTH_TEST_N
*& Package: $TMP (Local Object)
*& Architecture: Dual-ALV Layout (Docking Single Roles + Fullscreen Missing Auths)
*&---------------------------------------------------------------------*
REPORT z_auth_test_n.

TABLES: usr02, agr_define.

*----------------------------------------------------------------------*
* 1. TYPES & DATA DEFINITIONS
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_user_role,
         radio    TYPE c LENGTH 4,         " Radio indicator: @06@ (Selected) / @07@ (Unselected)
         agr_name TYPE agr_name,           " Single Role Name
         text     TYPE c LENGTH 80,        " Role Description
         from_dat TYPE agr_fdate,          " Valid From Date
         to_dat   TYPE agr_tdate,          " Valid To Date
       END OF ty_user_role.

TYPES: tt_user_role TYPE STANDARD TABLE OF ty_user_role.

TYPES: BEGIN OF ty_check_value,
         field TYPE xufield,
         value TYPE xuval,
       END OF ty_check_value.
TYPES: tt_check_value TYPE STANDARD TABLE OF ty_check_value WITH DEFAULT KEY.

TYPES: BEGIN OF ty_missing_auth,
         sel         TYPE c LENGTH 1,         " Checkbox
         status      TYPE c LENGTH 4,         " Status Icon (@0A@ Red / @08@ Green)
         tcode       TYPE tstc-tcode,         " Transaction Code
         object      TYPE tobj-objct,         " Authorization Object
         object_text TYPE c LENGTH 60,        " Object Description
         combination TYPE string,             " Combination of Fields & Values
         fiel1       TYPE xufield,            " Field 1
         val01       TYPE xuval,              " Value 1
         fiel2       TYPE xufield,            " Field 2
         val02       TYPE xuval,              " Value 2
         fiel3       TYPE xufield,            " Field 3
         val03       TYPE xuval,              " Value 3
         filter_miss TYPE abap_bool,
         hits        TYPE i,
         role_detail TYPE string,
         planned     TYPE string,
         auto_values TYPE string,
         result      TYPE string,
         check_key   TYPE string,
         check_values TYPE tt_check_value,    " All SU53 field/value pairs
         subrc       TYPE sy-subrc,           " Return Code (sy-subrc)
         user_values TYPE string,             " Current Values in User Role
         check_time  TYPE string,             " Timestamp of Failed Check
         raw_time    TYPE timestampl,         " Raw Timestamp for Chronological Sort
         is_in_role  TYPE abap_bool,          " Already satisfied in Selected Role
         cell_style  TYPE lvc_t_styl,         " Cell style (enabled / disabled checkbox)
         cell_color  TYPE lvc_t_scol,         " Cell color
       END OF ty_missing_auth.

TYPES: tt_missing_auth TYPE STANDARD TABLE OF ty_missing_auth.

* Aggregation types for batch processing
TYPES: BEGIN OF ty_agg_val,
         field TYPE xufield,
         low   TYPE xuval,
       END OF ty_agg_val.

TYPES: tt_agg_val TYPE STANDARD TABLE OF ty_agg_val WITH DEFAULT KEY.

TYPES: BEGIN OF ty_agg_obj,
         object TYPE tobj-objct,
         values TYPE tt_agg_val,
       END OF ty_agg_obj.

TYPES: tt_agg_obj TYPE STANDARD TABLE OF ty_agg_obj WITH KEY object.

TYPES: BEGIN OF ty_usorg,
         field TYPE usorg-field,
         varbl TYPE usorg-varbl,
       END OF ty_usorg.
TYPES: tt_usorg TYPE HASHED TABLE OF ty_usorg WITH UNIQUE KEY field.

TYPES: BEGIN OF ty_org_val,
         varbl TYPE agr_1252-varbl,
         low   TYPE agr_1252-low,
       END OF ty_org_val.
TYPES: tt_org_val TYPE SORTED TABLE OF ty_org_val WITH UNIQUE KEY varbl low.

TYPES: tt_obj_name TYPE SORTED TABLE OF tobj-objct WITH UNIQUE KEY table_line.

TYPES: BEGIN OF ty_obj_field,
         object TYPE tobj-objct,
         field  TYPE xufield,
       END OF ty_obj_field.
TYPES: tt_obj_field TYPE HASHED TABLE OF ty_obj_field WITH UNIQUE KEY object field.

TYPES: tt_pt1250 TYPE STANDARD TABLE OF pt1250 WITH DEFAULT KEY.
TYPES: tt_pt1251 TYPE STANDARD TABLE OF pt1251 WITH DEFAULT KEY.
TYPES: tt_pt1252 TYPE STANDARD TABLE OF pt1252 WITH DEFAULT KEY.

TYPES: BEGIN OF ty_role_fld,
         object TYPE tobj-objct,
         auth   TYPE xuauth,
         field  TYPE xufield,
         low    TYPE xuval,
         high   TYPE xuval,
       END OF ty_role_fld.
TYPES: tt_role_fld TYPE STANDARD TABLE OF ty_role_fld WITH DEFAULT KEY.

TYPES: BEGIN OF ty_role_obj,
         object TYPE tobj-objct,
         auth   TYPE xuauth,
       END OF ty_role_obj.
TYPES: tt_role_obj TYPE STANDARD TABLE OF ty_role_obj WITH DEFAULT KEY.

TYPES: tt_tcode TYPE SORTED TABLE OF sytcode WITH UNIQUE KEY table_line.

TYPES: tt_fields TYPE STANDARD TABLE OF xufield WITH DEFAULT KEY.
TYPES: BEGIN OF ty_override,
         check_key TYPE string,
         field TYPE xufield,
         value TYPE xuval,
       END OF ty_override.
TYPES tt_override TYPE HASHED TABLE OF ty_override WITH UNIQUE KEY check_key field.
TYPES: BEGIN OF ty_log,
         stamp TYPE timestampl,
         actor TYPE syuname,
         role TYPE agr_name,
         step TYPE c LENGTH 25,
         severity TYPE c LENGTH 1,
         detail TYPE string,
       END OF ty_log.
TYPES tt_log TYPE STANDARD TABLE OF ty_log WITH DEFAULT KEY.
DATA: gv_log_text TYPE string,
      gv_last_error TYPE string,
      gt_override TYPE tt_override,
      gt_log TYPE tt_log,
      gv_trace_warning TYPE string,
      gv_profile_state TYPE string,
      gv_compare_state TYPE string,
      gv_maintenance_error TYPE abap_bool.
DATA: gt_missing_auth  TYPE tt_missing_auth,
      gt_user_roles    TYPE tt_user_role,
      gv_selected_role TYPE agr_name,
      gv_in_refresh    TYPE abap_bool,
      go_docking       TYPE REF TO cl_gui_docking_container,
      go_grid_roles    TYPE REF TO cl_gui_alv_grid,
      go_grid_auths    TYPE REF TO cl_gui_alv_grid.

CONSTANTS: gc_icon_red    TYPE c LENGTH 4 VALUE '@0A@',
           gc_icon_green  TYPE c LENGTH 4 VALUE '@08@',
           gc_icon_yellow TYPE c LENGTH 4 VALUE '@09@',
           gc_radio_on    TYPE c LENGTH 4 VALUE '@06@',
           gc_radio_off   TYPE c LENGTH 4 VALUE '@07@'.

*----------------------------------------------------------------------*
* 2. CLASS DEFINITIONS & EVENT HANDLERS
*----------------------------------------------------------------------*
CLASS lcl_event_handler DEFINITION.
  PUBLIC SECTION.
    METHODS:
      on_toolbar_roles FOR EVENT toolbar OF cl_gui_alv_grid
        IMPORTING e_object,
      on_user_command_roles FOR EVENT user_command OF cl_gui_alv_grid
        IMPORTING e_ucomm,
      on_hotspot_roles FOR EVENT hotspot_click OF cl_gui_alv_grid
        IMPORTING e_row_id e_column_id,
      on_double_click_roles FOR EVENT double_click OF cl_gui_alv_grid
        IMPORTING e_row e_column,
      on_hotspot_auths FOR EVENT hotspot_click OF cl_gui_alv_grid
        IMPORTING e_row_id e_column_id,
      on_double_click_auths FOR EVENT double_click OF cl_gui_alv_grid
        IMPORTING e_row e_column,
      on_before_command_auths FOR EVENT before_user_command OF cl_gui_alv_grid
        IMPORTING e_ucomm.
ENDCLASS.

DATA: go_event_handler TYPE REF TO lcl_event_handler.

*----------------------------------------------------------------------*
* 3. SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE title1.
  PARAMETERS: p_uname TYPE usr02-bname OBLIGATORY DEFAULT 'ROLE_TEST'.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE title2.
  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS: p_actv TYPE abap_bool DEFAULT 'X' AS CHECKBOX.
    SELECTION-SCREEN COMMENT 3(65) text_a.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b2.

*----------------------------------------------------------------------*
* 4. MAIN EVENTS
*----------------------------------------------------------------------*
INITIALIZATION.
  title1 = '1. User Selection'.
  title2 = '2. Filter Options'.
  text_a = 'Active Single Roles Only'.

AT SELECTION-SCREEN OUTPUT.
  IF go_docking IS BOUND.
    go_docking->free( ).
    FREE: go_docking, go_grid_roles, go_grid_auths.
  ENDIF.

START-OF-SELECTION.
  PERFORM validate_user.
  CLEAR: gt_override, gt_log, gv_profile_state, gv_compare_state.
  PERFORM get_user_roles USING p_uname p_actv.

  IF gt_user_roles IS NOT INITIAL.
    ASSIGN gt_user_roles[ 1 ] TO FIELD-SYMBOL(<ls_r_init>).
    IF sy-subrc = 0.
      gv_selected_role = <ls_r_init>-agr_name.
    ENDIF.
  ELSE.
    CLEAR gv_selected_role.
  ENDIF.

  " Set initial radio state
  LOOP AT gt_user_roles ASSIGNING FIELD-SYMBOL(<ls_r_sync>).
    IF <ls_r_sync>-agr_name = gv_selected_role.
      <ls_r_sync>-radio = gc_radio_on.
    ELSE.
      <ls_r_sync>-radio = gc_radio_off.
    ENDIF.
  ENDLOOP.

  PERFORM get_missing_authorizations USING p_uname.
  PERFORM eval_auths_for_role USING gv_selected_role.
  PERFORM display_alv_grid_lvc.

*----------------------------------------------------------------------*
* 5. SUBROUTINES: DATA EXTRACTION
*----------------------------------------------------------------------*
FORM add_su53_field USING pv_field TYPE xufield
                          pv_value TYPE xuval
                    CHANGING ct_values TYPE tt_check_value.
  IF pv_field IS INITIAL OR pv_field = 'dummyfield'.
    RETURN.
  ENDIF.
  APPEND VALUE ty_check_value( field = pv_field value = pv_value ) TO ct_values.
ENDFORM.

FORM fill_su53_check USING ps_su53 TYPE usr07_ext
                     CHANGING ct_values TYPE tt_check_value
                              cv_combination TYPE string
                              cv_f1 TYPE xufield
                              cv_v1 TYPE xuval
                              cv_f2 TYPE xufield
                              cv_v2 TYPE xuval
                              cv_f3 TYPE xufield
                              cv_v3 TYPE xuval.
  DATA ls_val TYPE ty_check_value.

  CLEAR: ct_values, cv_combination, cv_f1, cv_v1, cv_f2, cv_v2, cv_f3, cv_v3.

  PERFORM add_su53_field USING ps_su53-fiel1 ps_su53-val01 CHANGING ct_values.
  PERFORM add_su53_field USING ps_su53-fiel2 ps_su53-val02 CHANGING ct_values.
  PERFORM add_su53_field USING ps_su53-fiel3 ps_su53-val03 CHANGING ct_values.
  PERFORM add_su53_field USING ps_su53-fiel4 ps_su53-val04 CHANGING ct_values.
  PERFORM add_su53_field USING ps_su53-fiel5 ps_su53-val05 CHANGING ct_values.
  PERFORM add_su53_field USING ps_su53-fiel6 ps_su53-val06 CHANGING ct_values.
  PERFORM add_su53_field USING ps_su53-fiel7 ps_su53-val07 CHANGING ct_values.
  PERFORM add_su53_field USING ps_su53-fiel8 ps_su53-val08 CHANGING ct_values.
  PERFORM add_su53_field USING ps_su53-fiel9 ps_su53-val09 CHANGING ct_values.
  PERFORM add_su53_field USING ps_su53-fiel0 ps_su53-val10 CHANGING ct_values.

  LOOP AT ct_values INTO ls_val.
    IF cv_combination IS INITIAL.
      cv_combination = |{ ls_val-field } = '{ ls_val-value }'|.
    ELSE.
      cv_combination = |{ cv_combination }, { ls_val-field } = '{ ls_val-value }'|.
    ENDIF.
  ENDLOOP.
  IF cv_combination IS INITIAL.
    cv_combination = '<Full Object Check>'.
  ENDIF.

  SORT ct_values BY field value.
  DELETE ADJACENT DUPLICATES FROM ct_values COMPARING field value.

  READ TABLE ct_values INTO ls_val INDEX 1.
  IF sy-subrc = 0.
    cv_f1 = ls_val-field.
    cv_v1 = ls_val-value.
  ENDIF.
  READ TABLE ct_values INTO ls_val INDEX 2.
  IF sy-subrc = 0.
    cv_f2 = ls_val-field.
    cv_v2 = ls_val-value.
  ENDIF.
  READ TABLE ct_values INTO ls_val INDEX 3.
  IF sy-subrc = 0.
    cv_f3 = ls_val-field.
    cv_v3 = ls_val-value.
  ENDIF.
ENDFORM.

FORM get_missing_authorizations USING pv_uname TYPE usr02-bname.
  CLEAR: gt_missing_auth, gv_trace_warning.

  DATA: lt_usr07_ext TYPE usr07_ext_tt,
        ls_return    TYPE bapiret2,
        lt_rfc_err   TYPE bapirettab,
        lv_from      TYPE timestampl.

  " Check for SAP_ALL superuser
  SELECT profile FROM ust04
    WHERE bname = @pv_uname
    INTO TABLE @DATA(lt_usr_profs).

  DATA: lv_is_super TYPE abap_bool VALUE abap_false.
  IF line_exists( lt_usr_profs[ profile = 'SAP_ALL' ] ).
    lv_is_super = abap_true.
  ENDIF.

  " Same window as transaction SU53 (SAPMS01GNEW): last 3 hours,
  " capped by auth/su53_buffer_entries and at least 100 entries.
  DATA: lv_max_entries TYPE i VALUE 100,
        lv_param       TYPE c LENGTH 10.
  CONSTANTS lc_su53_seconds TYPE i VALUE 10800.

  CLEAR lv_param.
  CALL 'C_SAPGPARAM'
    ID 'NAME'  FIELD 'auth/su53_buffer_entries'
    ID 'VALUE' FIELD lv_param.
  IF sy-subrc = 0.
    CONDENSE lv_param NO-GAPS.
    IF lv_param CO '0123456789' AND lv_param IS NOT INITIAL.
      lv_max_entries = lv_param.
    ENDIF.
  ENDIF.
  IF lv_max_entries < 100.
    lv_max_entries = 100.
  ENDIF.

  GET TIME STAMP FIELD lv_from.
  TRY.
      cl_abap_tstmp=>subtractsecs(
        EXPORTING
          tstmp   = lv_from
          secs    = lc_su53_seconds
        RECEIVING
          r_tstmp = lv_from ).
    CATCH cx_parameter_invalid_range cx_parameter_invalid_type.
      GET TIME STAMP FIELD lv_from.
  ENDTRY.


  CALL FUNCTION 'SUSR_USER_SU53_READ'
    EXPORTING
      iv_bname              = pv_uname
      iv_from               = lv_from
      iv_all_servers        = 'X'
      iv_convert_app_name   = ' '
      iv_max_server_entries = lv_max_entries
    IMPORTING
      et_usr07_ext          = lt_usr07_ext
      es_return             = ls_return
      et_rfc_error          = lt_rfc_err.

  IF ls_return-type CA 'AEX'.
    gv_trace_warning = ls_return-message.
  ENDIF.
  IF lt_rfc_err IS NOT INITIAL.
    gv_trace_warning = |{ gv_trace_warning } SU53 data is incomplete: some servers could not be read.|.
  ENDIF.
  IF gv_trace_warning IS NOT INITIAL.
    PERFORM add_log USING 'SU53' 'W' gv_trace_warning.
    APPEND VALUE #( object = 'INFO' status = gc_icon_yellow
      object_text = 'SU53 read warning - do not interpret as no failures'
      combination = gv_trace_warning is_in_role = abap_true ) TO gt_missing_auth.
  ENDIF.

  IF lt_usr07_ext IS NOT INITIAL.
    SORT lt_usr07_ext BY timestamp DESCENDING instance ASCENDING.

    LOOP AT lt_usr07_ext INTO DATA(ls_su53).
      DATA: lv_f1 TYPE xufield, lv_v1 TYPE xuval,
            lv_f2 TYPE xufield, lv_v2 TYPE xuval,
            lv_f3 TYPE xufield, lv_v3 TYPE xuval,
            lt_check_values TYPE tt_check_value,
            lv_combination  TYPE string.

      PERFORM fill_su53_check USING ls_su53
                              CHANGING lt_check_values
                                       lv_combination
                                       lv_f1 lv_v1
                                       lv_f2 lv_v2
                                       lv_f3 lv_v3.

      DATA(lv_key) = |{ ls_su53-objct }/{ ls_su53-p_tcode }/{ ls_su53-rc }|.
      LOOP AT lt_check_values INTO DATA(ls_key_value).
        lv_key = |{ lv_key }/{ ls_key_value-field }:{ strlen( ls_key_value-value ) }:{ ls_key_value-value }|.
      ENDLOOP.
      READ TABLE gt_missing_auth ASSIGNING FIELD-SYMBOL(<ls_duplicate>) WITH KEY check_key = lv_key.
      IF sy-subrc = 0.
        <ls_duplicate>-hits = <ls_duplicate>-hits + 1.
        CONTINUE.
      ENDIF.

      DATA: lv_tcode TYPE tstc-tcode.
      lv_tcode = ls_su53-p_tcode.

      DATA lv_obj_text TYPE tobjt-ttext.
      CLEAR lv_obj_text.
      SELECT SINGLE ttext FROM tobjt
        WHERE langu = 'E' AND object = @ls_su53-objct
        INTO @lv_obj_text.
      IF sy-subrc <> 0.
        SELECT SINGLE ttext FROM tobjt
          WHERE langu = @sy-langu AND object = @ls_su53-objct
          INTO @lv_obj_text.
      ENDIF.

      DATA: lt_uvals TYPE STANDARD TABLE OF usvalues.
      CLEAR lt_uvals.
      CALL FUNCTION 'SUSR_USER_AUTH_FOR_OBJ_GET'
        EXPORTING
          user_name  = pv_uname
          sel_object = ls_su53-objct
        TABLES
          values     = lt_uvals
        EXCEPTIONS
          OTHERS     = 1.

      DATA(lv_user_read_rc) = sy-subrc.

      DATA: lv_time_str TYPE string.
      IF ls_su53-timestamp > 0.
        DATA: lv_tstmp_d TYPE d, lv_tstmp_t TYPE t.
        CONVERT TIME STAMP ls_su53-timestamp TIME ZONE sy-zonlo INTO DATE lv_tstmp_d TIME lv_tstmp_t.
        lv_time_str = |{ lv_tstmp_d DATE = USER } { lv_tstmp_t TIME = USER }|.
      ENDIF.

      " Build current user values string for checked fields
      DATA: lv_curr_str TYPE string.
      CLEAR lv_curr_str.

      IF lv_user_read_rc <> 0.
        lv_curr_str = '<User authorization values could not be read>'.
      ELSEIF lt_uvals IS INITIAL.
        lv_curr_str = '<Object NOT in any assigned Role>'.
      ELSE.
        LOOP AT lt_check_values INTO DATA(ls_cv).
          DATA(lv_cf) = ls_cv-field.
          DATA: lv_fld_vals TYPE string.
          CLEAR lv_fld_vals.
          LOOP AT lt_uvals INTO DATA(ls_u) WHERE field = lv_cf.
            IF ls_u-von = ls_u-bis OR ls_u-bis IS INITIAL.
              IF ls_u-von IS INITIAL.
                lv_fld_vals = |{ lv_fld_vals } ' '|.
              ELSE.
                lv_fld_vals = |{ lv_fld_vals } { ls_u-von }|.
              ENDIF.
            ELSE.
              lv_fld_vals = |{ lv_fld_vals } { ls_u-von }..{ ls_u-bis }|.
            ENDIF.
          ENDLOOP.

          IF lv_fld_vals IS INITIAL.
            lv_fld_vals = ' <None>'.
          ENDIF.

          IF lv_curr_str IS INITIAL.
            lv_curr_str = |{ lv_cf }:[{ lv_fld_vals+1 }]|.
          ELSE.
            lv_curr_str = |{ lv_curr_str }, { lv_cf }:[{ lv_fld_vals+1 }]|.
          ENDIF.
        ENDLOOP.
      ENDIF.

      APPEND VALUE #(
        sel         = ' '
        status      = gc_icon_red
        tcode       = lv_tcode
        object      = ls_su53-objct
        object_text = lv_obj_text
        combination = lv_combination
        fiel1       = lv_f1
        val01       = lv_v1
        fiel2       = lv_f2
        val02       = lv_v2
        fiel3       = lv_f3
        val03       = lv_v3
        hits        = 1
        check_key   = lv_key
        check_values = lt_check_values
        subrc       = ls_su53-rc
        user_values = lv_curr_str
        check_time  = lv_time_str
        raw_time    = ls_su53-timestamp
        is_in_role  = abap_false
      ) TO gt_missing_auth.
    ENDLOOP.

  ELSEIF gv_trace_warning IS INITIAL.
    IF lv_is_super = abap_true.
      APPEND VALUE #(
        sel         = ' '
        status      = gc_icon_green
        tcode       = 'ALL'
        object      = 'SAP_ALL'
        object_text = 'Superuser Profile'
        combination = 'Full System Authorization (SAP_ALL)'
        subrc       = 0
        user_values = 'All authorizations active'
        check_time  = ''
        is_in_role  = abap_true
      ) TO gt_missing_auth.
    ELSE.
      APPEND VALUE #(
        sel         = ' '
        status      = gc_icon_yellow
        tcode       = 'INFO'
        object      = 'INFO'
        object_text = 'SU53 buffer has no recorded authorization failures'
        combination = 'No recorded failures in the requested SU53 time window'
        subrc       = 0
        user_values = 'No errors'
        check_time  = ''
        is_in_role  = abap_true
      ) TO gt_missing_auth.
    ENDIF.
  ENDIF.
ENDFORM.

FORM get_user_roles USING pv_uname  TYPE usr02-bname
                          pv_active TYPE abap_bool.
  CLEAR: gt_user_roles.

  SELECT u~agr_name, t~text, u~from_dat, u~to_dat
    FROM agr_users AS u
    LEFT OUTER JOIN agr_texts AS t
      ON u~agr_name = t~agr_name
     AND t~spras = 'E'
     AND t~line  = '00000'
    WHERE u~uname = @pv_uname
    INTO TABLE @DATA(lt_roles).

  IF lt_roles IS INITIAL.
    SELECT u~agr_name, t~text, u~from_dat, u~to_dat
      FROM agr_users AS u
      LEFT OUTER JOIN agr_texts AS t
        ON u~agr_name = t~agr_name
       AND t~spras = @sy-langu
       AND t~line  = '00000'
      WHERE u~uname = @pv_uname
      INTO TABLE @lt_roles.
  ENDIF.

  LOOP AT lt_roles INTO DATA(ls_r).
    IF pv_active = abap_true.
      IF ls_r-from_dat > sy-datum OR ls_r-to_dat < sy-datum.
        CONTINUE.
      ENDIF.
    ENDIF.

    DATA: lv_coll TYPE char01, lv_inh TYPE agr_name.
    CLEAR: lv_coll, lv_inh.
    CALL FUNCTION 'PRGN_GET_COLLECTIVE_AGR_FLAG'
      EXPORTING
        activity_group      = ls_r-agr_name
      IMPORTING
        collective_agr_flag = lv_coll
        inh_role            = lv_inh
      EXCEPTIONS
        OTHERS              = 1.

    IF sy-subrc = 0 AND lv_coll = 'X'.
      CONTINUE.
    ENDIF.

    APPEND VALUE #(
      radio    = gc_radio_off
      agr_name = ls_r-agr_name
      text     = ls_r-text
      from_dat = ls_r-from_dat
      to_dat   = ls_r-to_dat
    ) TO gt_user_roles.
  ENDLOOP.

  SORT gt_user_roles BY agr_name.
ENDFORM.

*----------------------------------------------------------------------*
* 6. SUBROUTINES: ROLE EVALUATION & VALIDATION
*----------------------------------------------------------------------*
FORM eval_auths_for_role USING pv_role TYPE agr_name.
  DATA: lt_role_flds TYPE tt_role_fld, lt_role_objs TYPE tt_role_obj,
        lt_orgs TYPE tt_pt1252, lv_match TYPE abap_bool,
        lv_instance TYPE xuauth, lv_detail TYPE string,
        lt_values TYPE tt_check_value, lt_auto TYPE tt_check_value,
        lv_error TYPE string.
  IF pv_role IS NOT INITIAL.
    SELECT object, auth, field, low, high FROM agr_1251
      WHERE agr_name = @pv_role AND deleted = ' ' INTO TABLE @lt_role_flds.
    SELECT object, auth FROM agr_1250
      WHERE agr_name = @pv_role AND deleted = ' ' INTO TABLE @lt_role_objs.
    SELECT * FROM agr_1252 WHERE agr_name = @pv_role INTO CORRESPONDING FIELDS OF TABLE @lt_orgs.
    PERFORM resolve_org_values USING lt_orgs CHANGING lt_role_flds.
  ENDIF.
  LOOP AT gt_missing_auth ASSIGNING FIELD-SYMBOL(<row>).
    CLEAR: <row>-cell_style, <row>-cell_color, <row>-planned, <row>-auto_values.
    IF <row>-object = 'INFO' OR <row>-object = 'SAP_ALL'.
      <row>-is_in_role = abap_true.
      CLEAR <row>-sel.
    ELSE.
      CLEAR: lv_match, lv_instance, lv_detail.
      PERFORM check_covered USING lt_role_flds lt_role_objs <row>-object <row>-check_values
        CHANGING lv_match lv_instance lv_detail.
      <row>-is_in_role = lv_match.
      <row>-role_detail = lv_detail.
      IF lv_match = abap_true.
        <row>-status = gc_icon_green.
        CLEAR <row>-sel.
        <row>-role_detail = |Covered by { pv_role } / { lv_instance }|.
      ELSE.
        <row>-status = gc_icon_red.
        IF pv_role IS INITIAL.
          <row>-role_detail = 'No target role available'.
          CLEAR <row>-sel.
        ENDIF.
        PERFORM complete_check USING <row>-object <row>-check_values <row>-check_key
          CHANGING lt_values lt_auto lv_error.
        IF lv_error IS INITIAL.
          PERFORM values_text USING lt_values CHANGING <row>-planned.
          PERFORM values_text USING lt_auto CHANGING <row>-auto_values.
        ELSE.
          <row>-planned = lv_error.
        ENDIF.
      ENDIF.
    ENDIF.
    <row>-filter_miss = <row>-is_in_role.
    IF <row>-object = 'INFO' OR <row>-object = 'SAP_ALL'. CLEAR <row>-filter_miss. ENDIF.
    IF <row>-is_in_role = abap_true OR pv_role IS INITIAL.
      APPEND VALUE lvc_s_styl( fieldname = 'SEL' style = cl_gui_alv_grid=>mc_style_disabled ) TO <row>-cell_style.
    ELSE.
      APPEND VALUE lvc_s_styl( fieldname = 'SEL' style = cl_gui_alv_grid=>mc_style_enabled ) TO <row>-cell_style.
    ENDIF.
  ENDLOOP.
  PERFORM apply_missing_filter.
ENDFORM.

*----------------------------------------------------------------------*
* 7. SUBROUTINES: ALV GRID DISPLAY & DOCKING ARCHITECTURE
*----------------------------------------------------------------------*
FORM display_alv_grid_lvc.
  DATA: lt_fieldcat   TYPE lvc_t_fcat,
        ls_layout_lvc TYPE lvc_s_layo,
        lv_repid      TYPE sy-repid.

  lv_repid = sy-repid.

  APPEND VALUE #(
    fieldname = 'SEL'
    coltext   = 'Select'
    checkbox  = 'X'
    edit      = 'X'
    outputlen = 6
  ) TO lt_fieldcat.

  APPEND VALUE #(
    fieldname = 'STATUS'
    coltext   = 'Status'
    icon      = 'X'
    outputlen = 6
  ) TO lt_fieldcat.

  APPEND VALUE #(
    fieldname = 'TCODE'
    coltext   = 'Transaction'
    outputlen = 11
    emphasize = 'C300'
  ) TO lt_fieldcat.

  APPEND VALUE #(
    fieldname = 'OBJECT'
    coltext   = 'Auth Object'
    outputlen = 14
    hotspot   = 'X'
    emphasize = 'C500'
  ) TO lt_fieldcat.

  APPEND VALUE #(
    fieldname = 'OBJECT_TEXT'
    coltext   = 'Object Description'
    outputlen = 30
  ) TO lt_fieldcat.

  APPEND VALUE #(
    fieldname = 'SUBRC'
    coltext   = 'RC'
    outputlen = 5
  ) TO lt_fieldcat.

  APPEND VALUE #(
    fieldname = 'COMBINATION'
    coltext   = 'Checked Fields & Values'
    outputlen = 36
    emphasize = 'C600'
  ) TO lt_fieldcat.

  APPEND VALUE #(
    fieldname = 'FIEL1'
    coltext   = 'Field 1'
    outputlen = 10
  ) TO lt_fieldcat.

  APPEND VALUE #(
    fieldname = 'VAL01'
    coltext   = 'Value 1'
    outputlen = 10
  ) TO lt_fieldcat.

  APPEND VALUE #(
    fieldname = 'FIEL2'
    coltext   = 'Field 2'
    outputlen = 10
  ) TO lt_fieldcat.

  APPEND VALUE #(
    fieldname = 'VAL02'
    coltext   = 'Value 2'
    outputlen = 10
  ) TO lt_fieldcat.

  APPEND VALUE #(
    fieldname = 'FIEL3'
    coltext   = 'Field 3'
    outputlen = 10
  ) TO lt_fieldcat.

  APPEND VALUE #(
    fieldname = 'VAL03'
    coltext   = 'Value 3'
    outputlen = 10
  ) TO lt_fieldcat.

  APPEND VALUE #(
    fieldname = 'USER_VALUES'
    coltext   = 'Current User Values'
    outputlen = 35
  ) TO lt_fieldcat.

  APPEND VALUE #(
    fieldname = 'CHECK_TIME'
    coltext   = 'Trace Timestamp'
    outputlen = 18
  ) TO lt_fieldcat.

  APPEND VALUE #( fieldname = 'HITS' coltext = 'Occurrences' outputlen = 8 ) TO lt_fieldcat.
  APPEND VALUE #( fieldname = 'ROLE_DETAIL' coltext = 'Role Coverage / Missing Fields' outputlen = 45 ) TO lt_fieldcat.
  APPEND VALUE #( fieldname = 'PLANNED' coltext = 'Values to Add' outputlen = 45 ) TO lt_fieldcat.
  APPEND VALUE #( fieldname = 'AUTO_VALUES' coltext = 'Auto Completed / Expanded to *' outputlen = 35 ) TO lt_fieldcat.
  APPEND VALUE #( fieldname = 'FILTER_MISS' coltext = 'Hide covered' tech = 'X' ) TO lt_fieldcat.
  APPEND VALUE #( fieldname = 'RESULT' coltext = 'Last Apply Result' outputlen = 45 ) TO lt_fieldcat.
  ls_layout_lvc-zebra      = 'X'.
  ls_layout_lvc-cwidth_opt = 'X'.
  ls_layout_lvc-stylefname = 'CELL_STYLE'.
  ls_layout_lvc-ctab_fname = 'CELL_COLOR'.
  ls_layout_lvc-grid_title = '2. Failed Authorization Checks (Select Items via Checkbox to Add to Target Role)'.

  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY_LVC'
    EXPORTING
      i_callback_program       = lv_repid
      i_callback_pf_status_set = 'SET_PF_STATUS'
      i_callback_user_command  = 'HANDLE_USER_COMMAND'
      is_layout_lvc            = ls_layout_lvc
      it_fieldcat_lvc          = lt_fieldcat
    TABLES
      t_outtab                 = gt_missing_auth
    EXCEPTIONS
      program_error            = 1
      OTHERS                   = 2.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  SET_PF_STATUS
*&---------------------------------------------------------------------*
FORM set_pf_status USING rt_extab TYPE slis_t_extab.
  DATA: lo_grid TYPE REF TO cl_gui_alv_grid.

  CALL FUNCTION 'GET_GLOBALS_FROM_SLVC_FULLSCR'
    IMPORTING
      e_grid = lo_grid.

  IF lo_grid IS BOUND.
    go_grid_auths = lo_grid.
    IF go_event_handler IS INITIAL.
      CREATE OBJECT go_event_handler.
    ENDIF.
    SET HANDLER go_event_handler->on_hotspot_auths FOR go_grid_auths.
    SET HANDLER go_event_handler->on_double_click_auths FOR go_grid_auths.
    SET HANDLER go_event_handler->on_before_command_auths FOR go_grid_auths.
    go_grid_auths->register_edit_event( cl_gui_alv_grid=>mc_evt_modified ).
    PERFORM apply_missing_filter.
  ENDIF.

  " Create Docking Container for Single Roles (Top Area)
  IF go_docking IS INITIAL.
    CREATE OBJECT go_docking
      EXPORTING
        side      = cl_gui_docking_container=>dock_at_top
        extension = 175
      EXCEPTIONS
        OTHERS    = 1.

    IF sy-subrc = 0.
      CREATE OBJECT go_grid_roles
        EXPORTING
          i_parent = go_docking.

      IF go_event_handler IS INITIAL.
        CREATE OBJECT go_event_handler.
      ENDIF.

      SET HANDLER go_event_handler->on_toolbar_roles FOR go_grid_roles.
      SET HANDLER go_event_handler->on_user_command_roles FOR go_grid_roles.
      SET HANDLER go_event_handler->on_hotspot_roles FOR go_grid_roles.
      SET HANDLER go_event_handler->on_double_click_roles FOR go_grid_roles.

      DATA: lt_fcat_roles TYPE lvc_t_fcat.
      APPEND VALUE #( fieldname = 'RADIO'    coltext = 'Target Role' icon = 'X' hotspot = 'X' outputlen = 12 ) TO lt_fcat_roles.
      APPEND VALUE #( fieldname = 'AGR_NAME' coltext = 'Single Role Name' outputlen = 25 emphasize = 'C400' ) TO lt_fcat_roles.
      APPEND VALUE #( fieldname = 'TEXT'     coltext = 'Role Description' outputlen = 40 ) TO lt_fcat_roles.
      APPEND VALUE #( fieldname = 'FROM_DAT' coltext = 'Valid From' outputlen = 12 ) TO lt_fcat_roles.
      APPEND VALUE #( fieldname = 'TO_DAT'   coltext = 'Valid To' outputlen = 12 ) TO lt_fcat_roles.

      DATA: ls_layo_roles TYPE lvc_s_layo.
      ls_layo_roles-zebra      = 'X'.
      ls_layo_roles-cwidth_opt = 'X'.
      ls_layo_roles-grid_title = '1. Assigned Single Roles of User (Click Radio Icon to Select Target Single Role)'.

      DATA: lt_excl TYPE ui_functions.
      APPEND cl_gui_alv_grid=>mc_fc_print TO lt_excl.
      APPEND cl_gui_alv_grid=>mc_fc_graph TO lt_excl.
      APPEND cl_gui_alv_grid=>mc_fc_views TO lt_excl.
      APPEND cl_gui_alv_grid=>mc_fc_info  TO lt_excl.
      APPEND cl_gui_alv_grid=>mc_fc_check TO lt_excl.

      go_grid_roles->set_table_for_first_display(
        EXPORTING
          is_layout            = ls_layo_roles
          it_toolbar_excluding = lt_excl
        CHANGING
          it_fieldcatalog      = lt_fcat_roles
          it_outtab            = gt_user_roles
      ).
    ENDIF.
  ENDIF.

  SET PF-STATUS 'STANDARD_FULLSCREEN' OF PROGRAM 'SAPLSLVC_FULLSCREEN' EXCLUDING rt_extab.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  HANDLE_USER_COMMAND
*&---------------------------------------------------------------------*
FORM handle_user_command USING r_ucomm     LIKE sy-ucomm
                                rs_selfield TYPE slis_selfield.
  IF go_grid_auths IS BOUND.
    go_grid_auths->check_changed_data( ).
  ENDIF.

  CASE r_ucomm.
    WHEN '&IC1'. " Double-Click
      READ TABLE gt_missing_auth INTO DATA(ls_m) INDEX rs_selfield-tabindex.
      IF sy-subrc = 0 AND ls_m-object IS NOT INITIAL AND ls_m-object <> 'SAP_ALL' AND ls_m-object <> 'INFO'.
        SET PARAMETER ID 'SUS' FIELD ls_m-object.
        CALL TRANSACTION 'SU03' AND SKIP FIRST SCREEN.
      ENDIF.

    WHEN '&REFRESH' OR 'REFRESH' OR '&F8' OR 'F8'.
      PERFORM refresh_all_data.
      rs_selfield-refresh = 'X'.

    WHEN 'ADD_ROLE'.
      PERFORM add_selected_auths_to_role.
      "Also re-evaluate a partially saved menu if a later step failed.
      "Never reload SU53 here: retain every displayed trace row.
      PERFORM eval_auths_for_role USING gv_selected_role.
      PERFORM refresh_grids.
      rs_selfield-refresh = 'X'.

    WHEN 'SEL_ALL'.
      LOOP AT gt_missing_auth ASSIGNING FIELD-SYMBOL(<ls_a>).
        IF <ls_a>-is_in_role = abap_false.
          <ls_a>-sel = 'X'.
        ENDIF.
      ENDLOOP.
      IF go_grid_auths IS BOUND.
        go_grid_auths->refresh_table_display( is_stable = VALUE #( row = 'X' col = 'X' ) ).
      ENDIF.

    WHEN 'DESEL_ALL'.
      LOOP AT gt_missing_auth ASSIGNING FIELD-SYMBOL(<ls_d>).
        <ls_d>-sel = ' '.
      ENDLOOP.
      IF go_grid_auths IS BOUND.
        go_grid_auths->refresh_table_display( is_stable = VALUE #( row = 'X' col = 'X' ) ).
      ENDIF.
  ENDCASE.
ENDFORM.

*----------------------------------------------------------------------*
* 8. SUBROUTINES: BATCH AGGREGATION & ROLE INJECTION VIA FMS
*----------------------------------------------------------------------*
FORM add_selected_auths_to_role.
  DATA: lv_ok TYPE abap_bool, lv_saved TYPE abap_bool,
        lv_failed TYPE abap_bool, lv_error TYPE string,
        lv_objects TYPE i, lv_values TYPE i, lv_counter TYPE i,
        lv_auth TYPE xuauth, lv_covered TYPE abap_bool, lv_instance TYPE xuauth,
        lv_detail TYPE string, lv_rc TYPE sy-subrc, lv_menu_added TYPE i,
        lv_menu_failed TYPE i, lv_abort TYPE abap_bool, lv_menu_text TYPE string,
        lt_selected TYPE tt_missing_auth, lt_tcodes TYPE tt_tcode,
        lt_auth TYPE tt_pt1250, lt_fields TYPE tt_pt1251,
        lt_eval_fields TYPE tt_role_fld, lt_eval_objs TYPE tt_role_obj,
        lt_orgs TYPE tt_pt1252, lt_complete TYPE tt_check_value,
        lt_auto TYPE tt_check_value, lt_new_fields TYPE tt_pt1251,
        lt_new_nodes TYPE tt_role_obj.
  CLEAR gv_last_error.
  IF go_grid_auths IS BOUND. go_grid_auths->check_changed_data( ). ENDIF.
  PERFORM validate_target CHANGING lv_ok.
  IF lv_ok = abap_false. RETURN. ENDIF.
  LOOP AT gt_missing_auth INTO DATA(ls_item) WHERE sel = 'X' AND is_in_role = abap_false.
    IF ls_item-object <> 'INFO' AND ls_item-object <> 'SAP_ALL'. APPEND ls_item TO lt_selected. ENDIF.
  ENDLOOP.
  IF lt_selected IS INITIAL.
    MESSAGE 'Select missing checks first.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.
  "Validate every tuple before starting any operation that may commit.
  LOOP AT lt_selected INTO ls_item.
    PERFORM complete_check USING ls_item-object ls_item-check_values ls_item-check_key
      CHANGING lt_complete lt_auto lv_error.
    IF lv_error IS NOT INITIAL. MESSAGE lv_error TYPE 'S' DISPLAY LIKE 'E'. RETURN. ENDIF.
    IF ls_item-object = 'S_TCODE'.
      READ TABLE lt_complete INTO DATA(ls_tcode) WITH KEY field = 'TCD'.
      IF sy-subrc <> 0 OR ls_tcode-value IS INITIAL OR ls_tcode-value CA '*+'.
        MESSAGE 'S_TCODE requires a concrete transaction from SU53; wildcard or blank is not supported.' TYPE 'S' DISPLAY LIKE 'E'. RETURN.
      ENDIF.
      SELECT SINGLE tcode FROM tstc WHERE tcode = @ls_tcode-value INTO @DATA(lv_existing_tcode).
      IF sy-subrc <> 0.
        MESSAGE 'Proposed transaction does not exist in TSTC' TYPE 'S' DISPLAY LIKE 'E'. RETURN.
      ENDIF.
        PERFORM collect_menu_tcode USING 'TCD' ls_tcode-value CHANGING lt_tcodes.
      IF lt_tcodes IS INITIAL.
        MESSAGE 'S_TCODE needs a concrete transaction; wildcard/blank menu entries are not supported.' TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
    ELSE.
      PERFORM complete_check USING ls_item-object ls_item-check_values ls_item-check_key
        CHANGING lt_complete lt_auto lv_error.
      IF lv_error IS NOT INITIAL. MESSAGE lv_error TYPE 'S' DISPLAY LIKE 'E'. RETURN. ENDIF.
    ENDIF.
  ENDLOOP.
  gv_profile_state = 'Pending'. gv_compare_state = 'Pending'.
  IF lt_tcodes IS NOT INITIAL.
    PERFORM add_tcodes_to_role_menu USING gv_selected_role
      CHANGING lt_tcodes lv_menu_added lv_menu_failed lv_menu_text lv_abort.
    IF lv_abort = abap_true OR lv_menu_failed > 0.
      ROLLBACK WORK.
      PERFORM add_log USING 'MENU' 'E' lv_menu_text.
      MESSAGE |Menu failed: { lv_menu_text }. Earlier menu commits may remain.| TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    COMMIT WORK AND WAIT.
    IF sy-subrc <> 0.
      PERFORM add_log USING 'MENU' 'E' 'Menu update task failed'.
      MESSAGE 'Menu update task failed; check PFCG before retrying.' TYPE 'S' DISPLAY LIKE 'E'. RETURN.
    ENDIF.
    PERFORM add_log USING 'MENU' 'S' 'Transactions added. Merge and complete all active open fields/org levels with *.'.
    PERFORM merge_menu USING gv_selected_role CHANGING lv_rc.
    IF lv_rc <> 0.
      MESSAGE |Menu saved, merge failed: { gv_last_error }. Check PFCG.| TYPE 'S' DISPLAY LIKE 'E'. RETURN.
    ENDIF.
  ENDIF.
  CLEAR gv_maintenance_error.
  CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE' EXPORTING activity_group = gv_selected_role
    EXCEPTIONS foreign_lock = 1 system_failure = 2 OTHERS = 3.
  IF sy-subrc <> 0.
    PERFORM add_log USING 'LOCK' 'E' 'Role could not be locked; earlier menu changes may already be saved'.
    MESSAGE 'Cannot lock role. Close PFCG edit mode and retry; earlier menu changes may remain.' TYPE 'S' DISPLAY LIKE 'E'. RETURN.
  ENDIF.
  TRY.
      CALL FUNCTION 'PRGN_1250_READ_AUTH_DATA' EXPORTING activity_group = gv_selected_role
        TABLES auth_data = lt_auth EXCEPTIONS no_data_available = 1 OTHERS = 2.
      IF sy-subrc > 1. lv_error = 'Cannot read role authorization headers'. ENDIF.
      CALL FUNCTION 'PRGN_1251_READ_FIELD_VALUES' EXPORTING activity_group = gv_selected_role
        TABLES field_values = lt_fields EXCEPTIONS no_data_available = 1 OTHERS = 2.
      IF sy-subrc > 1. lv_error = 'Cannot read role field values'. ENDIF.
      SELECT * FROM agr_1252 WHERE agr_name = @gv_selected_role INTO CORRESPONDING FIELDS OF TABLE @lt_orgs.
      IF lv_error IS INITIAL.
        "Tcode Add follows Z_AUTH_TEST: complete ALL active open entries,
        "including entries that existed before this menu update.
        IF lt_tcodes IS NOT INITIAL.
          PERFORM complete_open_values CHANGING lt_auth lt_fields lt_orgs lv_values lv_error.
        ENDIF.
      ENDIF.
      IF lv_error IS INITIAL.
        PERFORM make_eval_tables USING lt_auth lt_fields lt_orgs CHANGING lt_eval_objs lt_eval_fields.
        LOOP AT lt_selected INTO ls_item.
          IF ls_item-object = 'S_TCODE'. CONTINUE. ENDIF.
          PERFORM complete_check USING ls_item-object ls_item-check_values ls_item-check_key
            CHANGING lt_complete lt_auto lv_error.
          IF lv_error IS NOT INITIAL. EXIT. ENDIF.
          "Check the complete, possibly edited tuple, not just the original trace.
          PERFORM check_covered USING lt_eval_fields lt_eval_objs ls_item-object lt_complete
            CHANGING lv_covered lv_instance lv_detail.
          IF lv_covered = abap_true.
            gv_log_text = |{ ls_item-object }: complete tuple already covered by { lv_instance }|.
    PERFORM add_log USING 'SKIP' 'S' gv_log_text.
            CONTINUE.
          ENDIF.
          PERFORM new_auth_name USING ls_item-object lt_auth CHANGING lv_counter lv_auth lv_error.
          IF lv_error IS NOT INITIAL. EXIT. ENDIF.
          APPEND VALUE #( object = ls_item-object auth = lv_auth modified = 'U' neu = 'X'
            deleted = ' ' atext = ls_item-object_text ) TO lt_auth.
          APPEND VALUE #( object = ls_item-object auth = lv_auth ) TO lt_new_nodes.
          LOOP AT lt_complete INTO DATA(ls_value).
            "Org fields are authorization-specific literals, never globalized.
            "This retains complete tuples instead of creating cross-products across org levels.
            APPEND VALUE #( object = ls_item-object auth = lv_auth field = ls_value-field
              low = ls_value-value modified = 'U' neu = 'X' deleted = ' ' ) TO lt_fields.
            lv_values = lv_values + 1.
          ENDLOOP.
          PERFORM initialize_new_orgs USING lt_complete CHANGING lt_orgs.
          lv_objects = lv_objects + 1.
          PERFORM values_text USING lt_complete CHANGING lv_detail.
          gv_log_text = |{ ls_item-object }/{ lv_auth }: { lv_detail }|.
    PERFORM add_log USING 'ADD INSTANCE' 'S' gv_log_text.
          PERFORM make_eval_tables USING lt_auth lt_fields lt_orgs CHANGING lt_eval_objs lt_eval_fields.
        ENDLOOP.
        IF lv_error IS INITIAL.
          PERFORM combine_nodes USING lt_orgs CHANGING lt_auth lt_fields lt_new_nodes.
        ENDIF.
      ENDIF.
      IF lv_error IS INITIAL AND ( lv_objects > 0 OR lv_values > 0 ).
        CALL FUNCTION 'PRGN_1250_SAVE_AUTH_DATA' EXPORTING activity_group = gv_selected_role
          TABLES auth_data = lt_auth EXCEPTIONS OTHERS = 1.
        IF sy-subrc <> 0. lv_error = 'Cannot stage role authorization headers'. ENDIF.
        IF lv_error IS INITIAL.
          CALL FUNCTION 'PRGN_1252_SAVE_ORG_LEVELS' EXPORTING activity_group = gv_selected_role
            TABLES org_levels = lt_orgs EXCEPTIONS OTHERS = 1.
          IF sy-subrc <> 0. lv_error = 'Cannot stage organizational levels'. ENDIF.
        ENDIF.
        IF lv_error IS INITIAL.
          CALL FUNCTION 'PRGN_1251_SAVE_FIELD_VALUES' EXPORTING activity_group = gv_selected_role
            TABLES field_values = lt_fields EXCEPTIONS OTHERS = 1.
          IF sy-subrc <> 0. lv_error = 'Cannot stage role field values'. ENDIF.
        ENDIF.
        IF lv_error IS INITIAL.
          CALL FUNCTION 'PRGN_UPDATE_DATABASE' EXCEPTIONS OTHERS = 1.
          IF sy-subrc <> 0. lv_error = 'Role database update failed'.
          ELSE.
            COMMIT WORK AND WAIT.
            IF sy-subrc <> 0. lv_error = 'Role update task failed'. ELSE. lv_saved = abap_true. ENDIF.
          ENDIF.
        ENDIF.
      ELSEIF lv_error IS INITIAL.
        lv_saved = abap_true.
      ENDIF.
    CATCH cx_root INTO DATA(lx_error).
      lv_error = lx_error->get_text( ).
  ENDTRY.
  IF lv_error IS NOT INITIAL. ROLLBACK WORK. ENDIF.
  CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE' EXPORTING activity_group = gv_selected_role.
  IF lv_error IS NOT INITIAL.
    PERFORM add_log USING 'SAVE' 'E' lv_error.
    PERFORM eval_auths_for_role USING gv_selected_role.
    PERFORM refresh_grids.
    MESSAGE lv_error TYPE 'S' DISPLAY LIKE 'E'. RETURN.
  ENDIF.
  gv_log_text = |Saved { lines( lt_new_nodes ) } new node(s) after combining { lv_objects } checks; { lv_values } values processed.|.
    PERFORM add_log USING 'SAVE' 'S' gv_log_text.
  DATA(lv_complete_open) = xsdbool( lt_tcodes IS NOT INITIAL ).
  PERFORM generate_role_profile USING gv_selected_role ' ' lv_complete_open abap_false CHANGING lv_rc.
  IF lv_rc = 0.
    PERFORM compare_role_users USING gv_selected_role CHANGING lv_rc.
  ENDIF.
  IF gv_compare_state = 'Compared'. PERFORM refresh_user_values. ENDIF.
  PERFORM eval_auths_for_role USING gv_selected_role.
  LOOP AT gt_missing_auth ASSIGNING FIELD-SYMBOL(<result>).
    IF line_exists( lt_selected[ check_key = <result>-check_key ] ).
      <result>-result = |Saved; profile: { gv_profile_state }; user comparison: { gv_compare_state }|.
      IF <result>-is_in_role = abap_true. CLEAR <result>-sel. ENDIF.
    ENDIF.
  ENDLOOP.
  PERFORM refresh_grids.
  IF lv_rc = 0.
    MESSAGE 'Role saved, profile generated, users compared. Re-test in a fresh user session; green means role coverage.' TYPE 'S'.
  ELSE.
    MESSAGE 'Role saved; generation/user comparison incomplete. Check role open fields and generation messages in PFCG.' TYPE 'S' DISPLAY LIKE 'W'.
  ENDIF.
ENDFORM.

*----------------------------------------------------------------------*
* Selected values, organizational levels, role menu
*----------------------------------------------------------------------*
FORM collect_menu_tcode USING pv_field TYPE xufield
                              pv_value TYPE xuval
                        CHANGING ct_tcodes TYPE tt_tcode.
  DATA lv_tcode TYPE sytcode.

  IF pv_value IS INITIAL.
    RETURN.
  ENDIF.
  IF pv_field IS NOT INITIAL AND pv_field <> 'TCD'.
    RETURN.
  ENDIF.
  IF pv_value CA '*+'.
    RETURN.
  ENDIF.

  lv_tcode = pv_value.
  CONDENSE lv_tcode.
  TRANSLATE lv_tcode TO UPPER CASE.
  IF lv_tcode IS INITIAL.
    RETURN.
  ENDIF.

  INSERT lv_tcode INTO TABLE ct_tcodes.
ENDFORM.

FORM add_tcodes_to_role_menu USING pv_role TYPE agr_name
                             CHANGING ct_tcodes    TYPE tt_tcode
                                      cv_added     TYPE i
                                      cv_failed    TYPE i
                                      cv_failed_txt TYPE string
                                      cv_abort     TYPE abap_bool.
  DATA: lv_tcode  TYPE sytcode,
        lt_return TYPE bapirettab.

  CLEAR: cv_added, cv_failed, cv_failed_txt, cv_abort.

  LOOP AT ct_tcodes INTO lv_tcode.
    CLEAR lt_return.
    CALL FUNCTION 'PRGN_RFC_ADD_TRANSACTION'
      EXPORTING
        activity_group                = pv_role
        tcode                         = lv_tcode
        no_dialog                     = 'X'
      TABLES
        return                        = lt_return
      EXCEPTIONS
        activity_group_enqueued       = 1
        activity_group_does_not_exist = 2
        namespace_problem             = 3
        tcodes_inherited_from_parent  = 4
        illegal_tcode                 = 5
        not_authorized                = 6
        profgen_tables_not_updated    = 7
        OTHERS                        = 8.
    DATA(lv_menu_rc) = sy-subrc.
    DATA lv_return_error TYPE abap_bool.
    PERFORM log_returns USING 'MENU' lt_return CHANGING lv_return_error.
    IF lv_menu_rc = 0 AND lv_return_error = abap_false.
      cv_added = cv_added + 1.
    ELSE.
      cv_failed = cv_failed + 1.
      cv_failed_txt = |{ cv_failed_txt } { lv_tcode }|.
      " Lock, missing role, derived menu, or missing authority blocks the whole add.
      IF lv_menu_rc = 1 OR lv_menu_rc = 2 OR lv_menu_rc = 4 OR lv_menu_rc = 6 OR lv_return_error = abap_true.
        cv_abort = abap_true.
        IF lv_menu_rc = 1.
          MESSAGE |Role { pv_role } is locked (Edit mode). Please exit Edit mode in PFCG first, then try again.| TYPE 'S' DISPLAY LIKE 'E'.
        ELSE.
          MESSAGE |Cannot add transaction { lv_tcode } to the menu of role { pv_role }.| TYPE 'S' DISPLAY LIKE 'E'.
        ENDIF.
        RETURN.
      ENDIF.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM generate_role_profile USING pv_role TYPE agr_name pv_rebuild TYPE char01
  pv_all_maintained TYPE abap_bool pv_caller_locked TYPE abap_bool CHANGING cv_subrc TYPE sy-subrc.
  DATA: lt_return TYPE bapirettab, lv_error TYPE abap_bool.
  CLEAR cv_subrc.
  CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE' EXPORTING activity_group = pv_role EXCEPTIONS OTHERS = 1.
  IF sy-subrc <> 0.
    cv_subrc = 10. gv_profile_state = 'Locked'.
    PERFORM add_log USING 'GENERATE' 'E' 'Role is locked; generation was not attempted'. RETURN.
  ENDIF.
  TRY.
  CALL FUNCTION 'SUPRN_DARK_MANIPULATE_PROFILE'
    EXPORTING activity_group = pv_role fill_orgs_with_star = pv_all_maintained
      fill_fields_with_star = pv_all_maintained no_dialog = 'X' rebuild_auth_data = pv_rebuild generate_profile = 'X'
    IMPORTING return = lt_return
    EXCEPTIONS open_auths = 1 no_auth_for_gen = 2 no_auths = 3
      error_when_generating_profile = 4 OTHERS = 5.
  cv_subrc = sy-subrc.
  PERFORM log_returns USING 'GENERATE' lt_return CHANGING lv_error.
  IF lv_error = abap_true AND cv_subrc = 0. cv_subrc = 8. ENDIF.
  IF cv_subrc = 0.
    COMMIT WORK AND WAIT.
    IF sy-subrc <> 0. cv_subrc = 9. ENDIF.
  ENDIF.
    CATCH cx_root INTO DATA(lx_generation).
      cv_subrc = 11.
      gv_log_text = lx_generation->get_text( ).
      PERFORM add_log USING 'GENERATE' 'E' gv_log_text.
  ENDTRY.
  CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE' EXPORTING activity_group = pv_role.
  IF cv_subrc = 0.
    gv_profile_state = 'Generated'.
    PERFORM add_log USING 'GENERATE' 'S' 'Profile generation completed'.
  ELSE.
    gv_profile_state = |Failed: { gv_last_error }|.
    gv_log_text = |Generation return code { cv_subrc }. Role data may be saved; check PFCG generation messages.|.
    PERFORM add_log USING 'GENERATE' 'E' gv_log_text.
  ENDIF.
ENDFORM.

FORM field_value_covered USING pt_flds TYPE tt_role_fld pv_object TYPE tobj-objct
  pv_auth TYPE xuauth pv_field TYPE xufield pv_value TYPE xuval CHANGING cv_covered TYPE abap_bool.
  cv_covered = abap_false.
  LOOP AT pt_flds INTO DATA(ls_fld) WHERE object = pv_object AND auth = pv_auth AND field = pv_field.
    IF ls_fld-low = '*' OR ls_fld-low = pv_value.
      cv_covered = abap_true. RETURN.
    ENDIF.
    IF ls_fld-high IS INITIAL AND ls_fld-low CS '*'.
      PERFORM star_matches USING ls_fld-low pv_value CHANGING cv_covered.
      IF cv_covered = abap_true. RETURN. ENDIF.
    ELSEIF ls_fld-high IS NOT INITIAL AND ls_fld-low IS NOT INITIAL
      AND pv_value >= ls_fld-low AND pv_value <= ls_fld-high.
      cv_covered = abap_true. RETURN.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM refresh_user_values.
  TYPES tt_uvalues TYPE STANDARD TABLE OF usvalues WITH DEFAULT KEY.
  DATA: lt_objects TYPE tt_obj_name, lt_values TYPE tt_uvalues,
        lv_text TYPE string, lv_values TYPE string, lv_rc TYPE sy-subrc.
  LOOP AT gt_missing_auth INTO DATA(ls_row).
    IF ls_row-object <> 'INFO' AND ls_row-object <> 'SAP_ALL'.
      INSERT ls_row-object INTO TABLE lt_objects.
    ENDIF.
  ENDLOOP.
  LOOP AT lt_objects INTO DATA(lv_object).
    CLEAR lt_values.
    CALL FUNCTION 'SUSR_USER_AUTH_FOR_OBJ_GET'
      EXPORTING user_name = p_uname sel_object = lv_object
      TABLES values = lt_values EXCEPTIONS OTHERS = 1.
    lv_rc = sy-subrc.
    LOOP AT gt_missing_auth ASSIGNING FIELD-SYMBOL(<row>) WHERE object = lv_object.
      CLEAR lv_text.
      IF lv_rc <> 0. lv_text = '<User authorization values could not be read>'.
      ELSEIF lt_values IS INITIAL. lv_text = '<Object NOT in any assigned Role>'.
      ELSE.
        LOOP AT <row>-check_values INTO DATA(ls_check).
          CLEAR lv_values.
          LOOP AT lt_values INTO DATA(ls_value) WHERE field = ls_check-field.
            IF ls_value-bis IS INITIAL OR ls_value-von = ls_value-bis.
              lv_values = |{ lv_values } { ls_value-von }|.
            ELSE. lv_values = |{ lv_values } { ls_value-von }..{ ls_value-bis }|. ENDIF.
          ENDLOOP.
          IF lv_values IS INITIAL. lv_values = ' <None>'. ENDIF.
          IF lv_text IS NOT INITIAL. lv_text = |{ lv_text }, |. ENDIF.
          lv_text = |{ lv_text }{ ls_check-field }:[{ lv_values+1 }]|.
        ENDLOOP.
      ENDIF.
      <row>-user_values = lv_text.
    ENDLOOP.
  ENDLOOP.
ENDFORM.

FORM refresh_all_data.
  IF gv_in_refresh = abap_true. RETURN. ENDIF.
  gv_in_refresh = abap_true.
  DATA lt_selected TYPE tt_missing_auth.
  LOOP AT gt_missing_auth INTO DATA(ls_old) WHERE sel = 'X'.
    APPEND ls_old TO lt_selected.
  ENDLOOP.
  PERFORM get_user_roles USING p_uname p_actv.
  IF NOT line_exists( gt_user_roles[ agr_name = gv_selected_role ] ).
    IF gt_user_roles IS NOT INITIAL. gv_selected_role = gt_user_roles[ 1 ]-agr_name.
    ELSE. CLEAR gv_selected_role. ENDIF.
  ENDIF.
  LOOP AT gt_user_roles ASSIGNING FIELD-SYMBOL(<role>).
    <role>-radio = COND #( WHEN <role>-agr_name = gv_selected_role THEN gc_radio_on ELSE gc_radio_off ).
  ENDLOOP.
  PERFORM get_missing_authorizations USING p_uname.
  LOOP AT gt_missing_auth ASSIGNING FIELD-SYMBOL(<row>).
    IF line_exists( lt_selected[ check_key = <row>-check_key ] ). <row>-sel = 'X'. ENDIF.
  ENDLOOP.
  PERFORM eval_auths_for_role USING gv_selected_role.
  PERFORM refresh_grids.
  gv_in_refresh = abap_false.
  IF gv_trace_warning IS NOT INITIAL.
    MESSAGE gv_trace_warning TYPE 'S' DISPLAY LIKE 'W'.
  ELSE.
    MESSAGE 'SU53 refreshed; duplicate failures grouped. Green means role coverage only.' TYPE 'S'.
  ENDIF.
ENDFORM.

*----------------------------------------------------------------------*
* 9. SUBROUTINES: EVENT HANDLER IMPLEMENTATION
*----------------------------------------------------------------------*
CLASS lcl_event_handler IMPLEMENTATION.
  METHOD on_toolbar_roles.
    DATA: lt_btn TYPE ttb_button.

    CLEAR lt_btn.

    APPEND VALUE stb_button(
      function  = 'ADD_ROLE'
      icon      = '@0Y@'
      text      = 'Add to Role'
      quickinfo = 'Batch add selected authorizations to target Single Role'
    ) TO lt_btn.

    APPEND VALUE stb_button(
      butn_type = 3 " Separator
    ) TO lt_btn.

    APPEND VALUE stb_button(
      function  = 'SEL_ALL'
      icon      = '@4B@'
      text      = 'Select All'
      quickinfo = 'Select all available missing authorizations'
    ) TO lt_btn.

    APPEND VALUE stb_button(
      function  = 'DESEL_ALL'
      icon      = '@4D@'
      text      = 'Deselect All'
      quickinfo = 'Deselect all'
    ) TO lt_btn.

    APPEND VALUE stb_button(
      function  = 'REFRESH'
      icon      = '@42@'
      text      = 'Refresh from SU53'
      quickinfo = 'Reload SU53 buffer and role values'
    ) TO lt_btn.

    INSERT LINES OF lt_btn INTO e_object->mt_toolbar INDEX 1.
  ENDMETHOD.

  METHOD on_user_command_roles.
    " Forward ALL toolbar commands to the fullscreen ALV PAI via set_new_ok_code.
    " Executing grid refresh from inside the grid's own event handler
    " (triggered during cl_gui_cfw=>dispatch) causes silent failures.
    CASE e_ucomm.
      WHEN 'ADD_ROLE' OR 'SEL_ALL' OR 'DESEL_ALL' OR 'REFRESH'.
        cl_gui_cfw=>set_new_ok_code( e_ucomm ).
    ENDCASE.
  ENDMETHOD.

  METHOD on_hotspot_roles.
    DATA: lv_idx TYPE i.
    lv_idx = e_row_id-index.

    READ TABLE gt_user_roles ASSIGNING FIELD-SYMBOL(<ls_clicked_role>) INDEX lv_idx.
    IF sy-subrc = 0.
      gv_selected_role = <ls_clicked_role>-agr_name.

      LOOP AT gt_user_roles ASSIGNING FIELD-SYMBOL(<ls_r>).
        IF <ls_r>-agr_name = gv_selected_role.
          <ls_r>-radio = gc_radio_on.
        ELSE.
          <ls_r>-radio = gc_radio_off.
        ENDIF.
      ENDLOOP.

      PERFORM eval_auths_for_role USING gv_selected_role.

      IF go_grid_roles IS BOUND.
        go_grid_roles->refresh_table_display( is_stable = VALUE #( row = 'X' col = 'X' ) ).
      ENDIF.
      IF go_grid_auths IS BOUND.
        go_grid_auths->refresh_table_display( is_stable = VALUE #( row = 'X' col = 'X' ) ).
      ENDIF.

      MESSAGE |Target Single Role switched to: { gv_selected_role }.| TYPE 'S'.
    ENDIF.
  ENDMETHOD.

  METHOD on_double_click_roles.
    DATA: lv_idx TYPE i.
    lv_idx = e_row-index.

    READ TABLE gt_user_roles ASSIGNING FIELD-SYMBOL(<ls_clicked_role>) INDEX lv_idx.
    IF sy-subrc = 0.
      gv_selected_role = <ls_clicked_role>-agr_name.

      LOOP AT gt_user_roles ASSIGNING FIELD-SYMBOL(<ls_r>).
        IF <ls_r>-agr_name = gv_selected_role.
          <ls_r>-radio = gc_radio_on.
        ELSE.
          <ls_r>-radio = gc_radio_off.
        ENDIF.
      ENDLOOP.

      PERFORM eval_auths_for_role USING gv_selected_role.

      IF go_grid_roles IS BOUND.
        go_grid_roles->refresh_table_display( is_stable = VALUE #( row = 'X' col = 'X' ) ).
      ENDIF.
      IF go_grid_auths IS BOUND.
        go_grid_auths->refresh_table_display( is_stable = VALUE #( row = 'X' col = 'X' ) ).
      ENDIF.

      MESSAGE |Target Single Role switched to: { gv_selected_role }.| TYPE 'S'.
    ENDIF.
  ENDMETHOD.

  METHOD on_before_command_auths.
    IF e_ucomm = cl_gui_alv_grid=>mc_fc_refresh
        OR e_ucomm = 'REFRESH'
        OR e_ucomm = 'F8'
        OR e_ucomm = '&F8'.
      cl_gui_cfw=>set_new_ok_code( 'REFRESH' ).
    ENDIF.
  ENDMETHOD.

  METHOD on_hotspot_auths.
    IF e_column_id-fieldname = 'OBJECT'.
      READ TABLE gt_missing_auth INTO DATA(ls_m) INDEX e_row_id-index.
      IF sy-subrc = 0 AND ls_m-object IS NOT INITIAL AND ls_m-object <> 'SAP_ALL' AND ls_m-object <> 'INFO'.
        SET PARAMETER ID 'SUS' FIELD ls_m-object.
        CALL TRANSACTION 'SU03' AND SKIP FIRST SCREEN.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD on_double_click_auths.
    READ TABLE gt_missing_auth INTO DATA(ls_m) INDEX e_row-index.
    IF sy-subrc = 0 AND ls_m-object IS NOT INITIAL AND ls_m-object <> 'SAP_ALL' AND ls_m-object <> 'INFO'.
      SET PARAMETER ID 'SUS' FIELD ls_m-object.
      CALL TRANSACTION 'SU03' AND SKIP FIRST SCREEN.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

* The following routines do not mutate SAP data unless explicitly marked.
FORM values_text USING pt_values TYPE tt_check_value CHANGING cv_text TYPE string.
  CLEAR cv_text.
  LOOP AT pt_values INTO DATA(ls_value).
    IF cv_text IS NOT INITIAL. cv_text = |{ cv_text }, |. ENDIF.
    cv_text = |{ cv_text }{ ls_value-field }='{ ls_value-value }'|.
  ENDLOOP.
ENDFORM.

FORM object_fields USING pv_object TYPE tobj-objct
  CHANGING ct_fields TYPE tt_fields cv_error TYPE string.
  TYPES: BEGIN OF ty_cache,
           object TYPE tobj-objct,
           fields TYPE tt_fields,
         END OF ty_cache.
  STATICS lt_cache TYPE HASHED TABLE OF ty_cache WITH UNIQUE KEY object.
  CLEAR: ct_fields, cv_error.
  READ TABLE lt_cache INTO DATA(ls_cache) WITH TABLE KEY object = pv_object.
  IF sy-subrc = 0. ct_fields = ls_cache-fields. RETURN. ENDIF.
  SELECT SINGLE * FROM tobj WHERE objct = @pv_object INTO @DATA(ls_object).
  IF sy-subrc <> 0.
    cv_error = |Unknown authorization object { pv_object }; no changes made.|. RETURN.
  ENDIF.
  DO 10 TIMES.
    DATA(lv_component) = |FIEL{ sy-index MOD 10 }|.
    ASSIGN COMPONENT lv_component OF STRUCTURE ls_object TO FIELD-SYMBOL(<field>).
    IF sy-subrc = 0 AND <field> IS NOT INITIAL. APPEND <field> TO ct_fields. ENDIF.
  ENDDO.
  SORT ct_fields.
  DELETE ADJACENT DUPLICATES FROM ct_fields.
  IF ct_fields IS INITIAL.
    cv_error = |Object { pv_object } has no field definition; check TOBJ.|. RETURN.
  ENDIF.
  INSERT VALUE #( object = pv_object fields = ct_fields ) INTO TABLE lt_cache.
ENDFORM.

FORM complete_check USING pv_object TYPE tobj-objct pt_need TYPE tt_check_value pv_key TYPE string
  CHANGING ct_complete TYPE tt_check_value ct_auto TYPE tt_check_value cv_error TYPE string.
  DATA lt_fields TYPE tt_fields.
  CLEAR: ct_complete, ct_auto, cv_error.
  PERFORM object_fields USING pv_object CHANGING lt_fields cv_error.
  IF cv_error IS NOT INITIAL. RETURN. ENDIF.
  LOOP AT pt_need INTO DATA(ls_need).
    IF NOT line_exists( lt_fields[ table_line = ls_need-field ] ).
      cv_error = |Trace field { ls_need-field } is not defined for { pv_object }; check metadata.|. RETURN.
    ENDIF.
  ENDLOOP.
  LOOP AT lt_fields INTO DATA(lv_field).
    DATA lv_value TYPE xuval.
    CLEAR lv_value.
    READ TABLE gt_override INTO DATA(ls_override) WITH TABLE KEY check_key = pv_key field = lv_field.
    IF sy-subrc = 0.
      lv_value = ls_override-value.
    ELSE.
      READ TABLE pt_need INTO ls_need WITH KEY field = lv_field.
      IF sy-subrc = 0. lv_value = ls_need-value. ENDIF.
    ENDIF.
    IF lv_value IS INITIAL.
      lv_value = '*'.
      APPEND VALUE #( field = lv_field value = lv_value ) TO ct_auto.
    ENDIF.
    READ TABLE pt_need INTO ls_need WITH KEY field = lv_field.
    IF sy-subrc = 0 AND ls_need-value IS NOT INITIAL.
      DATA lv_matches TYPE abap_bool.
      PERFORM star_matches USING lv_value ls_need-value CHANGING lv_matches.
      IF lv_matches = abap_false.
        cv_error = |Proposed { lv_field }='{ lv_value }' does not cover the SU53 value '{ ls_need-value }'.|.
        RETURN.
      ENDIF.
    ENDIF.
    APPEND VALUE #( field = lv_field value = lv_value ) TO ct_complete.
  ENDLOOP.
ENDFORM.

FORM initialize_new_orgs USING pt_complete TYPE tt_check_value CHANGING ct_orgs TYPE tt_pt1252.
  "Existing global organizational levels are not widened. New org variables need a maintained value.
  STATICS lt_usorg TYPE tt_usorg.
  IF lt_usorg IS INITIAL. SELECT field, varbl FROM usorg INTO TABLE @lt_usorg. ENDIF.
  LOOP AT pt_complete INTO DATA(ls_value).
    READ TABLE lt_usorg INTO DATA(ls_org_field) WITH TABLE KEY field = ls_value-field.
    IF sy-subrc = 0 AND NOT line_exists( ct_orgs[ varbl = ls_org_field-varbl ] ).
      APPEND VALUE #( varbl = ls_org_field-varbl low = ls_value-value ) TO ct_orgs.
      gv_log_text = |Initialized new org variable { ls_org_field-varbl }={ ls_value-value }; tuple uses local org values.|.
      PERFORM add_log USING 'NEW ORG' 'W' gv_log_text.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM star_matches USING pv_pattern TYPE xuval pv_value TYPE xuval CHANGING cv_match TYPE abap_bool.
  "SAP-style '*' matching, case-sensitive; '+', '#', '?' are literals, not ABAP CP operators.
  DATA: lv_p TYPE i, lv_v TYPE i, lv_star TYPE i VALUE -1, lv_retry TYPE i,
        lv_plen TYPE i, lv_vlen TYPE i.
  lv_plen = strlen( pv_pattern ). lv_vlen = strlen( pv_value ).
  cv_match = abap_false.
  WHILE lv_v < lv_vlen.
    IF lv_p < lv_plen AND pv_pattern+lv_p(1) = '*'.
      lv_star = lv_p. lv_p = lv_p + 1. lv_retry = lv_v.
    ELSEIF lv_p < lv_plen AND pv_pattern+lv_p(1) = pv_value+lv_v(1).
      lv_p = lv_p + 1. lv_v = lv_v + 1.
    ELSEIF lv_star >= 0.
      lv_p = lv_star + 1. lv_retry = lv_retry + 1. lv_v = lv_retry.
    ELSE. RETURN.
    ENDIF.
  ENDWHILE.
  WHILE lv_p < lv_plen AND pv_pattern+lv_p(1) = '*'. lv_p = lv_p + 1. ENDWHILE.
  IF lv_p = lv_plen. cv_match = abap_true. ENDIF.
ENDFORM.

FORM resolve_org_values USING pt_orgs TYPE tt_pt1252 CHANGING ct_fields TYPE tt_role_fld.
  DATA lt_resolved TYPE tt_role_fld.
  LOOP AT ct_fields INTO DATA(ls_field).
    IF ls_field-low(1) = '$'.
      LOOP AT pt_orgs INTO DATA(ls_org) WHERE varbl = ls_field-low.
        IF ls_org-low IS INITIAL AND ls_org-high IS INITIAL. CONTINUE. ENDIF.
        DATA(ls_resolved) = ls_field.
        ls_resolved-low = ls_org-low. ls_resolved-high = ls_org-high.
        APPEND ls_resolved TO lt_resolved.
      ENDLOOP.
    ELSE.
      APPEND ls_field TO lt_resolved.
    ENDIF.
  ENDLOOP.
  ct_fields = lt_resolved.
ENDFORM.

FORM check_covered USING pt_fields TYPE tt_role_fld pt_objects TYPE tt_role_obj
  pv_object TYPE tobj-objct pt_need TYPE tt_check_value
  CHANGING cv_match TYPE abap_bool cv_instance TYPE xuauth cv_detail TYPE string.
  DATA: lv_match TYPE abap_bool, lv_field_match TYPE abap_bool,
        lv_detail TYPE string, lv_best_count TYPE i VALUE -1, lv_count TYPE i.
  CLEAR: cv_match, cv_instance, cv_detail.
  LOOP AT pt_objects INTO DATA(ls_object) WHERE object = pv_object.
    lv_match = abap_true. CLEAR: lv_count, lv_detail.
    LOOP AT pt_need INTO DATA(ls_need).
      PERFORM field_value_covered USING pt_fields pv_object ls_object-auth ls_need-field ls_need-value
        CHANGING lv_field_match.
      IF lv_field_match = abap_false.
        lv_match = abap_false.
        lv_detail = |{ lv_detail } { ls_need-field }='{ ls_need-value }';|.
      ELSE. lv_count = lv_count + 1.
      ENDIF.
    ENDLOOP.
    IF lv_match = abap_true.
      cv_match = abap_true. cv_instance = ls_object-auth. RETURN.
    ENDIF.
    IF lv_count > lv_best_count.
      lv_best_count = lv_count.
      cv_detail = |Instance { ls_object-auth } missing:{ lv_detail }|.
    ENDIF.
  ENDLOOP.
  IF cv_detail IS INITIAL. cv_detail = |Object { pv_object } is not active in this role|. ENDIF.
ENDFORM.

FORM make_eval_tables USING pt_auth TYPE tt_pt1250 pt_fields TYPE tt_pt1251 pt_orgs TYPE tt_pt1252
  CHANGING ct_objects TYPE tt_role_obj ct_fields TYPE tt_role_fld.
  CLEAR: ct_objects, ct_fields.
  LOOP AT pt_auth INTO DATA(ls_auth) WHERE deleted = space.
    APPEND VALUE #( object = ls_auth-object auth = ls_auth-auth ) TO ct_objects.
  ENDLOOP.
  LOOP AT pt_fields INTO DATA(ls_field) WHERE deleted = space.
    APPEND VALUE #( object = ls_field-object auth = ls_field-auth field = ls_field-field
      low = ls_field-low high = ls_field-high ) TO ct_fields.
  ENDLOOP.
  PERFORM resolve_org_values USING pt_orgs CHANGING ct_fields.
ENDFORM.

FORM complete_open_values CHANGING ct_auth TYPE tt_pt1250 ct_fields TYPE tt_pt1251
  ct_orgs TYPE tt_pt1252 cv_values TYPE i cv_error TYPE string.
  DATA lt_required TYPE tt_fields.
  CLEAR cv_error.
  LOOP AT ct_auth ASSIGNING FIELD-SYMBOL(<auth>) WHERE deleted = space.
    PERFORM object_fields USING <auth>-object CHANGING lt_required cv_error.
    IF cv_error IS NOT INITIAL. RETURN. ENDIF.
    LOOP AT lt_required INTO DATA(lv_field).
      IF NOT line_exists( ct_fields[ object = <auth>-object auth = <auth>-auth field = lv_field deleted = space ] ).
        APPEND VALUE #( object = <auth>-object auth = <auth>-auth field = lv_field
          low = '*' modified = 'U' neu = 'X' ) TO ct_fields.
        <auth>-modified = 'U'. cv_values = cv_values + 1.
      ENDIF.
    ENDLOOP.
    LOOP AT ct_fields ASSIGNING FIELD-SYMBOL(<field>)
      WHERE object = <auth>-object AND auth = <auth>-auth AND deleted = space.
      IF <field>-low IS INITIAL AND <field>-high IS INITIAL.
        <field>-low = '*'. <field>-modified = 'U'. <field>-neu = 'X'.
        <auth>-modified = 'U'. cv_values = cv_values + 1.
      ELSEIF <field>-low(1) = '$' AND NOT line_exists( ct_orgs[ varbl = <field>-low ] ).
        APPEND VALUE #( varbl = <field>-low low = '*' ) TO ct_orgs.
        cv_values = cv_values + 1.
      ENDIF.
    ENDLOOP.
  ENDLOOP.
  LOOP AT ct_orgs ASSIGNING FIELD-SYMBOL(<org>) WHERE low = space AND high = space.
    <org>-low = '*'. cv_values = cv_values + 1.
  ENDLOOP.
ENDFORM.

FORM node_values USING pv_object TYPE tobj-objct pv_auth TYPE xuauth
  pt_fields TYPE tt_pt1251 pt_orgs TYPE tt_pt1252
  CHANGING ct_values TYPE tt_role_fld cv_ok TYPE abap_bool.
  DATA: lt_required TYPE tt_fields, lv_error TYPE string.
  CLEAR: ct_values, cv_ok.
  LOOP AT pt_fields INTO DATA(ls_field)
    WHERE object = pv_object AND auth = pv_auth AND deleted = space.
    APPEND VALUE #( field = ls_field-field low = ls_field-low high = ls_field-high ) TO ct_values.
  ENDLOOP.
  PERFORM resolve_org_values USING pt_orgs CHANGING ct_values.
  PERFORM object_fields USING pv_object CHANGING lt_required lv_error.
  IF lv_error IS NOT INITIAL OR ct_values IS INITIAL. RETURN. ENDIF.
  LOOP AT lt_required INTO DATA(lv_field).
    IF NOT line_exists( ct_values[ field = lv_field ] ). RETURN. ENDIF.
  ENDLOOP.
  LOOP AT ct_values INTO DATA(ls_value).
    IF ls_value-low IS INITIAL OR NOT line_exists( lt_required[ table_line = ls_value-field ] ). RETURN. ENDIF.
  ENDLOOP.
  SORT ct_values BY field low high.
  DELETE ADJACENT DUPLICATES FROM ct_values COMPARING field low high.
  cv_ok = abap_true.
ENDFORM.

FORM merge_dimension USING pt_left TYPE tt_role_fld pt_right TYPE tt_role_fld
  CHANGING cv_ok TYPE abap_bool cv_field TYPE xufield.
  "Two rectangles can be united without extra tuples when at most one
  "field's complete value set differs. Never just compare one matched value.
  DATA: lt_fields TYPE tt_fields, lt_a TYPE tt_role_fld, lt_b TYPE tt_role_fld,
        lv_different TYPE i.
  CLEAR: cv_ok, cv_field.
  LOOP AT pt_left INTO DATA(ls_value). APPEND ls_value-field TO lt_fields. ENDLOOP.
  LOOP AT pt_right INTO ls_value. APPEND ls_value-field TO lt_fields. ENDLOOP.
  SORT lt_fields. DELETE ADJACENT DUPLICATES FROM lt_fields.
  LOOP AT lt_fields INTO DATA(lv_field).
    CLEAR: lt_a, lt_b.
    LOOP AT pt_left INTO ls_value WHERE field = lv_field. APPEND ls_value TO lt_a. ENDLOOP.
    LOOP AT pt_right INTO ls_value WHERE field = lv_field. APPEND ls_value TO lt_b. ENDLOOP.
    IF lt_a IS INITIAL OR lt_b IS INITIAL. RETURN. ENDIF.
    IF lt_a <> lt_b.
      lv_different = lv_different + 1. cv_field = lv_field.
      IF lv_different > 1. CLEAR cv_field. RETURN. ENDIF.
    ENDIF.
  ENDLOOP.
  cv_ok = abap_true.
ENDFORM.

FORM combine_nodes USING pt_orgs TYPE tt_pt1252
  CHANGING ct_auth TYPE tt_pt1250 ct_fields TYPE tt_pt1251 ct_new TYPE tt_role_obj.
  DATA: lt_pending TYPE tt_role_obj, lt_left TYPE tt_role_fld, lt_right TYPE tt_role_fld,
        lt_union TYPE tt_role_fld, lv_left_ok TYPE abap_bool, lv_right_ok TYPE abap_bool,
        lv_merge TYPE abap_bool, lv_changed TYPE abap_bool, lv_field TYPE xufield.
  "Prefer existing headers. Only nodes created by this Add can be removed.
  "Repeat to a fixed point: e.g. a complete 2x2 grid becomes one node,
  "whereas a diagonal stays separate and retains its exact combinations.
  DO.
    CLEAR lv_changed. lt_pending = ct_new.
    LOOP AT lt_pending INTO DATA(ls_new).
      IF NOT line_exists( ct_new[ object = ls_new-object auth = ls_new-auth ] ). CONTINUE. ENDIF.
      PERFORM node_values USING ls_new-object ls_new-auth ct_fields pt_orgs CHANGING lt_right lv_right_ok.
      IF lv_right_ok = abap_false. CONTINUE. ENDIF.
      LOOP AT ct_auth INTO DATA(ls_target) WHERE object = ls_new-object AND deleted = space.
        IF ls_target-auth = ls_new-auth. CONTINUE. ENDIF.
        PERFORM node_values USING ls_target-object ls_target-auth ct_fields pt_orgs CHANGING lt_left lv_left_ok.
        IF lv_left_ok = abap_false. CONTINUE. ENDIF.
        PERFORM merge_dimension USING lt_left lt_right CHANGING lv_merge lv_field.
        IF lv_merge = abap_false. CONTINUE. ENDIF.
        IF lv_field IS NOT INITIAL.
          CLEAR lt_union.
          LOOP AT lt_left INTO DATA(ls_value) WHERE field = lv_field. APPEND ls_value TO lt_union. ENDLOOP.
          LOOP AT lt_right INTO ls_value WHERE field = lv_field. APPEND ls_value TO lt_union. ENDLOOP.
          SORT lt_union BY field low high.
          DELETE ADJACENT DUPLICATES FROM lt_union COMPARING field low high.
          IF line_exists( lt_union[ low = '*' high = space ] ).
            DELETE lt_union WHERE low <> '*' OR high <> space.
          ENDIF.
          "Materialize only this instance's changed org field; never expand AGR1252.
          DELETE ct_fields WHERE object = ls_target-object AND auth = ls_target-auth
            AND field = lv_field AND deleted = space.
          LOOP AT lt_union INTO ls_value.
            APPEND VALUE #( object = ls_target-object auth = ls_target-auth field = lv_field
              low = ls_value-low high = ls_value-high modified = 'U' neu = 'X' ) TO ct_fields.
          ENDLOOP.
          READ TABLE ct_auth ASSIGNING FIELD-SYMBOL(<target>) WITH KEY object = ls_target-object auth = ls_target-auth.
          <target>-modified = 'U'.
        ENDIF.
        DELETE ct_fields WHERE object = ls_new-object AND auth = ls_new-auth.
        DELETE ct_auth WHERE object = ls_new-object AND auth = ls_new-auth.
        DELETE ct_new WHERE object = ls_new-object AND auth = ls_new-auth.
        gv_log_text = |Combined { ls_new-object } into { ls_target-auth }; differing field { lv_field }|.
        PERFORM add_log USING 'COMBINE' 'S' gv_log_text.
        lv_changed = abap_true.
        EXIT.
      ENDLOOP.
    ENDLOOP.
    IF lv_changed = abap_false. EXIT. ENDIF.
  ENDDO.
ENDFORM.

FORM new_auth_name USING pv_object TYPE tobj-objct pt_auth TYPE tt_pt1250
  CHANGING cv_counter TYPE i cv_auth TYPE xuauth cv_error TYPE string.
  CLEAR: cv_auth, cv_error.
  DO 99999 TIMES.
    cv_counter = cv_counter + 1.
    cv_auth = |ZT{ cv_counter WIDTH = 10 ALIGN = RIGHT PAD = '0' }|.
    IF NOT line_exists( pt_auth[ object = pv_object auth = cv_auth ] ). RETURN. ENDIF.
  ENDDO.
  cv_error = 'No free authorization instance name could be allocated'.
ENDFORM.

FORM validate_user.
  SELECT SINGLE class FROM usr02 WHERE bname = @p_uname INTO @DATA(lv_class).
  IF sy-subrc <> 0. MESSAGE 'User does not exist in this SAP client' TYPE 'E'. ENDIF.
  IF p_uname <> sy-uname.
    AUTHORITY-CHECK OBJECT 'S_USER_GRP' ID 'CLASS' FIELD lv_class ID 'ACTVT' FIELD '03'.
    IF sy-subrc <> 0. MESSAGE 'Not authorized to inspect this user group' TYPE 'E'. ENDIF.
  ENDIF.
ENDFORM.

FORM validate_target CHANGING cv_ok TYPE abap_bool.
  DATA: lv_composite TYPE char01, lv_parent TYPE agr_name.
  cv_ok = abap_false.
  IF gv_selected_role IS INITIAL.
    MESSAGE 'Select a target Single Role first' TYPE 'S' DISPLAY LIKE 'E'. RETURN.
  ENDIF.
  AUTHORITY-CHECK OBJECT 'S_USER_AGR' ID 'ACT_GROUP' FIELD gv_selected_role ID 'ACTVT' FIELD '02'.
  IF sy-subrc <> 0.
    MESSAGE 'Not authorized to change the selected role' TYPE 'S' DISPLAY LIKE 'E'. RETURN.
  ENDIF.
  SELECT SINGLE agr_name FROM agr_users WHERE uname = @p_uname AND agr_name = @gv_selected_role
    AND from_dat <= @sy-datum AND to_dat >= @sy-datum INTO @DATA(lv_assigned).
  IF sy-subrc <> 0.
    MESSAGE 'Target role is not currently valid for the test user. Refresh role assignments.' TYPE 'S' DISPLAY LIKE 'E'. RETURN.
  ENDIF.
  CALL FUNCTION 'PRGN_GET_COLLECTIVE_AGR_FLAG' EXPORTING activity_group = gv_selected_role
    IMPORTING collective_agr_flag = lv_composite inh_role = lv_parent EXCEPTIONS OTHERS = 1.
  IF sy-subrc <> 0 OR lv_composite = 'X' OR lv_parent IS NOT INITIAL.
    MESSAGE 'Choose a non-derived Single Role. Derived roles require maintenance through their parent.' TYPE 'S' DISPLAY LIKE 'E'. RETURN.
  ENDIF.
  cv_ok = abap_true.
ENDFORM.

FORM add_log USING pv_step TYPE c pv_severity TYPE c pv_detail TYPE string.
  DATA lv_stamp TYPE timestampl.
  GET TIME STAMP FIELD lv_stamp.
  IF pv_severity CA 'AEX'. gv_last_error = pv_detail. ENDIF.
  APPEND VALUE #( stamp = lv_stamp actor = sy-uname role = gv_selected_role
    step = pv_step severity = pv_severity detail = pv_detail ) TO gt_log.
ENDFORM.

FORM log_returns USING pv_step TYPE c pt_return TYPE bapirettab CHANGING cv_error TYPE abap_bool.
  cv_error = abap_false.
  LOOP AT pt_return INTO DATA(ls_return).
    DATA(lv_message) = CONV string( ls_return-message ).
    IF lv_message IS INITIAL.
      MESSAGE ID ls_return-id TYPE 'S' NUMBER ls_return-number
        WITH ls_return-message_v1 ls_return-message_v2 ls_return-message_v3 ls_return-message_v4
        INTO lv_message.
    ENDIF.
    PERFORM add_log USING pv_step ls_return-type lv_message.
    IF ls_return-type CA 'AEX'. cv_error = abap_true. ENDIF.
  ENDLOOP.
ENDFORM.


FORM refresh_grids.
  IF go_grid_roles IS BOUND.
    go_grid_roles->refresh_table_display( is_stable = VALUE #( row = 'X' col = 'X' ) ).
  ENDIF.
  IF go_grid_auths IS BOUND.
    go_grid_auths->refresh_table_display( is_stable = VALUE #( row = 'X' col = 'X' ) ).
  ENDIF.
ENDFORM.

FORM apply_missing_filter.
  IF go_grid_auths IS NOT BOUND. RETURN. ENDIF.
  DATA lt_filters TYPE lvc_t_filt.
  go_grid_auths->get_filter_criteria( IMPORTING et_filter = lt_filters ).
  DELETE lt_filters WHERE fieldname = 'FILTER_MISS' OR fieldname = 'IS_IN_ROLE'.
  go_grid_auths->set_filter_criteria( EXPORTING it_filter = lt_filters ).
ENDFORM.




FORM merge_menu USING pv_role TYPE agr_name CHANGING cv_subrc TYPE sy-subrc.
  DATA: lt_return TYPE bapirettab, lv_error TYPE abap_bool.
  CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE' EXPORTING activity_group = pv_role EXCEPTIONS OTHERS = 1.
  IF sy-subrc <> 0. cv_subrc = 10. RETURN. ENDIF.
  TRY.
  CALL FUNCTION 'SUPRN_DARK_MANIPULATE_PROFILE'
    EXPORTING activity_group = pv_role rebuild_auth_data = 'M' generate_profile = space
      fill_orgs_with_star = 'X' fill_fields_with_star = 'X' no_dialog = 'X'
    IMPORTING return = lt_return EXCEPTIONS OTHERS = 1.
  cv_subrc = sy-subrc.
  PERFORM log_returns USING 'MENU MERGE' lt_return CHANGING lv_error.
  IF lv_error = abap_true AND cv_subrc = 0. cv_subrc = 8. ENDIF.
  IF cv_subrc = 0. COMMIT WORK AND WAIT. cv_subrc = sy-subrc. ENDIF.
    CATCH cx_root INTO DATA(lx_merge).
      cv_subrc = 11. gv_log_text = lx_merge->get_text( ).
      PERFORM add_log USING 'MENU MERGE' 'E' gv_log_text.
  ENDTRY.
  CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE' EXPORTING activity_group = pv_role.
  IF cv_subrc <> 0. gv_log_text = |Menu merge failed, rc { cv_subrc }|.
    PERFORM add_log USING 'MENU MERGE' 'E' gv_log_text. ENDIF.
ENDFORM.

FORM compare_role_users USING pv_role TYPE agr_name CHANGING cv_subrc TYPE sy-subrc.
  DATA: lt_return TYPE bapirettab, lv_error TYPE abap_bool.
  TRY.
  CALL FUNCTION 'PRGN_ACTIVITY_GROUP_USERPROFS'
    EXPORTING activity_group = pv_role display_messages = space clean_agrs2 = space
    IMPORTING return = lt_return
    EXCEPTIONS authority_incomplete = 1 at_least_one_user_enqueued = 2
      too_many_profiles_in_user = 3 OTHERS = 4.
  cv_subrc = sy-subrc.
  PERFORM log_returns USING 'USER COMPARE' lt_return CHANGING lv_error.
  IF lv_error = abap_true AND cv_subrc = 0. cv_subrc = 8. ENDIF.
  IF cv_subrc = 0. COMMIT WORK AND WAIT. cv_subrc = sy-subrc. ENDIF.
    CATCH cx_root INTO DATA(lx_compare).
      cv_subrc = 11. gv_log_text = lx_compare->get_text( ).
      PERFORM add_log USING 'USER COMPARE' 'E' gv_log_text.
  ENDTRY.
  IF cv_subrc = 0.
    gv_compare_state = 'Compared'.
    PERFORM add_log USING 'USER COMPARE' 'S' 'Role users compared. Existing logon sessions may still need to refresh their authorization buffer.'.
  ELSE.
    gv_compare_state = |Failed: { gv_last_error }|.
    gv_log_text = |User comparison incomplete, rc { cv_subrc }|.
    PERFORM add_log USING 'USER COMPARE' 'E' gv_log_text.
  ENDIF.
ENDFORM.



CLASS ltcl_role_test DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS: wildcard_literals FOR TESTING,
             wildcard_case FOR TESTING,
             wildcard_backtrack FOR TESTING,
             instance_and_semantics FOR TESTING,
             org_resolution FOR TESTING,
             interval_boundaries FOR TESTING,
             complete_blank_fields FOR TESTING,
             edits_must_cover_trace FOR TESTING,
             complete_tuples_stay_separate FOR TESTING,
             deleted_auth_not_covered FOR TESTING,
             new_name_preserves_existing FOR TESTING,
             empty_trace_keeps_object FOR TESTING.
    METHODS: combine_same_activity FOR TESTING,
             combine_diagonal_is_separate FOR TESTING,
             combine_full_grid FOR TESTING,
             combine_existing_multivalue FOR TESTING,
             combine_org_does_not_expand FOR TESTING,
             combine_open_node_untouched FOR TESTING.
    METHODS: tcode_completes_existing_open FOR TESTING,
             tcode_preserves_deleted FOR TESTING,
             tcode_completes_missing_fields FOR TESTING.
    METHODS build_node IMPORTING iv_auth TYPE xuauth iv_activity TYPE xuval iv_report TYPE xuval
      CHANGING ct_auth TYPE tt_pt1250 ct_fields TYPE tt_pt1251.
ENDCLASS.

CLASS ltcl_role_test IMPLEMENTATION.
  METHOD tcode_completes_existing_open.
    DATA: lt_auth TYPE tt_pt1250, lt_fields TYPE tt_pt1251, lt_orgs TYPE tt_pt1252,
          lv_count TYPE i, lv_error TYPE string.
    build_node( EXPORTING iv_auth = 'EXISTING' iv_activity = space iv_report = 'ZA'
      CHANGING ct_auth = lt_auth ct_fields = lt_fields ).
    lt_orgs = VALUE #( ( varbl = '$BUKRS' ) ( varbl = '$WERKS' low = '1000' high = '2000' ) ).
    PERFORM complete_open_values CHANGING lt_auth lt_fields lt_orgs lv_count lv_error.
    cl_abap_unit_assert=>assert_initial( lv_error ).
    cl_abap_unit_assert=>assert_equals( act = lt_fields[ field = 'ACTVT' ]-low exp = '*' ).
    cl_abap_unit_assert=>assert_equals( act = lt_fields[ field = 'REPORT' ]-low exp = 'ZA' ).
    cl_abap_unit_assert=>assert_equals( act = lt_orgs[ varbl = '$BUKRS' ]-low exp = '*' ).
    cl_abap_unit_assert=>assert_equals( act = lt_orgs[ varbl = '$WERKS' ]-low exp = '1000' ).
    cl_abap_unit_assert=>assert_equals( act = lt_orgs[ varbl = '$WERKS' ]-high exp = '2000' ).
    cl_abap_unit_assert=>assert_equals( act = lv_count exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = lt_auth[ 1 ]-modified exp = 'U' ).
    "Repeated completion must not introduce changes or duplicate values.
    CLEAR lv_count.
    PERFORM complete_open_values CHANGING lt_auth lt_fields lt_orgs lv_count lv_error.
    cl_abap_unit_assert=>assert_initial( lv_count ).
  ENDMETHOD.
  METHOD tcode_preserves_deleted.
    DATA: lt_auth TYPE tt_pt1250, lt_fields TYPE tt_pt1251, lt_orgs TYPE tt_pt1252,
          lt_before TYPE tt_pt1251, lv_count TYPE i, lv_error TYPE string.
    build_node( EXPORTING iv_auth = 'DELETED' iv_activity = space iv_report = 'ZA'
      CHANGING ct_auth = lt_auth ct_fields = lt_fields ).
    lt_auth[ 1 ]-deleted = 'X'. lt_before = lt_fields.
    PERFORM complete_open_values CHANGING lt_auth lt_fields lt_orgs lv_count lv_error.
    cl_abap_unit_assert=>assert_equals( act = lt_fields exp = lt_before ).
    cl_abap_unit_assert=>assert_initial( lv_count ).
    cl_abap_unit_assert=>assert_equals( act = lt_auth[ 1 ]-deleted exp = 'X' ).
  ENDMETHOD.
  METHOD tcode_completes_missing_fields.
    DATA: lt_auth TYPE tt_pt1250, lt_fields TYPE tt_pt1251, lt_orgs TYPE tt_pt1252,
          lv_count TYPE i, lv_error TYPE string.
    lt_auth = VALUE #( ( object = 'S_ALV_LAYR' auth = 'EXISTING' ) ).
    lt_fields = VALUE #( ( object = 'S_ALV_LAYR' auth = 'EXISTING' field = 'REPORT' low = '$TEST' ) ).
    PERFORM complete_open_values CHANGING lt_auth lt_fields lt_orgs lv_count lv_error.
    cl_abap_unit_assert=>assert_initial( lv_error ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_fields ) exp = 4 ).
    cl_abap_unit_assert=>assert_equals( act = lt_fields[ field = 'ACTVT' ]-low exp = '*' ).
    cl_abap_unit_assert=>assert_equals( act = lt_fields[ field = 'HANDLE' ]-low exp = '*' ).
    cl_abap_unit_assert=>assert_equals( act = lt_fields[ field = 'LOG_GROUP' ]-low exp = '*' ).
    cl_abap_unit_assert=>assert_equals( act = lt_fields[ field = 'REPORT' ]-low exp = '$TEST' ).
    cl_abap_unit_assert=>assert_equals( act = lt_orgs[ varbl = '$TEST' ]-low exp = '*' ).
    cl_abap_unit_assert=>assert_equals( act = lv_count exp = 4 ).
  ENDMETHOD.
  METHOD build_node.
    APPEND VALUE #( object = 'S_ALV_LAYR' auth = iv_auth ) TO ct_auth.
    APPEND VALUE #( object = 'S_ALV_LAYR' auth = iv_auth field = 'ACTVT' low = iv_activity ) TO ct_fields.
    APPEND VALUE #( object = 'S_ALV_LAYR' auth = iv_auth field = 'REPORT' low = iv_report ) TO ct_fields.
    APPEND VALUE #( object = 'S_ALV_LAYR' auth = iv_auth field = 'HANDLE' low = '*' ) TO ct_fields.
    APPEND VALUE #( object = 'S_ALV_LAYR' auth = iv_auth field = 'LOG_GROUP' low = '*' ) TO ct_fields.
  ENDMETHOD.
  METHOD combine_same_activity.
    DATA: lt_auth TYPE tt_pt1250, lt_fields TYPE tt_pt1251, lt_orgs TYPE tt_pt1252, lt_new TYPE tt_role_obj.
    build_node( EXPORTING iv_auth = 'EXISTING' iv_activity = '03' iv_report = 'AUTHORIZED' CHANGING ct_auth = lt_auth ct_fields = lt_fields ).
    DATA lt_views TYPE STANDARD TABLE OF xuval.
    lt_views = VALUE #( ( 'SCOPED' ) ( 'SCOPEABLE' ) ( 'INSTALLED' ) ( 'ACTIVATED' ) ).
    LOOP AT lt_views INTO DATA(lv_view).
      DATA(lv_auth) = CONV xuauth( |NEW{ sy-tabix }| ).
      build_node( EXPORTING iv_auth = lv_auth iv_activity = '03' iv_report = lv_view CHANGING ct_auth = lt_auth ct_fields = lt_fields ).
      APPEND VALUE #( object = 'S_ALV_LAYR' auth = lv_auth ) TO lt_new.
    ENDLOOP.
    PERFORM combine_nodes USING lt_orgs CHANGING lt_auth lt_fields lt_new.
    cl_abap_unit_assert=>assert_equals( act = lines( lt_auth ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = lt_auth[ 1 ]-auth exp = 'EXISTING' ).
    cl_abap_unit_assert=>assert_initial( lt_new ).
    DATA(lv_count) = 0.
    LOOP AT lt_fields TRANSPORTING NO FIELDS WHERE field = 'REPORT'. lv_count = lv_count + 1. ENDLOOP.
    cl_abap_unit_assert=>assert_equals( act = lv_count exp = 5 ).
    cl_abap_unit_assert=>assert_equals( act = lt_fields[ field = 'ACTVT' ]-low exp = '03' ).
  ENDMETHOD.
  METHOD combine_diagonal_is_separate.
    DATA: lt_auth TYPE tt_pt1250, lt_fields TYPE tt_pt1251, lt_orgs TYPE tt_pt1252, lt_new TYPE tt_role_obj.
    build_node( EXPORTING iv_auth = 'EXISTING' iv_activity = '03' iv_report = 'A' CHANGING ct_auth = lt_auth ct_fields = lt_fields ).
    build_node( EXPORTING iv_auth = 'NEW' iv_activity = '02' iv_report = 'B' CHANGING ct_auth = lt_auth ct_fields = lt_fields ).
    lt_new = VALUE #( ( object = 'S_ALV_LAYR' auth = 'NEW' ) ).
    PERFORM combine_nodes USING lt_orgs CHANGING lt_auth lt_fields lt_new.
    cl_abap_unit_assert=>assert_equals( act = lines( lt_auth ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = lt_fields[ auth = 'EXISTING' field = 'REPORT' ]-low exp = 'A' ).
  ENDMETHOD.
  METHOD combine_full_grid.
    DATA: lt_auth TYPE tt_pt1250, lt_fields TYPE tt_pt1251, lt_orgs TYPE tt_pt1252, lt_new TYPE tt_role_obj.
    build_node( EXPORTING iv_auth = 'EXISTING' iv_activity = '03' iv_report = 'A' CHANGING ct_auth = lt_auth ct_fields = lt_fields ).
    build_node( EXPORTING iv_auth = 'NEW1' iv_activity = '02' iv_report = 'B' CHANGING ct_auth = lt_auth ct_fields = lt_fields ).
    build_node( EXPORTING iv_auth = 'NEW2' iv_activity = '02' iv_report = 'A' CHANGING ct_auth = lt_auth ct_fields = lt_fields ).
    build_node( EXPORTING iv_auth = 'NEW3' iv_activity = '03' iv_report = 'B' CHANGING ct_auth = lt_auth ct_fields = lt_fields ).
    lt_new = VALUE #( ( object = 'S_ALV_LAYR' auth = 'NEW1' ) ( object = 'S_ALV_LAYR' auth = 'NEW2' ) ( object = 'S_ALV_LAYR' auth = 'NEW3' ) ).
    PERFORM combine_nodes USING lt_orgs CHANGING lt_auth lt_fields lt_new.
    cl_abap_unit_assert=>assert_equals( act = lines( lt_auth ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_fields ) exp = 6 ).
  ENDMETHOD.
  METHOD combine_existing_multivalue.
    DATA: lt_auth TYPE tt_pt1250, lt_fields TYPE tt_pt1251, lt_orgs TYPE tt_pt1252, lt_new TYPE tt_role_obj.
    build_node( EXPORTING iv_auth = 'EXISTING' iv_activity = '03' iv_report = 'A' CHANGING ct_auth = lt_auth ct_fields = lt_fields ).
    APPEND VALUE #( object = 'S_ALV_LAYR' auth = 'EXISTING' field = 'ACTVT' low = '02' ) TO lt_fields.
    build_node( EXPORTING iv_auth = 'NEW' iv_activity = '03' iv_report = 'B' CHANGING ct_auth = lt_auth ct_fields = lt_fields ).
    lt_new = VALUE #( ( object = 'S_ALV_LAYR' auth = 'NEW' ) ).
    PERFORM combine_nodes USING lt_orgs CHANGING lt_auth lt_fields lt_new.
    "Must not introduce ACTVT=02 / REPORT=B through one matching ACTVT row.
    cl_abap_unit_assert=>assert_equals( act = lines( lt_auth ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_fields ) exp = 9 ).
  ENDMETHOD.
  METHOD combine_org_does_not_expand.
    DATA: lt_auth TYPE tt_pt1250, lt_fields TYPE tt_pt1251, lt_orgs TYPE tt_pt1252, lt_before TYPE tt_pt1252, lt_new TYPE tt_role_obj.
    build_node( EXPORTING iv_auth = 'EXISTING' iv_activity = '03' iv_report = '$TEST' CHANGING ct_auth = lt_auth ct_fields = lt_fields ).
    build_node( EXPORTING iv_auth = 'NEW' iv_activity = '03' iv_report = 'B' CHANGING ct_auth = lt_auth ct_fields = lt_fields ).
    lt_orgs = VALUE #( ( varbl = '$TEST' low = 'A' ) ). lt_before = lt_orgs.
    lt_new = VALUE #( ( object = 'S_ALV_LAYR' auth = 'NEW' ) ).
    PERFORM combine_nodes USING lt_orgs CHANGING lt_auth lt_fields lt_new.
    cl_abap_unit_assert=>assert_equals( act = lines( lt_auth ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = lt_orgs exp = lt_before ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( lt_fields[ auth = 'EXISTING' field = 'REPORT' low = 'A' ] ) ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( lt_fields[ auth = 'EXISTING' field = 'REPORT' low = 'B' ] ) ) ).
  ENDMETHOD.
  METHOD combine_open_node_untouched.
    DATA: lt_auth TYPE tt_pt1250, lt_fields TYPE tt_pt1251, lt_orgs TYPE tt_pt1252, lt_new TYPE tt_role_obj.
    build_node( EXPORTING iv_auth = 'EXISTING' iv_activity = space iv_report = 'A' CHANGING ct_auth = lt_auth ct_fields = lt_fields ).
    build_node( EXPORTING iv_auth = 'NEW' iv_activity = '03' iv_report = 'A' CHANGING ct_auth = lt_auth ct_fields = lt_fields ).
    lt_new = VALUE #( ( object = 'S_ALV_LAYR' auth = 'NEW' ) ).
    PERFORM combine_nodes USING lt_orgs CHANGING lt_auth lt_fields lt_new.
    cl_abap_unit_assert=>assert_equals( act = lines( lt_auth ) exp = 2 ).
    cl_abap_unit_assert=>assert_initial( lt_fields[ auth = 'EXISTING' field = 'ACTVT' ]-low ).
  ENDMETHOD.
  METHOD wildcard_literals.
    DATA: lv_pattern TYPE xuval VALUE 'Z+*', lv_value TYPE xuval VALUE 'Z+ABC', lv_match TYPE abap_bool.
    PERFORM star_matches USING lv_pattern lv_value CHANGING lv_match.
    cl_abap_unit_assert=>assert_true( lv_match ).
    lv_value = 'ZXABC'.
    PERFORM star_matches USING lv_pattern lv_value CHANGING lv_match.
    cl_abap_unit_assert=>assert_false( lv_match ).
  ENDMETHOD.
  METHOD wildcard_case.
    DATA: lv_pattern TYPE xuval VALUE 'Z*', lv_value TYPE xuval VALUE 'zREPORT', lv_match TYPE abap_bool.
    PERFORM star_matches USING lv_pattern lv_value CHANGING lv_match.
    cl_abap_unit_assert=>assert_false( lv_match ).
    lv_pattern = '*'. CLEAR lv_value.
    PERFORM star_matches USING lv_pattern lv_value CHANGING lv_match.
    cl_abap_unit_assert=>assert_true( lv_match ).
  ENDMETHOD.
  METHOD wildcard_backtrack.
    DATA: lv_pattern TYPE xuval VALUE 'A*BC*D', lv_value TYPE xuval VALUE 'ABXBCYYD', lv_match TYPE abap_bool.
    PERFORM star_matches USING lv_pattern lv_value CHANGING lv_match.
    cl_abap_unit_assert=>assert_true( lv_match ).
    lv_value = 'ABXBCYYE'.
    PERFORM star_matches USING lv_pattern lv_value CHANGING lv_match.
    cl_abap_unit_assert=>assert_false( lv_match ).
  ENDMETHOD.
  METHOD instance_and_semantics.
    DATA: lt_fields TYPE tt_role_fld, lt_objs TYPE tt_role_obj, lt_need TYPE tt_check_value,
          lv_object TYPE tobj-objct VALUE 'S_ALV_LAYR', lv_match TYPE abap_bool,
          lv_auth TYPE xuauth, lv_detail TYPE string.
    lt_objs = VALUE #( ( object = lv_object auth = 'A' ) ( object = lv_object auth = 'B' ) ).
    lt_fields = VALUE #( ( object = lv_object auth = 'A' field = 'ACTVT' low = '03' )
      ( object = lv_object auth = 'A' field = 'REPORT' low = 'ZA' )
      ( object = lv_object auth = 'B' field = 'ACTVT' low = '02' )
      ( object = lv_object auth = 'B' field = 'REPORT' low = 'ZB' ) ).
    lt_need = VALUE #( ( field = 'ACTVT' value = '03' ) ( field = 'REPORT' value = 'ZB' ) ).
    PERFORM check_covered USING lt_fields lt_objs lv_object lt_need CHANGING lv_match lv_auth lv_detail.
    cl_abap_unit_assert=>assert_false( lv_match ).
    lt_need[ 2 ]-value = 'ZA'.
    PERFORM check_covered USING lt_fields lt_objs lv_object lt_need CHANGING lv_match lv_auth lv_detail.
    cl_abap_unit_assert=>assert_true( lv_match ).
    cl_abap_unit_assert=>assert_equals( act = lv_auth exp = 'A' ).
  ENDMETHOD.
  METHOD org_resolution.
    DATA: lt_fields TYPE tt_role_fld, lt_orgs TYPE tt_pt1252.
    lt_fields = VALUE #( ( object = 'M_TEST' auth = 'A' field = 'BUKRS' low = '$BUKRS' )
      ( object = 'M_TEST' auth = 'B' field = 'BUKRS' low = '3000' ) ).
    lt_orgs = VALUE #( ( varbl = '$BUKRS' low = '1000' ) ( varbl = '$BUKRS' low = '2000' ) ).
    PERFORM resolve_org_values USING lt_orgs CHANGING lt_fields.
    cl_abap_unit_assert=>assert_equals( act = lines( lt_fields ) exp = 3 ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( lt_fields[ auth = 'B' low = '3000' ] ) ) ).
    cl_abap_unit_assert=>assert_false( xsdbool( line_exists( lt_fields[ auth = 'B' low = '1000' ] ) ) ).
  ENDMETHOD.
  METHOD interval_boundaries.
    DATA: lt_fields TYPE tt_role_fld, lv_object TYPE tobj-objct VALUE 'M_TEST',
          lv_auth TYPE xuauth VALUE 'A', lv_field TYPE xufield VALUE 'BUKRS',
          lv_value TYPE xuval, lv_match TYPE abap_bool.
    lt_fields = VALUE #( ( object = lv_object auth = lv_auth field = lv_field low = '1000' high = '1999' ) ).
    lv_value = '1000'.
    PERFORM field_value_covered USING lt_fields lv_object lv_auth lv_field lv_value CHANGING lv_match.
    cl_abap_unit_assert=>assert_true( lv_match ).
    lv_value = '1999'.
    PERFORM field_value_covered USING lt_fields lv_object lv_auth lv_field lv_value CHANGING lv_match.
    cl_abap_unit_assert=>assert_true( lv_match ).
    lv_value = '2000'.
    PERFORM field_value_covered USING lt_fields lv_object lv_auth lv_field lv_value CHANGING lv_match.
    cl_abap_unit_assert=>assert_false( lv_match ).
  ENDMETHOD.
  METHOD complete_blank_fields.
    DATA: lv_object TYPE tobj-objct VALUE 'S_ALV_LAYR', lv_key TYPE string VALUE 'TEST_BLANK',
          lt_need TYPE tt_check_value, lt_complete TYPE tt_check_value, lt_auto TYPE tt_check_value, lv_error TYPE string.
    lt_need = VALUE #( ( field = 'ACTVT' value = '23' ) ( field = 'REPORT' value = 'ZA' )
      ( field = 'LOG_GROUP' value = space ) ).
    PERFORM complete_check USING lv_object lt_need lv_key CHANGING lt_complete lt_auto lv_error.
    cl_abap_unit_assert=>assert_initial( lv_error ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_complete ) exp = 4 ).
    cl_abap_unit_assert=>assert_equals( act = lt_complete[ field = 'LOG_GROUP' ]-value exp = '*' ).
    cl_abap_unit_assert=>assert_equals( act = lt_complete[ field = 'HANDLE' ]-value exp = '*' ).
    cl_abap_unit_assert=>assert_equals( act = lt_complete[ field = 'ACTVT' ]-value exp = '23' ).
  ENDMETHOD.
  METHOD edits_must_cover_trace.
    DATA: lv_object TYPE tobj-objct VALUE 'S_TCODE', lv_key TYPE string VALUE 'TEST_EDIT',
          lt_need TYPE tt_check_value, lt_complete TYPE tt_check_value, lt_auto TYPE tt_check_value, lv_error TYPE string.
    lt_need = VALUE #( ( field = 'TCD' value = 'ME21N' ) ).
    INSERT VALUE #( check_key = lv_key field = 'TCD' value = 'ME22N' ) INTO TABLE gt_override.
    PERFORM complete_check USING lv_object lt_need lv_key CHANGING lt_complete lt_auto lv_error.
    DELETE TABLE gt_override WITH TABLE KEY check_key = lv_key field = 'TCD'.
    cl_abap_unit_assert=>assert_not_initial( lv_error ).
  ENDMETHOD.
  METHOD complete_tuples_stay_separate.
    DATA: lv_object TYPE tobj-objct VALUE 'S_ALV_LAYR', lv_key TYPE string,
          lt_need TYPE tt_check_value, lt_a TYPE tt_check_value, lt_b TYPE tt_check_value,
          lt_auto TYPE tt_check_value, lv_error TYPE string.
    lt_need = VALUE #( ( field = 'ACTVT' value = '03' ) ( field = 'REPORT' value = 'ZA' ) ).
    lv_key = 'TEST_A'.
    PERFORM complete_check USING lv_object lt_need lv_key CHANGING lt_a lt_auto lv_error.
    lt_need = VALUE #( ( field = 'ACTVT' value = '02' ) ( field = 'REPORT' value = 'ZB' ) ).
    lv_key = 'TEST_B'.
    PERFORM complete_check USING lv_object lt_need lv_key CHANGING lt_b lt_auto lv_error.
    cl_abap_unit_assert=>assert_initial( lv_error ).
    cl_abap_unit_assert=>assert_equals( act = lt_a[ field = 'ACTVT' ]-value exp = '03' ).
    cl_abap_unit_assert=>assert_equals( act = lt_a[ field = 'REPORT' ]-value exp = 'ZA' ).
    cl_abap_unit_assert=>assert_equals( act = lt_b[ field = 'ACTVT' ]-value exp = '02' ).
    cl_abap_unit_assert=>assert_equals( act = lt_b[ field = 'REPORT' ]-value exp = 'ZB' ).
  ENDMETHOD.
  METHOD deleted_auth_not_covered.
    DATA: lt_auth TYPE tt_pt1250, lt_fields TYPE tt_pt1251, lt_orgs TYPE tt_pt1252,
          lt_objs TYPE tt_role_obj, lt_eval TYPE tt_role_fld,
          lv_object TYPE tobj-objct VALUE 'S_TCODE', lt_need TYPE tt_check_value,
          lv_match TYPE abap_bool, lv_instance TYPE xuauth, lv_detail TYPE string.
    lt_auth = VALUE #( ( object = lv_object auth = 'A' deleted = 'X' ) ).
    lt_fields = VALUE #( ( object = lv_object auth = 'A' field = 'TCD' low = '*' deleted = space ) ).
    lt_need = VALUE #( ( field = 'TCD' value = 'ME21N' ) ).
    PERFORM make_eval_tables USING lt_auth lt_fields lt_orgs CHANGING lt_objs lt_eval.
    PERFORM check_covered USING lt_eval lt_objs lv_object lt_need CHANGING lv_match lv_instance lv_detail.
    cl_abap_unit_assert=>assert_false( lv_match ).
    cl_abap_unit_assert=>assert_equals( act = lt_auth[ 1 ]-deleted exp = 'X' ).
  ENDMETHOD.
  METHOD new_name_preserves_existing.
    DATA: lt_auth TYPE tt_pt1250, lt_before TYPE tt_pt1250, lv_object TYPE tobj-objct VALUE 'S_TCODE',
          lv_counter TYPE i, lv_auth TYPE xuauth, lv_error TYPE string.
    lt_auth = VALUE #( ( object = lv_object auth = 'ZT0000000001' deleted = 'X' ) ). lt_before = lt_auth.
    PERFORM new_auth_name USING lv_object lt_auth CHANGING lv_counter lv_auth lv_error.
    cl_abap_unit_assert=>assert_initial( lv_error ).
    cl_abap_unit_assert=>assert_equals( act = lv_auth exp = 'ZT0000000002' ).
    cl_abap_unit_assert=>assert_equals( act = lt_auth exp = lt_before ).
  ENDMETHOD.
  METHOD empty_trace_keeps_object.
    DATA: lv_object TYPE tobj-objct VALUE 'S_TCODE', lv_key TYPE string VALUE 'TEST_EMPTY',
          lt_need TYPE tt_check_value, lt_complete TYPE tt_check_value, lt_auto TYPE tt_check_value, lv_error TYPE string.
    PERFORM complete_check USING lv_object lt_need lv_key CHANGING lt_complete lt_auto lv_error.
    cl_abap_unit_assert=>assert_initial( lv_error ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_complete ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = lt_complete[ field = 'TCD' ]-value exp = '*' ).
  ENDMETHOD.
ENDCLASS.
