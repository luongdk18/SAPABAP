*&---------------------------------------------------------------------*
*& Report Z_EXPORT_OBJ_LEVELS
*&---------------------------------------------------------------------*
*& Exports all Authorization Objects & Fields from TOBJ, TOBJT, TOBCT
*&---------------------------------------------------------------------*
REPORT z_export_obj_levels LINE-SIZE 1023 NO STANDARD PAGE HEADING.

PARAMETERS: p_langu TYPE sy-langu DEFAULT 'E'.

TYPES: BEGIN OF ty_tobj,
         objct TYPE tobj-objct,
         fiel1 TYPE tobj-fiel1,
         fiel2 TYPE tobj-fiel2,
         fiel3 TYPE tobj-fiel3,
         fiel4 TYPE tobj-fiel4,
         fiel5 TYPE tobj-fiel5,
         fiel6 TYPE tobj-fiel6,
         fiel7 TYPE tobj-fiel7,
         fiel8 TYPE tobj-fiel8,
         fiel9 TYPE tobj-fiel9,
         fiel0 TYPE tobj-fiel0,
         oclss TYPE tobj-oclss,
         ttext TYPE tobjt-ttext,
         ctext TYPE tobct-ctext,
       END OF ty_tobj.

DATA: lt_tobj   TYPE STANDARD TABLE OF ty_tobj,
      lt_f      TYPE STANDARD TABLE OF xufield,
      lv_idx    TYPE i,
      lv_fname  TYPE char10,
      lv_fval   TYPE string.

FIELD-SYMBOLS: <lv_fld> TYPE any.

INITIALIZATION.
  %_p_langu_%_app_%-text = 'Description Language'.

START-OF-SELECTION.
  AUTHORITY-CHECK OBJECT 'S_USER_AGR'
    ID 'ACT_GROUP' DUMMY
    ID 'ACTVT'     FIELD '03'.
  IF sy-subrc <> 0.
    AUTHORITY-CHECK OBJECT 'S_TABU_NAM'
      ID 'ACTVT' FIELD '03'
      ID 'TABLE' FIELD 'TOBJ'.
    IF sy-subrc <> 0.
      MESSAGE 'No authorization to export authorization catalog (S_USER_AGR or S_TABU_NAM 03).' TYPE 'E'.
    ENDIF.
  ENDIF.

  SELECT t~objct, t~fiel1, t~fiel2, t~fiel3, t~fiel4, t~fiel5,
         t~fiel6, t~fiel7, t~fiel8, t~fiel9, t~fiel0,
         t~oclss,
         coalesce( j1~ttext, j2~ttext ) AS ttext,
         coalesce( c1~ctext, c2~ctext ) AS ctext
    FROM tobj AS t
    LEFT OUTER JOIN tobjt AS j1 ON j1~object = t~objct AND j1~langu = @p_langu
    LEFT OUTER JOIN tobjt AS j2 ON j2~object = t~objct AND j2~langu = 'E'
    LEFT OUTER JOIN tobct AS c1 ON c1~oclss  = t~oclss AND c1~langu = @p_langu
    LEFT OUTER JOIN tobct AS c2 ON c2~oclss  = t~oclss AND c2~langu = 'E'
    ORDER BY t~objct
    INTO TABLE @lt_tobj.

  IF lt_tobj IS INITIAL.
    MESSAGE 'No authorization objects found in table TOBJ.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  LOOP AT lt_tobj INTO DATA(ls_t).
    CLEAR lt_f.
    DO 10 TIMES.
      lv_idx = sy-index MOD 10.
      lv_fname = |FIEL{ lv_idx }|.
      ASSIGN COMPONENT lv_fname OF STRUCTURE ls_t TO <lv_fld>.
      IF sy-subrc = 0 AND <lv_fld> IS NOT INITIAL.
        lv_fval = to_upper( condense( CONV string( <lv_fld> ) ) ).
        IF lv_fval <> 'DUMMYFIELD'.
          APPEND <lv_fld> TO lt_f.
        ENDIF.
      ENDIF.
    ENDDO.

    LOOP AT lt_f INTO DATA(lv_f).
      WRITE: / ls_t-objct, '###', lv_f, '###', ls_t-oclss, '###', ls_t-ttext, '###', ls_t-ctext.
    ENDLOOP.
  ENDLOOP.
