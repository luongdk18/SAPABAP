---
name: sap-security-api-guidelines
description: >-
  Standard guidelines, function module mapping, and coding patterns for SAP Security,
  User Administration, and Role/Profile Maintenance in ABAP. Activate this skill whenever
  authoring, updating, or debugging ABAP code that interacts with SAP roles (PFCG),
  authorization objects, org levels, user accounts, or role assignments to strictly
  prohibit direct database modifications and enforce 100% standard SAP BAPI/FM compliance.
---

# SAP Security & PFCG API Guidelines

This skill provides certified patterns, Function Module signatures, and best practices for developing ABAP utilities in SAP Security and Basis administration.

---

## 🚫 Cardinal Rule: No Direct Table Updates

Never write OpenSQL `UPDATE`, `INSERT INTO`, `DELETE FROM`, or `MODIFY` against standard SAP security and user tables (`AGR_*`, `USR*`, `ADR*`). Direct updates cause data inconsistency, bypass enqueue locks, skip audit change documents, and fail SAP security audits.

---

## 📚 Standard Function Modules & Code Patterns

### 1. Role Text & Description Maintenance
- **FM**: `PRGN_RFC_CHANGE_TEXTS`
- **Replaces**: `UPDATE agr_texts`, `DELETE FROM agr_texts`
- **Behavior**: Sets role description on `line = '00000'`, writes change documents (`PRGN_CHANGEDOCUMENT_WRITE`), and automatically strips obsolete comments (`line > '00000'`).

```abap
DATA: lt_texts TYPE STANDARD TABLE OF agr_texts.
CLEAR lt_texts.
APPEND VALUE agr_texts(
  spras = sy-langu
  line  = '00000'
  text  = iv_role_desc
) TO lt_texts.

CALL FUNCTION 'PRGN_RFC_CHANGE_TEXTS'
  EXPORTING
    activity_group = iv_agr_name
    no_dialog      = 'X'
  TABLES
    texts          = lt_texts
  EXCEPTIONS
    OTHERS         = 0.
```

---

### 2. Authorization Objects & Fields Maintenance
- **FMs**: `PRGN_1251_READ_FIELD_VALUES` & `PRGN_1251_SAVE_FIELD_VALUES`
- **Replaces**: `UPDATE agr_1251`, `MODIFY agr_1251`

```abap
DATA: lt_pt1251 TYPE STANDARD TABLE OF pt1251.

" 1. Read existing field values
CALL FUNCTION 'PRGN_1251_READ_FIELD_VALUES'
  EXPORTING
    activity_group    = iv_agr_name
  TABLES
    field_values      = lt_pt1251
  EXCEPTIONS
    no_data_available = 1
    OTHERS            = 2.

" 2. Modify values in memory
LOOP AT lt_pt1251 ASSIGNING FIELD-SYMBOL(<ls_fld>)
  WHERE object = iv_object AND field = iv_field.
  <ls_fld>-low      = iv_val_low.
  <ls_fld>-high     = iv_val_high.
  <ls_fld>-modified = 'U'.
ENDLOOP.

" 3. Save via standard PFCG FM
CALL FUNCTION 'PRGN_1251_SAVE_FIELD_VALUES'
  EXPORTING
    activity_group = iv_agr_name
  TABLES
    field_values   = lt_pt1251.

CALL FUNCTION 'PRGN_UPDATE_DATABASE'.
COMMIT WORK AND WAIT.
```

---

### 3. Organizational Levels Maintenance
- **FMs**: `PRGN_1252_READ_ORG_LEVELS` & `PRGN_1252_SAVE_ORG_LEVELS`
- **Replaces**: `UPDATE agr_1252`

```abap
DATA: lt_pt1252 TYPE STANDARD TABLE OF pt1252.

" 1. Read existing org levels
CALL FUNCTION 'PRGN_1252_READ_ORG_LEVELS'
  EXPORTING
    activity_group    = iv_agr_name
  TABLES
    org_levels        = lt_pt1252
  EXCEPTIONS
    no_data_available = 1
    OTHERS            = 2.

" 2. Maintain org values
LOOP AT lt_pt1252 ASSIGNING FIELD-SYMBOL(<ls_org>)
  WHERE varbl = iv_varbl.
  <ls_org>-low  = iv_val_low.
  <ls_org>-high = iv_val_high.
ENDLOOP.

" 3. Save via standard FM
CALL FUNCTION 'PRGN_1252_SAVE_ORG_LEVELS'
  EXPORTING
    activity_group = iv_agr_name
  TABLES
    org_levels     = lt_pt1252.

CALL FUNCTION 'PRGN_UPDATE_DATABASE'.
COMMIT WORK AND WAIT.
```

---

### 4. Role Hierarchy & Derivation
- **FMs**: `PRGN_RFC_CREATE_DERIVATION`, `PRGN_STRU_SAVE_DEFINITION`
- **Replaces**: `UPDATE agr_define SET parent_agr = ...`

```abap
" Inherit authorizations and establish parent link
CALL FUNCTION 'PRGN_RFC_CREATE_DERIVATION'
  EXPORTING
    role            = lv_derived_role
    parent_role     = lv_master_role
    adjust_auths    = 'X'
    profile_gen     = space
    no_dialog       = 'X'
  IMPORTING
    derivation_ok   = lv_drv_ok
    adjust_auths_ok = lv_adj_ok
  TABLES
    return          = lt_bapiret.

" Reparenting existing role via PRGN_STRU_SAVE_DEFINITION
DATA: lt_def TYPE STANDARD TABLE OF agr_define.
APPEND VALUE agr_define(
  agr_name   = lv_derived_role
  parent_agr = lv_master_role
) TO lt_def.

CALL FUNCTION 'PRGN_STRU_SAVE_DEFINITION'
  EXPORTING
    enqueue        = 'X'
    message_output = space
  TABLES
    i_definition   = lt_def
    return         = lt_bapiret.
```

---

### 5. Profile Compilation & Generation
- **FM**: `SUPRN_DARK_MANIPULATE_PROFILE`

```abap
" Note: Ensure role is dequeued before calling SUPRN_DARK_MANIPULATE_PROFILE
CALL FUNCTION 'SUPRN_DARK_MANIPULATE_PROFILE'
  EXPORTING
    activity_group        = iv_agr_name
    fill_orgs_with_star   = space
    fill_fields_with_star = space
    no_dialog             = 'X'
    rebuild_auth_data     = space
    generate_profile      = 'X'
  IMPORTING
    return                = lt_bapiret
  EXCEPTIONS
    OTHERS                = 1.

COMMIT WORK AND WAIT.

" Check profile compilation status
DATA: lv_color TYPE char10,
      lv_msg   TYPE c LENGTH 255.
CALL FUNCTION 'PRGN_CHECK_PROFILE_STATUS'
  EXPORTING
    activity_group = iv_agr_name
  IMPORTING
    message_text   = lv_msg
    led_color      = lv_color.
```

---

### 6. User Master & Role Assignments
- **BAPIs**: `BAPI_USER_CREATE1`, `BAPI_USER_CHANGE`, `BAPI_USER_ACTGROUPS_ASSIGN`
- **Password Generation**: `SUSR_GENERATE_PASSWORD`

```abap
" Dynamic password generation
DATA: lv_password TYPE bapipwd.
CALL FUNCTION 'SUSR_GENERATE_PASSWORD'
  EXPORTING
    pwdlen = 10
  IMPORTING
    pwd    = lv_password.

" Role Assignment
CALL FUNCTION 'BAPI_USER_ACTGROUPS_ASSIGN'
  EXPORTING
    username  = iv_bapi_user
  TABLES
    activitygroups = lt_roles_to_assign
    return         = lt_bapiret.

CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
  EXPORTING
    wait = 'X'.
```
