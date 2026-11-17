*&---------------------------------------------------------------------*
*& Report Z_EXPORT_OBJ_LEVELS
*&---------------------------------------------------------------------*
*& Exports all Authorization Objects & Fields from TOBJ, TOBJT, TOBCT
*&---------------------------------------------------------------------*
REPORT z_export_obj_levels LINE-SIZE 1023.

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

DATA: lt_tobj TYPE STANDARD TABLE OF ty_tobj.

SELECT t~objct, t~fiel1, t~fiel2, t~fiel3, t~fiel4, t~fiel5, t~fiel6, t~fiel7, t~fiel8, t~fiel9, t~fiel0,
       t~oclss, j~ttext, c~ctext
  FROM tobj AS t
  LEFT OUTER JOIN tobjt AS j ON j~object = t~objct AND j~langu = 'E'
  LEFT OUTER JOIN tobct AS c ON c~oclss = t~oclss AND c~langu = 'E'
  ORDER BY t~objct
  INTO TABLE @lt_tobj.

LOOP AT lt_tobj INTO DATA(ls_t).
  DATA: lt_f TYPE STANDARD TABLE OF xufield.
  CLEAR lt_f.
  IF ls_t-fiel1 IS NOT INITIAL AND ls_t-fiel1 <> 'dummyfield'. APPEND ls_t-fiel1 TO lt_f. ENDIF.
  IF ls_t-fiel2 IS NOT INITIAL AND ls_t-fiel2 <> 'dummyfield'. APPEND ls_t-fiel2 TO lt_f. ENDIF.
  IF ls_t-fiel3 IS NOT INITIAL AND ls_t-fiel3 <> 'dummyfield'. APPEND ls_t-fiel3 TO lt_f. ENDIF.
  IF ls_t-fiel4 IS NOT INITIAL AND ls_t-fiel4 <> 'dummyfield'. APPEND ls_t-fiel4 TO lt_f. ENDIF.
  IF ls_t-fiel5 IS NOT INITIAL AND ls_t-fiel5 <> 'dummyfield'. APPEND ls_t-fiel5 TO lt_f. ENDIF.
  IF ls_t-fiel6 IS NOT INITIAL AND ls_t-fiel6 <> 'dummyfield'. APPEND ls_t-fiel6 TO lt_f. ENDIF.
  IF ls_t-fiel7 IS NOT INITIAL AND ls_t-fiel7 <> 'dummyfield'. APPEND ls_t-fiel7 TO lt_f. ENDIF.
  IF ls_t-fiel8 IS NOT INITIAL AND ls_t-fiel8 <> 'dummyfield'. APPEND ls_t-fiel8 TO lt_f. ENDIF.
  IF ls_t-fiel9 IS NOT INITIAL AND ls_t-fiel9 <> 'dummyfield'. APPEND ls_t-fiel9 TO lt_f. ENDIF.
  IF ls_t-fiel0 IS NOT INITIAL AND ls_t-fiel0 <> 'dummyfield'. APPEND ls_t-fiel0 TO lt_f. ENDIF.

  LOOP AT lt_f INTO DATA(lv_f).
    WRITE: / ls_t-objct, '###', lv_f, '###', ls_t-oclss, '###', ls_t-ttext, '###', ls_t-ctext.
  ENDLOOP.
ENDLOOP.
