*&---------------------------------------------------------------------*
*& Report Z_AUTH_TEST
*&---------------------------------------------------------------------*
*& Advanced SU53 Authorization Trace & Role Diagnostics Analyzer
*& Transaction Code: ZAT
*& Package: $TMP (Local Object)
*& Architecture: Dual-ALV Layout (Docking Single Roles + Fullscreen Missing Auths)
*&---------------------------------------------------------------------*
REPORT z_auth_test.

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
  CLEAR: gt_missing_auth.

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

      DATA: lv_tcode TYPE tstc-tcode.
      lv_tcode = ls_su53-p_tcode.

      SELECT SINGLE ttext FROM tobjt
        WHERE langu = 'E' AND object = @ls_su53-objct
        INTO @DATA(lv_obj_text).
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

      DATA: lv_time_str TYPE string.
      IF ls_su53-timestamp > 0.
        DATA: lv_tstmp_d TYPE d, lv_tstmp_t TYPE t.
        CONVERT TIME STAMP ls_su53-timestamp TIME ZONE sy-zonlo INTO DATE lv_tstmp_d TIME lv_tstmp_t.
        lv_time_str = |{ lv_tstmp_d DATE = USER } { lv_tstmp_t TIME = USER }|.
      ENDIF.

      " Build current user values string for checked fields
      DATA: lv_curr_str TYPE string.
      CLEAR lv_curr_str.

      IF lt_uvals IS INITIAL.
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
        check_values = lt_check_values
        subrc       = ls_su53-rc
        user_values = lv_curr_str
        check_time  = lv_time_str
        raw_time    = ls_su53-timestamp
        is_in_role  = abap_false
      ) TO gt_missing_auth.
    ENDLOOP.

  ELSE.
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
        combination = 'No failed checks in the SU53 buffer (last 3 hours)'
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
  IF pv_role IS INITIAL.
    RETURN.
  ENDIF.

  " Read all active field values currently in this role (ignore deactivated)
  DATA: lt_role_flds TYPE tt_role_fld,
        lt_role_objs TYPE tt_role_obj.

  SELECT object, auth, field, low, high
    FROM agr_1251
    WHERE agr_name = @pv_role
      AND deleted  = ' '
    INTO TABLE @lt_role_flds.

  " Read active authorization objects defined in this role
  SELECT object, auth
    FROM agr_1250
    WHERE agr_name = @pv_role
      AND deleted  = ' '
    INTO TABLE @lt_role_objs.

  " Flags must be cleared on every row and every authorization instance.
  " DATA ... VALUE is applied only once, so a match on an earlier object
  " would otherwise mark every following object as already assigned.
  DATA: lv_all_match  TYPE abap_bool,
        lv_auth_match TYPE abap_bool,
        lv_covered    TYPE abap_bool.

  LOOP AT gt_missing_auth ASSIGNING FIELD-SYMBOL(<ls_m>).
    CLEAR: <ls_m>-cell_style, <ls_m>-cell_color.

    IF <ls_m>-object = 'SAP_ALL' OR <ls_m>-object = 'INFO'.
      <ls_m>-is_in_role = abap_true.
      <ls_m>-sel        = ' '.
      APPEND VALUE lvc_s_styl( fieldname = 'SEL' style = cl_gui_alv_grid=>mc_style_disabled ) TO <ls_m>-cell_style.
      CONTINUE.
    ENDIF.

    lv_all_match = abap_false.

    " One authorization instance must cover every checked field (AND).
    " Any instance of the object is enough (OR).
    LOOP AT lt_role_objs INTO DATA(ls_ro) WHERE object = <ls_m>-object.
      lv_auth_match = abap_true.

      DATA lt_need TYPE tt_check_value.
      CLEAR lt_need.
      IF <ls_m>-check_values IS NOT INITIAL.
        lt_need = <ls_m>-check_values.
      ELSE.
        IF <ls_m>-fiel1 IS NOT INITIAL.
          APPEND VALUE #( field = <ls_m>-fiel1 value = <ls_m>-val01 ) TO lt_need.
        ENDIF.
        IF <ls_m>-fiel2 IS NOT INITIAL.
          APPEND VALUE #( field = <ls_m>-fiel2 value = <ls_m>-val02 ) TO lt_need.
        ENDIF.
        IF <ls_m>-fiel3 IS NOT INITIAL.
          APPEND VALUE #( field = <ls_m>-fiel3 value = <ls_m>-val03 ) TO lt_need.
        ENDIF.
      ENDIF.

      LOOP AT lt_need INTO DATA(ls_need).
        PERFORM field_value_covered USING lt_role_flds
                                          <ls_m>-object
                                          ls_ro-auth
                                          ls_need-field
                                          ls_need-value
                                    CHANGING lv_covered.
        IF lv_covered = abap_false.
          lv_auth_match = abap_false.
          EXIT.
        ENDIF.
      ENDLOOP.

      IF lv_auth_match = abap_true.
        lv_all_match = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    <ls_m>-is_in_role = lv_all_match.

    IF <ls_m>-is_in_role = abap_true.
      <ls_m>-status      = gc_icon_green.
      <ls_m>-sel         = ' '.
      <ls_m>-user_values = |Present in role { pv_role }|.
      APPEND VALUE lvc_s_styl( fieldname = 'SEL' style = cl_gui_alv_grid=>mc_style_disabled ) TO <ls_m>-cell_style.
      APPEND VALUE lvc_s_scol( fname = 'STATUS' color = VALUE #( col = 5 int = 1 ) ) TO <ls_m>-cell_color.
    ELSE.
      <ls_m>-status      = gc_icon_red.
      <ls_m>-user_values = |Missing in role { pv_role }|.
      APPEND VALUE lvc_s_styl( fieldname = 'SEL' style = cl_gui_alv_grid=>mc_style_enabled ) TO <ls_m>-cell_style.
      APPEND VALUE lvc_s_scol( fname = 'STATUS' color = VALUE #( col = 6 int = 0 ) ) TO <ls_m>-cell_color.
      APPEND VALUE lvc_s_scol( fname = 'SUBRC'  color = VALUE #( col = 6 int = 1 ) ) TO <ls_m>-cell_color.
    ENDIF.
  ENDLOOP.
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
    coltext   = 'Values in Selected Role'
    outputlen = 35
  ) TO lt_fieldcat.

  APPEND VALUE #(
    fieldname = 'CHECK_TIME'
    coltext   = 'Trace Timestamp'
    outputlen = 18
  ) TO lt_fieldcat.

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
  IF go_grid_auths IS BOUND.
    go_grid_auths->check_changed_data( ).
  ENDIF.

  IF gv_selected_role IS INITIAL.
    MESSAGE 'Please select a target Single Role first by clicking its radio icon.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  " Collect selected items that are not yet in the role
  DATA: lt_selected TYPE tt_missing_auth.
  CLEAR lt_selected.
  LOOP AT gt_missing_auth INTO DATA(ls_item) WHERE sel = 'X' AND is_in_role = abap_false.
    APPEND ls_item TO lt_selected.
  ENDLOOP.

  IF lt_selected IS INITIAL.
    MESSAGE 'No eligible missing authorizations selected to add.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  " S_TCODE is granted by adding the transaction to the role menu.
  " Profile merge then creates the standard S_TCODE value from that menu.
  " Inserting S_TCODE directly into AGR_1250/AGR_1251 leaves a manual object.
  DATA: lt_menu_tcodes TYPE tt_tcode,
        lt_object_auth TYPE tt_missing_auth,
        lt_agg_objs    TYPE tt_agg_obj,
        lv_menu_added  TYPE i,
        lv_menu_failed TYPE i,
        lv_menu_abort  TYPE abap_bool,
        lv_failed_txt  TYPE string,
        lv_gen_subrc   TYPE sy-subrc,
        lv_gen_failed  TYPE abap_bool,
        lv_total_added TYPE i,
        lv_obj_count   TYPE i,
        lv_org_added   TYPE i,
        lv_tcode_val   TYPE xuval,
        lt_usorg       TYPE tt_usorg,
        lt_org_vals    TYPE tt_org_val,
        lt_sel_objects TYPE tt_obj_name.

  CLEAR: lt_menu_tcodes, lt_object_auth, lt_agg_objs, lt_org_vals, lt_sel_objects,
         lv_menu_added, lv_menu_failed, lv_menu_abort, lv_failed_txt,
         lv_gen_subrc, lv_gen_failed, lv_total_added, lv_obj_count, lv_org_added.

  LOOP AT lt_selected INTO ls_item.
    DATA(lt_pairs) = ls_item-check_values.
    IF lt_pairs IS INITIAL.
      IF ls_item-fiel1 IS NOT INITIAL.
        APPEND VALUE #( field = ls_item-fiel1 value = ls_item-val01 ) TO lt_pairs.
      ENDIF.
      IF ls_item-fiel2 IS NOT INITIAL.
        APPEND VALUE #( field = ls_item-fiel2 value = ls_item-val02 ) TO lt_pairs.
      ENDIF.
      IF ls_item-fiel3 IS NOT INITIAL.
        APPEND VALUE #( field = ls_item-fiel3 value = ls_item-val03 ) TO lt_pairs.
      ENDIF.
    ENDIF.

    IF ls_item-object = 'S_TCODE'.
      DATA lv_has_tcd TYPE abap_bool.
      CLEAR lv_has_tcd.
      LOOP AT lt_pairs INTO DATA(ls_pair).
        PERFORM collect_menu_tcode USING ls_pair-field ls_pair-value CHANGING lt_menu_tcodes.
        IF ls_pair-field = 'TCD'.
          lv_has_tcd = abap_true.
        ENDIF.
      ENDLOOP.
      IF lv_has_tcd = abap_false
         AND ls_item-tcode IS NOT INITIAL
         AND ls_item-tcode <> 'INFO'
         AND ls_item-tcode <> 'ALL'.
        lv_tcode_val = ls_item-tcode.
        PERFORM collect_menu_tcode USING 'TCD' lv_tcode_val CHANGING lt_menu_tcodes.
      ENDIF.
    ELSE.
      ls_item-check_values = lt_pairs.
      APPEND ls_item TO lt_object_auth.
    ENDIF.
  ENDLOOP.

  IF lt_menu_tcodes IS INITIAL AND lt_object_auth IS INITIAL.
    MESSAGE 'S_TCODE can only be granted by adding a concrete transaction to the role menu.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF lt_menu_tcodes IS NOT INITIAL.
    PERFORM add_tcodes_to_role_menu USING gv_selected_role
                                    CHANGING lt_menu_tcodes
                                             lv_menu_added
                                             lv_menu_failed
                                             lv_failed_txt
                                             lv_menu_abort.
    IF lv_menu_abort = abap_true.
      ROLLBACK WORK.
      RETURN.
    ENDIF.
    IF lv_menu_added > 0.
      COMMIT WORK AND WAIT.
      " All maintained: star open fields brought in by the menu merge.
      " Organizational levels stay as maintained in AGR_1252.
      PERFORM generate_role_profile USING gv_selected_role 'M' abap_true abap_false CHANGING lv_gen_subrc.
      IF lv_gen_subrc <> 0.
        lv_gen_failed = abap_true.
      ELSE.
        COMMIT WORK AND WAIT.
      ENDIF.
    ELSEIF lv_menu_failed > 0 AND lt_object_auth IS INITIAL.
      MESSAGE |No transaction was added to the menu of role { gv_selected_role }:{ lv_failed_txt }| TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
  ENDIF.

  IF lt_object_auth IS INITIAL.
    CLEAR lv_obj_count.
    PERFORM recheck_auths_after_add USING lv_menu_added
                                          lv_menu_failed
                                          lv_failed_txt
                                          lv_gen_failed
                                          lv_obj_count
                                          lv_total_added.
    RETURN.
  ENDIF.

  " Only the selected field values are kept. They are trimmed and grouped
  " so the same object never receives the same field value twice.
  " Organizational levels are stored separately for AGR_1252.
  SELECT field, varbl FROM usorg INTO TABLE @lt_usorg.

  LOOP AT lt_object_auth INTO ls_item.
    DATA: lt_def_fields TYPE STANDARD TABLE OF xufield,
          ls_tobj_def   TYPE tobj.
    CLEAR: lt_def_fields, ls_tobj_def.

    SELECT SINGLE fiel1, fiel2, fiel3, fiel4, fiel5, fiel6, fiel7, fiel8, fiel9, fiel0
      FROM tobj
      WHERE objct = @ls_item-object
      INTO CORRESPONDING FIELDS OF @ls_tobj_def.
    IF sy-subrc = 0.
      IF ls_tobj_def-fiel1 IS NOT INITIAL. APPEND ls_tobj_def-fiel1 TO lt_def_fields. ENDIF.
      IF ls_tobj_def-fiel2 IS NOT INITIAL. APPEND ls_tobj_def-fiel2 TO lt_def_fields. ENDIF.
      IF ls_tobj_def-fiel3 IS NOT INITIAL. APPEND ls_tobj_def-fiel3 TO lt_def_fields. ENDIF.
      IF ls_tobj_def-fiel4 IS NOT INITIAL. APPEND ls_tobj_def-fiel4 TO lt_def_fields. ENDIF.
      IF ls_tobj_def-fiel5 IS NOT INITIAL. APPEND ls_tobj_def-fiel5 TO lt_def_fields. ENDIF.
      IF ls_tobj_def-fiel6 IS NOT INITIAL. APPEND ls_tobj_def-fiel6 TO lt_def_fields. ENDIF.
      IF ls_tobj_def-fiel7 IS NOT INITIAL. APPEND ls_tobj_def-fiel7 TO lt_def_fields. ENDIF.
      IF ls_tobj_def-fiel8 IS NOT INITIAL. APPEND ls_tobj_def-fiel8 TO lt_def_fields. ENDIF.
      IF ls_tobj_def-fiel9 IS NOT INITIAL. APPEND ls_tobj_def-fiel9 TO lt_def_fields. ENDIF.
      IF ls_tobj_def-fiel0 IS NOT INITIAL. APPEND ls_tobj_def-fiel0 TO lt_def_fields. ENDIF.
    ENDIF.

    IF lt_def_fields IS NOT INITIAL.
      LOOP AT lt_def_fields INTO DATA(lv_df).
        DATA lv_df_val TYPE xuval.
        CLEAR lv_df_val.
        READ TABLE ls_item-check_values INTO DATA(ls_scv) WITH KEY field = lv_df.
        IF sy-subrc = 0 AND ls_scv-value IS NOT INITIAL.
          lv_df_val = ls_scv-value.
        ELSE.
          lv_df_val = '*'.
        ENDIF.
        PERFORM collect_selected_value USING ls_item-object lv_df lv_df_val lt_usorg
                                       CHANGING lt_agg_objs lt_org_vals lt_sel_objects.
      ENDLOOP.
    ELSE.
      LOOP AT ls_item-check_values INTO DATA(ls_sel_val).
        PERFORM collect_selected_value USING ls_item-object ls_sel_val-field ls_sel_val-value lt_usorg
                                       CHANGING lt_agg_objs lt_org_vals lt_sel_objects.
      ENDLOOP.
    ENDIF.
    INSERT ls_item-object INTO TABLE lt_sel_objects.
  ENDLOOP.

  IF lt_agg_objs IS INITIAL AND lt_org_vals IS INITIAL.
    IF lv_menu_added = 0.
      MESSAGE 'No authorization value left to add after cleanup.' TYPE 'S' DISPLAY LIKE 'E'.
    ENDIF.
    CLEAR lv_obj_count.
    PERFORM recheck_auths_after_add USING lv_menu_added
                                          lv_menu_failed
                                          lv_failed_txt
                                          lv_gen_failed
                                          lv_obj_count
                                          lv_total_added.
    RETURN.
  ENDIF.

  " 2. Lock the Role (Enqueue) - check if role is being edited
  CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
    EXPORTING
      activity_group = gv_selected_role
    EXCEPTIONS
      foreign_lock   = 1
      system_failure = 2
      OTHERS         = 3.
  IF sy-subrc <> 0.
    " sy-msgv1 contains the lock holder's username on foreign_lock
    DATA(lv_lock_user) = sy-msgv1.

    PERFORM eval_auths_for_role USING gv_selected_role.
    IF go_grid_auths IS BOUND.
      go_grid_auths->refresh_table_display( is_stable = VALUE #( row = 'X' col = 'X' ) ).
    ENDIF.

    IF lv_lock_user IS NOT INITIAL.
      MESSAGE |Role { gv_selected_role } is locked by user { lv_lock_user }. Please exit Edit mode in PFCG first, then try again.| TYPE 'S' DISPLAY LIKE 'E'.
    ELSE.
      MESSAGE |Role { gv_selected_role } is locked. Please exit Edit mode in PFCG first, then try again.| TYPE 'S' DISPLAY LIKE 'E'.
    ENDIF.
    RETURN.
  ENDIF.

  " 3. Read Current Role Authorization Structures via FMs
  DATA: lt_auth_data    TYPE tt_pt1250,
        lt_field_values TYPE tt_pt1251.

  CALL FUNCTION 'PRGN_1250_READ_AUTH_DATA'
    EXPORTING
      activity_group    = gv_selected_role
    TABLES
      auth_data         = lt_auth_data
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.

  CALL FUNCTION 'PRGN_1251_READ_FIELD_VALUES'
    EXPORTING
      activity_group    = gv_selected_role
    TABLES
      field_values      = lt_field_values
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.

  " 4. Add only the cleaned values. Open fields are left as they are.
  DATA: lv_auth_counter TYPE i.
  CLEAR: lv_auth_counter, lv_total_added, lv_org_added.

  LOOP AT lt_sel_objects INTO DATA(lv_sel_obj).
    PERFORM ensure_role_auth USING lv_sel_obj
                             CHANGING lt_auth_data lv_auth_counter.
  ENDLOOP.

  LOOP AT lt_agg_objs INTO DATA(ls_agg_obj).
    DATA: lv_auth TYPE xuauth.
    CLEAR lv_auth.
    READ TABLE lt_auth_data ASSIGNING FIELD-SYMBOL(<ls_ad>)
      WITH KEY object = ls_agg_obj-object.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.
    lv_auth = <ls_ad>-auth.
    <ls_ad>-modified = 'U'.
    <ls_ad>-deleted  = ' '.  " Reactivate if was deactivated

    LOOP AT ls_agg_obj-values INTO DATA(ls_val).
      READ TABLE lt_field_values ASSIGNING FIELD-SYMBOL(<ls_fv>)
        WITH KEY object = ls_agg_obj-object auth = lv_auth field = ls_val-field low = ls_val-low.
      IF sy-subrc = 0.
        <ls_fv>-deleted  = ' '.
        <ls_fv>-modified = 'U'.
      ELSE.
        READ TABLE lt_field_values ASSIGNING FIELD-SYMBOL(<ls_empty_fv>)
          WITH KEY object = ls_agg_obj-object auth = lv_auth field = ls_val-field low = space.
        IF sy-subrc = 0.
          <ls_empty_fv>-low      = ls_val-low.
          <ls_empty_fv>-modified = 'U'.
          <ls_empty_fv>-deleted  = ' '.
          <ls_empty_fv>-neu      = 'X'.
        ELSE.
          READ TABLE lt_field_values ASSIGNING FIELD-SYMBOL(<ls_star_fv>)
            WITH KEY object = ls_agg_obj-object auth = lv_auth field = ls_val-field low = '*'.
          IF sy-subrc = 0.
            <ls_star_fv>-deleted  = ' '.
            <ls_star_fv>-modified = 'U'.
          ELSE.
            APPEND VALUE pt1251(
              object   = ls_agg_obj-object
              auth     = lv_auth
              variant  = ' '
              field    = ls_val-field
              low      = ls_val-low
              modified = 'U'
              neu      = 'X'
              deleted  = ' '
            ) TO lt_field_values.
          ENDIF.
        ENDIF.
        lv_total_added = lv_total_added + 1.
      ENDIF.
    ENDLOOP.

    " Ensure 100% completeness: every single field defined in TOBJ must be present!
    SELECT SINGLE fiel1, fiel2, fiel3, fiel4, fiel5, fiel6, fiel7, fiel8, fiel9, fiel0
      FROM tobj
      WHERE objct = @ls_agg_obj-object
      INTO CORRESPONDING FIELDS OF @ls_tobj_def.
    IF sy-subrc = 0.
      CLEAR lt_def_fields.
      IF ls_tobj_def-fiel1 IS NOT INITIAL. APPEND ls_tobj_def-fiel1 TO lt_def_fields. ENDIF.
      IF ls_tobj_def-fiel2 IS NOT INITIAL. APPEND ls_tobj_def-fiel2 TO lt_def_fields. ENDIF.
      IF ls_tobj_def-fiel3 IS NOT INITIAL. APPEND ls_tobj_def-fiel3 TO lt_def_fields. ENDIF.
      IF ls_tobj_def-fiel4 IS NOT INITIAL. APPEND ls_tobj_def-fiel4 TO lt_def_fields. ENDIF.
      IF ls_tobj_def-fiel5 IS NOT INITIAL. APPEND ls_tobj_def-fiel5 TO lt_def_fields. ENDIF.
      IF ls_tobj_def-fiel6 IS NOT INITIAL. APPEND ls_tobj_def-fiel6 TO lt_def_fields. ENDIF.
      IF ls_tobj_def-fiel7 IS NOT INITIAL. APPEND ls_tobj_def-fiel7 TO lt_def_fields. ENDIF.
      IF ls_tobj_def-fiel8 IS NOT INITIAL. APPEND ls_tobj_def-fiel8 TO lt_def_fields. ENDIF.
      IF ls_tobj_def-fiel9 IS NOT INITIAL. APPEND ls_tobj_def-fiel9 TO lt_def_fields. ENDIF.
      IF ls_tobj_def-fiel0 IS NOT INITIAL. APPEND ls_tobj_def-fiel0 TO lt_def_fields. ENDIF.

      LOOP AT lt_def_fields INTO DATA(lv_check_fld).
        READ TABLE lt_field_values ASSIGNING FIELD-SYMBOL(<ls_any_fv>)
          WITH KEY object = ls_agg_obj-object auth = lv_auth field = lv_check_fld.
        IF sy-subrc <> 0.
          APPEND VALUE pt1251(
            object   = ls_agg_obj-object
            auth     = lv_auth
            variant  = ' '
            field    = lv_check_fld
            low      = '*'
            modified = 'U'
            neu      = 'X'
            deleted  = ' '
          ) TO lt_field_values.
          lv_total_added = lv_total_added + 1.
        ELSE.
          IF <ls_any_fv>-low IS INITIAL OR <ls_any_fv>-low = space.
            <ls_any_fv>-low      = '*'.
            <ls_any_fv>-modified = 'U'.
            <ls_any_fv>-neu      = 'X'.
          ENDIF.
          <ls_any_fv>-deleted  = ' '.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDLOOP.

  " Global sweep: ensure NO field in lt_field_values for target role has low = space
  LOOP AT lt_field_values ASSIGNING FIELD-SYMBOL(<ls_sweep_fv>).
    IF <ls_sweep_fv>-low IS INITIAL OR <ls_sweep_fv>-low = space.
      <ls_sweep_fv>-low      = '*'.
      <ls_sweep_fv>-modified = 'U'.
      <ls_sweep_fv>-neu      = 'X'.
    ENDIF.
    <ls_sweep_fv>-deleted  = ' '.
  ENDLOOP.

  " Organizational levels are maintained in AGR_1252, then copied onto
  " every authorization of objects that use that field.
  IF lt_org_vals IS NOT INITIAL.
    DATA lt_org_all TYPE tt_pt1252.
    PERFORM save_org_levels USING gv_selected_role lt_org_vals
                            CHANGING lt_org_all lv_org_added.
    PERFORM distribute_org_levels USING lt_usorg lt_org_vals lt_org_all
                                  CHANGING lt_auth_data lt_field_values.
    lv_total_added = lv_total_added + lv_org_added.
  ENDIF.

  lv_obj_count = lines( lt_sel_objects ).

  " 5. Save Changes via Standard PFCG Function Modules
  CALL FUNCTION 'PRGN_1250_SAVE_AUTH_DATA'
    EXPORTING
      activity_group = gv_selected_role
    TABLES
      auth_data      = lt_auth_data.

  CALL FUNCTION 'PRGN_1251_SAVE_FIELD_VALUES'
    EXPORTING
      activity_group = gv_selected_role
    TABLES
      field_values   = lt_field_values.

  CALL FUNCTION 'PRGN_UPDATE_DATABASE'.
  COMMIT WORK AND WAIT.

  " 6. Unlock the Role (Dequeue) BEFORE profile generation.
  " The generation FM needs to manage its own lock lifecycle.
  CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
    EXPORTING
      activity_group = gv_selected_role.

  " 7. Regenerate profile. The FM will enqueue/dequeue on its own.
  PERFORM generate_role_profile USING gv_selected_role ' ' abap_true abap_false CHANGING lv_gen_subrc.
  IF lv_gen_subrc <> 0.
    lv_gen_failed = abap_true.
  ENDIF.
  COMMIT WORK AND WAIT.

  PERFORM recheck_auths_after_add USING lv_menu_added
                                        lv_menu_failed
                                        lv_failed_txt
                                        lv_gen_failed
                                        lv_obj_count
                                        lv_total_added.
ENDFORM.

*----------------------------------------------------------------------*
* Selected values, organizational levels, role menu
*----------------------------------------------------------------------*
FORM collect_selected_value USING pv_object TYPE tobj-objct
                                  pv_field  TYPE xufield
                                  pv_value  TYPE xuval
                                  pt_usorg  TYPE tt_usorg
                            CHANGING ct_objs TYPE tt_agg_obj
                                     ct_orgs TYPE tt_org_val
                                     ct_sel  TYPE tt_obj_name.
  DATA: lv_value TYPE xuval,
        lv_field TYPE xufield,
        ls_usorg TYPE ty_usorg,
        ls_org   TYPE ty_org_val.

  IF pv_object IS INITIAL OR pv_field IS INITIAL OR pv_value IS INITIAL.
    RETURN.
  ENDIF.

  lv_field = pv_field.
  TRANSLATE lv_field TO UPPER CASE.
  CONDENSE lv_field NO-GAPS.
  IF lv_field IS INITIAL OR lv_field = 'DUMMYFIELD'.
    RETURN.
  ENDIF.

  lv_value = pv_value.
  CONDENSE lv_value.
  IF lv_value IS INITIAL.
    RETURN.
  ENDIF.

  READ TABLE pt_usorg INTO ls_usorg WITH TABLE KEY field = lv_field.
  IF sy-subrc = 0 AND ls_usorg-varbl IS NOT INITIAL.
    ls_org-varbl = ls_usorg-varbl.
    ls_org-low   = lv_value.
    INSERT ls_org INTO TABLE ct_orgs.
    INSERT pv_object INTO TABLE ct_sel.
    RETURN.
  ENDIF.

  READ TABLE ct_objs ASSIGNING FIELD-SYMBOL(<ls_obj>) WITH KEY object = pv_object.
  IF sy-subrc <> 0.
    APPEND VALUE ty_agg_obj( object = pv_object ) TO ct_objs.
    ASSIGN ct_objs[ object = pv_object ] TO <ls_obj>.
  ENDIF.

  READ TABLE <ls_obj>-values TRANSPORTING NO FIELDS
    WITH KEY field = lv_field low = lv_value.
  IF sy-subrc <> 0.
    APPEND VALUE ty_agg_val( field = lv_field low = lv_value ) TO <ls_obj>-values.
  ENDIF.
  INSERT pv_object INTO TABLE ct_sel.
ENDFORM.

FORM ensure_role_auth USING pv_object TYPE tobj-objct
                      CHANGING ct_auth    TYPE tt_pt1250
                               cv_counter TYPE i.
  DATA lv_auth TYPE xuauth.

  READ TABLE ct_auth ASSIGNING FIELD-SYMBOL(<ls_auth>) WITH KEY object = pv_object.
  IF sy-subrc = 0.
    <ls_auth>-modified = 'U'.
    <ls_auth>-deleted  = ' '.  " Reactivate if was deactivated!
    RETURN.
  ENDIF.

  DO 99 TIMES.
    lv_auth = |__________{ cv_counter WIDTH = 2 ALIGN = RIGHT PAD = '0' }|.
    READ TABLE ct_auth TRANSPORTING NO FIELDS
      WITH KEY object = pv_object auth = lv_auth.
    IF sy-subrc <> 0.
      EXIT.
    ENDIF.
    cv_counter = cv_counter + 1.
  ENDDO.

  SELECT SINGLE ttext FROM tobjt
    WHERE langu = @sy-langu AND object = @pv_object
    INTO @DATA(lv_text).
  IF sy-subrc <> 0.
    SELECT SINGLE ttext FROM tobjt
      WHERE langu = 'E' AND object = @pv_object
      INTO @lv_text.
  ENDIF.

  APPEND VALUE pt1250(
    object   = pv_object
    auth     = lv_auth
    variant  = ' '
    modified = 'U'
    copied   = ' '
    neu      = 'X'
    deleted  = ' '
    atext    = lv_text
  ) TO ct_auth.
ENDFORM.

FORM save_org_levels USING pv_role TYPE agr_name
                           pt_new  TYPE tt_org_val
                     CHANGING ct_all   TYPE tt_pt1252
                              cv_added TYPE i.
  DATA: ls_new TYPE ty_org_val,
        ls_row TYPE pt1252.

  CLEAR: ct_all, cv_added.

  CALL FUNCTION 'PRGN_1252_READ_ORG_LEVELS'
    EXPORTING
      activity_group    = pv_role
    TABLES
      org_levels        = ct_all
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.

  LOOP AT pt_new INTO ls_new.
    READ TABLE ct_all TRANSPORTING NO FIELDS
      WITH KEY varbl = ls_new-varbl low = ls_new-low.
    IF sy-subrc <> 0.
      CLEAR ls_row.
      ls_row-varbl = ls_new-varbl.
      ls_row-low   = ls_new-low.
      APPEND ls_row TO ct_all.
      cv_added = cv_added + 1.
    ENDIF.
  ENDLOOP.

  CALL FUNCTION 'PRGN_1252_SAVE_ORG_LEVELS'
    EXPORTING
      activity_group = pv_role
    TABLES
      org_levels     = ct_all.
ENDFORM.

FORM add_obj_field USING pv_object TYPE tobj-objct
                         pv_field  TYPE xufield
                   CHANGING ct_fields TYPE tt_obj_field.
  DATA ls_fld TYPE ty_obj_field.

  IF pv_object IS INITIAL OR pv_field IS INITIAL.
    RETURN.
  ENDIF.
  ls_fld-object = pv_object.
  ls_fld-field  = pv_field.
  TRANSLATE ls_fld-field TO UPPER CASE.
  INSERT ls_fld INTO TABLE ct_fields.
ENDFORM.

FORM distribute_org_levels USING pt_usorg TYPE tt_usorg
                                 pt_new   TYPE tt_org_val
                                 pt_all   TYPE tt_pt1252
                           CHANGING ct_auth TYPE tt_pt1250
                                    ct_flds TYPE tt_pt1251.
  DATA: lt_obj_fields TYPE tt_obj_field,
        lt_varbl      TYPE SORTED TABLE OF agr_1252-varbl WITH UNIQUE KEY table_line,
        lv_field      TYPE xufield.

  IF ct_auth IS INITIAL.
    RETURN.
  ENDIF.

  SELECT objct, fiel1, fiel2, fiel3, fiel4, fiel5,
         fiel6, fiel7, fiel8, fiel9, fiel0
    FROM tobj
    FOR ALL ENTRIES IN @ct_auth
    WHERE objct = @ct_auth-object
    INTO TABLE @DATA(lt_tobj).

  LOOP AT lt_tobj INTO DATA(ls_tobj).
    PERFORM add_obj_field USING ls_tobj-objct ls_tobj-fiel1 CHANGING lt_obj_fields.
    PERFORM add_obj_field USING ls_tobj-objct ls_tobj-fiel2 CHANGING lt_obj_fields.
    PERFORM add_obj_field USING ls_tobj-objct ls_tobj-fiel3 CHANGING lt_obj_fields.
    PERFORM add_obj_field USING ls_tobj-objct ls_tobj-fiel4 CHANGING lt_obj_fields.
    PERFORM add_obj_field USING ls_tobj-objct ls_tobj-fiel5 CHANGING lt_obj_fields.
    PERFORM add_obj_field USING ls_tobj-objct ls_tobj-fiel6 CHANGING lt_obj_fields.
    PERFORM add_obj_field USING ls_tobj-objct ls_tobj-fiel7 CHANGING lt_obj_fields.
    PERFORM add_obj_field USING ls_tobj-objct ls_tobj-fiel8 CHANGING lt_obj_fields.
    PERFORM add_obj_field USING ls_tobj-objct ls_tobj-fiel9 CHANGING lt_obj_fields.
    PERFORM add_obj_field USING ls_tobj-objct ls_tobj-fiel0 CHANGING lt_obj_fields.
  ENDLOOP.

  LOOP AT pt_new INTO DATA(ls_new).
    INSERT ls_new-varbl INTO TABLE lt_varbl.
  ENDLOOP.

  LOOP AT lt_varbl INTO DATA(lv_varbl).
    CLEAR lv_field.
    LOOP AT pt_usorg INTO DATA(ls_us) WHERE varbl = lv_varbl.
      lv_field = ls_us-field.
      EXIT.
    ENDLOOP.
    IF lv_field IS INITIAL.
      CONTINUE.
    ENDIF.

    LOOP AT ct_auth ASSIGNING FIELD-SYMBOL(<ls_auth>).
      READ TABLE lt_obj_fields TRANSPORTING NO FIELDS
        WITH TABLE KEY object = <ls_auth>-object field = lv_field.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      DELETE ct_flds WHERE object = <ls_auth>-object
                       AND auth   = <ls_auth>-auth
                       AND field  = lv_field.

      DATA lv_org_appended TYPE abap_bool.
      lv_org_appended = abap_false.

      LOOP AT pt_all INTO DATA(ls_all) WHERE varbl = lv_varbl.
        IF ls_all-low IS INITIAL AND ls_all-high IS INITIAL.
          CONTINUE.
        ENDIF.
        APPEND VALUE pt1251(
          object   = <ls_auth>-object
          auth     = <ls_auth>-auth
          variant  = ' '
          field    = lv_field
          low      = ls_all-low
          high     = ls_all-high
          modified = 'U'
          neu      = 'X'
          deleted  = ' '
        ) TO ct_flds.
        lv_org_appended = abap_true.
      ENDLOOP.

      IF lv_org_appended = abap_false.
        APPEND VALUE pt1251(
          object   = <ls_auth>-object
          auth     = <ls_auth>-auth
          variant  = ' '
          field    = lv_field
          low      = '*'
          modified = 'U'
          neu      = 'X'
          deleted  = ' '
        ) TO ct_flds.
      ENDIF.
      <ls_auth>-modified = 'U'.
      <ls_auth>-deleted  = ' '.
    ENDLOOP.
  ENDLOOP.
ENDFORM.

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
    IF sy-subrc = 0.
      cv_added = cv_added + 1.
    ELSE.
      cv_failed = cv_failed + 1.
      cv_failed_txt = |{ cv_failed_txt } { lv_tcode }|.
      " Lock, missing role, derived menu, or missing authority blocks the whole add.
      IF sy-subrc = 1 OR sy-subrc = 2 OR sy-subrc = 4 OR sy-subrc = 6.
        cv_abort = abap_true.
        IF sy-subrc = 1.
          MESSAGE |Role { pv_role } is locked (Edit mode). Please exit Edit mode in PFCG first, then try again.| TYPE 'S' DISPLAY LIKE 'E'.
        ELSE.
          MESSAGE |Cannot add transaction { lv_tcode } to the menu of role { pv_role }.| TYPE 'S' DISPLAY LIKE 'E'.
        ENDIF.
        RETURN.
      ENDIF.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM generate_role_profile USING pv_role           TYPE agr_name
                                 pv_rebuild        TYPE char01
                                 pv_all_maintained TYPE abap_bool
                                 pv_caller_locked  TYPE abap_bool
                           CHANGING cv_subrc TYPE sy-subrc.
  DATA: lt_return  TYPE bapirettab,
        lt_orgs    TYPE tt_pt1252,
        lv_org_mod TYPE abap_bool.

  IF pv_caller_locked = abap_false.
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
      EXPORTING
        activity_group = pv_role
      EXCEPTIONS
        foreign_lock   = 1
        system_failure = 2
        OTHERS         = 3.
    IF sy-subrc <> 0.
      cv_subrc = sy-subrc.
      RETURN.
    ENDIF.
  ENDIF.

  " Force-maintain all unmaintained Organizational Levels in AGR_1252 with '*'
  " This mirrors what PFCG does when an administrator generates a profile
  " and chooses 'All maintained' (full authorization for unmaintained org levels)
  CLEAR: lt_orgs, lv_org_mod.
  CALL FUNCTION 'PRGN_1252_READ_ORG_LEVELS'
    EXPORTING
      activity_group    = pv_role
    TABLES
      org_levels        = lt_orgs
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.
  IF sy-subrc = 0 AND lt_orgs IS NOT INITIAL.
    LOOP AT lt_orgs ASSIGNING FIELD-SYMBOL(<ls_org>).
      IF <ls_org>-low IS INITIAL OR <ls_org>-low = space.
        <ls_org>-low = '*'.
        lv_org_mod   = abap_true.
      ENDIF.
    ENDLOOP.
    IF lv_org_mod = abap_true.
      CALL FUNCTION 'PRGN_1252_SAVE_ORG_LEVELS'
        EXPORTING
          activity_group = pv_role
        TABLES
          org_levels     = lt_orgs.
      CALL FUNCTION 'PRGN_UPDATE_DATABASE'.
      COMMIT WORK AND WAIT.
    ENDIF.
  ENDIF.

  CALL FUNCTION 'SUPRN_DARK_MANIPULATE_PROFILE'
    EXPORTING
      activity_group        = pv_role
      fill_orgs_with_star   = 'X'
      fill_fields_with_star = 'X'
      no_dialog             = 'X'
      rebuild_auth_data     = pv_rebuild
      generate_profile      = 'X'
    IMPORTING
      return                = lt_return
    EXCEPTIONS
      open_auths                     = 1
      no_auth_for_gen                = 2
      no_auths                       = 3
      error_when_generating_profile  = 4
      OTHERS                         = 5.
  cv_subrc = sy-subrc.

  " Fallback: if SUPRN_DARK fails (e.g. open_auths), try standard generation
  IF cv_subrc <> 0.
    CLEAR lt_return.
    CALL FUNCTION 'PRGN_AUTO_GENERATE_PROFILE_NEW'
      EXPORTING
        activity_group              = pv_role
        no_dialog                   = 'X'
        rebuild_auth_data           = pv_rebuild
        org_levels_with_star        = 'X'
        fill_empty_fields_with_star = 'X'
        generate_profile            = 'X'
      TABLES
        return                      = lt_return
      EXCEPTIONS
        OTHERS                      = 1.
    cv_subrc = sy-subrc.
  ENDIF.

  IF pv_caller_locked = abap_false.
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
      EXPORTING
        activity_group = pv_role.
  ENDIF.
ENDFORM.

FORM field_value_covered USING pt_flds   TYPE tt_role_fld
                               pv_object TYPE tobj-objct
                               pv_auth   TYPE xuauth
                               pv_field  TYPE xufield
                               pv_value  TYPE xuval
                         CHANGING cv_covered TYPE abap_bool.
  cv_covered = abap_false.

  IF pv_field IS INITIAL.
    cv_covered = abap_true.
    RETURN.
  ENDIF.

  LOOP AT pt_flds INTO DATA(ls_fld)
    WHERE object = pv_object
      AND auth   = pv_auth
      AND field  = pv_field.
    IF ls_fld-low = '*' OR ls_fld-low = pv_value.
      cv_covered = abap_true.
      RETURN.
    ENDIF.
    IF ls_fld-high IS NOT INITIAL
       AND ls_fld-low IS NOT INITIAL
       AND ls_fld-low <> '*'
       AND pv_value >= ls_fld-low
       AND pv_value <= ls_fld-high.
      cv_covered = abap_true.
      RETURN.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM recheck_auths_after_add USING pv_menu_added TYPE i
                                   pv_menu_failed TYPE i
                                   pv_failed_txt  TYPE string
                                   pv_gen_failed  TYPE abap_bool
                                   pv_obj_count   TYPE i
                                   pv_val_count   TYPE i.
  DATA: lv_msg     TYPE string,
        lv_has_info TYPE abap_bool VALUE abap_false.

  PERFORM eval_auths_for_role USING gv_selected_role.
  IF go_grid_auths IS BOUND.
    go_grid_auths->refresh_table_display( is_stable = VALUE #( row = 'X' col = 'X' ) ).
  ENDIF.
  IF go_grid_roles IS BOUND.
    go_grid_roles->refresh_table_display( is_stable = VALUE #( row = 'X' col = 'X' ) ).
  ENDIF.

  lv_msg = |Role { gv_selected_role }:|.

  IF pv_menu_added > 0.
    lv_msg = |{ lv_msg } { pv_menu_added } TCode(s) added to menu.|.
    lv_has_info = abap_true.
  ENDIF.
  IF pv_obj_count > 0 OR pv_val_count > 0.
    lv_msg = |{ lv_msg } { pv_obj_count } object(s) / { pv_val_count } value(s) added.|.
    lv_has_info = abap_true.
  ENDIF.
  IF pv_menu_failed > 0.
    lv_msg = |{ lv_msg } Menu skipped:{ pv_failed_txt }.|.
    lv_has_info = abap_true.
  ENDIF.
  IF pv_gen_failed = abap_true.
    lv_msg = |{ lv_msg } Profile generation had warnings (profile may still be updated).|.
    lv_has_info = abap_true.
  ENDIF.

  IF lv_has_info = abap_false.
    lv_msg = |{ lv_msg } No new changes (values may already exist in role). Profile regenerated.|.
  ENDIF.

  IF pv_gen_failed = abap_true.
    MESSAGE lv_msg TYPE 'S' DISPLAY LIKE 'W'.
  ELSE.
    MESSAGE lv_msg TYPE 'S'.
  ENDIF.
ENDFORM.

FORM refresh_all_data.
  IF gv_in_refresh = abap_true.
    RETURN.
  ENDIF.
  gv_in_refresh = abap_true.

  PERFORM get_user_roles USING p_uname p_actv.
  IF gv_selected_role IS INITIAL
     OR NOT line_exists( gt_user_roles[ agr_name = gv_selected_role ] ).
    IF gt_user_roles IS NOT INITIAL.
      gv_selected_role = gt_user_roles[ 1 ]-agr_name.
    ELSE.
      CLEAR gv_selected_role.
    ENDIF.
  ENDIF.
  LOOP AT gt_user_roles ASSIGNING FIELD-SYMBOL(<ls_rf>).
    IF <ls_rf>-agr_name = gv_selected_role.
      <ls_rf>-radio = gc_radio_on.
    ELSE.
      <ls_rf>-radio = gc_radio_off.
    ENDIF.
  ENDLOOP.

  PERFORM get_missing_authorizations USING p_uname.
  PERFORM eval_auths_for_role USING gv_selected_role.

  IF go_grid_roles IS BOUND.
    go_grid_roles->refresh_table_display( is_stable = VALUE #( row = 'X' col = 'X' ) ).
  ENDIF.
  IF go_grid_auths IS BOUND.
    go_grid_auths->refresh_table_display( is_stable = VALUE #( row = 'X' col = 'X' ) ).
  ENDIF.

  MESSAGE 'Data refreshed from SU53 buffer and SAP user roles.' TYPE 'S'.
  gv_in_refresh = abap_false.
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
      PERFORM refresh_all_data.
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
