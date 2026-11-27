*&---------------------------------------------------------------------*
*& Report Z_AUTH_SU53_ANALYZER
*&---------------------------------------------------------------------*
*& Advanced SU53 Authorization Trace & Role Diagnostics Analyzer
*& Transaction Code: ZAT
*& Package: $TMP (Local Object) or Custom Package
*& Architecture: Dual-ALV Layout (Docking Single Roles + Fullscreen Missing Auths)
*&---------------------------------------------------------------------*
REPORT z_auth_su53_analyzer.

TABLES: usr02, agr_define.

*----------------------------------------------------------------------*
* 1. TYPES & DATA DEFINITIONS
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_user_role,
         locked     TYPE c LENGTH 1,         " 'X' if role is currently locked/targeted
         radio      TYPE c LENGTH 4,         " Radio indicator: @06@ (Selected) / @07@ (Unselected)
         agr_name   TYPE agr_name,           " Single Role Name
         text       TYPE c LENGTH 80,        " Role Description
         parent_agr TYPE agr_name,           " Leading Role (Master Role)
         comp_agr   TYPE agr_name,           " Composite Role
         from_dat   TYPE agr_fdate,          " Valid From Date
         to_dat     TYPE agr_tdate,          " Valid To Date
         row_color  TYPE c LENGTH 4,         " Row highlight color for locked role
       END OF ty_user_role.

TYPES: tt_user_role TYPE STANDARD TABLE OF ty_user_role.

TYPES: BEGIN OF ty_check_value,
         field TYPE xufield,
         value TYPE xuval,
       END OF ty_check_value.
TYPES: tt_check_value TYPE STANDARD TABLE OF ty_check_value WITH DEFAULT KEY.

TYPES: BEGIN OF ty_missing_auth,
         sel         TYPE c LENGTH 1,         " Checkbox
         status      TYPE c LENGTH 12,        " Status Icon & Code: @08@ [OK], @09@ [WARN], @0A@ [ERR]
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

TYPES: BEGIN OF ty_combo_org,
         field TYPE xufield,
         varbl TYPE usorg-varbl,
         low   TYPE xuval,
       END OF ty_combo_org.
TYPES: tt_combo_org TYPE STANDARD TABLE OF ty_combo_org WITH DEFAULT KEY.

TYPES: BEGIN OF ty_sel_combo,
         object     TYPE tobj-objct,
         values     TYPE tt_agg_val,
         org_fields TYPE tt_combo_org,
       END OF ty_sel_combo.
TYPES: tt_sel_combo TYPE STANDARD TABLE OF ty_sel_combo WITH DEFAULT KEY.

TYPES: tt_varbl  TYPE SORTED TABLE OF agr_1252-varbl WITH UNIQUE KEY table_line,
       tt_xuauth TYPE SORTED TABLE OF xuauth WITH UNIQUE KEY table_line.

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
         object   TYPE tobj-objct,
         auth     TYPE xuauth,
         field    TYPE xufield,
         low      TYPE xuval,
         high     TYPE xuval,
         modified TYPE tpr_st_mod,
       END OF ty_role_fld.
TYPES: tt_role_fld TYPE STANDARD TABLE OF ty_role_fld WITH DEFAULT KEY.

TYPES: BEGIN OF ty_role_obj,
         object TYPE tobj-objct,
         auth   TYPE xuauth,
       END OF ty_role_obj.
TYPES: tt_role_obj TYPE STANDARD TABLE OF ty_role_obj WITH DEFAULT KEY.

TYPES: tt_tcode TYPE SORTED TABLE OF sytcode WITH UNIQUE KEY table_line.
TYPES: tt_agr_name TYPE STANDARD TABLE OF agr_name WITH DEFAULT KEY.

DATA: gt_missing_auth  TYPE tt_missing_auth,
      gt_user_roles    TYPE tt_user_role,
      gv_selected_role TYPE agr_name,
      gv_leading_role  TYPE agr_name,
      gv_in_refresh    TYPE abap_bool,
      go_docking       TYPE REF TO cl_gui_docking_container,
      go_grid_roles    TYPE REF TO cl_gui_alv_grid,
      go_grid_auths    TYPE REF TO cl_gui_alv_grid.

CONSTANTS: gc_icon_red    TYPE c LENGTH 12 VALUE '@0A@ [ERR]',
           gc_icon_green  TYPE c LENGTH 12 VALUE '@08@ [OK]',
           gc_icon_yellow TYPE c LENGTH 12 VALUE '@09@ [WARN]',
           gc_radio_on    TYPE c LENGTH 4 VALUE '@06@',
           gc_radio_off   TYPE c LENGTH 4 VALUE '@07@',
           gc_blank_val   TYPE xuval VALUE ''''''.

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
  PARAMETERS: p_uname TYPE usr02-bname OBLIGATORY.
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
  PERFORM check_display_authority USING p_uname.
  PERFORM get_user_roles USING p_uname p_actv.

  IF gt_user_roles IS NOT INITIAL.
    ASSIGN gt_user_roles[ 1 ] TO FIELD-SYMBOL(<ls_r_init>).
    IF sy-subrc = 0.
      PERFORM sync_role_selection USING <ls_r_init>-agr_name.
    ENDIF.
  ELSE.
    CLEAR: gv_selected_role, gv_leading_role.
  ENDIF.

  PERFORM get_missing_authorizations USING p_uname.
  PERFORM eval_auths_for_role USING gv_selected_role.
  PERFORM display_alv_grid_lvc.

*&---------------------------------------------------------------------*
*& Form check_display_authority
*&---------------------------------------------------------------------*
FORM check_display_authority USING pv_uname TYPE usr02-bname.
  DATA lv_usr_class TYPE usr02-class.

  IF pv_uname <> sy-uname.
    CLEAR lv_usr_class.
    SELECT SINGLE class FROM usr02
      WHERE bname = @pv_uname
      INTO @lv_usr_class.
    AUTHORITY-CHECK OBJECT 'S_USER_GRP'
      ID 'CLASS' FIELD lv_usr_class
      ID 'ACTVT' FIELD '03'.
    IF sy-subrc <> 0.
      MESSAGE |No display authorization for user group '{ lv_usr_class }' (S_USER_GRP ACTVT 03).| TYPE 'E'.
    ENDIF.
  ENDIF.

  AUTHORITY-CHECK OBJECT 'S_USER_AGR'
    ID 'ACT_GROUP' DUMMY
    ID 'ACTVT'     FIELD '03'.
  IF sy-subrc <> 0.
    MESSAGE 'No display authorization for SAP roles (S_USER_AGR ACTVT 03).' TYPE 'E'.
  ENDIF.
ENDFORM.

*----------------------------------------------------------------------*
* 5. SUBROUTINES: DATA EXTRACTION
*----------------------------------------------------------------------*
FORM add_su53_field USING pv_field TYPE xufield
                          pv_value TYPE xuval
                    CHANGING ct_values TYPE tt_check_value.
  IF pv_field IS INITIAL OR to_upper( pv_field ) = 'DUMMYFIELD'.
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

  IF ls_return-type CA 'EA'.
    MESSAGE |SU53 read warning: { ls_return-message }| TYPE 'S' DISPLAY LIKE 'W'.
  ELSEIF lt_rfc_err IS NOT INITIAL.
    MESSAGE |SU53 read completed with RFC warnings on { lines( lt_rfc_err ) } server(s).| TYPE 'S' DISPLAY LIKE 'W'.
  ENDIF.

  IF lt_usr07_ext IS NOT INITIAL.
    SORT lt_usr07_ext BY timestamp DESCENDING instance ASCENDING.

    DATA: lv_obj_text TYPE tobjt-ttext,
          lv_time_str TYPE string,
          lv_tstmp_d  TYPE d,
          lv_tstmp_t  TYPE t.

    LOOP AT lt_usr07_ext INTO DATA(ls_su53).
      DATA: lv_f1 TYPE xufield, lv_v1 TYPE xuval,
            lv_f2 TYPE xufield, lv_v2 TYPE xuval,
            lv_f3 TYPE xufield, lv_v3 TYPE xuval,
            lt_check_values TYPE tt_check_value,
            lv_combination  TYPE string.

      CLEAR: lv_obj_text, lv_time_str, lv_tstmp_d, lv_tstmp_t.

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
        INTO @lv_obj_text.
      IF sy-subrc <> 0.
        SELECT SINGLE ttext FROM tobjt
          WHERE langu = @sy-langu AND object = @ls_su53-objct
          INTO @lv_obj_text.
      ENDIF.

      IF ls_su53-timestamp > 0.
        CONVERT TIME STAMP ls_su53-timestamp TIME ZONE sy-zonlo INTO DATE lv_tstmp_d TIME lv_tstmp_t.
        lv_time_str = |{ lv_tstmp_d DATE = USER } { lv_tstmp_t TIME = USER }|.
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
        user_values = '<No authorized role selected>'
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

  SELECT u~agr_name,
         COALESCE( t_en~text, t_sy~text ) AS text,
         u~from_dat,
         u~to_dat,
         d~parent_agr
    FROM agr_users AS u
    LEFT OUTER JOIN agr_texts AS t_en
      ON u~agr_name = t_en~agr_name
     AND t_en~spras = 'E'
     AND t_en~line  = '00000'
    LEFT OUTER JOIN agr_texts AS t_sy
      ON u~agr_name = t_sy~agr_name
     AND t_sy~spras = @sy-langu
     AND t_sy~line  = '00000'
    LEFT OUTER JOIN agr_define AS d
      ON u~agr_name = d~agr_name
    WHERE u~uname   = @pv_uname
      AND u~exclude = @space
    INTO TABLE @DATA(lt_roles).

  DATA: lt_user_comp TYPE tt_agr_name,
        lv_coll      TYPE char01,
        lv_inh       TYPE agr_name.

  LOOP AT lt_roles INTO DATA(ls_r).
    IF pv_active = abap_true.
      IF ls_r-from_dat > sy-datum OR ls_r-to_dat < sy-datum.
        CONTINUE.
      ENDIF.
    ENDIF.

    " SU53-M1: Enforce per-role display authorization (S_USER_AGR ACTVT 03)
    AUTHORITY-CHECK OBJECT 'S_USER_AGR'
      ID 'ACT_GROUP' FIELD ls_r-agr_name
      ID 'ACTVT'     FIELD '03'.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

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
      APPEND ls_r-agr_name TO lt_user_comp.
      CONTINUE.
    ENDIF.

    APPEND VALUE #(
      locked     = ' '
      radio      = gc_radio_off
      agr_name   = ls_r-agr_name
      text       = ls_r-text
      parent_agr = ls_r-parent_agr
      comp_agr   = space
      from_dat   = ls_r-from_dat
      to_dat     = ls_r-to_dat
      row_color  = space
    ) TO gt_user_roles.
  ENDLOOP.

  IF gt_user_roles IS NOT INITIAL AND lt_user_comp IS NOT INITIAL.
    SELECT agr_name, child_agr
      FROM agr_agrs
      FOR ALL ENTRIES IN @gt_user_roles
      WHERE child_agr = @gt_user_roles-agr_name
      INTO TABLE @DATA(lt_comp_map).

    SORT lt_comp_map BY child_agr agr_name.

    LOOP AT gt_user_roles ASSIGNING FIELD-SYMBOL(<ls_ur>).
      LOOP AT lt_comp_map INTO DATA(ls_map) WHERE child_agr = <ls_ur>-agr_name.
        IF line_exists( lt_user_comp[ table_line = ls_map-agr_name ] ).
          <ls_ur>-comp_agr = ls_map-agr_name.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDIF.

  SORT gt_user_roles BY comp_agr agr_name.
ENDFORM.

FORM sync_role_selection USING pv_role TYPE agr_name.
  gv_selected_role = pv_role.
  CLEAR gv_leading_role.

  READ TABLE gt_user_roles INTO DATA(ls_r) WITH KEY agr_name = gv_selected_role.
  IF sy-subrc = 0 AND ls_r-parent_agr IS NOT INITIAL.
    gv_leading_role = ls_r-parent_agr.
  ELSE.
    gv_leading_role = gv_selected_role.
  ENDIF.

  LOOP AT gt_user_roles ASSIGNING FIELD-SYMBOL(<ls_r>).
    IF <ls_r>-agr_name = gv_selected_role.
      <ls_r>-locked    = 'X'.
      <ls_r>-radio     = gc_radio_on.
      <ls_r>-row_color = 'C500'.
    ELSE.
      <ls_r>-locked    = ' '.
      <ls_r>-radio     = gc_radio_off.
      <ls_r>-row_color = space.
    ENDIF.
  ENDLOOP.
ENDFORM.

*----------------------------------------------------------------------*
* 6. SUBROUTINES: ROLE EVALUATION & VALIDATION
*----------------------------------------------------------------------*
FORM eval_auths_for_role USING pv_role TYPE agr_name.
  IF pv_role IS INITIAL.
    LOOP AT gt_missing_auth ASSIGNING FIELD-SYMBOL(<ls_no_r>).
      CLEAR: <ls_no_r>-cell_style, <ls_no_r>-cell_color.
      <ls_no_r>-sel = ' '.
      IF <ls_no_r>-object = 'SAP_ALL'.
        <ls_no_r>-is_in_role  = abap_true.
        <ls_no_r>-status      = gc_icon_green.
        <ls_no_r>-user_values = 'All authorizations active'.
      ELSEIF <ls_no_r>-object = 'INFO'.
        <ls_no_r>-is_in_role  = abap_true.
        <ls_no_r>-status      = gc_icon_yellow.
        <ls_no_r>-user_values = 'No errors'.
      ELSE.
        <ls_no_r>-is_in_role  = abap_false.
        <ls_no_r>-status      = gc_icon_red.
        <ls_no_r>-user_values = '<No authorized role selected>'.
      ENDIF.
      APPEND VALUE lvc_s_styl( fieldname = 'SEL' style = cl_gui_alv_grid=>mc_style_disabled ) TO <ls_no_r>-cell_style.
    ENDLOOP.
    RETURN.
  ENDIF.

  " Read all active field values currently in this role (ignore deactivated)
  DATA: lt_role_flds TYPE tt_role_fld,
        lt_role_objs TYPE tt_role_obj,
        lt_role_orgs TYPE tt_pt1252,
        lt_usorg_ev  TYPE tt_usorg.

  SELECT field, varbl FROM usorg INTO TABLE @lt_usorg_ev.

  SELECT object, auth, field, low, high, modified
    FROM agr_1251
    WHERE agr_name = @pv_role
      AND deleted  = ' '
      AND copied  <> 'I'
    INTO TABLE @lt_role_flds.

  " Read active authorization objects defined in this role
  SELECT object, auth
    FROM agr_1250
    WHERE agr_name = @pv_role
      AND deleted  = ' '
      AND copied  <> 'I'
    INTO TABLE @lt_role_objs.

  " Read Org Levels (AGR_1252) so $VARBL placeholders in AGR_1251 resolve accurately
  CALL FUNCTION 'PRGN_1252_READ_ORG_LEVELS'
    EXPORTING
      activity_group    = pv_role
    TABLES
      org_levels        = lt_role_orgs
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.

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
                                          lt_role_orgs
                                          lt_usorg_ev
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
    outputlen = 10
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
  ls_layout_lvc-grid_title = '2. Failed Authorization Checks (Select Items to Add to Role)'.

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
      APPEND VALUE #( fieldname = 'LOCKED'     coltext = 'Locked'           outputlen = 6 hotspot = 'X' just = 'C' ) TO lt_fcat_roles.
      APPEND VALUE #( fieldname = 'RADIO'      coltext = 'Target'           icon = 'X' hotspot = 'X' outputlen = 8 ) TO lt_fcat_roles.
      APPEND VALUE #( fieldname = 'AGR_NAME'   coltext = 'Assigned Role'    outputlen = 25 ) TO lt_fcat_roles.
      APPEND VALUE #( fieldname = 'TEXT'       coltext = 'Role Description' outputlen = 35 ) TO lt_fcat_roles.
      APPEND VALUE #( fieldname = 'PARENT_AGR' coltext = 'Leading Role'     outputlen = 25 hotspot = 'X' ) TO lt_fcat_roles.
      APPEND VALUE #( fieldname = 'COMP_AGR'   coltext = 'Composite Role'   outputlen = 25 ) TO lt_fcat_roles.
      APPEND VALUE #( fieldname = 'FROM_DAT'   coltext = 'Valid From'       outputlen = 12 ) TO lt_fcat_roles.
      APPEND VALUE #( fieldname = 'TO_DAT'     coltext = 'Valid To'         outputlen = 12 ) TO lt_fcat_roles.

      DATA: ls_layo_roles TYPE lvc_s_layo.
      ls_layo_roles-zebra      = 'X'.
      ls_layo_roles-cwidth_opt = 'X'.
      ls_layo_roles-info_fname = 'ROW_COLOR'.
      ls_layo_roles-grid_title = '1. Assigned Roles of User ("Locked" [X] = Active Target Role)'.

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
    WHEN '&REFRESH' OR 'REFRESH' OR '&F8' OR 'F8'.
      PERFORM refresh_all_data.
      rs_selfield-refresh = 'X'.

    WHEN 'ADD_ROLE'.
      PERFORM add_selected_auths_to_role.
      rs_selfield-refresh = 'X'.

    WHEN 'SEL_ALL'.
      DATA: lt_filtered TYPE lvc_t_fidx.
      CLEAR lt_filtered.
      IF go_grid_auths IS BOUND.
        go_grid_auths->get_filtered_entries( IMPORTING et_filtered_entries = lt_filtered ).
      ENDIF.
      LOOP AT gt_missing_auth ASSIGNING FIELD-SYMBOL(<ls_a>).
        DATA(lv_row_idx) = sy-tabix.
        IF line_exists( lt_filtered[ table_line = lv_row_idx ] ).
          CONTINUE.
        ENDIF.
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

  " Determine target Leading Role (Master Role).
  " If selected role is a Derived Role, all TCode/Auth additions MUST be made
  " to the Leading Role first, then selectively derived down to child roles.
  DATA: lv_target_role TYPE agr_name,
        lv_is_derived  TYPE abap_bool.

  READ TABLE gt_user_roles INTO DATA(ls_target_r) WITH KEY agr_name = gv_selected_role.
  IF sy-subrc = 0 AND ls_target_r-parent_agr IS NOT INITIAL.
    lv_target_role = ls_target_r-parent_agr.
    lv_is_derived  = abap_true.
  ELSE.
    lv_target_role = gv_selected_role.
    lv_is_derived  = abap_false.
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

  " Determine derived child roles upfront to verify atomic S_USER_AGR/S_USER_PRO/S_USER_VAL BEFORE any commit
  DATA: lt_child_roles TYPE tt_agr_name,
        lv_is_master_r TYPE abap_bool,
        lv_confirm_ans TYPE c LENGTH 1,
        lv_confirm_q   TYPE string.

  CLEAR: lt_child_roles, lv_is_master_r, lv_confirm_ans.
  SELECT agr_name FROM agr_define
    WHERE parent_agr = @lv_target_role
    INTO TABLE @lt_child_roles.
  lv_is_master_r = xsdbool( lv_is_derived = abap_true OR lt_child_roles IS NOT INITIAL ).

  " S_USER_AGR ACTVT '02' upfront on target role AND every derived child role (prevents Master/Child drift!)
  AUTHORITY-CHECK OBJECT 'S_USER_AGR'
    ID 'ACT_GROUP' FIELD lv_target_role
    ID 'ACTVT'     FIELD '02'.
  IF sy-subrc <> 0.
    MESSAGE |No change authorization (S_USER_AGR ACTVT 02) for role { lv_target_role }.| TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  LOOP AT lt_child_roles INTO DATA(lv_ch_auth_chk).
    AUTHORITY-CHECK OBJECT 'S_USER_AGR'
      ID 'ACT_GROUP' FIELD lv_ch_auth_chk
      ID 'ACTVT'     FIELD '02'.
    IF sy-subrc <> 0.
      MESSAGE |No change authorization (S_USER_AGR ACTVT 02) for derived role { lv_ch_auth_chk }.| TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
  ENDLOOP.

  " AUD-H5: Enforce S_USER_PRO against actual profiles from AGR_1016 on target & child roles BEFORE any write
  TYPES: BEGIN OF ty_role_prof,
           agr_name TYPE agr_name,
           profile  TYPE xuprofile,
         END OF ty_role_prof,
         BEGIN OF ty_d3_pair,
           object TYPE tobj-objct,
           field  TYPE xufield,
           varbl  TYPE usorg-varbl,
         END OF ty_d3_pair,
         BEGIN OF ty_su24_key,
           name   TYPE usobx_c-name,
           object TYPE usobx_c-object,
         END OF ty_su24_key.

  DATA: lt_prof_chk_roles TYPE tt_agr_name,
        lt_role_profs     TYPE STANDARD TABLE OF ty_role_prof,
        lt_menu_tcodes     TYPE tt_tcode,
        lt_object_auth     TYPE tt_missing_auth,
        lt_sel_combos      TYPE tt_sel_combo,
        lt_auth_data       TYPE tt_pt1250,
        lt_field_values    TYPE tt_pt1251,
        lt_org_curr        TYPE tt_pt1252,
        lt_lead_objs_prior TYPE SORTED TABLE OF tobj-objct WITH UNIQUE KEY table_line,
        lt_su24_objs       TYPE SORTED TABLE OF tobj-objct WITH UNIQUE KEY table_line,
        lt_su24_c_keys     TYPE HASHED TABLE OF ty_su24_key WITH UNIQUE KEY name object,
        lt_usorg           TYPE tt_usorg,
        lt_org_vals        TYPE tt_org_val,
        lt_sel_objects     TYPE tt_obj_name,
        lt_pre_tobj_objs   TYPE tt_obj_name,
        lt_pre_tobj_flds   TYPE tt_obj_field,
        lt_d3_pairs        TYPE HASHED TABLE OF ty_d3_pair WITH UNIQUE KEY object field varbl,
        lv_menu_added      TYPE i,
        lv_menu_failed     TYPE i,
        lv_menu_abort      TYPE abap_bool,
        lv_failed_txt      TYPE string,
        lv_gen_subrc       TYPE sy-subrc,
        lv_gen_failed      TYPE abap_bool,
        lv_total_added     TYPE i,
        lv_obj_count       TYPE i,
        lv_org_added       TYPE i,
        lv_tcode_val       TYPE xuval,
        lv_chk_val         TYPE xuval,
        lv_m_org_mod       TYPE abap_bool,
        lv_step2_err       TYPE abap_bool,
        lv_step2_msg       TYPE string.

  CLEAR: lt_prof_chk_roles, lt_role_profs, lt_menu_tcodes, lt_object_auth,
         lt_sel_combos, lt_org_vals, lt_sel_objects, lt_lead_objs_prior,
         lt_su24_objs, lt_su24_c_keys, lt_usorg, lt_pre_tobj_objs,
         lt_pre_tobj_flds, lt_d3_pairs, lv_menu_added, lv_menu_failed,
         lv_menu_abort, lv_failed_txt, lv_gen_subrc, lv_gen_failed,
         lv_total_added, lv_obj_count, lv_org_added, lv_m_org_mod,
         lv_step2_err, lv_step2_msg.

  APPEND lv_target_role TO lt_prof_chk_roles.
  APPEND LINES OF lt_child_roles TO lt_prof_chk_roles.
  SELECT agr_name, profile FROM agr_1016
    FOR ALL ENTRIES IN @lt_prof_chk_roles
    WHERE agr_name = @lt_prof_chk_roles-table_line
    INTO TABLE @lt_role_profs.

  LOOP AT lt_prof_chk_roles INTO DATA(lv_pr_role).
    DATA(lv_has_prof_row) = abap_false.
    LOOP AT lt_role_profs INTO DATA(ls_rp) WHERE agr_name = lv_pr_role.
      lv_has_prof_row = abap_true.
      AUTHORITY-CHECK OBJECT 'S_USER_PRO'
        ID 'PROFILE' FIELD ls_rp-profile
        ID 'ACTVT'   FIELD '02'.
      IF sy-subrc <> 0.
        AUTHORITY-CHECK OBJECT 'S_USER_PRO'
          ID 'PROFILE' FIELD ls_rp-profile
          ID 'ACTVT'   FIELD '01'.
        IF sy-subrc <> 0.
          MESSAGE |No profile authorization (S_USER_PRO) for profile { ls_rp-profile } of role { lv_pr_role }.| TYPE 'S' DISPLAY LIKE 'E'.
          RETURN.
        ENDIF.
      ENDIF.
    ENDLOOP.
    IF lv_has_prof_row = abap_false.
      AUTHORITY-CHECK OBJECT 'S_USER_PRO'
        ID 'PROFILE' DUMMY
        ID 'ACTVT'   FIELD '01'.
      IF sy-subrc <> 0.
        AUTHORITY-CHECK OBJECT 'S_USER_PRO'
          ID 'PROFILE' DUMMY
          ID 'ACTVT'   FIELD '02'.
        IF sy-subrc <> 0.
          MESSAGE |No profile generation authorization (S_USER_PRO) for role { lv_pr_role }.| TYPE 'S' DISPLAY LIKE 'E'.
          RETURN.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDLOOP.

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

  " Load USORG unconditionally for upfront S_USER_VAL, Standalone, and Derived D3 checks
  SELECT field, varbl FROM usorg INTO TABLE @lt_usorg.

  " Parse selected objects into distinct SU53 combos (C3) BEFORE S_USER_VAL check and confirmation
  IF lt_object_auth IS NOT INITIAL.
    LOOP AT lt_object_auth INTO ls_item.
      PERFORM collect_item_combo USING ls_item lt_usorg
                                 CHANGING lt_sel_combos lt_org_vals lt_sel_objects.
    ENDLOOP.
  ENDIF.

  " Determine SU24 objects & check SU24 non-org proposal values (USOBT_C / USOBT) upfront
  IF lt_menu_tcodes IS NOT INITIAL.
    DATA: lt_tcd_sel     TYPE RANGE OF sytcode,
          lt_su24_y_c    TYPE HASHED TABLE OF ty_su24_key WITH UNIQUE KEY name object,
          lt_su24_y_s    TYPE HASHED TABLE OF ty_su24_key WITH UNIQUE KEY name object.
    lt_tcd_sel = VALUE #( FOR tc IN lt_menu_tcodes ( sign = 'I' option = 'EQ' low = tc ) ).

    SELECT name, object, okflag FROM usobx_c
      WHERE name IN @lt_tcd_sel AND type = 'TR'
      INTO TABLE @DATA(lt_su24_c).
    LOOP AT lt_su24_c INTO DATA(ls_c).
      INSERT VALUE ty_su24_key( name = ls_c-name object = ls_c-object ) INTO TABLE lt_su24_c_keys.
      IF ls_c-okflag = 'Y' AND ls_c-object <> 'S_TCODE'.
        INSERT ls_c-object INTO TABLE lt_su24_objs.
        INSERT VALUE ty_su24_key( name = ls_c-name object = ls_c-object ) INTO TABLE lt_su24_y_c.
      ENDIF.
    ENDLOOP.

    SELECT name, object FROM usobx
      WHERE name IN @lt_tcd_sel AND type = 'TR' AND okflag = 'Y'
      INTO TABLE @DATA(lt_su24_s).
    LOOP AT lt_su24_s INTO DATA(ls_s).
      IF ls_s-object = 'S_TCODE'.
        CONTINUE.
      ENDIF.
      IF line_exists( lt_su24_c_keys[ name = ls_s-name object = ls_s-object ] ).
        CONTINUE.
      ENDIF.
      INSERT ls_s-object INTO TABLE lt_su24_objs.
      INSERT VALUE ty_su24_key( name = ls_s-name object = ls_s-object ) INTO TABLE lt_su24_y_s.
    ENDLOOP.

    IF lt_su24_y_c IS NOT INITIAL.
      SELECT name, object, field, low, high FROM usobt_c
        WHERE name IN @lt_tcd_sel AND type = 'TR'
        INTO TABLE @DATA(lt_usobt_c).
      LOOP AT lt_usobt_c INTO DATA(ls_utc).
        IF NOT line_exists( lt_su24_y_c[ name = ls_utc-name object = ls_utc-object ] )
           OR ls_utc-object = 'S_TCODE'.
          CONTINUE.
        ENDIF.
        READ TABLE lt_usorg INTO DATA(ls_uo_uc) WITH TABLE KEY field = ls_utc-field.
        IF sy-subrc = 0 AND ls_uo_uc-varbl IS NOT INITIAL.
          CONTINUE.
        ENDIF.
        IF ls_utc-high IS INITIAL
           AND ( ls_utc-low IS INITIAL OR ls_utc-low = '-1' OR ls_utc-low = '$' ).
          CONTINUE.
        ENDIF.
        IF ls_utc-low IS NOT INITIAL AND ls_utc-low <> '-1' AND ls_utc-low <> '$'.
          lv_chk_val = COND #( WHEN ls_utc-low = gc_blank_val THEN space ELSE ls_utc-low ).
          AUTHORITY-CHECK OBJECT 'S_USER_VAL'
            ID 'OBJECT'     FIELD ls_utc-object
            ID 'AUTH_FIELD' FIELD ls_utc-field
            ID 'AUTH_VALUE' FIELD lv_chk_val.
          IF sy-subrc <> 0.
            MESSAGE |No authorization (S_USER_VAL) for SU24 proposal { ls_utc-object } / { ls_utc-field } = '{ ls_utc-low }'.| TYPE 'S' DISPLAY LIKE 'E'.
            RETURN.
          ENDIF.
        ENDIF.
        IF ls_utc-high IS NOT INITIAL.
          lv_chk_val = COND #( WHEN ls_utc-high = gc_blank_val THEN space ELSE ls_utc-high ).
          AUTHORITY-CHECK OBJECT 'S_USER_VAL'
            ID 'OBJECT'     FIELD ls_utc-object
            ID 'AUTH_FIELD' FIELD ls_utc-field
            ID 'AUTH_VALUE' FIELD lv_chk_val.
          IF sy-subrc <> 0.
            MESSAGE |No authorization (S_USER_VAL) for SU24 proposal { ls_utc-object } / { ls_utc-field } = '{ ls_utc-high }'.| TYPE 'S' DISPLAY LIKE 'E'.
            RETURN.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDIF.

    IF lt_su24_y_s IS NOT INITIAL.
      SELECT name, object, field, low, high FROM usobt
        WHERE name IN @lt_tcd_sel AND type = 'TR'
        INTO TABLE @DATA(lt_usobt_s).
      LOOP AT lt_usobt_s INTO DATA(ls_uts).
        IF NOT line_exists( lt_su24_y_s[ name = ls_uts-name object = ls_uts-object ] )
           OR ls_uts-object = 'S_TCODE'.
          CONTINUE.
        ENDIF.
        READ TABLE lt_usorg INTO ls_uo_uc WITH TABLE KEY field = ls_uts-field.
        IF sy-subrc = 0 AND ls_uo_uc-varbl IS NOT INITIAL.
          CONTINUE.
        ENDIF.
        IF ls_uts-high IS INITIAL
           AND ( ls_uts-low IS INITIAL OR ls_uts-low = '-1' OR ls_uts-low = '$' ).
          CONTINUE.
        ENDIF.
        IF ls_uts-low IS NOT INITIAL AND ls_uts-low <> '-1' AND ls_uts-low <> '$'.
          lv_chk_val = COND #( WHEN ls_uts-low = gc_blank_val THEN space ELSE ls_uts-low ).
          AUTHORITY-CHECK OBJECT 'S_USER_VAL'
            ID 'OBJECT'     FIELD ls_uts-object
            ID 'AUTH_FIELD' FIELD ls_uts-field
            ID 'AUTH_VALUE' FIELD lv_chk_val.
          IF sy-subrc <> 0.
            MESSAGE |No authorization (S_USER_VAL) for SU24 default { ls_uts-object } / { ls_uts-field } = '{ ls_uts-low }'.| TYPE 'S' DISPLAY LIKE 'E'.
            RETURN.
          ENDIF.
        ENDIF.
        IF ls_uts-high IS NOT INITIAL.
          lv_chk_val = COND #( WHEN ls_uts-high = gc_blank_val THEN space ELSE ls_uts-high ).
          AUTHORITY-CHECK OBJECT 'S_USER_VAL'
            ID 'OBJECT'     FIELD ls_uts-object
            ID 'AUTH_FIELD' FIELD ls_uts-field
            ID 'AUTH_VALUE' FIELD lv_chk_val.
          IF sy-subrc <> 0.
            MESSAGE |No authorization (S_USER_VAL) for SU24 default { ls_uts-object } / { ls_uts-field } = '{ ls_uts-high }'.| TYPE 'S' DISPLAY LIKE 'E'.
            RETURN.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDIF.

  " Collect TOBJ field catalog for selected objects & SU24 objects
  LOOP AT lt_sel_objects INTO DATA(lv_pto).
    INSERT lv_pto INTO TABLE lt_pre_tobj_objs.
  ENDLOOP.
  LOOP AT lt_su24_objs INTO lv_pto.
    INSERT lv_pto INTO TABLE lt_pre_tobj_objs.
  ENDLOOP.
  IF lt_pre_tobj_objs IS NOT INITIAL.
    SELECT objct, fiel1, fiel2, fiel3, fiel4, fiel5,
           fiel6, fiel7, fiel8, fiel9, fiel0
      FROM tobj
      FOR ALL ENTRIES IN @lt_pre_tobj_objs
      WHERE objct = @lt_pre_tobj_objs-table_line
      INTO TABLE @DATA(lt_pre_tobj).
    LOOP AT lt_pre_tobj INTO DATA(ls_pt).
      PERFORM add_obj_field USING ls_pt-objct ls_pt-fiel1 CHANGING lt_pre_tobj_flds.
      PERFORM add_obj_field USING ls_pt-objct ls_pt-fiel2 CHANGING lt_pre_tobj_flds.
      PERFORM add_obj_field USING ls_pt-objct ls_pt-fiel3 CHANGING lt_pre_tobj_flds.
      PERFORM add_obj_field USING ls_pt-objct ls_pt-fiel4 CHANGING lt_pre_tobj_flds.
      PERFORM add_obj_field USING ls_pt-objct ls_pt-fiel5 CHANGING lt_pre_tobj_flds.
      PERFORM add_obj_field USING ls_pt-objct ls_pt-fiel6 CHANGING lt_pre_tobj_flds.
      PERFORM add_obj_field USING ls_pt-objct ls_pt-fiel7 CHANGING lt_pre_tobj_flds.
      PERFORM add_obj_field USING ls_pt-objct ls_pt-fiel8 CHANGING lt_pre_tobj_flds.
      PERFORM add_obj_field USING ls_pt-objct ls_pt-fiel9 CHANGING lt_pre_tobj_flds.
      PERFORM add_obj_field USING ls_pt-objct ls_pt-fiel0 CHANGING lt_pre_tobj_flds.
    ENDLOOP.
  ENDIF.

  " Enforce S_USER_VAL and S_USER_TCD for every TCode, SU53 field/value, and DUMMY blank fields
  LOOP AT lt_menu_tcodes INTO DATA(lv_chk_tc).
    AUTHORITY-CHECK OBJECT 'S_USER_VAL'
      ID 'OBJECT'     FIELD 'S_TCODE'
      ID 'AUTH_FIELD' FIELD 'TCD'
      ID 'AUTH_VALUE' FIELD lv_chk_tc.
    IF sy-subrc <> 0.
      MESSAGE |No authorization (S_USER_VAL) to assign transaction { lv_chk_tc } (S_TCODE).| TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    AUTHORITY-CHECK OBJECT 'S_USER_TCD'
      ID 'TCD' FIELD lv_chk_tc.
    IF sy-subrc <> 0.
      MESSAGE |No authorization (S_USER_TCD) to assign menu transaction { lv_chk_tc }.| TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
  ENDLOOP.

  LOOP AT lt_sel_combos INTO DATA(ls_chk_cb).
    IF ls_chk_cb-values IS INITIAL AND ls_chk_cb-org_fields IS INITIAL.
      AUTHORITY-CHECK OBJECT 'S_USER_VAL'
        ID 'OBJECT'     FIELD ls_chk_cb-object
        ID 'AUTH_FIELD' DUMMY
        ID 'AUTH_VALUE' DUMMY.
      IF sy-subrc <> 0.
        MESSAGE |No authorization (S_USER_VAL) to maintain object { ls_chk_cb-object }.| TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
    ELSE.
      LOOP AT ls_chk_cb-values INTO DATA(ls_chk_v).
        lv_chk_val = COND #( WHEN ls_chk_v-low = gc_blank_val THEN space ELSE ls_chk_v-low ).
        AUTHORITY-CHECK OBJECT 'S_USER_VAL'
          ID 'OBJECT'     FIELD ls_chk_cb-object
          ID 'AUTH_FIELD' FIELD ls_chk_v-field
          ID 'AUTH_VALUE' FIELD lv_chk_val.
        IF sy-subrc <> 0.
          MESSAGE |No authorization (S_USER_VAL) for { ls_chk_cb-object } / { ls_chk_v-field } = '{ ls_chk_v-low }'.| TYPE 'S' DISPLAY LIKE 'E'.
          RETURN.
        ENDIF.
      ENDLOOP.
      LOOP AT ls_chk_cb-org_fields INTO DATA(ls_chk_o).
        lv_chk_val = COND #( WHEN ls_chk_o-low = gc_blank_val THEN space ELSE ls_chk_o-low ).
        AUTHORITY-CHECK OBJECT 'S_USER_VAL'
          ID 'OBJECT'     FIELD ls_chk_cb-object
          ID 'AUTH_FIELD' FIELD ls_chk_o-field
          ID 'AUTH_VALUE' FIELD lv_chk_val.
        IF sy-subrc <> 0.
          MESSAGE |No authorization (S_USER_VAL) for { ls_chk_cb-object } / { ls_chk_o-field } = '{ ls_chk_o-low }'.| TYPE 'S' DISPLAY LIKE 'E'.
          RETURN.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " Check S_USER_VAL = space for any unchecked DUMMY non-org TOBJ fields (which fill as gc_blank_val)
    LOOP AT lt_pre_tobj_flds INTO DATA(ls_pof) WHERE object = ls_chk_cb-object.
      READ TABLE lt_usorg INTO DATA(ls_uo_pf) WITH TABLE KEY field = ls_pof-field.
      IF sy-subrc = 0 AND ls_uo_pf-varbl IS NOT INITIAL.
        CONTINUE.
      ENDIF.
      IF NOT line_exists( ls_chk_cb-values[ field = ls_pof-field ] ).
        AUTHORITY-CHECK OBJECT 'S_USER_VAL'
          ID 'OBJECT'     FIELD ls_chk_cb-object
          ID 'AUTH_FIELD' FIELD ls_pof-field
          ID 'AUTH_VALUE' FIELD space.
        IF sy-subrc <> 0.
          MESSAGE |No authorization (S_USER_VAL) for DUMMY field { ls_chk_cb-object } / { ls_pof-field } = ''''''.| TYPE 'S' DISPLAY LIKE 'E'.
          RETURN.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDLOOP.

  " Identify ALL active org (object, field) pairs on lv_target_role that restore_role_1251_org_bindings
  " or distribute_org_levels will bind/rebind to $VARBL (lacking concrete G/M/U or not clean S=$VARBL)
  DATA: lt_rebound_flds   TYPE tt_obj_field,
        lt_dist_ov        TYPE HASHED TABLE OF usorg-varbl WITH UNIQUE KEY table_line,
        lt_role_tobj_flds TYPE tt_obj_field.
  CLEAR: lt_rebound_flds, lt_dist_ov, lt_role_tobj_flds.
  LOOP AT lt_org_vals INTO DATA(ls_ov_d).
    INSERT ls_ov_d-varbl INTO TABLE lt_dist_ov.
  ENDLOOP.

  SELECT object, auth FROM agr_1250
    WHERE agr_name = @lv_target_role AND deleted = @space AND copied <> 'I'
    INTO TABLE @DATA(lt_pre_1250).
  IF lt_pre_1250 IS NOT INITIAL.
    SELECT objct, fiel1, fiel2, fiel3, fiel4, fiel5, fiel6, fiel7, fiel8, fiel9, fiel0
      FROM tobj
      FOR ALL ENTRIES IN @lt_pre_1250
      WHERE objct = @lt_pre_1250-object
      INTO TABLE @DATA(lt_pre_act_tobj).

    LOOP AT lt_pre_act_tobj INTO DATA(ls_pat).
      PERFORM add_obj_field USING ls_pat-objct ls_pat-fiel1 CHANGING lt_role_tobj_flds.
      PERFORM add_obj_field USING ls_pat-objct ls_pat-fiel2 CHANGING lt_role_tobj_flds.
      PERFORM add_obj_field USING ls_pat-objct ls_pat-fiel3 CHANGING lt_role_tobj_flds.
      PERFORM add_obj_field USING ls_pat-objct ls_pat-fiel4 CHANGING lt_role_tobj_flds.
      PERFORM add_obj_field USING ls_pat-objct ls_pat-fiel5 CHANGING lt_role_tobj_flds.
      PERFORM add_obj_field USING ls_pat-objct ls_pat-fiel6 CHANGING lt_role_tobj_flds.
      PERFORM add_obj_field USING ls_pat-objct ls_pat-fiel7 CHANGING lt_role_tobj_flds.
      PERFORM add_obj_field USING ls_pat-objct ls_pat-fiel8 CHANGING lt_role_tobj_flds.
      PERFORM add_obj_field USING ls_pat-objct ls_pat-fiel9 CHANGING lt_role_tobj_flds.
      PERFORM add_obj_field USING ls_pat-objct ls_pat-fiel0 CHANGING lt_role_tobj_flds.
    ENDLOOP.

    SELECT object, auth, field, low, high, modified
      FROM agr_1251
      WHERE agr_name = @lv_target_role AND deleted = @space AND copied <> 'I'
      INTO TABLE @DATA(lt_pre_1251).

    LOOP AT lt_pre_1250 INTO DATA(ls_p50).
      LOOP AT lt_role_tobj_flds INTO DATA(ls_rtf) WHERE object = ls_p50-object.
        READ TABLE lt_usorg INTO DATA(ls_uo_rb) WITH TABLE KEY field = ls_rtf-field.
        IF sy-subrc <> 0 OR ls_uo_rb-varbl IS INITIAL.
          CONTINUE.
        ENDIF.
        DATA(lv_cnt_rb) = 0.
        DATA(lv_dec_rb) = abap_false.
        DATA(lv_var_rb) = abap_false.
        LOOP AT lt_pre_1251 INTO DATA(ls_p51_rb)
          WHERE object = ls_p50-object AND auth = ls_p50-auth AND field = ls_rtf-field.
          lv_cnt_rb = lv_cnt_rb + 1.
          IF ( ls_p51_rb-modified = 'G' OR ls_p51_rb-modified = 'M' OR ls_p51_rb-modified = 'U' )
             AND ( ( ls_p51_rb-low IS NOT INITIAL AND ls_p51_rb-low <> '-1'
                     AND ls_p51_rb-low <> '$' AND ls_p51_rb-low <> ls_uo_rb-varbl )
                   OR ls_p51_rb-high IS NOT INITIAL ).
            lv_dec_rb = abap_true.
          ENDIF.
          IF ls_p51_rb-modified = 'S' AND ls_p51_rb-low = ls_uo_rb-varbl AND ls_p51_rb-high IS INITIAL.
            lv_var_rb = abap_true.
          ENDIF.
        ENDLOOP.
        IF lv_cnt_rb > 0.
          IF NOT ( lv_dec_rb = abap_true OR ( lv_cnt_rb = 1 AND lv_var_rb = abap_true ) ).
            INSERT VALUE ty_obj_field( object = ls_p50-object field = ls_rtf-field )
              INTO TABLE lt_rebound_flds.
          ENDIF.
        ELSEIF line_exists( lt_dist_ov[ table_line = ls_uo_rb-varbl ] ).
          INSERT VALUE ty_obj_field( object = ls_p50-object field = ls_rtf-field )
            INTO TABLE lt_rebound_flds.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDIF.

  " HIGH-1 + V5/V6 HIGH-2: On Standalone Role, check S_USER_VAL for existing + new/SU24 objects
  " sharing new orgs AND check new/SU24 + rebound org objects against ALL pre-existing AGR_1252 values
  IF lv_is_master_r = abap_false
     AND ( lt_org_vals IS NOT INITIAL OR lt_pre_tobj_flds IS NOT INITIAL OR lt_rebound_flds IS NOT INITIAL ).
    SELECT DISTINCT f~object, f~field
      FROM agr_1251 AS f
      INNER JOIN agr_1250 AS h
        ON  h~agr_name = f~agr_name
        AND h~object   = f~object
        AND h~auth     = f~auth
      WHERE f~agr_name = @lv_target_role
        AND f~deleted  = @space AND f~copied <> 'I'
        AND h~deleted  = @space AND h~copied <> 'I'
      INTO TABLE @DATA(lt_st_sh_flds).

    DATA lt_st_check_flds TYPE tt_obj_field.
    CLEAR lt_st_check_flds.
    LOOP AT lt_st_sh_flds INTO DATA(ls_st_e).
      INSERT VALUE ty_obj_field( object = ls_st_e-object field = ls_st_e-field ) INTO TABLE lt_st_check_flds.
    ENDLOOP.
    LOOP AT lt_pre_tobj_flds INTO ls_pof.
      INSERT VALUE ty_obj_field( object = ls_pof-object field = ls_pof-field ) INTO TABLE lt_st_check_flds.
    ENDLOOP.
    LOOP AT lt_rebound_flds INTO DATA(ls_rbf).
      INSERT ls_rbf INTO TABLE lt_st_check_flds.
    ENDLOOP.

    IF lt_org_vals IS NOT INITIAL.
      LOOP AT lt_st_check_flds INTO DATA(ls_sh).
        READ TABLE lt_usorg INTO DATA(ls_uo_sh) WITH TABLE KEY field = ls_sh-field.
        IF sy-subrc <> 0 OR ls_uo_sh-varbl IS INITIAL.
          CONTINUE.
        ENDIF.
        LOOP AT lt_org_vals INTO DATA(ls_ov_sh) WHERE varbl = ls_uo_sh-varbl.
          lv_chk_val = COND #( WHEN ls_ov_sh-low = gc_blank_val THEN space ELSE ls_ov_sh-low ).
          AUTHORITY-CHECK OBJECT 'S_USER_VAL'
            ID 'OBJECT'     FIELD ls_sh-object
            ID 'AUTH_FIELD' FIELD ls_sh-field
            ID 'AUTH_VALUE' FIELD lv_chk_val.
          IF sy-subrc <> 0.
            MESSAGE |No authorization (S_USER_VAL) for shared org { ls_sh-object } / { ls_sh-field } = '{ ls_ov_sh-low }'.| TYPE 'S' DISPLAY LIKE 'E'.
            RETURN.
          ENDIF.
        ENDLOOP.
      ENDLOOP.
    ENDIF.

    DATA lt_st_pre_chk TYPE tt_obj_field.
    CLEAR lt_st_pre_chk.
    LOOP AT lt_pre_tobj_flds INTO ls_pof.
      INSERT ls_pof INTO TABLE lt_st_pre_chk.
    ENDLOOP.
    LOOP AT lt_rebound_flds INTO ls_rbf.
      INSERT ls_rbf INTO TABLE lt_st_pre_chk.
    ENDLOOP.

    IF lt_st_pre_chk IS NOT INITIAL.
      SELECT varbl, low, high FROM agr_1252
        WHERE agr_name = @lv_target_role
        INTO TABLE @DATA(lt_st_1252_pre).
      LOOP AT lt_st_pre_chk INTO ls_pof.
        READ TABLE lt_usorg INTO ls_uo_sh WITH TABLE KEY field = ls_pof-field.
        IF sy-subrc <> 0 OR ls_uo_sh-varbl IS INITIAL.
          CONTINUE.
        ENDIF.
        LOOP AT lt_st_1252_pre INTO DATA(ls_st_pre_o) WHERE varbl = ls_uo_sh-varbl.
          IF ls_st_pre_o-high IS INITIAL
             AND ( ls_st_pre_o-low IS INITIAL OR ls_st_pre_o-low = '-1' OR ls_st_pre_o-low = '$' ).
            CONTINUE.
          ENDIF.
          IF ls_st_pre_o-low IS NOT INITIAL AND ls_st_pre_o-low <> '-1' AND ls_st_pre_o-low <> '$'.
            lv_chk_val = COND #( WHEN ls_st_pre_o-low = gc_blank_val THEN space ELSE ls_st_pre_o-low ).
            AUTHORITY-CHECK OBJECT 'S_USER_VAL'
              ID 'OBJECT'     FIELD ls_pof-object
              ID 'AUTH_FIELD' FIELD ls_pof-field
              ID 'AUTH_VALUE' FIELD lv_chk_val.
            IF sy-subrc <> 0.
              MESSAGE |No authorization (S_USER_VAL) for existing org { ls_pof-object } / { ls_pof-field } = '{ ls_st_pre_o-low }'.| TYPE 'S' DISPLAY LIKE 'E'.
              RETURN.
            ENDIF.
          ELSEIF ls_st_pre_o-low IS INITIAL AND ls_st_pre_o-high IS NOT INITIAL.
            AUTHORITY-CHECK OBJECT 'S_USER_VAL'
              ID 'OBJECT'     FIELD ls_pof-object
              ID 'AUTH_FIELD' FIELD ls_pof-field
              ID 'AUTH_VALUE' FIELD space.
            IF sy-subrc <> 0.
              MESSAGE |No authorization (S_USER_VAL) for existing org { ls_pof-object } / { ls_pof-field } = ''''''.| TYPE 'S' DISPLAY LIKE 'E'.
              RETURN.
            ENDIF.
          ENDIF.
          IF ls_st_pre_o-high IS NOT INITIAL.
            lv_chk_val = COND #( WHEN ls_st_pre_o-high = gc_blank_val THEN space ELSE ls_st_pre_o-high ).
            AUTHORITY-CHECK OBJECT 'S_USER_VAL'
              ID 'OBJECT'     FIELD ls_pof-object
              ID 'AUTH_FIELD' FIELD ls_pof-field
              ID 'AUTH_VALUE' FIELD lv_chk_val.
            IF sy-subrc <> 0.
              MESSAGE |No authorization (S_USER_VAL) for existing org { ls_pof-object } / { ls_pof-field } = '{ ls_st_pre_o-high }'.| TYPE 'S' DISPLAY LIKE 'E'.
              RETURN.
            ENDIF.
          ENDIF.
        ENDLOOP.
      ENDLOOP.
    ENDIF.
  ENDIF.

  " AUD-C3 + HIGH-1 + MED-3 + V6 Fix: On Master with Derived Roles, verify S_USER_VAL for Master's own
  " AGR_1252 (new/rebound), Child pre-existing AGR_1252 (new/rebound on Master OR Child), and D3 '*'
  IF lt_child_roles IS NOT INITIAL.
    DATA lt_m_pre_chk TYPE tt_obj_field.
    CLEAR lt_m_pre_chk.
    LOOP AT lt_pre_tobj_flds INTO ls_pof.
      INSERT ls_pof INTO TABLE lt_m_pre_chk.
    ENDLOOP.
    LOOP AT lt_rebound_flds INTO ls_rbf.
      INSERT ls_rbf INTO TABLE lt_m_pre_chk.
    ENDLOOP.
    IF lt_m_pre_chk IS NOT INITIAL.
      SELECT varbl, low, high FROM agr_1252
        WHERE agr_name = @lv_target_role
        INTO TABLE @DATA(lt_m_1252_pre).
      LOOP AT lt_m_pre_chk INTO ls_pof.
        READ TABLE lt_usorg INTO ls_uo_sh WITH TABLE KEY field = ls_pof-field.
        IF sy-subrc <> 0 OR ls_uo_sh-varbl IS INITIAL.
          CONTINUE.
        ENDIF.
        LOOP AT lt_m_1252_pre INTO DATA(ls_m_pre_o) WHERE varbl = ls_uo_sh-varbl.
          IF ls_m_pre_o-high IS INITIAL
             AND ( ls_m_pre_o-low IS INITIAL OR ls_m_pre_o-low = '-1' OR ls_m_pre_o-low = '$' ).
            CONTINUE.
          ENDIF.
          IF ls_m_pre_o-low IS NOT INITIAL AND ls_m_pre_o-low <> '-1' AND ls_m_pre_o-low <> '$'.
            lv_chk_val = COND #( WHEN ls_m_pre_o-low = gc_blank_val THEN space ELSE ls_m_pre_o-low ).
            AUTHORITY-CHECK OBJECT 'S_USER_VAL'
              ID 'OBJECT'     FIELD ls_pof-object
              ID 'AUTH_FIELD' FIELD ls_pof-field
              ID 'AUTH_VALUE' FIELD lv_chk_val.
            IF sy-subrc <> 0.
              MESSAGE |No authorization (S_USER_VAL) for master org { ls_pof-object } / { ls_pof-field } = '{ ls_m_pre_o-low }'.| TYPE 'S' DISPLAY LIKE 'E'.
              RETURN.
            ENDIF.
          ELSEIF ls_m_pre_o-low IS INITIAL AND ls_m_pre_o-high IS NOT INITIAL.
            AUTHORITY-CHECK OBJECT 'S_USER_VAL'
              ID 'OBJECT'     FIELD ls_pof-object
              ID 'AUTH_FIELD' FIELD ls_pof-field
              ID 'AUTH_VALUE' FIELD space.
            IF sy-subrc <> 0.
              MESSAGE |No authorization (S_USER_VAL) for master org { ls_pof-object } / { ls_pof-field } = ''''''.| TYPE 'S' DISPLAY LIKE 'E'.
              RETURN.
            ENDIF.
          ENDIF.
          IF ls_m_pre_o-high IS NOT INITIAL.
            lv_chk_val = COND #( WHEN ls_m_pre_o-high = gc_blank_val THEN space ELSE ls_m_pre_o-high ).
            AUTHORITY-CHECK OBJECT 'S_USER_VAL'
              ID 'OBJECT'     FIELD ls_pof-object
              ID 'AUTH_FIELD' FIELD ls_pof-field
              ID 'AUTH_VALUE' FIELD lv_chk_val.
            IF sy-subrc <> 0.
              MESSAGE |No authorization (S_USER_VAL) for master org { ls_pof-object } / { ls_pof-field } = '{ ls_m_pre_o-high }'.| TYPE 'S' DISPLAY LIKE 'E'.
              RETURN.
            ENDIF.
          ENDIF.
        ENDLOOP.
      ENDLOOP.
    ENDIF.

    SELECT DISTINCT f~object, f~field
      FROM agr_1251 AS f
      INNER JOIN agr_1250 AS h
        ON  h~agr_name = f~agr_name
        AND h~object   = f~object
        AND h~auth     = f~auth
      WHERE f~agr_name = @lv_target_role
        AND f~deleted  = @space AND f~copied <> 'I'
        AND h~deleted  = @space AND h~copied <> 'I'
      INTO TABLE @DATA(lt_m_act_flds).
    LOOP AT lt_m_act_flds INTO DATA(ls_mf).
      READ TABLE lt_usorg INTO DATA(ls_uo_d3) WITH TABLE KEY field = ls_mf-field.
      IF sy-subrc = 0 AND ls_uo_d3-varbl IS NOT INITIAL.
        INSERT VALUE ty_d3_pair(
          object = ls_mf-object field = ls_mf-field varbl = ls_uo_d3-varbl )
          INTO TABLE lt_d3_pairs.
      ENDIF.
    ENDLOOP.
    LOOP AT lt_pre_tobj_flds INTO ls_pof.
      READ TABLE lt_usorg INTO ls_uo_d3 WITH TABLE KEY field = ls_pof-field.
      IF sy-subrc = 0 AND ls_uo_d3-varbl IS NOT INITIAL.
        INSERT VALUE ty_d3_pair(
          object = ls_pof-object field = ls_pof-field varbl = ls_uo_d3-varbl )
          INTO TABLE lt_d3_pairs.
      ENDIF.
    ENDLOOP.
    LOOP AT lt_rebound_flds INTO ls_rbf.
      READ TABLE lt_usorg INTO ls_uo_d3 WITH TABLE KEY field = ls_rbf-field.
      IF sy-subrc = 0 AND ls_uo_d3-varbl IS NOT INITIAL.
        INSERT VALUE ty_d3_pair(
          object = ls_rbf-object field = ls_rbf-field varbl = ls_uo_d3-varbl )
          INTO TABLE lt_d3_pairs.
      ENDIF.
    ENDLOOP.

    TYPES: BEGIN OF ty_ch_obj_field,
             agr_name TYPE agr_name,
             object   TYPE tobj-objct,
             field    TYPE xufield,
           END OF ty_ch_obj_field.
    DATA lt_ch_rebound_flds TYPE HASHED TABLE OF ty_ch_obj_field WITH UNIQUE KEY agr_name object field.
    CLEAR lt_ch_rebound_flds.

    SELECT agr_name, object, auth FROM agr_1250
      FOR ALL ENTRIES IN @lt_child_roles
      WHERE agr_name = @lt_child_roles-table_line
        AND deleted = @space AND copied <> 'I'
      INTO TABLE @DATA(lt_ch_pre_1250).

    SELECT DISTINCT f~agr_name, f~object, f~field
      FROM agr_1251 AS f
      INNER JOIN agr_1250 AS h
        ON  h~agr_name = f~agr_name
        AND h~object   = f~object
        AND h~auth     = f~auth
      FOR ALL ENTRIES IN @lt_child_roles
      WHERE f~agr_name = @lt_child_roles-table_line
        AND f~deleted  = @space AND f~copied <> 'I'
        AND h~deleted  = @space AND h~copied <> 'I'
      INTO TABLE @DATA(lt_ch_act_flds).

    IF lt_ch_pre_1250 IS NOT INITIAL.
      SELECT agr_name, object, auth, field, low, high, modified
        FROM agr_1251
        FOR ALL ENTRIES IN @lt_child_roles
        WHERE agr_name = @lt_child_roles-table_line
          AND deleted = @space AND copied <> 'I'
        INTO TABLE @DATA(lt_ch_pre_1251).

      SELECT objct, fiel1, fiel2, fiel3, fiel4, fiel5, fiel6, fiel7, fiel8, fiel9, fiel0
        FROM tobj
        FOR ALL ENTRIES IN @lt_ch_pre_1250
        WHERE objct = @lt_ch_pre_1250-object
        INTO TABLE @DATA(lt_ch_pre_tobj).

      DATA lt_ch_tobj_flds TYPE tt_obj_field.
      CLEAR lt_ch_tobj_flds.
      LOOP AT lt_ch_pre_tobj INTO DATA(ls_cpt).
        PERFORM add_obj_field USING ls_cpt-objct ls_cpt-fiel1 CHANGING lt_ch_tobj_flds.
        PERFORM add_obj_field USING ls_cpt-objct ls_cpt-fiel2 CHANGING lt_ch_tobj_flds.
        PERFORM add_obj_field USING ls_cpt-objct ls_cpt-fiel3 CHANGING lt_ch_tobj_flds.
        PERFORM add_obj_field USING ls_cpt-objct ls_cpt-fiel4 CHANGING lt_ch_tobj_flds.
        PERFORM add_obj_field USING ls_cpt-objct ls_cpt-fiel5 CHANGING lt_ch_tobj_flds.
        PERFORM add_obj_field USING ls_cpt-objct ls_cpt-fiel6 CHANGING lt_ch_tobj_flds.
        PERFORM add_obj_field USING ls_cpt-objct ls_cpt-fiel7 CHANGING lt_ch_tobj_flds.
        PERFORM add_obj_field USING ls_cpt-objct ls_cpt-fiel8 CHANGING lt_ch_tobj_flds.
        PERFORM add_obj_field USING ls_cpt-objct ls_cpt-fiel9 CHANGING lt_ch_tobj_flds.
        PERFORM add_obj_field USING ls_cpt-objct ls_cpt-fiel0 CHANGING lt_ch_tobj_flds.
      ENDLOOP.

      LOOP AT lt_ch_pre_1250 INTO DATA(ls_c50).
        LOOP AT lt_ch_tobj_flds INTO DATA(ls_crtf) WHERE object = ls_c50-object.
          READ TABLE lt_usorg INTO DATA(ls_cuo_rb) WITH TABLE KEY field = ls_crtf-field.
          IF sy-subrc <> 0 OR ls_cuo_rb-varbl IS INITIAL.
            CONTINUE.
          ENDIF.
          DATA(lv_ccnt_rb) = 0.
          DATA(lv_cdec_rb) = abap_false.
          DATA(lv_cvar_rb) = abap_false.
          LOOP AT lt_ch_pre_1251 INTO DATA(ls_c51_rb)
            WHERE agr_name = ls_c50-agr_name AND object = ls_c50-object
              AND auth = ls_c50-auth AND field = ls_crtf-field.
            lv_ccnt_rb = lv_ccnt_rb + 1.
            IF ( ls_c51_rb-modified = 'G' OR ls_c51_rb-modified = 'M' OR ls_c51_rb-modified = 'U' )
               AND ( ( ls_c51_rb-low IS NOT INITIAL AND ls_c51_rb-low <> '-1'
                       AND ls_c51_rb-low <> '$' AND ls_c51_rb-low <> ls_cuo_rb-varbl )
                     OR ls_c51_rb-high IS NOT INITIAL ).
              lv_cdec_rb = abap_true.
            ENDIF.
            IF ls_c51_rb-modified = 'S' AND ls_c51_rb-low = ls_cuo_rb-varbl AND ls_c51_rb-high IS INITIAL.
              lv_cvar_rb = abap_true.
            ENDIF.
          ENDLOOP.
          IF lv_ccnt_rb > 0 AND NOT ( lv_cdec_rb = abap_true OR ( lv_ccnt_rb = 1 AND lv_cvar_rb = abap_true ) ).
            INSERT VALUE ty_ch_obj_field(
              agr_name = ls_c50-agr_name object = ls_c50-object field = ls_crtf-field )
              INTO TABLE lt_ch_rebound_flds.
          ENDIF.
        ENDLOOP.
      ENDLOOP.
    ENDIF.

    SELECT agr_name, varbl, low, high FROM agr_1252
      FOR ALL ENTRIES IN @lt_child_roles
      WHERE agr_name = @lt_child_roles-table_line
      INTO TABLE @DATA(lt_ch_1252_pre).

    LOOP AT lt_child_roles INTO DATA(lv_ch_pre).
      DATA lt_ch_chk_pairs TYPE HASHED TABLE OF ty_d3_pair WITH UNIQUE KEY object field varbl.
      CLEAR lt_ch_chk_pairs.
      LOOP AT lt_d3_pairs INTO DATA(ls_d3p).
        INSERT ls_d3p INTO TABLE lt_ch_chk_pairs.
      ENDLOOP.
      LOOP AT lt_ch_act_flds INTO DATA(ls_caf) WHERE agr_name = lv_ch_pre.
        READ TABLE lt_usorg INTO ls_uo_d3 WITH TABLE KEY field = ls_caf-field.
        IF sy-subrc = 0 AND ls_uo_d3-varbl IS NOT INITIAL.
          INSERT VALUE ty_d3_pair(
            object = ls_caf-object field = ls_caf-field varbl = ls_uo_d3-varbl )
            INTO TABLE lt_ch_chk_pairs.
        ENDIF.
      ENDLOOP.

      LOOP AT lt_ch_chk_pairs INTO ls_d3p.
        DATA(lv_ch_pre_maint) = abap_false.
        DATA(lv_is_new_obj_p) = xsdbool(
          line_exists( lt_pre_tobj_flds[ object = ls_d3p-object field = ls_d3p-field ] )
          OR line_exists( lt_rebound_flds[ object = ls_d3p-object field = ls_d3p-field ] )
          OR line_exists( lt_ch_rebound_flds[
               agr_name = lv_ch_pre object = ls_d3p-object field = ls_d3p-field ] ) ).
        LOOP AT lt_ch_1252_pre INTO DATA(ls_c1252p)
          WHERE agr_name = lv_ch_pre AND varbl = ls_d3p-varbl.
          IF ( ls_c1252p-low IS NOT INITIAL AND ls_c1252p-low <> '-1' AND ls_c1252p-low <> '$' )
             OR ls_c1252p-high IS NOT INITIAL.
            lv_ch_pre_maint = abap_true.
            IF lv_is_new_obj_p = abap_true.
              IF ls_c1252p-low IS NOT INITIAL AND ls_c1252p-low <> '-1' AND ls_c1252p-low <> '$'.
                lv_chk_val = COND #( WHEN ls_c1252p-low = gc_blank_val THEN space ELSE ls_c1252p-low ).
                AUTHORITY-CHECK OBJECT 'S_USER_VAL'
                  ID 'OBJECT'     FIELD ls_d3p-object
                  ID 'AUTH_FIELD' FIELD ls_d3p-field
                  ID 'AUTH_VALUE' FIELD lv_chk_val.
                IF sy-subrc <> 0.
                  MESSAGE |No authorization (S_USER_VAL) for derived org { ls_d3p-object } / { ls_d3p-field } = '{ ls_c1252p-low }' ({ lv_ch_pre }).| TYPE 'S' DISPLAY LIKE 'E'.
                  RETURN.
                ENDIF.
              ELSEIF ls_c1252p-low IS INITIAL AND ls_c1252p-high IS NOT INITIAL.
                AUTHORITY-CHECK OBJECT 'S_USER_VAL'
                  ID 'OBJECT'     FIELD ls_d3p-object
                  ID 'AUTH_FIELD' FIELD ls_d3p-field
                  ID 'AUTH_VALUE' FIELD space.
                IF sy-subrc <> 0.
                  MESSAGE |No authorization (S_USER_VAL) for derived org { ls_d3p-object } / { ls_d3p-field } = '''''' ({ lv_ch_pre }).| TYPE 'S' DISPLAY LIKE 'E'.
                  RETURN.
                ENDIF.
              ENDIF.
              IF ls_c1252p-high IS NOT INITIAL.
                lv_chk_val = COND #( WHEN ls_c1252p-high = gc_blank_val THEN space ELSE ls_c1252p-high ).
                AUTHORITY-CHECK OBJECT 'S_USER_VAL'
                  ID 'OBJECT'     FIELD ls_d3p-object
                  ID 'AUTH_FIELD' FIELD ls_d3p-field
                  ID 'AUTH_VALUE' FIELD lv_chk_val.
                IF sy-subrc <> 0.
                  MESSAGE |No authorization (S_USER_VAL) for derived org { ls_d3p-object } / { ls_d3p-field } = '{ ls_c1252p-high }' ({ lv_ch_pre }).| TYPE 'S' DISPLAY LIKE 'E'.
                  RETURN.
                ENDIF.
              ENDIF.
            ENDIF.
          ENDIF.
        ENDLOOP.
        IF lv_ch_pre_maint = abap_false.
          AUTHORITY-CHECK OBJECT 'S_USER_VAL'
            ID 'OBJECT'     FIELD ls_d3p-object
            ID 'AUTH_FIELD' FIELD ls_d3p-field
            ID 'AUTH_VALUE' FIELD '*'.
          IF sy-subrc <> 0.
            MESSAGE |No authorization (S_USER_VAL '*') to auto-default unmaintained org level { ls_d3p-varbl } ({ ls_d3p-object }/{ ls_d3p-field }) on derived role { lv_ch_pre }.| TYPE 'S' DISPLAY LIKE 'E'.
            RETURN.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDIF.

  IF lt_child_roles IS NOT INITIAL.
    lv_confirm_q = |Add { lines( lt_selected ) } item(s) to Leading Role { lv_target_role } and propagate to { lines( lt_child_roles ) } derived role(s)?|.
  ELSE.
    lv_confirm_q = |Add { lines( lt_selected ) } item(s) to role { lv_target_role } and regenerate its profile?|.
  ENDIF.

  CALL FUNCTION 'POPUP_TO_CONFIRM'
    EXPORTING
      titlebar              = 'Confirm Role Authorization Update'
      text_question         = lv_confirm_q
      text_button_1         = 'Yes, Update'
      text_button_2         = 'Cancel'
      default_button        = '2'
      display_cancel_button = space
    IMPORTING
      answer                = lv_confirm_ans
    EXCEPTIONS
      text_not_found        = 1
      OTHERS                = 2.
  IF sy-subrc <> 0 OR lv_confirm_ans <> '1'.
    MESSAGE 'Role modification cancelled by user.' TYPE 'S'.
    RETURN.
  ENDIF.

  " Take snapshot of active objects in Master Role before any menu / auth additions
  SELECT DISTINCT object FROM agr_1250
    WHERE agr_name = @lv_target_role
      AND deleted  = ' '
      AND copied  <> 'I'
    INTO TABLE @lt_lead_objs_prior.

  " 1. Add TCodes to Master role menu hierarchy (under first folder or home)
  IF lt_menu_tcodes IS NOT INITIAL.
    PERFORM add_tcodes_to_role_menu USING lv_target_role
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
      " Profile merge 'M': brings in SU24 default authorization objects for the new TCodes
      PERFORM generate_role_profile USING lv_target_role 'M' abap_true abap_false CHANGING lv_gen_subrc.
      IF lv_gen_subrc <> 0.
        lv_gen_failed = abap_true.
      ELSE.
        COMMIT WORK AND WAIT.
      ENDIF.
      " SU53-H4: Sync any newly merged Master Org Levels to '-1'; if changed & Step 2 won't run, re-gen for GREEN LED
      IF lv_is_master_r = abap_true.
        CLEAR lv_m_org_mod.
        PERFORM ensure_master_org_levels USING lv_target_role CHANGING lv_m_org_mod.
        IF lv_m_org_mod = abap_true AND lt_sel_combos IS INITIAL AND lt_org_vals IS INITIAL.
          PERFORM generate_role_profile USING lv_target_role ' ' abap_true abap_false CHANGING lv_gen_subrc.
          IF lv_gen_subrc <> 0.
            lv_gen_failed = abap_true.
          ELSE.
            COMMIT WORK AND WAIT.
          ENDIF.
        ENDIF.
      ENDIF.
    ELSEIF lv_menu_failed > 0 AND lt_sel_combos IS INITIAL AND lt_org_vals IS INITIAL.
      MESSAGE |No transaction was added to the menu of role { lv_target_role }:{ lv_failed_txt }| TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
  ENDIF.

  " 2. If explicit authorization objects were selected (non-TCode), add them to Master/Standalone Role
  IF lt_sel_combos IS NOT INITIAL OR lt_org_vals IS NOT INITIAL.
    DATA: lv_auth_counter TYPE i,
          lv_auth         TYPE xuauth,
          lv_merge_auth   TYPE xuauth,
          lv_fld_mod      TYPE c LENGTH 1,
          lv_m_def_val    TYPE xuval,
          lv_m_mod        TYPE c LENGTH 1,
          lv_m_neu        TYPE c LENGTH 1,
          lv_already_cov  TYPE abap_bool,
          lv_has_act_org  TYPE abap_bool,
          lv_found_act    TYPE abap_bool,
          lv_found_emp    TYPE abap_bool,
          lv_found_str    TYPE abap_bool,
          lv_found_fld    TYPE abap_bool,
          lv_created_node TYPE abap_bool,
          lv_save_err     TYPE abap_bool,
          lv_org_save_err TYPE abap_bool,
          lv_sval_abort   TYPE abap_bool,
          lv_sval_msg     TYPE string,
          lt_new_auths    TYPE tt_role_obj,
          lt_tobj_vars    TYPE tt_varbl,
          lt_def_fields   TYPE STANDARD TABLE OF xufield,
          ls_tobj_def     TYPE tobj.
    CLEAR: lv_auth_counter, lt_new_auths, lt_tobj_vars,
           lv_save_err, lv_org_save_err, lv_sval_abort, lv_sval_msg.

    " Lock Role (Enqueue with no_dialog = 'X')
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
      EXPORTING
        activity_group = lv_target_role
        no_dialog      = 'X'
      EXCEPTIONS
        foreign_lock   = 1
        system_error   = 2
        OTHERS         = 3.
    IF sy-subrc <> 0.
      DATA(lv_lock_user) = sy-msgv1.
      lv_step2_err = abap_true.
      lv_step2_msg = COND #(
        WHEN lv_lock_user IS NOT INITIAL
        THEN |Role { lv_target_role } is locked by user { lv_lock_user }. Please exit Edit mode in PFCG first.|
        ELSE |Role { lv_target_role } is locked. Please exit Edit mode in PFCG first.| ).
    ENDIF.

    IF lv_step2_err = abap_false.
      CLEAR: lt_auth_data, lt_field_values, lt_org_curr.
      CALL FUNCTION 'PRGN_1250_READ_AUTH_DATA'
        EXPORTING
          activity_group    = lv_target_role
        TABLES
          auth_data         = lt_auth_data
        EXCEPTIONS
          no_data_available = 1
          OTHERS            = 2.
      IF sy-subrc = 2.
        lv_step2_err = abap_true.
        lv_step2_msg = |Error reading authorization header (AGR_1250) for role { lv_target_role }.|.
      ENDIF.
    ENDIF.

    IF lv_step2_err = abap_false.
      CALL FUNCTION 'PRGN_1251_READ_FIELD_VALUES'
        EXPORTING
          activity_group    = lv_target_role
        TABLES
          field_values      = lt_field_values
        EXCEPTIONS
          no_data_available = 1
          OTHERS            = 2.
      IF sy-subrc = 2.
        lv_step2_err = abap_true.
        lv_step2_msg = |Error reading field values (AGR_1251) for role { lv_target_role }.|.
      ENDIF.
    ENDIF.

    IF lv_step2_err = abap_false.
      CALL FUNCTION 'PRGN_1252_READ_ORG_LEVELS'
        EXPORTING
          activity_group    = lv_target_role
        TABLES
          org_levels        = lt_org_curr
        EXCEPTIONS
          no_data_available = 1
          OTHERS            = 2.
      IF sy-subrc = 2.
        lv_step2_err = abap_true.
        lv_step2_msg = |Error reading org levels (AGR_1252) for role { lv_target_role }.|.
      ENDIF.
    ENDIF.

    IF lv_step2_err = abap_true.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
        EXPORTING
          activity_group = lv_target_role
        EXCEPTIONS
          OTHERS         = 0.
      IF lv_menu_added = 0.
        PERFORM eval_auths_for_role USING gv_selected_role.
        IF go_grid_auths IS BOUND.
          go_grid_auths->refresh_table_display( is_stable = VALUE #( row = 'X' col = 'X' ) ).
        ENDIF.
        MESSAGE lv_step2_msg TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
    ENDIF.

    DATA lt_touched_auths TYPE tt_role_obj.
    CLEAR lt_touched_auths.

    IF lv_step2_err = abap_false.
      " C3: Process each distinct SU53 combination separately to prevent Cartesian escalation
      LOOP AT lt_sel_combos INTO DATA(ls_combo).
        CLEAR: lv_auth, lv_merge_auth, lv_fld_mod, lv_already_cov, lv_created_node.

        IF ls_combo-values IS INITIAL.
          " Org-only or Full-Object check: reuse an active auth without conflicting decoupled 'G'/'M'/'U' org overrides
          lv_has_act_org = abap_false.
          LOOP AT lt_auth_data INTO DATA(ls_ad_o)
            WHERE object = ls_combo-object AND deleted = space AND copied <> 'I'.
            DATA(lv_org_conflict) = abap_false.
            LOOP AT ls_combo-org_fields INTO DATA(ls_co_chk).
              LOOP AT lt_field_values INTO DATA(ls_fv_chk)
                WHERE object = ls_combo-object AND auth = ls_ad_o-auth
                  AND field = ls_co_chk-field AND deleted = space AND copied <> 'I'.
                IF ( ls_fv_chk-modified = 'G' OR ls_fv_chk-modified = 'M' OR ls_fv_chk-modified = 'U' )
                   AND ( ( ls_fv_chk-low IS NOT INITIAL AND ls_fv_chk-low <> '-1'
                           AND ls_fv_chk-low <> '$' AND ls_fv_chk-low <> ls_co_chk-varbl )
                         OR ls_fv_chk-high IS NOT INITIAL )
                   AND ls_fv_chk-low <> ls_co_chk-low.
                  lv_org_conflict = abap_true.
                  EXIT.
                ENDIF.
              ENDLOOP.
              IF lv_org_conflict = abap_true.
                EXIT.
              ENDIF.
            ENDLOOP.
            IF lv_org_conflict = abap_false.
              lv_has_act_org = abap_true.
              EXIT.
            ENDIF.
          ENDLOOP.
          IF lv_has_act_org = abap_false.
            PERFORM ensure_role_auth USING ls_combo-object abap_true
                                     CHANGING lt_auth_data lv_auth_counter lv_auth lv_created_node.
            IF lv_created_node = abap_true AND lv_auth IS NOT INITIAL.
              APPEND VALUE ty_role_obj( object = ls_combo-object auth = lv_auth ) TO lt_new_auths.
              IF NOT line_exists( lt_touched_auths[ object = ls_combo-object auth = lv_auth ] ).
                APPEND VALUE ty_role_obj( object = ls_combo-object auth = lv_auth ) TO lt_touched_auths.
              ENDIF.
            ENDIF.
          ENDIF.
          CONTINUE.
        ENDIF.

        " Find whether combo is already covered or has a mathematically Cartesian-safe merge candidate
        PERFORM find_safe_auth_for_combo USING ls_combo lt_auth_data lt_field_values lt_org_curr lt_usorg
                                         CHANGING lv_already_cov lv_merge_auth.
        IF lv_already_cov = abap_true.
          CONTINUE.
        ENDIF.

        IF lv_merge_auth IS NOT INITIAL.
          LOOP AT lt_auth_data ASSIGNING FIELD-SYMBOL(<ls_ad>)
            WHERE object = ls_combo-object AND auth = lv_merge_auth
              AND deleted = space AND copied <> 'I'.
            lv_auth = <ls_ad>-auth.
            IF <ls_ad>-modified <> 'U'.
              <ls_ad>-modified = 'M'.
            ENDIF.
            lv_fld_mod = <ls_ad>-modified.
            EXIT.
          ENDLOOP.
        ELSE.
          " Create a brand-new active Manual ('U') AUTH instance (zero cross-product with existing auths!)
          PERFORM ensure_role_auth USING ls_combo-object abap_true
                                   CHANGING lt_auth_data lv_auth_counter lv_auth lv_created_node.
          IF lv_auth IS INITIAL.
            CONTINUE.
          ENDIF.
          lv_fld_mod = 'U'.
          IF lv_created_node = abap_true.
            APPEND VALUE ty_role_obj( object = ls_combo-object auth = lv_auth ) TO lt_new_auths.
          ENDIF.
        ENDIF.

        IF lv_auth IS INITIAL.
          CONTINUE.
        ENDIF.
        IF NOT line_exists( lt_touched_auths[ object = ls_combo-object auth = lv_auth ] ).
          APPEND VALUE ty_role_obj( object = ls_combo-object auth = lv_auth ) TO lt_touched_auths.
        ENDIF.

        LOOP AT ls_combo-values INTO DATA(ls_val).
          CLEAR: lv_found_act, lv_found_emp, lv_found_str.
          LOOP AT lt_field_values ASSIGNING FIELD-SYMBOL(<ls_fv>)
            WHERE object = ls_combo-object AND auth = lv_auth
              AND field = ls_val-field AND low = ls_val-low AND high = space
              AND deleted = space AND copied <> 'I'.
            <ls_fv>-modified = lv_fld_mod.
            lv_found_act = abap_true.
            EXIT.
          ENDLOOP.
          IF lv_found_act = abap_false.
            LOOP AT lt_field_values ASSIGNING FIELD-SYMBOL(<ls_empty_fv>)
              WHERE object = ls_combo-object AND auth = lv_auth
                AND field = ls_val-field AND low = space AND high = space
                AND deleted = space AND copied <> 'I'.
              <ls_empty_fv>-low      = ls_val-low.
              <ls_empty_fv>-high     = space.
              <ls_empty_fv>-modified = lv_fld_mod.
              <ls_empty_fv>-neu      = 'N'.
              lv_found_emp = abap_true.
              EXIT.
            ENDLOOP.
            IF lv_found_emp = abap_false.
              LOOP AT lt_field_values ASSIGNING FIELD-SYMBOL(<ls_star_fv>)
                WHERE object = ls_combo-object AND auth = lv_auth
                  AND field = ls_val-field AND low = '*' AND high = space
                  AND deleted = space AND copied <> 'I'.
                <ls_star_fv>-modified = lv_fld_mod.
                lv_found_str = abap_true.
                EXIT.
              ENDLOOP.
              IF lv_found_str = abap_false.
                APPEND VALUE pt1251(
                  object   = ls_combo-object
                  auth     = lv_auth
                  variant  = ' '
                  field    = ls_val-field
                  low      = ls_val-low
                  high     = space
                  modified = lv_fld_mod
                  neu      = 'N'
                  deleted  = ' '
                ) TO lt_field_values.
              ENDIF.
            ENDIF.
            lv_total_added = lv_total_added + 1.
          ENDIF.
        ENDLOOP.
      ENDLOOP.

      " TOBJ completeness over ALL touched (new AND merged) AUTH instances (MEDIUM-1):
      " - Org fields bind to $VARBL with MODIFIED = 'S' (only if not concrete 'G'/'M'/'U' decoupled)
      " - Unchecked/empty non-org fields fill with explicit blank gc_blank_val (''''), NEVER '*'!
      LOOP AT lt_touched_auths INTO DATA(ls_na).
        DATA(lv_touch_hdr_mod) = CONV tpr_st_mod( 'U' ).
        LOOP AT lt_auth_data INTO DATA(ls_thdr)
          WHERE object = ls_na-object AND auth = ls_na-auth
            AND deleted = space AND copied <> 'I'.
          lv_touch_hdr_mod = COND #( WHEN ls_thdr-modified = 'U' THEN 'U' ELSE 'M' ).
          EXIT.
        ENDLOOP.

        CLEAR ls_tobj_def.
        SELECT SINGLE fiel1, fiel2, fiel3, fiel4, fiel5, fiel6, fiel7, fiel8, fiel9, fiel0
          FROM tobj
          WHERE objct = @ls_na-object
          INTO CORRESPONDING FIELDS OF @ls_tobj_def.
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.

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
          CLEAR lv_found_fld.
          LOOP AT lt_field_values ASSIGNING FIELD-SYMBOL(<ls_any_fv>)
            WHERE object = ls_na-object AND auth = ls_na-auth
              AND field = lv_check_fld AND deleted = space AND copied <> 'I'.
            lv_found_fld = abap_true.
            IF <ls_any_fv>-low IS INITIAL AND <ls_any_fv>-high IS INITIAL.
              READ TABLE lt_usorg INTO DATA(ls_uo_m) WITH TABLE KEY field = lv_check_fld.
              IF sy-subrc = 0 AND ls_uo_m-varbl IS NOT INITIAL.
                DATA(lv_t_dec) = abap_false.
                LOOP AT lt_field_values INTO DATA(ls_td_chk)
                  WHERE object = ls_na-object AND auth = ls_na-auth
                    AND field = lv_check_fld AND deleted = space AND copied <> 'I'.
                  IF ( ls_td_chk-modified = 'G' OR ls_td_chk-modified = 'M' OR ls_td_chk-modified = 'U' )
                     AND ( ( ls_td_chk-low IS NOT INITIAL AND ls_td_chk-low <> '-1'
                             AND ls_td_chk-low <> '$' AND ls_td_chk-low <> ls_uo_m-varbl )
                           OR ls_td_chk-high IS NOT INITIAL ).
                    lv_t_dec = abap_true.
                    EXIT.
                  ENDIF.
                ENDLOOP.
                IF lv_t_dec = abap_false.
                  <ls_any_fv>-low      = ls_uo_m-varbl.
                  <ls_any_fv>-high     = space.
                  <ls_any_fv>-modified = 'S'.
                  <ls_any_fv>-neu      = 'O'.
                  INSERT ls_uo_m-varbl INTO TABLE lt_tobj_vars.
                ENDIF.
              ELSE.
                AUTHORITY-CHECK OBJECT 'S_USER_VAL'
                  ID 'OBJECT'     FIELD ls_na-object
                  ID 'AUTH_FIELD' FIELD lv_check_fld
                  ID 'AUTH_VALUE' FIELD space.
                IF sy-subrc <> 0.
                  lv_sval_abort = abap_true.
                  lv_sval_msg   = |No authorization (S_USER_VAL) for DUMMY field { ls_na-object } / { lv_check_fld } = ''''''.|.
                  EXIT.
                ENDIF.
                <ls_any_fv>-low      = gc_blank_val.
                <ls_any_fv>-high     = space.
                <ls_any_fv>-modified = lv_touch_hdr_mod.
                <ls_any_fv>-neu      = 'O'.
              ENDIF.
            ENDIF.
          ENDLOOP.
          IF lv_sval_abort = abap_true.
            EXIT.
          ENDIF.

          IF lv_found_fld = abap_false.
            READ TABLE lt_usorg INTO ls_uo_m WITH TABLE KEY field = lv_check_fld.
            IF sy-subrc = 0 AND ls_uo_m-varbl IS NOT INITIAL.
              lv_m_def_val = ls_uo_m-varbl.
              lv_m_mod     = 'S'.
              lv_m_neu     = 'O'.
              INSERT ls_uo_m-varbl INTO TABLE lt_tobj_vars.
            ELSE.
              AUTHORITY-CHECK OBJECT 'S_USER_VAL'
                ID 'OBJECT'     FIELD ls_na-object
                ID 'AUTH_FIELD' FIELD lv_check_fld
                ID 'AUTH_VALUE' FIELD space.
              IF sy-subrc <> 0.
                lv_sval_abort = abap_true.
                lv_sval_msg   = |No authorization (S_USER_VAL) for DUMMY field { ls_na-object } / { lv_check_fld } = ''''''.|.
                EXIT.
              ENDIF.
              lv_m_def_val = gc_blank_val.
              lv_m_mod     = lv_touch_hdr_mod.
              lv_m_neu     = 'O'.
            ENDIF.
            APPEND VALUE pt1251(
              object   = ls_na-object
              auth     = ls_na-auth
              variant  = ' '
              field    = lv_check_fld
              low      = lv_m_def_val
              high     = space
              modified = lv_m_mod
              neu      = lv_m_neu
              deleted  = ' '
            ) TO lt_field_values.
            lv_total_added = lv_total_added + 1.
          ENDIF.
        ENDLOOP.
        IF lv_sval_abort = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.

      IF lv_sval_abort = abap_true.
        CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
          EXPORTING
            activity_group = lv_target_role
          EXCEPTIONS
            OTHERS         = 0.
        lv_step2_err = abap_true.
        lv_step2_msg = lv_sval_msg.
        IF lv_menu_added = 0.
          MESSAGE lv_step2_msg TYPE 'S' DISPLAY LIKE 'E'.
          RETURN.
        ENDIF.
      ENDIF.
    ENDIF.

    IF lv_step2_err = abap_false.
      CALL FUNCTION 'PRGN_CLEAR_BUFFER'.

      " SU53-H4: Save Org Levels for explicit SU53 orgs AND newly introduced TOBJ $VARBLs
      IF lt_org_vals IS NOT INITIAL OR lt_tobj_vars IS NOT INITIAL.
        DATA lt_org_all TYPE tt_pt1252.
        PERFORM save_org_levels USING lv_target_role lt_org_vals lt_tobj_vars lv_is_master_r
                                CHANGING lt_org_all lv_org_added lv_org_save_err.
        IF lv_org_save_err = abap_true.
          lv_save_err = abap_true.
        ELSEIF lt_org_vals IS NOT INITIAL.
          " C2: Pass lt_new_auths so pre-existing decoupled 'G'/'M'/'U' overrides are NEVER overwritten
          PERFORM distribute_org_levels USING lt_usorg lt_org_vals lt_org_all lt_new_auths
                                        CHANGING lt_auth_data lt_field_values.
        ENDIF.
        lv_total_added = lv_total_added + lv_org_added.
      ENDIF.

      " Save Role auth data with explicit sy-subrc checks (SU53-M4)
      IF lv_save_err = abap_false.
        CALL FUNCTION 'PRGN_1250_SAVE_AUTH_DATA'
          EXPORTING
            activity_group = lv_target_role
          TABLES
            auth_data      = lt_auth_data
          EXCEPTIONS
            OTHERS         = 1.
        IF sy-subrc <> 0.
          lv_save_err = abap_true.
        ENDIF.
      ENDIF.

      IF lv_save_err = abap_false.
        CALL FUNCTION 'PRGN_1251_SAVE_FIELD_VALUES'
          EXPORTING
            activity_group = lv_target_role
          TABLES
            field_values   = lt_field_values
          EXCEPTIONS
            OTHERS         = 1.
        IF sy-subrc <> 0.
          lv_save_err = abap_true.
        ENDIF.
      ENDIF.

      IF lv_save_err = abap_false.
        CALL FUNCTION 'PRGN_UPDATE_DATABASE'
          EXCEPTIONS
            OTHERS = 1.
        IF sy-subrc <> 0.
          lv_save_err = abap_true.
        ENDIF.
      ENDIF.

      IF lv_save_err = abap_true.
        ROLLBACK WORK.
        CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
        CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
          EXPORTING
            activity_group = lv_target_role
          EXCEPTIONS
            OTHERS         = 0.
        lv_step2_err = abap_true.
        lv_step2_msg = |Failed to save authorization data for role { lv_target_role }. Explicit auth changes rolled back.|.
        IF lv_menu_added = 0.
          MESSAGE lv_step2_msg TYPE 'S' DISPLAY LIKE 'E'.
          RETURN.
        ENDIF.
      ELSE.
        CALL FUNCTION 'PRGN_SET_ACTGROUP_TIMESTAMP'
          EXPORTING
            activity_group = lv_target_role
            no_commit      = 'X'
          EXCEPTIONS
            OTHERS         = 0.
        COMMIT WORK AND WAIT.

        " Unlock Role BEFORE org sync / profile generation
        CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
          EXPORTING
            activity_group = lv_target_role.

        " SU53-H4: Ensure Master Org Levels BEFORE generating profile so PFCG LED stays GREEN!
        IF lv_is_master_r = abap_true.
          CLEAR lv_m_org_mod.
          PERFORM ensure_master_org_levels USING lv_target_role CHANGING lv_m_org_mod.
        ENDIF.

        " Regenerate profile for target role (also restores rebindable 1251 $VARBL bindings)
        PERFORM generate_role_profile USING lv_target_role ' ' abap_true abap_false CHANGING lv_gen_subrc.
        IF lv_gen_subrc <> 0.
          lv_gen_failed = abap_true.
        ELSE.
          COMMIT WORK AND WAIT.
        ENDIF.
      ENDIF.
    ENDIF.

    " MEDIUM-3: Re-generate Master profile if Step 1 ensure_master_org_levels changed timestamp & Step 2 failed
    IF lv_is_master_r = abap_true AND lv_m_org_mod = abap_true AND lv_step2_err = abap_true.
      PERFORM generate_role_profile USING lv_target_role ' ' abap_true abap_false CHANGING lv_gen_subrc.
      IF lv_gen_subrc <> 0.
        lv_gen_failed = abap_true.
      ELSE.
        COMMIT WORK AND WAIT.
      ENDIF.
    ENDIF.
  ENDIF.

  " 3. Read fully updated authorization structures of Master Role (abort Step 4/5 on sy-subrc = 2!)
  CLEAR: lt_auth_data, lt_field_values.
  DATA(lv_lead_read_err) = abap_false.

  CALL FUNCTION 'PRGN_1250_READ_AUTH_DATA'
    EXPORTING
      activity_group    = lv_target_role
    TABLES
      auth_data         = lt_auth_data
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.
  IF sy-subrc = 2.
    lv_gen_failed    = abap_true.
    lv_lead_read_err = abap_true.
  ENDIF.

  CALL FUNCTION 'PRGN_1251_READ_FIELD_VALUES'
    EXPORTING
      activity_group    = lv_target_role
    TABLES
      field_values      = lt_field_values
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.
  IF sy-subrc = 2.
    lv_gen_failed    = abap_true.
    lv_lead_read_err = abap_true.
  ENDIF.

  " 4. Add newly introduced Master Role objects AND SU24 accompanying objects into lt_sel_objects
  IF lv_step2_err = abap_true OR lv_lead_read_err = abap_true.
    " Step 2 failed -> derive ONLY Step 1 menu/SU24 objects; Step 3 failed -> do NOT propagate partial reads
    CLEAR lt_sel_objects.
  ENDIF.
  IF lv_lead_read_err = abap_false.
    LOOP AT lt_auth_data INTO DATA(ls_ad_chk)
      WHERE deleted = ' ' AND copied <> 'I' AND object <> 'S_TCODE'.
      READ TABLE lt_lead_objs_prior TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_ad_chk-object.
      IF sy-subrc <> 0.
        INSERT ls_ad_chk-object INTO TABLE lt_sel_objects.
      ELSE.
        READ TABLE lt_su24_objs TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_ad_chk-object.
        IF sy-subrc = 0.
          INSERT ls_ad_chk-object INTO TABLE lt_sel_objects.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDIF.

  lv_obj_count = lines( lt_sel_objects ).

  " 5. Selectively propagate ONLY the newly added object(s) / TCodes down to all derived child roles
  DATA: lv_der_count TYPE i VALUE 0.

  IF lv_lead_read_err = abap_false
     AND lt_child_roles IS NOT INITIAL
     AND ( lt_sel_objects IS NOT INITIAL OR lt_menu_tcodes IS NOT INITIAL ).
    PERFORM derive_specific_objects
      USING lv_target_role
            lt_child_roles
            lt_sel_objects
            lt_menu_tcodes
            lt_auth_data
            lt_field_values
      CHANGING lv_der_count lv_gen_failed.
  ENDIF.

  PERFORM recheck_auths_after_add USING lv_target_role
                                        lv_der_count
                                        lv_menu_added
                                        lv_menu_failed
                                        lv_failed_txt
                                        lv_gen_failed
                                        lv_obj_count
                                        lv_total_added.
  IF lv_step2_err = abap_true AND lv_step2_msg IS NOT INITIAL.
    IF lt_child_roles IS NOT INITIAL.
      MESSAGE |{ lv_step2_msg } (Menu TCodes propagated to derived roles.)| TYPE 'S' DISPLAY LIKE 'E'.
    ELSE.
      MESSAGE |{ lv_step2_msg } (Menu TCodes added to role.)| TYPE 'S' DISPLAY LIKE 'E'.
    ENDIF.
  ENDIF.
ENDFORM.

*----------------------------------------------------------------------*
* Selected values, organizational levels, role menu
*----------------------------------------------------------------------*
FORM collect_item_combo USING    ps_item   TYPE ty_missing_auth
                                 pt_usorg  TYPE tt_usorg
                        CHANGING ct_combos TYPE tt_sel_combo
                                 ct_orgs   TYPE tt_org_val
                                 ct_sel    TYPE tt_obj_name.
  DATA: ls_combo TYPE ty_sel_combo,
        lv_field TYPE xufield,
        lv_value TYPE xuval,
        ls_usorg TYPE ty_usorg,
        ls_org   TYPE ty_org_val,
        lv_dup   TYPE abap_bool.

  IF ps_item-object IS INITIAL.
    RETURN.
  ENDIF.

  CLEAR ls_combo.
  ls_combo-object = ps_item-object.

  LOOP AT ps_item-check_values INTO DATA(ls_cv).
    lv_field = ls_cv-field.
    TRANSLATE lv_field TO UPPER CASE.
    CONDENSE lv_field NO-GAPS.
    IF lv_field IS INITIAL OR lv_field = 'DUMMYFIELD'.
      CONTINUE.
    ENDIF.

    " AUD-M5: Preserve exact leading/internal spaces; map empty check value to SAP blank literal ''
    IF ls_cv-value IS INITIAL.
      lv_value = gc_blank_val.
    ELSE.
      lv_value = ls_cv-value.
    ENDIF.

    READ TABLE pt_usorg INTO ls_usorg WITH TABLE KEY field = lv_field.
    IF sy-subrc = 0 AND ls_usorg-varbl IS NOT INITIAL.
      ls_org-varbl = ls_usorg-varbl.
      ls_org-low   = lv_value.
      INSERT ls_org INTO TABLE ct_orgs.
      READ TABLE ls_combo-org_fields TRANSPORTING NO FIELDS
        WITH KEY field = lv_field low = lv_value.
      IF sy-subrc <> 0.
        APPEND VALUE ty_combo_org(
          field = lv_field
          varbl = ls_usorg-varbl
          low   = lv_value ) TO ls_combo-org_fields.
      ENDIF.
    ELSE.
      READ TABLE ls_combo-values TRANSPORTING NO FIELDS
        WITH KEY field = lv_field low = lv_value.
      IF sy-subrc <> 0.
        APPEND VALUE ty_agg_val( field = lv_field low = lv_value ) TO ls_combo-values.
      ENDIF.
    ENDIF.
  ENDLOOP.

  SORT ls_combo-values BY field ASCENDING low ASCENDING.
  SORT ls_combo-org_fields BY field ASCENDING low ASCENDING.

  " Deduplicate identical combinations
  lv_dup = abap_false.
  LOOP AT ct_combos INTO DATA(ls_ex) WHERE object = ls_combo-object.
    IF ls_ex-values = ls_combo-values AND ls_ex-org_fields = ls_combo-org_fields.
      lv_dup = abap_true.
      EXIT.
    ENDIF.
  ENDLOOP.
  IF lv_dup = abap_false.
    APPEND ls_combo TO ct_combos.
  ENDIF.

  INSERT ps_item-object INTO TABLE ct_sel.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form find_safe_auth_for_combo
*&---------------------------------------------------------------------*
* Finds whether an active AUTH already covers ps_combo or whether a merge
* is 100% Cartesian-free (inspecting ALL TOBJ fields, including DUMMY!).
* Otherwise returns cv_auth = space so caller creates a new 'U' AUTH.
*&---------------------------------------------------------------------*
FORM find_safe_auth_for_combo USING    ps_combo     TYPE ty_sel_combo
                                       pt_auth_data TYPE tt_pt1250
                                       pt_flds      TYPE tt_pt1251
                                       pt_orgs      TYPE tt_pt1252
                                       pt_usorg     TYPE tt_usorg
                              CHANGING cv_covered   TYPE abap_bool
                                       cv_auth      TYPE xuauth.
  DATA: lt_live_flds    TYPE tt_role_fld,
        lt_tobj_flds    TYPE STANDARD TABLE OF xufield,
        ls_tobj_m       TYPE tobj,
        lv_org_ok       TYPE abap_bool,
        lv_all_cov      TYPE abap_bool,
        lv_unchk_ok     TYPE abap_bool,
        lv_cov          TYPE abap_bool,
        lv_chk_v        TYPE xuval,
        lv_need_add     TYPE i,
        lv_empty_cnt    TYPE i,
        lv_broad_cnt    TYPE i,
        lv_nonempty     TYPE i,
        lv_all_exact    TYPE abap_bool.

  CLEAR: cv_covered, cv_auth, lt_live_flds, lt_tobj_flds, ls_tobj_m.

  SELECT SINGLE fiel1, fiel2, fiel3, fiel4, fiel5, fiel6, fiel7, fiel8, fiel9, fiel0
    FROM tobj WHERE objct = @ps_combo-object
    INTO CORRESPONDING FIELDS OF @ls_tobj_m.
  IF sy-subrc = 0.
    IF ls_tobj_m-fiel1 IS NOT INITIAL. APPEND ls_tobj_m-fiel1 TO lt_tobj_flds. ENDIF.
    IF ls_tobj_m-fiel2 IS NOT INITIAL. APPEND ls_tobj_m-fiel2 TO lt_tobj_flds. ENDIF.
    IF ls_tobj_m-fiel3 IS NOT INITIAL. APPEND ls_tobj_m-fiel3 TO lt_tobj_flds. ENDIF.
    IF ls_tobj_m-fiel4 IS NOT INITIAL. APPEND ls_tobj_m-fiel4 TO lt_tobj_flds. ENDIF.
    IF ls_tobj_m-fiel5 IS NOT INITIAL. APPEND ls_tobj_m-fiel5 TO lt_tobj_flds. ENDIF.
    IF ls_tobj_m-fiel6 IS NOT INITIAL. APPEND ls_tobj_m-fiel6 TO lt_tobj_flds. ENDIF.
    IF ls_tobj_m-fiel7 IS NOT INITIAL. APPEND ls_tobj_m-fiel7 TO lt_tobj_flds. ENDIF.
    IF ls_tobj_m-fiel8 IS NOT INITIAL. APPEND ls_tobj_m-fiel8 TO lt_tobj_flds. ENDIF.
    IF ls_tobj_m-fiel9 IS NOT INITIAL. APPEND ls_tobj_m-fiel9 TO lt_tobj_flds. ENDIF.
    IF ls_tobj_m-fiel0 IS NOT INITIAL. APPEND ls_tobj_m-fiel0 TO lt_tobj_flds. ENDIF.
  ENDIF.

  LOOP AT pt_flds INTO DATA(ls_pf)
    WHERE object = ps_combo-object AND deleted = space AND copied <> 'I'.
    APPEND VALUE ty_role_fld(
      object   = ls_pf-object
      auth     = ls_pf-auth
      field    = ls_pf-field
      low      = ls_pf-low
      high     = ls_pf-high
      modified = ls_pf-modified ) TO lt_live_flds.
  ENDLOOP.

  " Pass 1: Already covered by an existing active AUTH instance
  LOOP AT pt_auth_data INTO DATA(ls_ad)
    WHERE object = ps_combo-object AND deleted = space AND copied <> 'I'.
    lv_org_ok = abap_true.
    LOOP AT ps_combo-org_fields INTO DATA(ls_co).
      lv_chk_v = COND #( WHEN ls_co-low = gc_blank_val THEN space ELSE ls_co-low ).
      PERFORM field_value_covered USING lt_live_flds pt_orgs pt_usorg
                                        ps_combo-object ls_ad-auth ls_co-field lv_chk_v
                                  CHANGING lv_cov.
      IF lv_cov = abap_false.
        lv_org_ok = abap_false.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF lv_org_ok = abap_false.
      CONTINUE.
    ENDIF.

    lv_all_cov = abap_true.
    LOOP AT ps_combo-values INTO DATA(ls_v).
      lv_chk_v = COND #( WHEN ls_v-low = gc_blank_val THEN space ELSE ls_v-low ).
      PERFORM field_value_covered USING lt_live_flds pt_orgs pt_usorg
                                        ps_combo-object ls_ad-auth ls_v-field lv_chk_v
                                  CHANGING lv_cov.
      IF lv_cov = abap_false.
        lv_all_cov = abap_false.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF lv_all_cov = abap_true.
      cv_covered = abap_true.
      RETURN.
    ENDIF.
  ENDLOOP.

  " Pass 2: Find a mathematically Cartesian-free merge candidate (inspecting DUMMY TOBJ fields!)
  LOOP AT pt_auth_data INTO ls_ad
    WHERE object = ps_combo-object AND deleted = space AND copied <> 'I'.
    lv_org_ok = abap_true.
    LOOP AT ps_combo-org_fields INTO ls_co.
      LOOP AT lt_live_flds INTO DATA(ls_lf_o)
        WHERE auth = ls_ad-auth AND field = ls_co-field.
        IF ( ls_lf_o-modified = 'G' OR ls_lf_o-modified = 'M' OR ls_lf_o-modified = 'U' )
           AND ( ( ls_lf_o-low IS NOT INITIAL AND ls_lf_o-low <> '-1'
                   AND ls_lf_o-low <> '$' AND ls_lf_o-low <> ls_co-varbl )
                 OR ls_lf_o-high IS NOT INITIAL ).
          IF ls_lf_o-low <> ls_co-low OR ls_lf_o-high IS NOT INITIAL.
            lv_org_ok = abap_false.
            EXIT.
          ENDIF.
        ENDIF.
      ENDLOOP.
      IF lv_org_ok = abap_false.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF lv_org_ok = abap_false.
      CONTINUE.
    ENDIF.

    " AUD-C1: Reject merging if candidate AUTH holds concrete values on any DUMMY (unchecked) TOBJ field
    lv_unchk_ok = abap_true.
    LOOP AT lt_tobj_flds INTO DATA(lv_tf).
      IF line_exists( ps_combo-values[ field = lv_tf ] )
         OR line_exists( ps_combo-org_fields[ field = lv_tf ] ).
        CONTINUE.
      ENDIF.
      READ TABLE pt_usorg INTO DATA(ls_uo_tf) WITH TABLE KEY field = lv_tf.
      IF sy-subrc = 0 AND ls_uo_tf-varbl IS NOT INITIAL.
        LOOP AT lt_live_flds INTO DATA(ls_lf_uo)
          WHERE auth = ls_ad-auth AND field = lv_tf.
          IF ( ls_lf_uo-modified = 'G' OR ls_lf_uo-modified = 'M' OR ls_lf_uo-modified = 'U' )
             AND ( ( ls_lf_uo-low IS NOT INITIAL AND ls_lf_uo-low <> '-1'
                     AND ls_lf_uo-low <> '$' AND ls_lf_uo-low <> ls_uo_tf-varbl )
                   OR ls_lf_uo-high IS NOT INITIAL ).
            lv_unchk_ok = abap_false.
            EXIT.
          ENDIF.
        ENDLOOP.
      ELSE.
        LOOP AT lt_live_flds INTO DATA(ls_lf_u)
          WHERE auth = ls_ad-auth AND field = lv_tf.
          IF ls_lf_u-low IS INITIAL AND ls_lf_u-high IS INITIAL.
            CONTINUE.
          ENDIF.
          IF ls_lf_u-low <> gc_blank_val OR ls_lf_u-high IS NOT INITIAL.
            lv_unchk_ok = abap_false.
            EXIT.
          ENDIF.
        ENDLOOP.
      ENDIF.
      IF lv_unchk_ok = abap_false.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF lv_unchk_ok = abap_false.
      CONTINUE.
    ENDIF.

    CLEAR: lv_need_add, lv_empty_cnt, lv_broad_cnt.
    LOOP AT ps_combo-values INTO ls_v.
      lv_chk_v     = COND #( WHEN ls_v-low = gc_blank_val THEN space ELSE ls_v-low ).
      lv_nonempty  = 0.
      lv_all_exact = abap_true.
      LOOP AT lt_live_flds INTO DATA(ls_lf)
        WHERE auth = ls_ad-auth AND field = ls_v-field.
        IF ls_lf-low IS INITIAL AND ls_lf-high IS INITIAL.
          CONTINUE.
        ENDIF.
        lv_nonempty = lv_nonempty + 1.
        IF ls_lf-low <> ls_v-low OR ls_lf-high IS NOT INITIAL.
          lv_all_exact = abap_false.
        ENDIF.
      ENDLOOP.

      PERFORM field_value_covered USING lt_live_flds pt_orgs pt_usorg
                                        ps_combo-object ls_ad-auth ls_v-field lv_chk_v
                                  CHANGING lv_cov.
      IF lv_nonempty = 0.
        lv_empty_cnt = lv_empty_cnt + 1.
      ELSEIF lv_cov = abap_true AND lv_all_exact = abap_true.
        " Exact single-value match on this field -> safe peer
      ELSEIF lv_cov = abap_true.
        lv_broad_cnt = lv_broad_cnt + 1.
      ELSE.
        lv_need_add = lv_need_add + 1.
      ENDIF.
    ENDLOOP.

    IF ( lv_need_add = 0 AND lv_broad_cnt = 0 AND lv_empty_cnt > 0 )
       OR ( lv_need_add = 1 AND lv_empty_cnt = 0 AND lv_broad_cnt = 0 ).
      cv_auth = ls_ad-auth.
      RETURN.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM ensure_role_auth USING    pv_object    TYPE tobj-objct
                               pv_force_new TYPE abap_bool
                      CHANGING ct_auth      TYPE tt_pt1250
                               cv_counter   TYPE i
                               ev_auth      TYPE xuauth
                               ev_created   TYPE abap_bool.
  DATA lv_auth TYPE xuauth.

  CLEAR: ev_auth, ev_created.

  " Search for existing ACTIVE node unless caller requires a brand-new instance
  IF pv_force_new = abap_false.
    LOOP AT ct_auth ASSIGNING FIELD-SYMBOL(<ls_auth>)
      WHERE object = pv_object AND deleted = space AND copied <> 'I'.
      IF <ls_auth>-modified <> 'U'.
        <ls_auth>-modified = 'M'.
      ENDIF.
      ev_auth = <ls_auth>-auth.
      RETURN.
    ENDLOOP.
  ENDIF.

  " Generate a brand new active manual ('U') node
  DATA(lv_found_slot) = abap_false.
  DO 999 TIMES.
    IF cv_counter < 100.
      lv_auth = |__________{ cv_counter WIDTH = 2 ALIGN = RIGHT PAD = '0' }|.
    ELSE.
      lv_auth = |________{ cv_counter WIDTH = 4 ALIGN = RIGHT PAD = '0' }|.
    ENDIF.
    READ TABLE ct_auth TRANSPORTING NO FIELDS
      WITH KEY auth = lv_auth.
    cv_counter = cv_counter + 1.
    IF sy-subrc <> 0.
      lv_found_slot = abap_true.
      EXIT.
    ENDIF.
  ENDDO.
  IF lv_found_slot = abap_false.
    RETURN.
  ENDIF.

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
    neu      = 'O'
    deleted  = ' '
    atext    = lv_text
  ) TO ct_auth.
  ev_auth    = lv_auth.
  ev_created = abap_true.
ENDFORM.

FORM save_org_levels USING    pv_role      TYPE agr_name
                              pt_new       TYPE tt_org_val
                              pt_tobj_vars TYPE tt_varbl
                              pv_is_master TYPE abap_bool
                     CHANGING ct_all       TYPE tt_pt1252
                              cv_added     TYPE i
                              ev_save_err  TYPE abap_bool.
  DATA: ls_new         TYPE ty_org_val,
        ls_row         TYPE pt1252,
        lv_org_changed TYPE abap_bool.

  CLEAR: ct_all, cv_added, ev_save_err, lv_org_changed.

  CALL FUNCTION 'PRGN_1252_READ_ORG_LEVELS'
    EXPORTING
      activity_group    = pv_role
    TABLES
      org_levels        = ct_all
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.
  IF sy-subrc = 2.
    ev_save_err = abap_true.
    RETURN.
  ENDIF.

  LOOP AT pt_new INTO ls_new.
    IF pv_is_master = abap_true.
      READ TABLE ct_all TRANSPORTING NO FIELDS
        WITH KEY varbl = ls_new-varbl.
      IF sy-subrc <> 0.
        CLEAR ls_row.
        ls_row-varbl = ls_new-varbl.
        ls_row-low   = '-1'.
        APPEND ls_row TO ct_all.
        cv_added       = cv_added + 1.
        lv_org_changed = abap_true.
      ENDIF.
    ELSE.
      DATA(lv_target_val) = ls_new-low.
      DATA(lv_covered)    = abap_false.
      LOOP AT ct_all INTO DATA(ls_ex_org) WHERE varbl = ls_new-varbl.
        IF ( ls_ex_org-low IS INITIAL OR ls_ex_org-low = '-1' OR ls_ex_org-low = '$' )
           AND ls_ex_org-high IS INITIAL.
          CONTINUE.
        ENDIF.
        IF ls_ex_org-low = '*' AND ls_ex_org-high IS INITIAL.
          lv_covered = abap_true.
          EXIT.
        ELSEIF ls_ex_org-low = lv_target_val AND ls_ex_org-high IS INITIAL.
          lv_covered = abap_true.
          EXIT.
        ELSEIF ls_ex_org-high IS NOT INITIAL
               AND lv_target_val <> gc_blank_val
               AND lv_target_val >= ls_ex_org-low
               AND lv_target_val <= ls_ex_org-high.
          lv_covered = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.

      IF lv_covered = abap_false.
        " Clean all stray empty/'-1'/'$' rows for this varbl before adding concrete value
        DELETE ct_all WHERE varbl = ls_new-varbl
                        AND ( low IS INITIAL OR low = '-1' OR low = '$' )
                        AND high IS INITIAL.
        CLEAR ls_row.
        ls_row-varbl = ls_new-varbl.
        ls_row-low   = lv_target_val.
        ls_row-high  = space.
        APPEND ls_row TO ct_all.
        cv_added       = cv_added + 1.
        lv_org_changed = abap_true.
      ENDIF.
    ENDIF.
  ENDLOOP.

  " Ensure every new TOBJ $VARBL has a corresponding AGR_1252 row (Master='-1', Standalone=space)
  LOOP AT pt_tobj_vars INTO DATA(lv_tv).
    READ TABLE ct_all TRANSPORTING NO FIELDS WITH KEY varbl = lv_tv.
    IF sy-subrc <> 0.
      CLEAR ls_row.
      ls_row-varbl = lv_tv.
      ls_row-low   = COND #( WHEN pv_is_master = abap_true THEN '-1' ELSE space ).
      ls_row-high  = space.
      APPEND ls_row TO ct_all.
      cv_added       = cv_added + 1.
      lv_org_changed = abap_true.
    ENDIF.
  ENDLOOP.

  IF lv_org_changed = abap_true.
    CALL FUNCTION 'PRGN_1252_SAVE_ORG_LEVELS'
      EXPORTING
        activity_group = pv_role
      TABLES
        org_levels     = ct_all
      EXCEPTIONS
        OTHERS         = 1.
    IF sy-subrc <> 0.
      ev_save_err = abap_true.
    ENDIF.
  ENDIF.
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

FORM distribute_org_levels USING    pt_usorg     TYPE tt_usorg
                                    pt_new       TYPE tt_org_val
                                    pt_all       TYPE tt_pt1252
                                    pt_new_auths TYPE tt_role_obj
                           CHANGING ct_auth      TYPE tt_pt1250
                                    ct_flds      TYPE tt_pt1251.
  DATA: lt_obj_fields  TYPE tt_obj_field,
        lt_varbl       TYPE SORTED TABLE OF agr_1252-varbl WITH UNIQUE KEY table_line,
        lv_field       TYPE xufield,
        lv_has_decoupl TYPE abap_bool,
        lv_already_var TYPE abap_bool,
        lv_row_cnt     TYPE i.

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
    " M2: Iterate ALL USORG fields sharing this $VARBL (do NOT exit after the first!)
    LOOP AT pt_usorg INTO DATA(ls_us) WHERE varbl = lv_varbl.
      lv_field = ls_us-field.
      IF lv_field IS INITIAL.
        CONTINUE.
      ENDIF.

      LOOP AT ct_auth ASSIGNING FIELD-SYMBOL(<ls_auth>)
        WHERE deleted = space AND copied <> 'I'.
        READ TABLE lt_obj_fields TRANSPORTING NO FIELDS
          WITH TABLE KEY object = <ls_auth>-object field = lv_field.
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.

        " Preserve decoupled concrete 'G'/'M'/'U' org overrides on pre-existing AUTH instances
        CLEAR: lv_has_decoupl, lv_already_var, lv_row_cnt.
        LOOP AT ct_flds INTO DATA(ls_chk_cf)
          WHERE object = <ls_auth>-object AND auth = <ls_auth>-auth
            AND field = lv_field AND deleted = space AND copied <> 'I'.
          lv_row_cnt = lv_row_cnt + 1.
          DATA(lv_cf_rebind) = xsdbool(
            NOT ( ( ls_chk_cf-modified = 'G' OR ls_chk_cf-modified = 'M' OR ls_chk_cf-modified = 'U' )
                  AND ( ( ls_chk_cf-low IS NOT INITIAL AND ls_chk_cf-low <> '-1'
                          AND ls_chk_cf-low <> '$' AND ls_chk_cf-low <> lv_varbl )
                        OR ls_chk_cf-high IS NOT INITIAL ) ) ).
          IF lv_cf_rebind = abap_false.
            lv_has_decoupl = abap_true.
          ENDIF.
          IF ls_chk_cf-modified = 'S' AND ls_chk_cf-low = lv_varbl AND ls_chk_cf-high IS INITIAL.
            lv_already_var = abap_true.
          ENDIF.
        ENDLOOP.

        IF lv_has_decoupl = abap_true
           AND NOT line_exists( pt_new_auths[ object = <ls_auth>-object auth = <ls_auth>-auth ] ).
          CONTINUE.
        ENDIF.
        IF lv_row_cnt = 1 AND lv_already_var = abap_true.
          CONTINUE.
        ENDIF.

        DELETE ct_flds WHERE object = <ls_auth>-object
                         AND auth   = <ls_auth>-auth
                         AND field  = lv_field
                         AND deleted = space AND copied <> 'I'.

        " SAPLSUPRN requires MODIFIED = 'S' on $VARBL rows for AGR_1252 expansion
        APPEND VALUE pt1251(
          object   = <ls_auth>-object
          auth     = <ls_auth>-auth
          variant  = ' '
          field    = lv_field
          low      = lv_varbl
          high     = space
          modified = 'S'
          neu      = 'O'
          deleted  = ' '
        ) TO ct_flds.
      ENDLOOP.
    ENDLOOP.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form ensure_master_org_levels
*&---------------------------------------------------------------------*
FORM ensure_master_org_levels USING    pv_role    TYPE agr_name
                              CHANGING cv_org_mod TYPE abap_bool.
  DATA: lt_orgs       TYPE tt_pt1252,
        lt_usorg_chk  TYPE HASHED TABLE OF usorg-varbl WITH UNIQUE KEY table_line,
        lv_has_ch     TYPE agr_name,
        lv_save_err   TYPE abap_bool.

  CLEAR: cv_org_mod, lv_save_err.

  " Only enforce '-1' Org Level placeholders on true Master Roles (with derived children)
  SELECT SINGLE agr_name FROM agr_define
    WHERE parent_agr = @pv_role
    INTO @lv_has_ch.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  SELECT DISTINCT varbl FROM usorg INTO TABLE @lt_usorg_chk.

  CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
    EXPORTING
      activity_group = pv_role
      no_dialog      = 'X'
    EXCEPTIONS
      foreign_lock   = 1
      system_error   = 2
      OTHERS         = 3.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  CALL FUNCTION 'PRGN_1252_READ_ORG_LEVELS'
    EXPORTING
      activity_group    = pv_role
    TABLES
      org_levels        = lt_orgs
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.
  IF sy-subrc = 2.
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
      EXPORTING
        activity_group = pv_role.
    RETURN.
  ENDIF.

  " 1. Any existing org level in Master Role with empty low & high becomes '-1'
  LOOP AT lt_orgs ASSIGNING FIELD-SYMBOL(<ls_o>).
    IF ( <ls_o>-low IS INITIAL OR <ls_o>-low = space ) AND <ls_o>-high IS INITIAL.
      <ls_o>-low = '-1'.
      cv_org_mod = abap_true.
    ENDIF.
  ENDLOOP.

  " 2. Only genuine USORG $VARBLs from ACTIVE AGR_1251 + ACTIVE AGR_1250 (never '$TMP' or inactive auths!)
  DATA lt_vars_in_1251 TYPE STANDARD TABLE OF agr_1251-low.
  SELECT DISTINCT f~low
    FROM agr_1251 AS f
    INNER JOIN agr_1250 AS a
      ON a~agr_name = f~agr_name
     AND a~object   = f~object
     AND a~auth     = f~auth
    INTO TABLE @lt_vars_in_1251
    WHERE f~agr_name = @pv_role
      AND f~low LIKE '$%'
      AND f~deleted  = @space AND f~copied <> 'I'
      AND a~deleted  = @space AND a~copied <> 'I'.

  LOOP AT lt_vars_in_1251 INTO DATA(lv_var_1251).
    IF NOT line_exists( lt_usorg_chk[ table_line = lv_var_1251 ] ).
      CONTINUE.
    ENDIF.
    READ TABLE lt_orgs WITH KEY varbl = lv_var_1251 TRANSPORTING NO FIELDS.
    IF sy-subrc <> 0.
      APPEND VALUE pt1252(
        varbl = lv_var_1251
        low   = '-1'
        high  = space
      ) TO lt_orgs.
      cv_org_mod = abap_true.
    ENDIF.
  ENDLOOP.

  IF cv_org_mod = abap_true.
    CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
    CALL FUNCTION 'PRGN_1252_SAVE_ORG_LEVELS'
      EXPORTING
        activity_group = pv_role
      TABLES
        org_levels     = lt_orgs
      EXCEPTIONS
        OTHERS         = 1.
    IF sy-subrc <> 0.
      lv_save_err = abap_true.
    ENDIF.

    IF lv_save_err = abap_false.
      CALL FUNCTION 'PRGN_UPDATE_DATABASE'
        EXCEPTIONS
          OTHERS = 1.
      IF sy-subrc <> 0.
        lv_save_err = abap_true.
      ENDIF.
    ENDIF.

    IF lv_save_err = abap_true.
      ROLLBACK WORK.
      CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
      cv_org_mod = abap_false.
    ELSE.
      CALL FUNCTION 'PRGN_SET_ACTGROUP_TIMESTAMP'
        EXPORTING
          activity_group = pv_role
          no_commit      = 'X'
        EXCEPTIONS
          OTHERS         = 0.
      COMMIT WORK AND WAIT.
    ENDIF.
  ENDIF.

  CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
    EXPORTING
      activity_group = pv_role.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form restore_role_1251_org_bindings
*&---------------------------------------------------------------------*
* Restores ONLY rebindable active Org Level fields in AGR_1251 to $VARBL
* while strictly preserving decoupled concrete 'M'/'U' overrides (C2)
* and honoring SAP TPR_ST_MOD domain ('S'/'G'/'M'/'U').
*&---------------------------------------------------------------------*
FORM restore_role_1251_org_bindings USING iv_agr_name TYPE agr_name.
  TYPES: BEGIN OF ty_seen_org,
           object TYPE tobj-objct,
           auth   TYPE xuauth,
           field  TYPE xufield,
         END OF ty_seen_org,
         BEGIN OF ty_hdr_mod,
           object   TYPE tobj-objct,
           auth     TYPE xuauth,
           modified TYPE c LENGTH 1,
         END OF ty_hdr_mod,
         BEGIN OF ty_healed_auth,
           object TYPE tobj-objct,
           auth   TYPE xuauth,
         END OF ty_healed_auth.

  DATA: lt_pt1251       TYPE STANDARD TABLE OF pt1251,
        lt_pt1250       TYPE STANDARD TABLE OF pt1250,
        lt_act_hdr      TYPE HASHED TABLE OF ty_hdr_mod WITH UNIQUE KEY object auth,
        lt_usorg        TYPE tt_usorg,
        lt_seen         TYPE HASHED TABLE OF ty_seen_org WITH UNIQUE KEY object auth field,
        lt_healed_auths TYPE HASHED TABLE OF ty_healed_auth WITH UNIQUE KEY object auth,
        lv_tgt_mod      TYPE c LENGTH 1,
        lv_mod51        TYPE abap_bool,
        lv_mod50        TYPE abap_bool,
        lv_save_err     TYPE abap_bool.

  CLEAR: lt_pt1251, lt_pt1250, lt_act_hdr, lt_usorg, lt_seen, lt_healed_auths,
         lv_mod51, lv_mod50, lv_save_err.

  SELECT field, varbl FROM usorg INTO TABLE @lt_usorg.
  IF lt_usorg IS INITIAL.
    RETURN.
  ENDIF.

  CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
    EXPORTING
      activity_group = iv_agr_name
      no_dialog      = 'X'
    EXCEPTIONS
      foreign_lock   = 1
      system_error   = 2
      OTHERS         = 3.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  CALL FUNCTION 'PRGN_1250_READ_AUTH_DATA'
    EXPORTING
      activity_group    = iv_agr_name
      no_texts          = 'X'
    TABLES
      auth_data         = lt_pt1250
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.

  IF sy-subrc <> 0 OR lt_pt1250 IS INITIAL.
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
      EXPORTING
        activity_group = iv_agr_name.
    RETURN.
  ENDIF.

  LOOP AT lt_pt1250 INTO DATA(ls_h50) WHERE deleted = space AND copied <> 'I'.
    INSERT VALUE ty_hdr_mod(
      object   = ls_h50-object
      auth     = ls_h50-auth
      modified = ls_h50-modified
    ) INTO TABLE lt_act_hdr.
  ENDLOOP.

  CALL FUNCTION 'PRGN_1251_READ_FIELD_VALUES'
    EXPORTING
      activity_group    = iv_agr_name
    TABLES
      field_values      = lt_pt1251
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.

  IF sy-subrc <> 0 OR lt_pt1251 IS INITIAL.
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
      EXPORTING
        activity_group = iv_agr_name.
    RETURN.
  ENDIF.

  " Pre-scan: identify any (object, auth, field) with an active concrete 'G'/'M'/'U' override
  DATA: lt_dec_flds TYPE SORTED TABLE OF ty_seen_org WITH UNIQUE KEY object auth field.
  LOOP AT lt_pt1251 INTO DATA(ls_f51_pre)
    WHERE deleted = space AND copied <> 'I'.
    READ TABLE lt_act_hdr TRANSPORTING NO FIELDS
      WITH TABLE KEY object = ls_f51_pre-object auth = ls_f51_pre-auth.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.
    READ TABLE lt_usorg INTO DATA(ls_uo_pre) WITH TABLE KEY field = ls_f51_pre-field.
    IF sy-subrc <> 0 OR ls_uo_pre-varbl IS INITIAL.
      CONTINUE.
    ENDIF.
    IF ( ls_f51_pre-modified = 'G' OR ls_f51_pre-modified = 'M' OR ls_f51_pre-modified = 'U' )
       AND ( ( ls_f51_pre-low IS NOT INITIAL AND ls_f51_pre-low <> '-1'
               AND ls_f51_pre-low <> '$' AND ls_f51_pre-low <> ls_uo_pre-varbl )
             OR ls_f51_pre-high IS NOT INITIAL ).
      INSERT VALUE ty_seen_org(
        object = ls_f51_pre-object
        auth   = ls_f51_pre-auth
        field  = ls_f51_pre-field ) INTO TABLE lt_dec_flds.
    ENDIF.
  ENDLOOP.

  " Restore ONLY rebindable org-level rows to $VARBL with MODIFIED = 'S'; preserve decoupled overrides
  DATA: lv_idx TYPE sy-tabix.
  LOOP AT lt_pt1251 ASSIGNING FIELD-SYMBOL(<ls_f51>).
    lv_idx = sy-tabix.
    IF <ls_f51>-deleted <> space OR <ls_f51>-copied = 'I'.
      CONTINUE.
    ENDIF.
    READ TABLE lt_act_hdr INTO DATA(ls_hdr)
      WITH TABLE KEY object = <ls_f51>-object auth = <ls_f51>-auth.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.
    READ TABLE lt_usorg INTO DATA(ls_uo) WITH TABLE KEY field = <ls_f51>-field.
    IF sy-subrc <> 0 OR ls_uo-varbl IS INITIAL.
      CONTINUE.
    ENDIF.

    READ TABLE lt_dec_flds TRANSPORTING NO FIELDS WITH TABLE KEY
      object = <ls_f51>-object auth = <ls_f51>-auth field = <ls_f51>-field.
    IF sy-subrc = 0.
      CONTINUE.
    ENDIF.

    DATA(ls_skey) = VALUE ty_seen_org(
      object = <ls_f51>-object
      auth   = <ls_f51>-auth
      field  = <ls_f51>-field ).
    READ TABLE lt_seen TRANSPORTING NO FIELDS WITH TABLE KEY
      object = ls_skey-object auth = ls_skey-auth field = ls_skey-field.
    IF sy-subrc = 0.
      DELETE lt_pt1251 INDEX lv_idx.
      lv_mod51 = abap_true.
      INSERT VALUE ty_healed_auth( object = ls_skey-object auth = ls_skey-auth ) INTO TABLE lt_healed_auths.
      CONTINUE.
    ENDIF.
    INSERT ls_skey INTO TABLE lt_seen.

    lv_tgt_mod = 'S'.
    IF <ls_f51>-low <> ls_uo-varbl OR <ls_f51>-high IS NOT INITIAL
       OR <ls_f51>-modified <> lv_tgt_mod.
      <ls_f51>-low      = ls_uo-varbl.
      <ls_f51>-high     = space.
      <ls_f51>-modified = lv_tgt_mod.
      <ls_f51>-neu      = 'O'.
      lv_mod51          = abap_true.
      INSERT VALUE ty_healed_auth( object = ls_skey-object auth = ls_skey-auth ) INTO TABLE lt_healed_auths.
    ENDIF.
  ENDLOOP.

  " Normalize ONLY 'M' headers in lt_healed_auths when no active 'M' fields remain; NEVER touch unrelated/Manual 'U'
  LOOP AT lt_pt1250 ASSIGNING FIELD-SYMBOL(<ls_a50>)
    WHERE modified = 'M' AND deleted = space AND copied <> 'I'.
    IF NOT line_exists( lt_healed_auths[ object = <ls_a50>-object auth = <ls_a50>-auth ] ).
      CONTINUE.
    ENDIF.
    DATA(lv_has_m) = abap_false.
    DATA(lv_has_g) = abap_false.
    LOOP AT lt_pt1251 INTO DATA(ls_chk_f)
      WHERE object = <ls_a50>-object AND auth = <ls_a50>-auth
        AND deleted = space AND copied <> 'I'.
      IF ls_chk_f-modified = 'M'.
        lv_has_m = abap_true.
        EXIT.
      ELSEIF ls_chk_f-modified = 'G'.
        lv_has_g = abap_true.
      ENDIF.
    ENDLOOP.
    IF lv_has_m = abap_false.
      <ls_a50>-modified = COND #( WHEN lv_has_g = abap_true THEN 'G' ELSE 'S' ).
      lv_mod50          = abap_true.
    ENDIF.
  ENDLOOP.

  IF lv_mod51 = abap_true OR lv_mod50 = abap_true.
    CALL FUNCTION 'PRGN_CLEAR_BUFFER'.

    IF lv_mod51 = abap_true.
      CALL FUNCTION 'PRGN_1251_SAVE_FIELD_VALUES'
        EXPORTING
          activity_group = iv_agr_name
        TABLES
          field_values   = lt_pt1251
        EXCEPTIONS
          OTHERS         = 1.
      IF sy-subrc <> 0.
        lv_save_err = abap_true.
      ENDIF.
    ENDIF.

    IF lv_save_err = abap_false AND lv_mod50 = abap_true.
      CALL FUNCTION 'PRGN_1250_SAVE_AUTH_DATA'
        EXPORTING
          activity_group = iv_agr_name
        TABLES
          auth_data      = lt_pt1250
        EXCEPTIONS
          OTHERS         = 1.
      IF sy-subrc <> 0.
        lv_save_err = abap_true.
      ENDIF.
    ENDIF.

    IF lv_save_err = abap_false.
      CALL FUNCTION 'PRGN_UPDATE_DATABASE'
        EXCEPTIONS
          OTHERS = 1.
      IF sy-subrc <> 0.
        lv_save_err = abap_true.
      ENDIF.
    ENDIF.

    IF lv_save_err = abap_true.
      ROLLBACK WORK.
      CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
    ELSE.
      CALL FUNCTION 'PRGN_SET_ACTGROUP_TIMESTAMP'
        EXPORTING
          activity_group = iv_agr_name
          no_commit      = 'X'
        EXCEPTIONS
          OTHERS         = 0.
      COMMIT WORK AND WAIT.
    ENDIF.
  ENDIF.

  CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
    EXPORTING
      activity_group = iv_agr_name.
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

*&---------------------------------------------------------------------*
*& Form add_tcodes_to_role_menu
*&---------------------------------------------------------------------*
*& Purpose: Add transaction codes into the target role's menu hierarchy.
*& Requirement: Always insert under the FIRST folder if one exists;
*&              otherwise fallback to home/root.
*&---------------------------------------------------------------------*
FORM add_tcodes_to_role_menu USING pv_role TYPE agr_name
                             CHANGING ct_tcodes     TYPE tt_tcode
                                      cv_added      TYPE i
                                      cv_failed     TYPE i
                                      cv_failed_txt TYPE string
                                      cv_abort      TYPE abap_bool.
  DATA: lt_nodes         TYPE STANDARD TABLE OF agr_shier,
        lt_texts         TYPE STANDARD TABLE OF agr_shiert,
        lt_folders       TYPE STANDARD TABLE OF agr_shier,
        lt_top_folders   TYPE STANDARD TABLE OF agr_shier,
        lt_invalid_tc    TYPE tt_tcode,
        lt_return        TYPE bapirettab,
        lv_err_flag      TYPE char01,
        lv_target_folder TYPE menu_num_8 VALUE 1,
        lv_target_level  TYPE menu_num_2 VALUE 1,
        lv_folder_found  TYPE abap_bool  VALUE abap_false,
        lv_max_id        TYPE menu_num_8 VALUE 1,
        lv_max_sort      TYPE menu_num_8 VALUE 0,
        lv_nodes_changed TYPE abap_bool  VALUE abap_false,
        lv_tcode         TYPE sytcode,
        lv_chk_tc        TYPE sytcode,
        lv_ttext         TYPE ssm_title,
        ls_new_node      TYPE agr_shier,
        ls_new_stck      TYPE smen_stck,
        ls_cur_stck      TYPE smen_stck,
        lv_in_nodes      TYPE abap_bool.

  CLEAR: cv_added, cv_failed, cv_failed_txt, cv_abort, lt_invalid_tc.

  IF ct_tcodes IS INITIAL.
    RETURN.
  ENDIF.

  " SU53-M4: Enqueue role BEFORE reading menu nodes to avoid TOCTOU overwrite race
  CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
    EXPORTING
      activity_group = pv_role
      no_dialog      = 'X'
    EXCEPTIONS
      foreign_lock   = 1
      system_error   = 2
      OTHERS         = 3.
  IF sy-subrc <> 0.
    DATA(lv_menu_lock_u) = sy-msgv1.
    cv_abort = abap_true.
    IF lv_menu_lock_u IS NOT INITIAL.
      MESSAGE |Role { pv_role } is locked by user { lv_menu_lock_u }. Please exit Edit mode in PFCG first.| TYPE 'S' DISPLAY LIKE 'E'.
    ELSE.
      MESSAGE |Role { pv_role } is locked (Edit mode). Please exit Edit mode in PFCG first.| TYPE 'S' DISPLAY LIKE 'E'.
    ENDIF.
    RETURN.
  ENDIF.

  " 1. Load existing menu hierarchy nodes and texts
  CALL FUNCTION 'PRGN_STRU_LOAD_NODES'
    EXPORTING
      activity_group = pv_role
    TABLES
      i_nodes_out    = lt_nodes
      i_texts_out    = lt_texts
    EXCEPTIONS
      not_authorized = 1
      OTHERS         = 2.
  IF sy-subrc <> 0.
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
      EXPORTING
        activity_group = pv_role.
    cv_abort = abap_true.
    MESSAGE |Not authorized or unable to read menu of role { pv_role }.| TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  " 2. Find the FIRST folder in role menu hierarchy:
  "    First priority: Top-level folder (parent_id = 1) with lowest sort_order / object_id.
  "    Second priority: Any folder (folder = 'X') with lowest level/sort_order.
  "    Fallback: Home/root (parent_id = 1, menu_level = 1).
  CLEAR: lt_folders, lt_top_folders.
  LOOP AT lt_nodes INTO DATA(ls_n) WHERE folder = 'X'.
    APPEND ls_n TO lt_folders.
    IF ls_n-parent_id = 1.
      APPEND ls_n TO lt_top_folders.
    ENDIF.
  ENDLOOP.

  IF lt_top_folders IS NOT INITIAL.
    SORT lt_top_folders BY sort_order ASCENDING object_id ASCENDING.
    READ TABLE lt_top_folders INTO DATA(ls_first_top) INDEX 1.
    IF sy-subrc = 0.
      lv_target_folder = ls_first_top-object_id.
      lv_target_level  = ls_first_top-menu_level + 1.
      lv_folder_found  = abap_true.
    ENDIF.
  ELSEIF lt_folders IS NOT INITIAL.
    SORT lt_folders BY menu_level ASCENDING sort_order ASCENDING object_id ASCENDING.
    READ TABLE lt_folders INTO DATA(ls_first_any) INDEX 1.
    IF sy-subrc = 0.
      lv_target_folder = ls_first_any-object_id.
      lv_target_level  = ls_first_any-menu_level + 1.
      lv_folder_found  = abap_true.
    ENDIF.
  ENDIF.

  IF lv_folder_found = abap_false.
    " No folder found in role menu -> place at home/root
    lv_target_folder = 1.
    lv_target_level  = 1.
  ENDIF.

  " 3. Determine max object_id in role and max sort_order under target folder
  lv_max_id   = 1.
  lv_max_sort = 0.
  LOOP AT lt_nodes INTO DATA(ls_chk_node).
    IF ls_chk_node-object_id > lv_max_id.
      lv_max_id = ls_chk_node-object_id.
    ENDIF.
    IF ls_chk_node-parent_id = lv_target_folder AND ls_chk_node-sort_order > lv_max_sort.
      lv_max_sort = ls_chk_node-sort_order.
    ENDIF.
  ENDLOOP.

  " Read currently assigned TCodes in AGR_TCODES to detect duplicates
  SELECT tcode FROM agr_tcodes
    WHERE agr_name = @pv_role AND type = 'TR'
    INTO TABLE @DATA(lt_curr_tcds).

  " 4. Add transactions under the chosen target folder
  LOOP AT ct_tcodes INTO lv_tcode.
    " Verify TCode exists in TSTC
    CLEAR lv_chk_tc.
    SELECT SINGLE tcode FROM tstc INTO @lv_chk_tc WHERE tcode = @lv_tcode.
    IF sy-subrc <> 0.
      cv_failed = cv_failed + 1.
      cv_failed_txt = |{ cv_failed_txt } { lv_tcode }|.
      INSERT lv_tcode INTO TABLE lt_invalid_tc.
      CONTINUE.
    ENDIF.

    " Skip if already in role menu (AGR_TCODES) without counting as newly added
    READ TABLE lt_curr_tcds WITH KEY tcode = lv_tcode TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      CONTINUE.
    ENDIF.

    " Also skip if already queued in lt_nodes in this run
    CLEAR lv_in_nodes.
    LOOP AT lt_nodes INTO DATA(ls_cur_nd).
      CLEAR ls_cur_stck.
      ls_cur_stck = ls_cur_nd-string1.
      IF ls_cur_stck-reporttype = 'TR' AND ls_cur_stck-report = lv_tcode.
        lv_in_nodes = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF lv_in_nodes = abap_true.
      CONTINUE.
    ENDIF.

    " Allocate new node ID and sort order
    lv_max_id   = lv_max_id + 1.
    lv_max_sort = lv_max_sort + 10.

    CLEAR: ls_new_node, ls_new_stck.
    ls_new_node-object_id  = lv_max_id.
    ls_new_node-parent_id  = lv_target_folder.
    ls_new_node-folder     = space.
    ls_new_node-menu_level = lv_target_level.
    ls_new_node-sort_order = lv_max_sort.
    ls_new_stck-reporttype = 'TR'.
    ls_new_stck-report     = lv_tcode.
    ls_new_node-string1    = ls_new_stck.
    APPEND ls_new_node TO lt_nodes.

    " Retrieve transaction descriptions from TSTCT (logon language + English)
    DATA: lv_ttext_en TYPE ssm_title.
    CLEAR: lv_ttext, lv_ttext_en.
    SELECT SINGLE ttext FROM tstct INTO @lv_ttext
      WHERE sprsl = @sy-langu AND tcode = @lv_tcode.
    SELECT SINGLE ttext FROM tstct INTO @lv_ttext_en
      WHERE sprsl = 'E' AND tcode = @lv_tcode.
    IF lv_ttext IS INITIAL.
      lv_ttext = COND #( WHEN lv_ttext_en IS NOT INITIAL THEN lv_ttext_en ELSE lv_tcode ).
    ENDIF.
    IF lv_ttext_en IS INITIAL.
      lv_ttext_en = lv_ttext.
    ENDIF.

    APPEND VALUE agr_shiert(
      object_id = lv_max_id
      spras     = sy-langu
      text      = lv_ttext
    ) TO lt_texts.

    IF sy-langu <> 'E'.
      APPEND VALUE agr_shiert(
        object_id = lv_max_id
        spras     = 'E'
        text      = lv_ttext_en
      ) TO lt_texts.
    ENDIF.

    cv_added = cv_added + 1.
    lv_nodes_changed = abap_true.
  ENDLOOP.

  " SU53-M2: Strip invalid TCodes (missing from TSTC) so they NEVER propagate to Derived S_TCODE
  LOOP AT lt_invalid_tc INTO DATA(lv_inv_tc).
    DELETE TABLE ct_tcodes WITH TABLE KEY table_line = lv_inv_tc.
  ENDLOOP.

  " 5. Save updated menu nodes if new transactions were added (lock already held -> enqueue = space)
  IF lv_nodes_changed = abap_true.
    CALL FUNCTION 'PRGN_STRU_SAVE_NODES'
      EXPORTING
        activity_group    = pv_role
        use_global_tables = space
        enqueue           = space
      IMPORTING
        error_flag        = lv_err_flag
      TABLES
        menu_hierarchy    = lt_nodes
        menu_texts        = lt_texts
        return            = lt_return
      EXCEPTIONS
        not_authorized          = 1
        activity_group_enqueued = 2
        OTHERS                  = 3.

    IF sy-subrc <> 0 OR lv_err_flag IS NOT INITIAL.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
        EXPORTING
          activity_group = pv_role.
      cv_abort = abap_true.
      IF sy-subrc = 2 OR lv_err_flag = 'L'.
        MESSAGE |Role { pv_role } is locked (Edit mode). Please exit Edit mode in PFCG first, then try again.| TYPE 'S' DISPLAY LIKE 'E'.
      ELSEIF sy-subrc = 1 OR lv_err_flag = 'A'.
        MESSAGE |Not authorized to maintain menu for role { pv_role }.| TYPE 'S' DISPLAY LIKE 'E'.
      ELSE.
        MESSAGE |Failed to update menu of role { pv_role } (error flag: { lv_err_flag }).| TYPE 'S' DISPLAY LIKE 'E'.
      ENDIF.
      RETURN.
    ENDIF.
  ENDIF.

  CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
    EXPORTING
      activity_group = pv_role.
ENDFORM.

FORM generate_role_profile USING pv_role           TYPE agr_name
                                 pv_rebuild        TYPE char01
                                 pv_all_maintained TYPE abap_bool
                                 pv_caller_locked  TYPE abap_bool
                           CHANGING cv_subrc TYPE sy-subrc.
  TYPES: BEGIN OF ty_var_objfld,
           object TYPE tobj-objct,
           field  TYPE xufield,
           varbl  TYPE usorg-varbl,
         END OF ty_var_objfld.
  DATA: lt_return       TYPE bapirettab,
        lt_orgs         TYPE tt_pt1252,
        lt_var_objflds  TYPE SORTED TABLE OF ty_var_objfld WITH NON-UNIQUE KEY varbl,
        lt_vars_dist    TYPE SORTED TABLE OF usorg-varbl WITH UNIQUE KEY table_line,
        lv_org_mod      TYPE abap_bool,
        lv_save_err     TYPE abap_bool,
        lv_star_auth_ok TYPE abap_bool VALUE abap_true.

  CLEAR: cv_subrc, lv_save_err.
  lv_star_auth_ok = abap_true.

  " C4: Restore $VARBL bindings in AGR_1251/1250 BEFORE reading/enqueueing orgs
  IF pv_caller_locked = abap_false.
    PERFORM restore_role_1251_org_bindings USING pv_role.
  ENDIF.

  IF pv_caller_locked = abap_false.
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
      EXPORTING
        activity_group = pv_role
        no_dialog      = 'X'
      EXCEPTIONS
        foreign_lock   = 1
        system_error   = 2
        OTHERS         = 3.
    IF sy-subrc <> 0.
      cv_subrc = sy-subrc.
      RETURN.
    ENDIF.
  ENDIF.

  " Check if this is a Master Role (has derived children), Standalone Role, or Derived Role (has parent)
  DATA: lv_parent TYPE agr_name,
        lv_child  TYPE agr_name.
  CLEAR: lv_parent, lv_child.
  SELECT SINGLE parent_agr FROM agr_define
    WHERE agr_name = @pv_role
    INTO @lv_parent.
  IF lv_parent IS INITIAL.
    SELECT SINGLE agr_name FROM agr_define
      WHERE parent_agr = @pv_role
      INTO @lv_child.
  ENDIF.

  " Handle Organizational Levels in AGR_1252 BEFORE compiling profile (prevents YELLOW LED):
  " - Master Role (with derived children): empty / missing $VARBL -> '-1'
  " - Derived Role (D3 + AUD-C3): verify S_USER_VAL '*' before defaulting unmaintained variables to '*'
  " - Standalone Role: add missing $VARBL row with space (never silently wildcard to '*')
  CLEAR: lt_orgs, lv_org_mod, lt_var_objflds, lt_vars_dist.
  CALL FUNCTION 'PRGN_1252_READ_ORG_LEVELS'
    EXPORTING
      activity_group    = pv_role
    TABLES
      org_levels        = lt_orgs
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.
  IF sy-subrc = 2.
    IF pv_caller_locked = abap_false.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
        EXPORTING
          activity_group = pv_role.
    ENDIF.
    cv_subrc = 4.
    RETURN.
  ENDIF.

  SELECT DISTINCT f~object, f~field, u~varbl, f~low, f~high, f~modified
    FROM agr_1251 AS f
    INNER JOIN agr_1250 AS a
      ON a~agr_name = f~agr_name
     AND a~object   = f~object
     AND a~auth     = f~auth
    INNER JOIN usorg AS u
      ON u~field = f~field
    WHERE f~agr_name = @pv_role
      AND f~deleted  = @space AND f~copied <> 'I'
      AND a~deleted  = @space AND a~copied <> 'I'
    INTO TABLE @DATA(lt_raw_org_refs).

  LOOP AT lt_raw_org_refs INTO DATA(ls_ror).
    IF ( ls_ror-modified = 'G' OR ls_ror-modified = 'M' OR ls_ror-modified = 'U' )
       AND ( ( ls_ror-low IS NOT INITIAL AND ls_ror-low <> '-1'
               AND ls_ror-low <> '$' AND ls_ror-low <> ls_ror-varbl )
             OR ls_ror-high IS NOT INITIAL ).
      CONTINUE.
    ENDIF.
    INSERT VALUE ty_var_objfld(
      object = ls_ror-object
      field  = ls_ror-field
      varbl  = ls_ror-varbl ) INTO TABLE lt_var_objflds.
    IF ls_ror-low = ls_ror-varbl AND ls_ror-high IS INITIAL.
      INSERT ls_ror-varbl INTO TABLE lt_vars_dist.
    ENDIF.
  ENDLOOP.

  LOOP AT lt_vars_dist INTO DATA(lv_v_gen).
    READ TABLE lt_orgs WITH KEY varbl = lv_v_gen TRANSPORTING NO FIELDS.
    IF sy-subrc <> 0.
      IF lv_parent IS NOT INITIAL.
        DATA(lv_v_star_ok) = abap_true.
        DATA(lv_v_checked) = abap_false.
        LOOP AT lt_var_objflds INTO DATA(ls_vof) WHERE varbl = lv_v_gen.
          lv_v_checked = abap_true.
          AUTHORITY-CHECK OBJECT 'S_USER_VAL'
            ID 'OBJECT'     FIELD ls_vof-object
            ID 'AUTH_FIELD' FIELD ls_vof-field
            ID 'AUTH_VALUE' FIELD '*'.
          IF sy-subrc <> 0.
            lv_v_star_ok = abap_false.
            EXIT.
          ENDIF.
        ENDLOOP.
        IF lv_v_checked = abap_false.
          SELECT field FROM usorg WHERE varbl = @lv_v_gen INTO TABLE @DATA(lt_vg_fb).
          IF sy-subrc = 0 AND lt_vg_fb IS NOT INITIAL.
            LOOP AT lt_vg_fb INTO DATA(lv_vg_fb).
              AUTHORITY-CHECK OBJECT 'S_USER_VAL'
                ID 'OBJECT'     FIELD '*'
                ID 'AUTH_FIELD' FIELD lv_vg_fb
                ID 'AUTH_VALUE' FIELD '*'.
              IF sy-subrc <> 0.
                lv_v_star_ok = abap_false.
                EXIT.
              ENDIF.
            ENDLOOP.
          ELSE.
            lv_v_star_ok = abap_false.
          ENDIF.
        ENDIF.
        IF lv_v_star_ok = abap_true.
          APPEND VALUE pt1252( varbl = lv_v_gen low = '*' high = space ) TO lt_orgs.
        ELSE.
          lv_star_auth_ok = abap_false.
          APPEND VALUE pt1252( varbl = lv_v_gen low = space high = space ) TO lt_orgs.
        ENDIF.
      ELSEIF lv_child IS NOT INITIAL.
        APPEND VALUE pt1252( varbl = lv_v_gen low = '-1' high = space ) TO lt_orgs.
      ELSE.
        APPEND VALUE pt1252( varbl = lv_v_gen low = space high = space ) TO lt_orgs.
      ENDIF.
      lv_org_mod = abap_true.
    ENDIF.
  ENDLOOP.

  IF lv_parent IS INITIAL AND lv_child IS NOT INITIAL.
    LOOP AT lt_orgs ASSIGNING FIELD-SYMBOL(<ls_org>).
      IF ( <ls_org>-low IS INITIAL OR <ls_org>-low = space ) AND <ls_org>-high IS INITIAL.
        <ls_org>-low = '-1'.
        lv_org_mod   = abap_true.
      ENDIF.
    ENDLOOP.
  ELSEIF lv_parent IS NOT INITIAL.
    DATA lt_dist_v TYPE SORTED TABLE OF agr_1252-varbl WITH UNIQUE KEY table_line.
    CLEAR lt_dist_v.
    LOOP AT lt_orgs INTO DATA(ls_ov).
      INSERT ls_ov-varbl INTO TABLE lt_dist_v.
    ENDLOOP.
    LOOP AT lt_dist_v INTO DATA(lv_dv).
      DATA(lv_has_maint_v) = abap_false.
      DATA(lv_has_blank_v) = abap_false.
      LOOP AT lt_orgs INTO DATA(ls_oc) WHERE varbl = lv_dv.
        IF ( ls_oc-low IS NOT INITIAL AND ls_oc-low <> '-1' AND ls_oc-low <> '$' )
           OR ls_oc-high IS NOT INITIAL.
          lv_has_maint_v = abap_true.
        ELSE.
          lv_has_blank_v = abap_true.
        ENDIF.
      ENDLOOP.
      IF lv_has_maint_v = abap_true AND lv_has_blank_v = abap_true.
        " Remove stray empty/'-1'/'$' rows without widening restricted maintained values to '*'
        DELETE lt_orgs WHERE varbl = lv_dv
                         AND ( low IS INITIAL OR low = '-1' OR low = '$' )
                         AND high IS INITIAL.
        lv_org_mod = abap_true.
      ELSEIF lv_has_maint_v = abap_false.
        DATA(lv_dv_star_ok) = abap_true.
        DATA(lv_dv_checked) = abap_false.
        LOOP AT lt_var_objflds INTO ls_vof WHERE varbl = lv_dv.
          lv_dv_checked = abap_true.
          AUTHORITY-CHECK OBJECT 'S_USER_VAL'
            ID 'OBJECT'     FIELD ls_vof-object
            ID 'AUTH_FIELD' FIELD ls_vof-field
            ID 'AUTH_VALUE' FIELD '*'.
          IF sy-subrc <> 0.
            lv_dv_star_ok = abap_false.
            EXIT.
          ENDIF.
        ENDLOOP.
        IF lv_dv_checked = abap_false.
          SELECT field FROM usorg WHERE varbl = @lv_dv INTO TABLE @DATA(lt_uof_fb).
          IF sy-subrc = 0 AND lt_uof_fb IS NOT INITIAL.
            LOOP AT lt_uof_fb INTO DATA(lv_uof_fb).
              AUTHORITY-CHECK OBJECT 'S_USER_VAL'
                ID 'OBJECT'     FIELD '*'
                ID 'AUTH_FIELD' FIELD lv_uof_fb
                ID 'AUTH_VALUE' FIELD '*'.
              IF sy-subrc <> 0.
                lv_dv_star_ok = abap_false.
                EXIT.
              ENDIF.
            ENDLOOP.
          ELSE.
            lv_dv_star_ok = abap_false.
          ENDIF.
        ENDIF.
        IF lv_dv_star_ok = abap_true.
          DELETE lt_orgs WHERE varbl = lv_dv.
          APPEND VALUE pt1252( varbl = lv_dv low = '*' high = space ) TO lt_orgs.
          lv_org_mod = abap_true.
        ELSE.
          lv_star_auth_ok = abap_false.
          DELETE lt_orgs WHERE varbl = lv_dv.
          APPEND VALUE pt1252( varbl = lv_dv low = space high = space ) TO lt_orgs.
          lv_org_mod = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDIF.

  IF lv_org_mod = abap_true.
    CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
    CALL FUNCTION 'PRGN_1252_SAVE_ORG_LEVELS'
      EXPORTING
        activity_group = pv_role
      TABLES
        org_levels     = lt_orgs
      EXCEPTIONS
        OTHERS         = 1.
    IF sy-subrc <> 0.
      lv_save_err = abap_true.
    ENDIF.

    IF lv_save_err = abap_false.
      CALL FUNCTION 'PRGN_UPDATE_DATABASE'
        EXCEPTIONS
          OTHERS = 1.
      IF sy-subrc <> 0.
        lv_save_err = abap_true.
      ENDIF.
    ENDIF.

    IF lv_save_err = abap_true.
      ROLLBACK WORK.
      CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
      IF pv_caller_locked = abap_false.
        CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
          EXPORTING
            activity_group = pv_role.
      ENDIF.
      cv_subrc = 4.
      RETURN.
    ENDIF.

    CALL FUNCTION 'PRGN_SET_ACTGROUP_TIMESTAMP'
      EXPORTING
        activity_group = pv_role
        no_commit      = 'X'
      EXCEPTIONS
        OTHERS         = 0.
    COMMIT WORK AND WAIT.
  ENDIF.

  " Release lock BEFORE profile generation (which manages its own lock lifecycle)
  IF pv_caller_locked = abap_false.
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
      EXPORTING
        activity_group = pv_role.
  ENDIF.

  " D3 + AUD-C3: Allow '*' for unmaintained Org Levels on Derived Roles only when S_USER_VAL '*' passed
  DATA(lv_fill_org_star) = COND char01(
    WHEN lv_parent IS NOT INITIAL AND lv_star_auth_ok = abap_true THEN 'X' ELSE ' ' ).

  CALL FUNCTION 'SUPRN_DARK_MANIPULATE_PROFILE'
    EXPORTING
      activity_group        = pv_role
      fill_orgs_with_star   = lv_fill_org_star
      fill_fields_with_star = space
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

  IF cv_subrc = 0.
    LOOP AT lt_return INTO DATA(ls_gen_ret) WHERE type CA 'EA'.
      cv_subrc = 4.
      EXIT.
    ENDLOOP.
  ENDIF.

  " Fallback: if SUPRN_DARK fails, try standard generation without wildcarding non-org fields
  IF cv_subrc <> 0.
    CLEAR lt_return.
    CALL FUNCTION 'PRGN_AUTO_GENERATE_PROFILE_NEW'
      EXPORTING
        activity_group              = pv_role
        no_dialog                   = 'X'
        rebuild_auth_data           = pv_rebuild
        org_levels_with_star        = lv_fill_org_star
        fill_empty_fields_with_star = space
        generate_profile            = 'X'
      TABLES
        return                      = lt_return
      EXCEPTIONS
        OTHERS                      = 1.
    cv_subrc = sy-subrc.
    IF cv_subrc = 0.
      LOOP AT lt_return INTO ls_gen_ret WHERE type CA 'EA'.
        cv_subrc = 4.
        EXIT.
      ENDLOOP.
    ENDIF.
  ENDIF.

  IF cv_subrc = 0.
    COMMIT WORK AND WAIT.
  ELSE.
    ROLLBACK WORK.
    CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
  ENDIF.
ENDFORM.

FORM match_auth_pattern USING    pv_pattern TYPE xuval
                                 pv_value   TYPE xuval
                        CHANGING cv_match   TYPE abap_bool.
  DATA: lv_pat TYPE string,
        lv_val TYPE string.

  cv_match = abap_false.
  lv_pat   = pv_pattern.
  lv_val   = pv_value.

  REPLACE ALL OCCURRENCES OF '\' IN lv_pat WITH '\\'.
  REPLACE ALL OCCURRENCES OF '.' IN lv_pat WITH '\.'.
  REPLACE ALL OCCURRENCES OF '^' IN lv_pat WITH '\^'.
  REPLACE ALL OCCURRENCES OF '$' IN lv_pat WITH '\$'.
  REPLACE ALL OCCURRENCES OF '[' IN lv_pat WITH '\['.
  REPLACE ALL OCCURRENCES OF ']' IN lv_pat WITH '\]'.
  REPLACE ALL OCCURRENCES OF '(' IN lv_pat WITH '\('.
  REPLACE ALL OCCURRENCES OF ')' IN lv_pat WITH '\)'.
  REPLACE ALL OCCURRENCES OF '{' IN lv_pat WITH '\{'.
  REPLACE ALL OCCURRENCES OF '}' IN lv_pat WITH '\}'.
  REPLACE ALL OCCURRENCES OF '?' IN lv_pat WITH '\?'.
  REPLACE ALL OCCURRENCES OF '|' IN lv_pat WITH '\|'.
  REPLACE ALL OCCURRENCES OF '+' IN lv_pat WITH '.'.
  REPLACE ALL OCCURRENCES OF '*' IN lv_pat WITH '.*'.
  lv_pat = '\A' && lv_pat && '\z'.

  TRY.
      FIND PCRE lv_pat IN lv_val RESPECTING CASE.
      IF sy-subrc = 0.
        cv_match = abap_true.
      ENDIF.
    CATCH cx_sy_regex.
      cv_match = abap_false.
  ENDTRY.
ENDFORM.

FORM field_value_covered USING pt_flds   TYPE tt_role_fld
                               pt_orgs   TYPE tt_pt1252
                               pt_usorg  TYPE tt_usorg
                               pv_object TYPE tobj-objct
                               pv_auth   TYPE xuauth
                               pv_field  TYPE xufield
                               pv_value  TYPE xuval
                         CHANGING cv_covered TYPE abap_bool.
  DATA lv_pat_match TYPE abap_bool.

  cv_covered = abap_false.

  IF pv_field IS INITIAL.
    cv_covered = abap_true.
    RETURN.
  ENDIF.

  LOOP AT pt_flds INTO DATA(ls_fld)
    WHERE object = pv_object
      AND auth   = pv_auth
      AND field  = pv_field.
    " Skip unmaintained empty/'-1'/'$' placeholder rows (never cover real values or blanks)
    IF ls_fld-high IS INITIAL
       AND ( ls_fld-low IS INITIAL OR ls_fld-low = '-1' OR ls_fld-low = '$' ).
      CONTINUE.
    ENDIF.

    " Resolve $VARBL Org Level placeholders ONLY when (field, low) is a genuine USORG variable
    " and active Standard ('S') binding (never treat literal '$TMP' in DEVCLASS as $VARBL)
    READ TABLE pt_usorg INTO DATA(ls_uo_cov) WITH TABLE KEY field = pv_field.
    IF sy-subrc = 0 AND ls_uo_cov-varbl IS NOT INITIAL
       AND ls_fld-low = ls_uo_cov-varbl AND ls_fld-high IS INITIAL
       AND ( ls_fld-modified = 'S' OR ls_fld-modified IS INITIAL ).
      LOOP AT pt_orgs INTO DATA(ls_org) WHERE varbl = ls_fld-low.
        IF ( ls_org-low IS INITIAL OR ls_org-low = '-1' OR ls_org-low = '$' )
           AND ls_org-high IS INITIAL.
          CONTINUE.
        ENDIF.
        IF ls_org-low = '*'.
          cv_covered = abap_true.
          RETURN.
        ENDIF.
        IF pv_value IS INITIAL.
          IF ls_org-low = gc_blank_val AND ls_org-high IS INITIAL.
            cv_covered = abap_true.
            RETURN.
          ENDIF.
          IF ls_org-high IS NOT INITIAL
             AND ( ls_org-low IS INITIAL OR ls_org-low = gc_blank_val ).
            cv_covered = abap_true.
            RETURN.
          ENDIF.
          CONTINUE.
        ENDIF.
        IF ls_org-low = pv_value.
          cv_covered = abap_true.
          RETURN.
        ENDIF.
        IF ls_org-low CA '*+'.
          PERFORM match_auth_pattern USING ls_org-low pv_value CHANGING lv_pat_match.
          IF lv_pat_match = abap_true.
            cv_covered = abap_true.
            RETURN.
          ENDIF.
        ENDIF.
        IF ls_org-high IS NOT INITIAL
           AND ls_org-low <> '*'
           AND ls_org-low <> '-1'
           AND ls_org-low <> '$'.
          IF ( ls_org-low IS INITIAL OR ls_org-low = gc_blank_val )
             AND pv_value <= ls_org-high.
            cv_covered = abap_true.
            RETURN.
          ELSEIF ls_org-low IS NOT INITIAL
             AND ls_org-low <> gc_blank_val
             AND pv_value >= ls_org-low
             AND pv_value <= ls_org-high.
            cv_covered = abap_true.
            RETURN.
          ENDIF.
        ENDIF.
      ENDLOOP.
      CONTINUE.
    ENDIF.

    IF ls_fld-low = '*'.
      cv_covered = abap_true.
      RETURN.
    ENDIF.
    IF pv_value IS INITIAL.
      IF ls_fld-low = gc_blank_val AND ls_fld-high IS INITIAL.
        cv_covered = abap_true.
        RETURN.
      ENDIF.
      IF ls_fld-high IS NOT INITIAL
         AND ( ls_fld-low IS INITIAL OR ls_fld-low = gc_blank_val ).
        cv_covered = abap_true.
        RETURN.
      ENDIF.
      CONTINUE.
    ENDIF.
    IF ls_fld-low = pv_value.
      cv_covered = abap_true.
      RETURN.
    ENDIF.
    IF ls_fld-low CA '*+'.
      PERFORM match_auth_pattern USING ls_fld-low pv_value CHANGING lv_pat_match.
      IF lv_pat_match = abap_true.
        cv_covered = abap_true.
        RETURN.
      ENDIF.
    ENDIF.
    IF ls_fld-high IS NOT INITIAL
       AND ls_fld-low <> '*'
       AND ls_fld-low <> '-1'
       AND ls_fld-low <> '$'.
      IF ( ls_fld-low IS INITIAL OR ls_fld-low = gc_blank_val )
         AND pv_value <= ls_fld-high.
        cv_covered = abap_true.
        RETURN.
      ELSEIF ls_fld-low IS NOT INITIAL
         AND ls_fld-low <> gc_blank_val
         AND pv_value >= ls_fld-low
         AND pv_value <= ls_fld-high.
        cv_covered = abap_true.
        RETURN.
      ENDIF.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form find_child_auth_for_master
*&---------------------------------------------------------------------*
* Content-aware Master -> Child AUTH matcher across all TOBJ fields
* (both Org Levels and non-Org fields) to prevent collapsing unrelated
* multi-instance objects or clobbering decoupled org overrides.
*&---------------------------------------------------------------------*
FORM find_child_auth_for_master USING    pv_obj        TYPE tobj-objct
                                         ps_lead_ad    TYPE pt1250
                                         pt_lead_1251  TYPE tt_pt1251
                                         pt_child_1250 TYPE tt_pt1250
                                         pt_child_1251 TYPE tt_pt1251
                                         pt_used_auths TYPE tt_xuauth
                                         pt_usorg      TYPE tt_usorg
                                CHANGING cv_child_auth TYPE xuauth.
  TYPES: BEGIN OF ty_lh_pair,
           low  TYPE xuval,
           high TYPE xuval,
         END OF ty_lh_pair.
  DATA: lt_all_fnames  TYPE SORTED TABLE OF xufield WITH UNIQUE KEY table_line,
        lt_m_vals      TYPE SORTED TABLE OF ty_lh_pair WITH UNIQUE KEY low high,
        lt_c_vals      TYPE SORTED TABLE OF ty_lh_pair WITH UNIQUE KEY low high,
        ls_tobj_fc     TYPE tobj,
        lv_same_auth   TYPE xuauth,
        lv_exact_auth  TYPE xuauth,
        lv_merge_auth  TYPE xuauth,
        lv_extra_flds  TYPE i,
        lv_empty_flds  TYPE i,
        lv_diff_peers  TYPE i,
        lv_all_cov     TYPE abap_bool,
        lv_org_conf    TYPE abap_bool,
        lv_m_org_dec   TYPE abap_bool,
        lv_c_org_dec   TYPE abap_bool.

  CLEAR: cv_child_auth, lt_all_fnames, ls_tobj_fc, lv_same_auth, lv_exact_auth, lv_merge_auth.

  " Gather complete TOBJ field schema plus any active fields present on Master or Child
  SELECT SINGLE fiel1, fiel2, fiel3, fiel4, fiel5, fiel6, fiel7, fiel8, fiel9, fiel0
    FROM tobj WHERE objct = @pv_obj
    INTO CORRESPONDING FIELDS OF @ls_tobj_fc.
  IF sy-subrc = 0.
    IF ls_tobj_fc-fiel1 IS NOT INITIAL. INSERT ls_tobj_fc-fiel1 INTO TABLE lt_all_fnames. ENDIF.
    IF ls_tobj_fc-fiel2 IS NOT INITIAL. INSERT ls_tobj_fc-fiel2 INTO TABLE lt_all_fnames. ENDIF.
    IF ls_tobj_fc-fiel3 IS NOT INITIAL. INSERT ls_tobj_fc-fiel3 INTO TABLE lt_all_fnames. ENDIF.
    IF ls_tobj_fc-fiel4 IS NOT INITIAL. INSERT ls_tobj_fc-fiel4 INTO TABLE lt_all_fnames. ENDIF.
    IF ls_tobj_fc-fiel5 IS NOT INITIAL. INSERT ls_tobj_fc-fiel5 INTO TABLE lt_all_fnames. ENDIF.
    IF ls_tobj_fc-fiel6 IS NOT INITIAL. INSERT ls_tobj_fc-fiel6 INTO TABLE lt_all_fnames. ENDIF.
    IF ls_tobj_fc-fiel7 IS NOT INITIAL. INSERT ls_tobj_fc-fiel7 INTO TABLE lt_all_fnames. ENDIF.
    IF ls_tobj_fc-fiel8 IS NOT INITIAL. INSERT ls_tobj_fc-fiel8 INTO TABLE lt_all_fnames. ENDIF.
    IF ls_tobj_fc-fiel9 IS NOT INITIAL. INSERT ls_tobj_fc-fiel9 INTO TABLE lt_all_fnames. ENDIF.
    IF ls_tobj_fc-fiel0 IS NOT INITIAL. INSERT ls_tobj_fc-fiel0 INTO TABLE lt_all_fnames. ENDIF.
  ENDIF.

  LOOP AT pt_lead_1251 INTO DATA(ls_lf)
    WHERE object = pv_obj AND auth = ps_lead_ad-auth
      AND deleted = space AND copied <> 'I'.
    IF ls_lf-field IS NOT INITIAL.
      INSERT ls_lf-field INTO TABLE lt_all_fnames.
    ENDIF.
  ENDLOOP.
  LOOP AT pt_child_1251 INTO DATA(ls_cf_all)
    WHERE object = pv_obj AND deleted = space AND copied <> 'I'.
    IF ls_cf_all-field IS NOT INITIAL.
      INSERT ls_cf_all-field INTO TABLE lt_all_fnames.
    ENDIF.
  ENDLOOP.

  LOOP AT pt_child_1250 INTO DATA(ls_cad)
    WHERE object = pv_obj AND deleted = space AND copied <> 'I'.
    IF line_exists( pt_used_auths[ table_line = ls_cad-auth ] ).
      CONTINUE.
    ENDIF.

    CLEAR: lv_extra_flds, lv_empty_flds, lv_diff_peers, lv_org_conf.
    lv_all_cov = abap_true.

    LOOP AT lt_all_fnames INTO DATA(lv_fn).
      CLEAR: lt_m_vals, lt_c_vals, lv_m_org_dec, lv_c_org_dec.

      READ TABLE pt_usorg INTO DATA(ls_uo_fc) WITH TABLE KEY field = lv_fn.
      DATA(lv_is_org_f) = xsdbool( sy-subrc = 0 AND ls_uo_fc-varbl IS NOT INITIAL ).

      IF lv_is_org_f = abap_true.
        LOOP AT pt_lead_1251 INTO ls_lf
          WHERE object = pv_obj AND auth = ps_lead_ad-auth
            AND field = lv_fn AND deleted = space AND copied <> 'I'.
          IF ( ls_lf-modified = 'G' OR ls_lf-modified = 'M' OR ls_lf-modified = 'U' )
             AND ( ( ls_lf-low IS NOT INITIAL AND ls_lf-low <> '-1'
                     AND ls_lf-low <> '$' AND ls_lf-low <> ls_uo_fc-varbl )
                   OR ls_lf-high IS NOT INITIAL ).
            lv_m_org_dec = abap_true.
            INSERT VALUE ty_lh_pair( low = ls_lf-low high = ls_lf-high ) INTO TABLE lt_m_vals.
          ENDIF.
        ENDLOOP.

        LOOP AT pt_child_1251 INTO DATA(ls_cf)
          WHERE object = pv_obj AND auth = ls_cad-auth
            AND field = lv_fn AND deleted = space AND copied <> 'I'.
          IF ( ls_cf-modified = 'G' OR ls_cf-modified = 'M' OR ls_cf-modified = 'U' )
             AND ( ( ls_cf-low IS NOT INITIAL AND ls_cf-low <> '-1'
                     AND ls_cf-low <> '$' AND ls_cf-low <> ls_uo_fc-varbl )
                   OR ls_cf-high IS NOT INITIAL ).
            lv_c_org_dec = abap_true.
            INSERT VALUE ty_lh_pair( low = ls_cf-low high = ls_cf-high ) INTO TABLE lt_c_vals.
          ENDIF.
        ENDLOOP.

        IF lv_m_org_dec <> lv_c_org_dec
           OR ( lv_m_org_dec = abap_true AND lt_m_vals <> lt_c_vals ).
          lv_org_conf = abap_true.
          EXIT.
        ENDIF.
        CONTINUE.
      ENDIF.

      LOOP AT pt_lead_1251 INTO ls_lf
        WHERE object = pv_obj AND auth = ps_lead_ad-auth
          AND field = lv_fn AND deleted = space AND copied <> 'I'.
        IF ls_lf-high IS INITIAL
           AND ( ls_lf-low IS INITIAL OR ls_lf-low = '-1' OR ls_lf-low = '$' ).
          CONTINUE.
        ENDIF.
        INSERT VALUE ty_lh_pair( low = ls_lf-low high = ls_lf-high ) INTO TABLE lt_m_vals.
      ENDLOOP.

      LOOP AT pt_child_1251 INTO ls_cf
        WHERE object = pv_obj AND auth = ls_cad-auth
          AND field = lv_fn AND deleted = space AND copied <> 'I'.
        IF ls_cf-high IS INITIAL
           AND ( ls_cf-low IS INITIAL OR ls_cf-low = '-1' OR ls_cf-low = '$' ).
          CONTINUE.
        ENDIF.
        INSERT VALUE ty_lh_pair( low = ls_cf-low high = ls_cf-high ) INTO TABLE lt_c_vals.
      ENDLOOP.

      IF lt_m_vals IS INITIAL AND lt_c_vals IS INITIAL.
        CONTINUE.
      ELSEIF lt_m_vals IS INITIAL AND lt_c_vals IS NOT INITIAL.
        lv_all_cov    = abap_false.
        lv_diff_peers = lv_diff_peers + 1.
        CONTINUE.
      ELSEIF lt_c_vals IS INITIAL.
        lv_all_cov    = abap_false.
        lv_empty_flds = lv_empty_flds + 1.
        CONTINUE.
      ENDIF.

      DATA(lv_has_m_extra) = abap_false.
      LOOP AT lt_m_vals INTO DATA(ls_mv).
        IF NOT line_exists( lt_c_vals[ low = ls_mv-low high = ls_mv-high ] ).
          lv_has_m_extra = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.

      DATA(lv_has_c_extra) = abap_false.
      LOOP AT lt_c_vals INTO DATA(ls_cv).
        IF NOT line_exists( lt_m_vals[ low = ls_cv-low high = ls_cv-high ] ).
          lv_has_c_extra = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.

      IF lv_has_m_extra = abap_true.
        lv_all_cov    = abap_false.
        lv_extra_flds = lv_extra_flds + 1.
      ENDIF.
      IF lv_has_c_extra = abap_true.
        lv_diff_peers = lv_diff_peers + 1.
      ENDIF.
    ENDLOOP.

    IF lv_org_conf = abap_true.
      CONTINUE.
    ENDIF.

    DATA(lv_is_safe_merge) = xsdbool(
      ( lv_extra_flds = 0 AND lv_diff_peers = 0 AND lv_empty_flds > 0 )
      OR ( lv_extra_flds = 1 AND lv_empty_flds = 0 AND lv_diff_peers = 0 ) ).

    IF ls_cad-auth = ps_lead_ad-auth AND ( lv_all_cov = abap_true OR lv_is_safe_merge = abap_true ).
      lv_same_auth = ls_cad-auth.
      EXIT.
    ELSEIF lv_all_cov = abap_true AND lv_exact_auth IS INITIAL.
      lv_exact_auth = ls_cad-auth.
    ELSEIF lv_is_safe_merge = abap_true AND lv_merge_auth IS INITIAL.
      lv_merge_auth = ls_cad-auth.
    ENDIF.
  ENDLOOP.

  IF lv_same_auth IS NOT INITIAL.
    cv_child_auth = lv_same_auth.
  ELSEIF lv_exact_auth IS NOT INITIAL.
    cv_child_auth = lv_exact_auth.
  ELSEIF lv_merge_auth IS NOT INITIAL.
    cv_child_auth = lv_merge_auth.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form derive_specific_objects
*&---------------------------------------------------------------------*
*& Purpose: Selectively propagate ONLY the newly added object(s) and
*&          T-Codes down to all derived child roles of the Leading Role.
*&          Strictly preserves all existing authorizations, org levels,
*&          and custom settings in each derived role without re-deriving
*&          or overwriting the rest of the role.
*&---------------------------------------------------------------------*
FORM derive_specific_objects
  USING pv_leading_role TYPE agr_name
        pt_child_roles  TYPE tt_agr_name
        pt_sel_objects  TYPE tt_obj_name
        pt_menu_tcodes  TYPE tt_tcode
        pt_lead_1250    TYPE tt_pt1250
        pt_lead_1251    TYPE tt_pt1251
  CHANGING cv_der_count  TYPE i
           cv_gen_failed TYPE abap_bool.

  DATA: lt_child_1250        TYPE tt_pt1250,
        lt_child_1251        TYPE tt_pt1251,
        lt_child_1252        TYPE tt_pt1252,
        lt_lead_1252         TYPE tt_pt1252,
        lt_usorg             TYPE tt_usorg,
        lt_def_child_flds    TYPE STANDARD TABLE OF xufield,
        lt_used_child_auths  TYPE tt_xuauth,
        ls_child_tobj        TYPE tobj,
        lv_child_auth        TYPE xuauth,
        lv_tgt_hdr_mod       TYPE c LENGTH 1,
        lv_tgt_fld_mod       TYPE c LENGTH 1,
        lv_counter           TYPE i,
        lv_gen_subrc         TYPE sy-subrc,
        lv_child_org_changed TYPE abap_bool,
        lv_child_save_err    TYPE abap_bool,
        lv_found_c_act       TYPE abap_bool,
        lv_found_c_emp       TYPE abap_bool,
        lv_found_c_fld       TYPE abap_bool,
        lv_high_to_use       TYPE xuval.

  CLEAR cv_der_count.

  IF pt_child_roles IS INITIAL.
    RETURN.
  ENDIF.

  IF pt_sel_objects IS INITIAL AND pt_menu_tcodes IS INITIAL.
    RETURN.
  ENDIF.

  SELECT field, varbl FROM usorg INTO TABLE @lt_usorg.

  " Read Master Role's Org Levels from AGR_1252
  CALL FUNCTION 'PRGN_1252_READ_ORG_LEVELS'
    EXPORTING
      activity_group    = pv_leading_role
    TABLES
      org_levels        = lt_lead_1252
    EXCEPTIONS
      no_data_available = 1
      OTHERS            = 2.
  IF sy-subrc = 2.
    cv_gen_failed = abap_true.
    RETURN.
  ENDIF.

  LOOP AT pt_child_roles INTO DATA(lv_child_role).
    CLEAR: lt_child_1250, lt_child_1251, lt_child_1252, lv_counter,
           lv_child_org_changed, lv_child_save_err.

    " Authorization check per derived role before modifying
    AUTHORITY-CHECK OBJECT 'S_USER_AGR'
      ID 'ACT_GROUP' FIELD lv_child_role
      ID 'ACTVT'     FIELD '02'.
    IF sy-subrc <> 0.
      cv_gen_failed = abap_true.
      CONTINUE.
    ENDIF.

    " 1. Enqueue derived role (with no_dialog = 'X')
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_ENQUEUE'
      EXPORTING
        activity_group = lv_child_role
        no_dialog      = 'X'
      EXCEPTIONS
        foreign_lock   = 1
        system_error   = 2
        OTHERS         = 3.
    IF sy-subrc <> 0.
      cv_gen_failed = abap_true.
      CONTINUE.
    ENDIF.

    " 2. Read existing authorization data of derived role
    CALL FUNCTION 'PRGN_1250_READ_AUTH_DATA'
      EXPORTING
        activity_group    = lv_child_role
      TABLES
        auth_data         = lt_child_1250
      EXCEPTIONS
        no_data_available = 1
        OTHERS            = 2.
    IF sy-subrc = 2.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
        EXPORTING
          activity_group = lv_child_role.
      cv_gen_failed = abap_true.
      CONTINUE.
    ENDIF.

    CALL FUNCTION 'PRGN_1251_READ_FIELD_VALUES'
      EXPORTING
        activity_group    = lv_child_role
      TABLES
        field_values      = lt_child_1251
      EXCEPTIONS
        no_data_available = 1
        OTHERS            = 2.
    IF sy-subrc = 2.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
        EXPORTING
          activity_group = lv_child_role.
      cv_gen_failed = abap_true.
      CONTINUE.
    ENDIF.

    CALL FUNCTION 'PRGN_1252_READ_ORG_LEVELS'
      EXPORTING
        activity_group    = lv_child_role
      TABLES
        org_levels        = lt_child_1252
      EXCEPTIONS
        no_data_available = 1
        OTHERS            = 2.
    IF sy-subrc = 2.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
        EXPORTING
          activity_group = lv_child_role.
      cv_gen_failed = abap_true.
      CONTINUE.
    ENDIF.

    " -----------------------------------------------------------------
    " Sync Org Levels from Master Role to Derived Role (D3 + AUD-C3):
    " Preserve maintained values; delete stray empty/'-1' rows when
    " maintained values exist; verify S_USER_VAL '*' before defaulting to '*'
    " -----------------------------------------------------------------
    DATA(lv_child_auth_abort) = abap_false.
    LOOP AT lt_lead_1252 INTO DATA(ls_l_org).
      DATA(lv_ch_has_any)   = abap_false.
      DATA(lv_ch_has_maint) = abap_false.
      DATA(lv_ch_has_blank) = abap_false.
      LOOP AT lt_child_1252 INTO DATA(ls_co_chk) WHERE varbl = ls_l_org-varbl.
        lv_ch_has_any = abap_true.
        IF ( ls_co_chk-low IS NOT INITIAL AND ls_co_chk-low <> '-1' AND ls_co_chk-low <> '$' )
           OR ls_co_chk-high IS NOT INITIAL.
          lv_ch_has_maint = abap_true.
        ELSE.
          lv_ch_has_blank = abap_true.
        ENDIF.
      ENDLOOP.
      IF lv_ch_has_any = abap_false.
        DATA(lv_star_ok_sync) = abap_true.
        PERFORM check_varbl_star_auth USING ls_l_org-varbl
                                            pt_lead_1250
                                            pt_lead_1251
                                            lt_child_1250
                                            lt_child_1251
                                            lt_usorg
                                      CHANGING lv_star_ok_sync.
        IF lv_star_ok_sync = abap_false.
          lv_child_auth_abort = abap_true.
          EXIT.
        ENDIF.
        APPEND VALUE pt1252( varbl = ls_l_org-varbl low = '*' high = space ) TO lt_child_1252.
        lv_child_org_changed = abap_true.
      ELSEIF lv_ch_has_maint = abap_true AND lv_ch_has_blank = abap_true.
        DELETE lt_child_1252 WHERE varbl = ls_l_org-varbl
                               AND ( low IS INITIAL OR low = '-1' OR low = '$' )
                               AND high IS INITIAL.
        lv_child_org_changed = abap_true.
      ELSEIF lv_ch_has_maint = abap_false.
        lv_star_ok_sync = abap_true.
        PERFORM check_varbl_star_auth USING ls_l_org-varbl
                                            pt_lead_1250
                                            pt_lead_1251
                                            lt_child_1250
                                            lt_child_1251
                                            lt_usorg
                                      CHANGING lv_star_ok_sync.
        IF lv_star_ok_sync = abap_false.
          lv_child_auth_abort = abap_true.
          EXIT.
        ENDIF.
        DELETE lt_child_1252 WHERE varbl = ls_l_org-varbl.
        APPEND VALUE pt1252( varbl = ls_l_org-varbl low = '*' high = space ) TO lt_child_1252.
        lv_child_org_changed = abap_true.
      ENDIF.
    ENDLOOP.

    IF lv_child_auth_abort = abap_true.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
        EXPORTING
          activity_group = lv_child_role.
      cv_gen_failed = abap_true.
      CONTINUE.
    ENDIF.

    " 3. Selectively add ONLY the newly added authorization objects (Cartesian-safe + preserves 'U'/'M'/'G'/'S')
    DATA(lv_has_changes) = abap_false.

    LOOP AT pt_sel_objects INTO DATA(lv_new_obj).
      CLEAR lt_used_child_auths.

      " Load TOBJ field list once per object
      CLEAR: lt_def_child_flds, ls_child_tobj.
      SELECT SINGLE fiel1, fiel2, fiel3, fiel4, fiel5, fiel6, fiel7, fiel8, fiel9, fiel0
        FROM tobj WHERE objct = @lv_new_obj
        INTO CORRESPONDING FIELDS OF @ls_child_tobj.
      IF sy-subrc = 0.
        IF ls_child_tobj-fiel1 IS NOT INITIAL. APPEND ls_child_tobj-fiel1 TO lt_def_child_flds. ENDIF.
        IF ls_child_tobj-fiel2 IS NOT INITIAL. APPEND ls_child_tobj-fiel2 TO lt_def_child_flds. ENDIF.
        IF ls_child_tobj-fiel3 IS NOT INITIAL. APPEND ls_child_tobj-fiel3 TO lt_def_child_flds. ENDIF.
        IF ls_child_tobj-fiel4 IS NOT INITIAL. APPEND ls_child_tobj-fiel4 TO lt_def_child_flds. ENDIF.
        IF ls_child_tobj-fiel5 IS NOT INITIAL. APPEND ls_child_tobj-fiel5 TO lt_def_child_flds. ENDIF.
        IF ls_child_tobj-fiel6 IS NOT INITIAL. APPEND ls_child_tobj-fiel6 TO lt_def_child_flds. ENDIF.
        IF ls_child_tobj-fiel7 IS NOT INITIAL. APPEND ls_child_tobj-fiel7 TO lt_def_child_flds. ENDIF.
        IF ls_child_tobj-fiel8 IS NOT INITIAL. APPEND ls_child_tobj-fiel8 TO lt_def_child_flds. ENDIF.
        IF ls_child_tobj-fiel9 IS NOT INITIAL. APPEND ls_child_tobj-fiel9 TO lt_def_child_flds. ENDIF.
        IF ls_child_tobj-fiel0 IS NOT INITIAL. APPEND ls_child_tobj-fiel0 TO lt_def_child_flds. ENDIF.
      ENDIF.

      " Iterate over each active Master Role AUTH instance separately (C3: content-aware matching!)
      LOOP AT pt_lead_1250 INTO DATA(ls_lead_ad)
        WHERE object = lv_new_obj AND deleted = space AND copied <> 'I'.
        CLEAR: lv_child_auth, lv_tgt_hdr_mod.

        lv_tgt_hdr_mod = COND #( WHEN ls_lead_ad-modified IS NOT INITIAL
                                 THEN ls_lead_ad-modified ELSE 'S' ).

        PERFORM find_child_auth_for_master USING lv_new_obj
                                                 ls_lead_ad
                                                 pt_lead_1251
                                                 lt_child_1250
                                                 lt_child_1251
                                                 lt_used_child_auths
                                                 lt_usorg
                                           CHANGING lv_child_auth.

        IF lv_child_auth IS NOT INITIAL.
          " SU53-H3: Preserve TPR_ST_MOD status hierarchy ('U' > 'M' > 'G' > 'S') - NEVER downgrade 'U' to 'S'!
          LOOP AT lt_child_1250 ASSIGNING FIELD-SYMBOL(<ls_cad>)
            WHERE object = lv_new_obj AND auth = lv_child_auth
              AND deleted = space AND copied <> 'I'.
            IF <ls_cad>-modified = 'U' OR lv_tgt_hdr_mod = 'U'.
              lv_tgt_hdr_mod = 'U'.
            ELSEIF <ls_cad>-modified = 'M' OR lv_tgt_hdr_mod = 'M'.
              lv_tgt_hdr_mod = 'M'.
            ELSEIF <ls_cad>-modified = 'G' OR lv_tgt_hdr_mod = 'G'.
              lv_tgt_hdr_mod = 'G'.
            ELSE.
              lv_tgt_hdr_mod = 'S'.
            ENDIF.
            IF <ls_cad>-modified <> lv_tgt_hdr_mod.
              <ls_cad>-modified = lv_tgt_hdr_mod.
              lv_has_changes    = abap_true.
            ENDIF.
            EXIT.
          ENDLOOP.
        ELSE.
          " Allocate a distinct new active child node preserving Master's modified flag ('U'/'M'/'G'/'S')
          DATA(lv_new_slot) = abap_false.
          DO 999 TIMES.
            IF lv_counter < 100.
              lv_child_auth = |__________{ lv_counter WIDTH = 2 ALIGN = RIGHT PAD = '0' }|.
            ELSE.
              lv_child_auth = |________{ lv_counter WIDTH = 4 ALIGN = RIGHT PAD = '0' }|.
            ENDIF.
            READ TABLE lt_child_1250 TRANSPORTING NO FIELDS WITH KEY auth = lv_child_auth.
            lv_counter = lv_counter + 1.
            IF sy-subrc <> 0.
              lv_new_slot = abap_true.
              EXIT.
            ENDIF.
          ENDDO.
          IF lv_new_slot = abap_false.
            CONTINUE.
          ENDIF.
          APPEND VALUE pt1250(
            object   = lv_new_obj
            auth     = lv_child_auth
            variant  = ' '
            modified = lv_tgt_hdr_mod
            copied   = ' '
            neu      = 'O'
            deleted  = ' '
            atext    = ls_lead_ad-atext
          ) TO lt_child_1250.
          lv_has_changes = abap_true.
        ENDIF.

        INSERT lv_child_auth INTO TABLE lt_used_child_auths.

        " Copy active field values from THIS specific Master AUTH instance only
        LOOP AT pt_lead_1251 INTO DATA(ls_lead_fv)
          WHERE object = lv_new_obj AND auth = ls_lead_ad-auth
            AND deleted = ' ' AND copied <> 'I'.

          DATA: lv_val_to_use TYPE xuval.
          lv_val_to_use  = ls_lead_fv-low.
          lv_high_to_use = ls_lead_fv-high.
          lv_tgt_fld_mod = COND #(
            WHEN lv_tgt_hdr_mod = 'U' THEN 'U'
            WHEN ls_lead_fv-modified IS NOT INITIAL THEN ls_lead_fv-modified
            ELSE lv_tgt_hdr_mod ).

          READ TABLE lt_usorg INTO DATA(ls_uo) WITH TABLE KEY field = ls_lead_fv-field.
          DATA(lv_is_child_org) = xsdbool( sy-subrc = 0 AND ls_uo-varbl IS NOT INITIAL ).

          " AUD-H1: Skip unmaintained empty Master non-org row when Child already has active rows
          IF lv_is_child_org = abap_false
             AND ls_lead_fv-low IS INITIAL AND ls_lead_fv-high IS INITIAL.
            DATA(lv_ch_has_fld) = abap_false.
            LOOP AT lt_child_1251 TRANSPORTING NO FIELDS
              WHERE object = lv_new_obj AND auth = lv_child_auth
                AND field = ls_lead_fv-field AND deleted = space AND copied <> 'I'.
              lv_ch_has_fld = abap_true.
              EXIT.
            ENDLOOP.
            IF lv_ch_has_fld = abap_true.
              CONTINUE.
            ENDIF.
          ENDIF.

          IF lv_is_child_org = abap_true.
            " Preserve decoupled concrete 'G'/'M'/'U' org overrides from Master; only bind standard orgs to $VARBL
            DATA(lv_lead_decoupled) = xsdbool(
              ( ls_lead_fv-modified = 'G' OR ls_lead_fv-modified = 'M' OR ls_lead_fv-modified = 'U' )
              AND ( ( ls_lead_fv-low IS NOT INITIAL AND ls_lead_fv-low <> '-1'
                      AND ls_lead_fv-low <> '$' AND ls_lead_fv-low <> ls_uo-varbl )
                    OR ls_lead_fv-high IS NOT INITIAL ) ).

            IF lv_lead_decoupled = abap_false.
              " If child ALREADY has a decoupled concrete 'G'/'M'/'U' override on this field, preserve it
              DATA(lv_ch_decoupled) = abap_false.
              LOOP AT lt_child_1251 INTO DATA(ls_ch_o_chk)
                WHERE object = lv_new_obj AND auth = lv_child_auth
                  AND field = ls_lead_fv-field AND deleted = space AND copied <> 'I'.
                IF ( ls_ch_o_chk-modified = 'G' OR ls_ch_o_chk-modified = 'M' OR ls_ch_o_chk-modified = 'U' )
                   AND ( ( ls_ch_o_chk-low IS NOT INITIAL AND ls_ch_o_chk-low <> '-1'
                           AND ls_ch_o_chk-low <> '$' AND ls_ch_o_chk-low <> ls_uo-varbl )
                         OR ls_ch_o_chk-high IS NOT INITIAL ).
                  lv_ch_decoupled = abap_true.
                  EXIT.
                ENDIF.
              ENDLOOP.
              IF lv_ch_decoupled = abap_true.
                CONTINUE.
              ENDIF.

              " SAPLSUPRN requires MODIFIED = 'S' on $VARBL rows for AGR_1252 expansion
              lv_val_to_use  = ls_uo-varbl.
              lv_high_to_use = space.
              lv_tgt_fld_mod = 'S'.

              " Ensure Org Level exists in child AGR_1252 (D3 + AUD-C3: check S_USER_VAL '*' before '*')
              DATA(lv_co2_any)   = abap_false.
              DATA(lv_co2_maint) = abap_false.
              DATA(lv_co2_blank) = abap_false.
              LOOP AT lt_child_1252 INTO DATA(ls_co2_chk) WHERE varbl = ls_uo-varbl.
                lv_co2_any = abap_true.
                IF ( ls_co2_chk-low IS NOT INITIAL AND ls_co2_chk-low <> '-1' AND ls_co2_chk-low <> '$' )
                   OR ls_co2_chk-high IS NOT INITIAL.
                  lv_co2_maint = abap_true.
                ELSE.
                  lv_co2_blank = abap_true.
                ENDIF.
              ENDLOOP.
              IF lv_co2_any = abap_false.
                AUTHORITY-CHECK OBJECT 'S_USER_VAL'
                  ID 'OBJECT'     FIELD lv_new_obj
                  ID 'AUTH_FIELD' FIELD ls_lead_fv-field
                  ID 'AUTH_VALUE' FIELD '*'.
                IF sy-subrc <> 0.
                  lv_child_auth_abort = abap_true.
                  EXIT.
                ENDIF.
                lv_star_ok_sync = abap_true.
                PERFORM check_varbl_star_auth USING ls_uo-varbl
                                                    pt_lead_1250
                                                    pt_lead_1251
                                                    lt_child_1250
                                                    lt_child_1251
                                                    lt_usorg
                                              CHANGING lv_star_ok_sync.
                IF lv_star_ok_sync = abap_false.
                  lv_child_auth_abort = abap_true.
                  EXIT.
                ENDIF.
                APPEND VALUE pt1252( varbl = ls_uo-varbl low = '*' high = space ) TO lt_child_1252.
                lv_child_org_changed = abap_true.
              ELSEIF lv_co2_maint = abap_true AND lv_co2_blank = abap_true.
                DELETE lt_child_1252 WHERE varbl = ls_uo-varbl
                                       AND ( low IS INITIAL OR low = '-1' OR low = '$' )
                                       AND high IS INITIAL.
                lv_child_org_changed = abap_true.
              ELSEIF lv_co2_maint = abap_false.
                AUTHORITY-CHECK OBJECT 'S_USER_VAL'
                  ID 'OBJECT'     FIELD lv_new_obj
                  ID 'AUTH_FIELD' FIELD ls_lead_fv-field
                  ID 'AUTH_VALUE' FIELD '*'.
                IF sy-subrc <> 0.
                  lv_child_auth_abort = abap_true.
                  EXIT.
                ENDIF.
                lv_star_ok_sync = abap_true.
                PERFORM check_varbl_star_auth USING ls_uo-varbl
                                                    pt_lead_1250
                                                    pt_lead_1251
                                                    lt_child_1250
                                                    lt_child_1251
                                                    lt_usorg
                                              CHANGING lv_star_ok_sync.
                IF lv_star_ok_sync = abap_false.
                  lv_child_auth_abort = abap_true.
                  EXIT.
                ENDIF.
                DELETE lt_child_1252 WHERE varbl = ls_uo-varbl.
                APPEND VALUE pt1252( varbl = ls_uo-varbl low = '*' high = space ) TO lt_child_1252.
                lv_child_org_changed = abap_true.
              ENDIF.
            ENDIF.
          ENDIF.

          " SU53-H5: Match BOTH low AND high so existing LOW..HIGH ranges are NEVER truncated!
          CLEAR: lv_found_c_act, lv_found_c_emp.
          LOOP AT lt_child_1251 ASSIGNING FIELD-SYMBOL(<ls_cfv>)
            WHERE object = lv_new_obj AND auth = lv_child_auth
              AND field = ls_lead_fv-field AND low = lv_val_to_use AND high = lv_high_to_use
              AND deleted = space AND copied <> 'I'.
            IF <ls_cfv>-modified <> lv_tgt_fld_mod.
              <ls_cfv>-modified = lv_tgt_fld_mod.
              lv_has_changes    = abap_true.
            ENDIF.
            lv_found_c_act = abap_true.
            EXIT.
          ENDLOOP.
          IF lv_found_c_act = abap_false.
            LOOP AT lt_child_1251 ASSIGNING FIELD-SYMBOL(<ls_empty_cfv>)
              WHERE object = lv_new_obj AND auth = lv_child_auth
                AND field = ls_lead_fv-field AND low = space AND high = space
                AND deleted = space AND copied <> 'I'.
              <ls_empty_cfv>-low      = lv_val_to_use.
              <ls_empty_cfv>-high     = lv_high_to_use.
              <ls_empty_cfv>-modified = lv_tgt_fld_mod.
              <ls_empty_cfv>-neu      = 'O'.
              lv_found_c_emp = abap_true.
              lv_has_changes = abap_true.
              EXIT.
            ENDLOOP.
            IF lv_found_c_emp = abap_false.
              APPEND VALUE pt1251(
                object   = lv_new_obj
                auth     = lv_child_auth
                variant  = ' '
                field    = ls_lead_fv-field
                low      = lv_val_to_use
                high     = lv_high_to_use
                modified = lv_tgt_fld_mod
                neu      = 'O'
                deleted  = ' '
              ) TO lt_child_1251.
              lv_has_changes = abap_true.
            ENDIF.
          ENDIF.
        ENDLOOP.

        IF lv_child_auth_abort = abap_true.
          EXIT.
        ENDIF.

        " Bind ONLY missing or rebindable Org Level fields to $VARBL with MODIFIED = 'S';
        " preserve any active concrete 'G'/'M'/'U' overrides untouched.
        LOOP AT lt_def_child_flds INTO DATA(lv_cfld).
          READ TABLE lt_usorg INTO DATA(ls_uo_chk) WITH TABLE KEY field = lv_cfld.
          IF sy-subrc <> 0 OR ls_uo_chk-varbl IS INITIAL.
            CONTINUE.
          ENDIF.

          DATA(lv_cfld_dec) = abap_false.
          LOOP AT lt_child_1251 INTO DATA(ls_cfv_pre)
            WHERE object = lv_new_obj AND auth = lv_child_auth
              AND field = lv_cfld AND deleted = space AND copied <> 'I'.
            IF ( ls_cfv_pre-modified = 'G' OR ls_cfv_pre-modified = 'M' OR ls_cfv_pre-modified = 'U' )
               AND ( ( ls_cfv_pre-low IS NOT INITIAL AND ls_cfv_pre-low <> '-1'
                       AND ls_cfv_pre-low <> '$' AND ls_cfv_pre-low <> ls_uo_chk-varbl )
                     OR ls_cfv_pre-high IS NOT INITIAL ).
              lv_cfld_dec = abap_true.
              EXIT.
            ENDIF.
          ENDLOOP.
          IF lv_cfld_dec = abap_true.
            CONTINUE.
          ENDIF.

          CLEAR lv_found_c_fld.
          DATA(lv_idx_cf) = 0.
          LOOP AT lt_child_1251 ASSIGNING FIELD-SYMBOL(<ls_cfv_chk>).
            lv_idx_cf = sy-tabix.
            IF <ls_cfv_chk>-object <> lv_new_obj OR <ls_cfv_chk>-auth <> lv_child_auth
               OR <ls_cfv_chk>-field <> lv_cfld OR <ls_cfv_chk>-deleted <> space
               OR <ls_cfv_chk>-copied = 'I'.
              CONTINUE.
            ENDIF.
            IF lv_found_c_fld = abap_true.
              DELETE lt_child_1251 INDEX lv_idx_cf.
              lv_has_changes = abap_true.
              CONTINUE.
            ENDIF.
            lv_found_c_fld = abap_true.
            IF <ls_cfv_chk>-low <> ls_uo_chk-varbl OR <ls_cfv_chk>-high IS NOT INITIAL
               OR <ls_cfv_chk>-modified <> 'S'.
              <ls_cfv_chk>-low      = ls_uo_chk-varbl.
              <ls_cfv_chk>-high     = space.
              <ls_cfv_chk>-modified = 'S'.
              <ls_cfv_chk>-neu      = 'O'.
              lv_has_changes        = abap_true.
            ENDIF.
          ENDLOOP.

          IF lv_found_c_fld = abap_false.
            APPEND VALUE pt1251(
              object   = lv_new_obj
              auth     = lv_child_auth
              variant  = ' '
              field    = lv_cfld
              low      = ls_uo_chk-varbl
              high     = space
              modified = 'S'
              neu      = 'O'
              deleted  = ' '
            ) TO lt_child_1251.
            lv_has_changes = abap_true.
          ENDIF.
        ENDLOOP.
      ENDLOOP.

      IF lv_child_auth_abort = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    IF lv_child_auth_abort = abap_true.
      CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
        EXPORTING
          activity_group = lv_child_role.
      cv_gen_failed = abap_true.
      CONTINUE.
    ENDIF.

    " 4. AUD-H2: Check TCode coverage across ALL active child S_TCODE instances & preserve 'S' status
    IF pt_menu_tcodes IS NOT INITIAL.
      DATA: lv_child_tcd_auth TYPE xuauth,
            lv_child_tcd_mod  TYPE c LENGTH 1,
            lv_std_tcd_auth   TYPE xuauth,
            lv_oth_tcd_auth   TYPE xuauth,
            lv_oth_tcd_mod    TYPE c LENGTH 1,
            lv_tcd_found      TYPE abap_bool,
            lt_missing_tcds   TYPE tt_tcode,
            lt_tcd_auths      TYPE tt_xuauth,
            lt_tcd_flds       TYPE tt_role_fld,
            lt_empty_1252     TYPE tt_pt1252.
      CLEAR: lv_child_tcd_auth, lv_child_tcd_mod, lv_std_tcd_auth, lv_oth_tcd_auth,
             lv_oth_tcd_mod, lt_missing_tcds, lt_tcd_auths, lt_tcd_flds, lt_empty_1252.

      LOOP AT lt_child_1250 INTO DATA(ls_tcd_chk)
        WHERE object = 'S_TCODE' AND deleted = space AND copied <> 'I'.
        INSERT ls_tcd_chk-auth INTO TABLE lt_tcd_auths.
        IF ls_tcd_chk-modified = 'S' AND lv_std_tcd_auth IS INITIAL.
          lv_std_tcd_auth = ls_tcd_chk-auth.
        ELSEIF lv_oth_tcd_auth IS INITIAL.
          lv_oth_tcd_auth = ls_tcd_chk-auth.
          lv_oth_tcd_mod  = ls_tcd_chk-modified.
        ENDIF.
      ENDLOOP.

      IF lt_tcd_auths IS NOT INITIAL.
        LOOP AT lt_child_1251 INTO DATA(ls_tcd_f)
          WHERE object = 'S_TCODE' AND field = 'TCD'
            AND deleted = space AND copied <> 'I'.
          IF line_exists( lt_tcd_auths[ table_line = ls_tcd_f-auth ] ).
            APPEND VALUE ty_role_fld(
              object   = ls_tcd_f-object
              auth     = ls_tcd_f-auth
              field    = ls_tcd_f-field
              low      = ls_tcd_f-low
              high     = ls_tcd_f-high
              modified = ls_tcd_f-modified ) TO lt_tcd_flds.
          ENDIF.
        ENDLOOP.
      ENDIF.

      LOOP AT pt_menu_tcodes INTO DATA(lv_menu_tc).
        lv_tcd_found = abap_false.
        DATA(lv_tcd_xuval) = CONV xuval( lv_menu_tc ).
        LOOP AT lt_tcd_auths INTO DATA(lv_chk_tcd_auth).
          PERFORM field_value_covered USING lt_tcd_flds
                                            lt_empty_1252
                                            lt_usorg
                                            'S_TCODE'
                                            lv_chk_tcd_auth
                                            'TCD'
                                            lv_tcd_xuval
                                      CHANGING lv_tcd_found.
          IF lv_tcd_found = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.
        IF lv_tcd_found = abap_false.
          INSERT lv_menu_tc INTO TABLE lt_missing_tcds.
        ENDIF.
      ENDLOOP.

      IF lt_missing_tcds IS NOT INITIAL.
        IF lv_std_tcd_auth IS NOT INITIAL.
          lv_child_tcd_auth = lv_std_tcd_auth.
          lv_child_tcd_mod  = 'S'.
        ELSEIF lv_oth_tcd_auth IS NOT INITIAL.
          lv_child_tcd_auth = lv_oth_tcd_auth.
          lv_child_tcd_mod  = COND #( WHEN lv_oth_tcd_mod IS NOT INITIAL THEN lv_oth_tcd_mod ELSE 'S' ).
        ELSE.
          " Allocate a Standard ('S') S_TCODE node without flipping menu sync status
          DATA(lv_tcd_slot_ok) = abap_false.
          DO 999 TIMES.
            IF lv_counter < 100.
              lv_child_tcd_auth = |__________{ lv_counter WIDTH = 2 ALIGN = RIGHT PAD = '0' }|.
            ELSE.
              lv_child_tcd_auth = |________{ lv_counter WIDTH = 4 ALIGN = RIGHT PAD = '0' }|.
            ENDIF.
            READ TABLE lt_child_1250 TRANSPORTING NO FIELDS WITH KEY auth = lv_child_tcd_auth.
            lv_counter = lv_counter + 1.
            IF sy-subrc <> 0.
              lv_tcd_slot_ok = abap_true.
              EXIT.
            ENDIF.
          ENDDO.
          IF lv_tcd_slot_ok = abap_true.
            SELECT SINGLE ttext FROM tobjt
              WHERE langu = @sy-langu AND object = 'S_TCODE'
              INTO @DATA(lv_tcd_atext).
            IF sy-subrc <> 0.
              SELECT SINGLE ttext FROM tobjt
                WHERE langu = 'E' AND object = 'S_TCODE'
                INTO @lv_tcd_atext.
            ENDIF.
            APPEND VALUE pt1250(
              object   = 'S_TCODE'
              auth     = lv_child_tcd_auth
              variant  = ' '
              modified = 'S'
              copied   = ' '
              neu      = 'O'
              deleted  = ' '
              atext    = lv_tcd_atext
            ) TO lt_child_1250.
            lv_child_tcd_mod = 'S'.
            lv_has_changes   = abap_true.
          ELSE.
            CLEAR lv_child_tcd_auth.
          ENDIF.
        ENDIF.

        IF lv_child_tcd_auth IS NOT INITIAL.
          LOOP AT lt_missing_tcds INTO lv_menu_tc.
            APPEND VALUE pt1251(
              object   = 'S_TCODE'
              auth     = lv_child_tcd_auth
              variant  = ' '
              field    = 'TCD'
              low      = lv_menu_tc
              high     = space
              modified = lv_child_tcd_mod
              neu      = 'N'
              deleted  = ' '
            ) TO lt_child_1251.
            lv_has_changes = abap_true.
          ENDLOOP.
        ENDIF.
      ENDIF.
    ENDIF.

    " 5 & 6. Clear SAPLPRGN globals and save child Org Levels / Auth Data with strict sy-subrc checks (SU53-M4)
    IF lv_child_org_changed = abap_true OR lv_has_changes = abap_true.
      CALL FUNCTION 'PRGN_CLEAR_BUFFER'.

      IF lv_child_org_changed = abap_true.
        CALL FUNCTION 'PRGN_1252_SAVE_ORG_LEVELS'
          EXPORTING
            activity_group = lv_child_role
          TABLES
            org_levels     = lt_child_1252
          EXCEPTIONS
            OTHERS         = 1.
        IF sy-subrc <> 0.
          lv_child_save_err = abap_true.
        ENDIF.
      ENDIF.

      IF lv_child_save_err = abap_false AND lv_has_changes = abap_true.
        CALL FUNCTION 'PRGN_1250_SAVE_AUTH_DATA'
          EXPORTING
            activity_group = lv_child_role
          TABLES
            auth_data      = lt_child_1250
          EXCEPTIONS
            OTHERS         = 1.
        IF sy-subrc <> 0.
          lv_child_save_err = abap_true.
        ENDIF.

        IF lv_child_save_err = abap_false.
          CALL FUNCTION 'PRGN_1251_SAVE_FIELD_VALUES'
            EXPORTING
              activity_group = lv_child_role
            TABLES
              field_values   = lt_child_1251
            EXCEPTIONS
              OTHERS         = 1.
          IF sy-subrc <> 0.
            lv_child_save_err = abap_true.
          ENDIF.
        ENDIF.
      ENDIF.

      IF lv_child_save_err = abap_false.
        CALL FUNCTION 'PRGN_UPDATE_DATABASE'
          EXCEPTIONS
            OTHERS = 1.
        IF sy-subrc <> 0.
          lv_child_save_err = abap_true.
        ENDIF.
      ENDIF.

      IF lv_child_save_err = abap_true.
        ROLLBACK WORK.
        CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
        CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
          EXPORTING
            activity_group = lv_child_role.
        cv_gen_failed = abap_true.
        CONTINUE.
      ENDIF.

      CALL FUNCTION 'PRGN_SET_ACTGROUP_TIMESTAMP'
        EXPORTING
          activity_group = lv_child_role
          no_commit      = 'X'
        EXCEPTIONS
          OTHERS         = 0.
      COMMIT WORK AND WAIT.
    ENDIF.

    " 7. Unlock child role BEFORE profile generation
    CALL FUNCTION 'PRGN_ACTIVITY_GROUP_DEQUEUE'
      EXPORTING
        activity_group = lv_child_role.

    " 8. Regenerate profile for derived role (also restores rebindable 1251 $VARBL bindings)
    IF lv_has_changes = abap_true OR lv_child_org_changed = abap_true.
      CLEAR lv_gen_subrc.
      PERFORM generate_role_profile USING lv_child_role ' ' abap_true abap_false
                                    CHANGING lv_gen_subrc.
      IF lv_gen_subrc = 0.
        COMMIT WORK AND WAIT.
        cv_der_count = cv_der_count + 1.
      ELSE.
        ROLLBACK WORK.
        CALL FUNCTION 'PRGN_CLEAR_BUFFER'.
        cv_gen_failed = abap_true.
      ENDIF.
    ENDIF.

  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form check_varbl_star_auth
*&---------------------------------------------------------------------*
FORM check_varbl_star_auth USING    pv_varbl      TYPE usorg-varbl
                                    pt_lead_1250  TYPE tt_pt1250
                                    pt_lead_1251  TYPE tt_pt1251
                                    pt_child_1250 TYPE tt_pt1250
                                    pt_child_1251 TYPE tt_pt1251
                                    pt_usorg      TYPE tt_usorg
                           CHANGING cv_allowed    TYPE abap_bool.
  DATA lv_checked TYPE abap_bool.

  cv_allowed = abap_true.

  LOOP AT pt_usorg INTO DATA(ls_uo_a) WHERE varbl = pv_varbl.
    LOOP AT pt_lead_1251 INTO DATA(ls_l51_a)
      WHERE field = ls_uo_a-field AND deleted = space AND copied <> 'I'.
      LOOP AT pt_lead_1250 TRANSPORTING NO FIELDS
        WHERE object = ls_l51_a-object AND auth = ls_l51_a-auth
          AND deleted = space AND copied <> 'I'.
        lv_checked = abap_true.
        AUTHORITY-CHECK OBJECT 'S_USER_VAL'
          ID 'OBJECT'     FIELD ls_l51_a-object
          ID 'AUTH_FIELD' FIELD ls_l51_a-field
          ID 'AUTH_VALUE' FIELD '*'.
        IF sy-subrc <> 0.
          cv_allowed = abap_false.
          RETURN.
        ENDIF.
        EXIT.
      ENDLOOP.
    ENDLOOP.

    LOOP AT pt_child_1251 INTO DATA(ls_c51_a)
      WHERE field = ls_uo_a-field AND deleted = space AND copied <> 'I'.
      LOOP AT pt_child_1250 TRANSPORTING NO FIELDS
        WHERE object = ls_c51_a-object AND auth = ls_c51_a-auth
          AND deleted = space AND copied <> 'I'.
        lv_checked = abap_true.
        AUTHORITY-CHECK OBJECT 'S_USER_VAL'
          ID 'OBJECT'     FIELD ls_c51_a-object
          ID 'AUTH_FIELD' FIELD ls_c51_a-field
          ID 'AUTH_VALUE' FIELD '*'.
        IF sy-subrc <> 0.
          cv_allowed = abap_false.
          RETURN.
        ENDIF.
        EXIT.
      ENDLOOP.
    ENDLOOP.
  ENDLOOP.

  IF lv_checked = abap_false.
    LOOP AT pt_usorg INTO ls_uo_a WHERE varbl = pv_varbl.
      lv_checked = abap_true.
      AUTHORITY-CHECK OBJECT 'S_USER_VAL'
        ID 'OBJECT'     FIELD '*'
        ID 'AUTH_FIELD' FIELD ls_uo_a-field
        ID 'AUTH_VALUE' FIELD '*'.
      IF sy-subrc <> 0.
        cv_allowed = abap_false.
        RETURN.
      ENDIF.
    ENDLOOP.
    IF lv_checked = abap_false.
      cv_allowed = abap_false.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form recheck_auths_after_add
*&---------------------------------------------------------------------*
FORM recheck_auths_after_add USING pv_target_role TYPE agr_name
                                   pv_der_count   TYPE i
                                   pv_menu_added  TYPE i
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

  IF pv_der_count > 0.
    lv_msg = |Leading Role { pv_target_role } updated & derived to { pv_der_count } child role(s):|.
  ELSE.
    lv_msg = |Role { pv_target_role }:|.
  ENDIF.

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
    READ TABLE gt_user_roles INTO DATA(ls_rf_first) INDEX 1.
    IF sy-subrc = 0.
      PERFORM sync_role_selection USING ls_rf_first-agr_name.
    ELSE.
      CLEAR: gv_selected_role, gv_leading_role.
    ENDIF.
  ELSE.
    PERFORM sync_role_selection USING gv_selected_role.
  ENDIF.

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
      IF e_column_id-fieldname = 'PARENT_AGR' AND <ls_clicked_role>-parent_agr IS NOT INITIAL.
        SET PARAMETER ID 'AGR' FIELD <ls_clicked_role>-parent_agr.
        TRY.
            CALL TRANSACTION 'PFCG' WITH AUTHORITY-CHECK AND SKIP FIRST SCREEN.
          CATCH cx_sy_authorization_error.
            MESSAGE 'No authorization to launch transaction PFCG.' TYPE 'S' DISPLAY LIKE 'E'.
        ENDTRY.
        RETURN.
      ENDIF.

      PERFORM sync_role_selection USING <ls_clicked_role>-agr_name.
      PERFORM eval_auths_for_role USING gv_selected_role.

      IF go_grid_roles IS BOUND.
        go_grid_roles->refresh_table_display( is_stable = VALUE #( row = 'X' col = 'X' ) ).
      ENDIF.
      IF go_grid_auths IS BOUND.
        go_grid_auths->refresh_table_display( is_stable = VALUE #( row = 'X' col = 'X' ) ).
      ENDIF.

      IF <ls_clicked_role>-parent_agr IS NOT INITIAL.
        MESSAGE |Role { gv_selected_role } is now LOCKED -> Target Leading Role: { gv_leading_role }.| TYPE 'S'.
      ELSE.
        MESSAGE |Role { gv_selected_role } is now LOCKED (Standalone / Master Role).| TYPE 'S'.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD on_double_click_roles.
    DATA: lv_idx TYPE i.
    lv_idx = e_row-index.

    READ TABLE gt_user_roles ASSIGNING FIELD-SYMBOL(<ls_clicked_role>) INDEX lv_idx.
    IF sy-subrc = 0.
      IF e_column-fieldname = 'PARENT_AGR' AND <ls_clicked_role>-parent_agr IS NOT INITIAL.
        SET PARAMETER ID 'AGR' FIELD <ls_clicked_role>-parent_agr.
        TRY.
            CALL TRANSACTION 'PFCG' WITH AUTHORITY-CHECK AND SKIP FIRST SCREEN.
          CATCH cx_sy_authorization_error.
            MESSAGE 'No authorization to launch transaction PFCG.' TYPE 'S' DISPLAY LIKE 'E'.
        ENDTRY.
        RETURN.
      ENDIF.

      PERFORM sync_role_selection USING <ls_clicked_role>-agr_name.
      PERFORM eval_auths_for_role USING gv_selected_role.

      IF go_grid_roles IS BOUND.
        go_grid_roles->refresh_table_display( is_stable = VALUE #( row = 'X' col = 'X' ) ).
      ENDIF.
      IF go_grid_auths IS BOUND.
        go_grid_auths->refresh_table_display( is_stable = VALUE #( row = 'X' col = 'X' ) ).
      ENDIF.

      IF <ls_clicked_role>-parent_agr IS NOT INITIAL.
        MESSAGE |Role { gv_selected_role } is now LOCKED -> Target Leading Role: { gv_leading_role }.| TYPE 'S'.
      ELSE.
        MESSAGE |Role { gv_selected_role } is now LOCKED (Standalone / Master Role).| TYPE 'S'.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD on_before_command_auths.
    " M9: Only intercept standard grid refresh button (avoid double execution with HANDLE_USER_COMMAND)
    IF e_ucomm = cl_gui_alv_grid=>mc_fc_refresh.
      PERFORM refresh_all_data.
      IF go_grid_auths IS BOUND.
        go_grid_auths->set_user_command( space ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD on_hotspot_auths.
    IF e_column_id-fieldname = 'OBJECT'.
      READ TABLE gt_missing_auth INTO DATA(ls_m) INDEX e_row_id-index.
      IF sy-subrc = 0 AND ls_m-object IS NOT INITIAL AND ls_m-object <> 'SAP_ALL' AND ls_m-object <> 'INFO'.
        " M11: XUOBJECT Set/Get Parameter ID for SU03 is 'XUO'
        SET PARAMETER ID 'XUO' FIELD ls_m-object.
        TRY.
            CALL TRANSACTION 'SU03' WITH AUTHORITY-CHECK AND SKIP FIRST SCREEN.
          CATCH cx_sy_authorization_error.
            MESSAGE 'No authorization to launch transaction SU03.' TYPE 'S' DISPLAY LIKE 'E'.
        ENDTRY.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD on_double_click_auths.
    READ TABLE gt_missing_auth INTO DATA(ls_m) INDEX e_row-index.
    IF sy-subrc = 0 AND ls_m-object IS NOT INITIAL AND ls_m-object <> 'SAP_ALL' AND ls_m-object <> 'INFO'.
      SET PARAMETER ID 'XUO' FIELD ls_m-object.
      TRY.
          CALL TRANSACTION 'SU03' WITH AUTHORITY-CHECK AND SKIP FIRST SCREEN.
        CATCH cx_sy_authorization_error.
          MESSAGE 'No authorization to launch transaction SU03.' TYPE 'S' DISPLAY LIKE 'E'.
      ENDTRY.
    ENDIF.
  ENDMETHOD.
ENDCLASS.
