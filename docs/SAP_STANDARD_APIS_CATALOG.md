# 🏛️ SAP Standard APIs & Function Modules Catalog

> **Repository Standard**: 100% BAPI & SAP Standard Function Module Architecture  
> **Direct Database Updates**: **STRICTLY PROHIBITED** (`UPDATE`, `DELETE FROM`, `MODIFY` on SAP tables)

This document serves as the central reference catalog of all SAP standard BAPIs and Function Modules employed across the ABAP utilities in this repository (`Z_ROLE_*`, `Z_USER_*`, `Z_AUTH_*`).

---

## 📑 Table of Contents

1. [Architectural Rationale](#1-architectural-rationale)
2. [Role Administration APIs (PFCG)](#2-role-administration-apis-pfcg)
   - [`PRGN_RFC_CREATE_AGR_MULTIPLE`](#prgn_rfc_create_agr_multiple)
   - [`PRGN_RFC_CHANGE_TEXTS`](#prgn_rfc_change_texts)
   - [`PRGN_RFC_CREATE_DERIVATION`](#prgn_rfc_create_derivation)
   - [`PRGN_STRU_SAVE_DEFINITION`](#prgn_stru_save_definition)
   - [`PRGN_RFC_ADD_ACTGROUPS`](#prgn_rfc_add_actgroups)
   - [`PRGN_SET_ACTGROUP_TIMESTAMP`](#prgn_set_actgroup_timestamp)
3. [Authorization Data & Org Levels APIs](#3-authorization-data--org-levels-apis)
   - [`PRGN_1250_READ_AUTH_DATA` & `PRGN_1250_SAVE_AUTH_DATA`](#prgn_1250_read_auth_data--prgn_1250_save_auth_data)
   - [`PRGN_1251_READ_FIELD_VALUES` & `PRGN_1251_SAVE_FIELD_VALUES`](#prgn_1251_read_field_values--prgn_1251_save_field_values)
   - [`PRGN_1252_READ_ORG_LEVELS` & `PRGN_1252_SAVE_ORG_LEVELS`](#prgn_1252_read_org_levels--prgn_1252_save_org_levels)
   - [`PRGN_UPDATE_DATABASE`](#prgn_update_database)
4. [Profile Compilation & Diagnostics APIs](#4-profile-compilation--diagnostics-apis)
   - [`SUPRN_DARK_MANIPULATE_PROFILE`](#suprn_dark_manipulate_profile)
   - [`PRGN_CHECK_PROFILE_STATUS`](#prgn_check_profile_status)
5. [User Administration APIs (SU01)](#5-user-administration-apis-su01)
   - [`BAPI_USER_CREATE1` & `BAPI_USER_CHANGE`](#bapi_user_create1--bapi_user_change)
   - [`BAPI_USER_ACTGROUPS_ASSIGN`](#bapi_user_actgroups_assign)
   - [`SUSR_GENERATE_PASSWORD`](#susr_generate_password)
   - [`BAPI_TRANSACTION_COMMIT`](#bapi_transaction_commit)
6. [Summary Usage Matrix across Programs](#6-summary-usage-matrix-across-programs)

---

## 1. Architectural Rationale

Direct database manipulation (`UPDATE`, `MODIFY`, `DELETE FROM`, `INSERT INTO`) on standard SAP security tables (`AGR_DEFINE`, `AGR_TEXTS`, `AGR_1250`, `AGR_1251`, `AGR_1252`, `USR02`, etc.) violates enterprise SAP development standards:

1. **Locking & Concurrency**: Direct updates do not respect SAP Enqueue Locks (`E_AGR_DEFINE`), risking severe deadlock and inconsistent data when administrators use `PFCG` or `SU01`.
2. **Audit Trails & Change Documents**: Standard SAP FMs automatically write change logs via `PRGN_CHANGEDOCUMENT_WRITE` and `S_USER_CHG`. Direct updates leave no change history, violating SOX, ISO 27001, and corporate internal audit compliance.
3. **PFCG Buffer Synchronization**: Role buffers, org level distributions, timestamp flags (`AGR_FLAGS`), and profile compilation pointers require atomic updates that only standard PFCG engines provide.
4. **Transport Request Recording**: Standard FMs integrate with the SAP Transport Organizer (`TRKORR`), ensuring clean transport into QA and Production environments.

---

## 2. Role Administration APIs (PFCG)

### `PRGN_RFC_CREATE_AGR_MULTIPLE`
- **Function Group**: `PRGN_RFC`
- **Purpose**: Creates single or composite role shells in SAP PFCG.
- **Used in**: `Z_ROLE_01_CREATE_MASTER`, `Z_ROLE_02_CREATE_DERIVE`, `Z_ROLE_04_CREATE_COMPOSITE`.
- **Signature**:
  ```abap
  CALL FUNCTION 'PRGN_RFC_CREATE_AGR_MULTIPLE'
    EXPORTING
      activity_group                = lv_role_name
      activity_group_text           = lv_role_desc
      collective_agr                = ' ' " 'X' for Composite, ' ' for Single
      no_dialog                     = 'X'
    TABLES
      return                        = lt_bapiret.
  ```

### `PRGN_RFC_CHANGE_TEXTS`
- **Function Group**: `PRGN_CATT`
- **Purpose**: Updates role description and cleans automatic boilerplate comments.
- **Replaces**: `UPDATE agr_texts` & `DELETE FROM agr_texts`.
- **Used in**: `Z_ROLE_01_CREATE_MASTER`, `Z_ROLE_02_CREATE_DERIVE`, `Z_ROLE_04_CREATE_COMPOSITE`.
- **Signature**:
  ```abap
  DATA: lt_texts TYPE STANDARD TABLE OF agr_texts.
  APPEND VALUE agr_texts(
    spras = sy-langu
    line  = '00000'
    text  = lv_role_desc
  ) TO lt_texts.

  CALL FUNCTION 'PRGN_RFC_CHANGE_TEXTS'
    EXPORTING
      activity_group = lv_role_name
      no_dialog      = 'X'
    TABLES
      texts          = lt_texts.
  ```

### `PRGN_RFC_CREATE_DERIVATION`
- **Function Group**: `PRGN_CATT`
- **Purpose**: Links a derived role to its master role, copies authorizations, and adjusts org levels.
- **Used in**: `Z_ROLE_02_CREATE_DERIVE`.
- **Signature**:
  ```abap
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
  ```

### `PRGN_STRU_SAVE_DEFINITION`
- **Function Group**: `PRGN_STRUCTURE`
- **Purpose**: Low-level certified API to update role definitions (such as reparenting `parent_agr`).
- **Replaces**: `UPDATE agr_define SET parent_agr = ...`.
- **Used in**: `Z_ROLE_02_CREATE_DERIVE`.

### `PRGN_RFC_ADD_ACTGROUPS`
- **Function Group**: `PRGN_RFC`
- **Purpose**: Atomically assigns single roles to a composite role.
- **Used in**: `Z_ROLE_04_CREATE_COMPOSITE`.

### `PRGN_SET_ACTGROUP_TIMESTAMP`
- **Function Group**: `PRGN_CATT`
- **Purpose**: Updates role timestamp in `AGR_FLAGS` and marks authorization profiles for regeneration.
- **Used in**: `Z_ROLE_01_CREATE_MASTER`, `Z_ROLE_02_CREATE_DERIVE`, `Z_ROLE_03A_UPDATE_ORG`, `Z_ROLE_03B_UPDATE_OBJECT`, `Z_AUTH_SU53_ANALYZER`.

---

## 3. Authorization Data & Org Levels APIs

### `PRGN_1250_READ_AUTH_DATA` & `PRGN_1250_SAVE_AUTH_DATA`
- **Function Group**: `PRGN_PFCG`
- **Purpose**: Reads and maintains authorization instances (`AGR_1250`).
- **Used in**: `Z_AUTH_SU53_ANALYZER`.

### `PRGN_1251_READ_FIELD_VALUES` & `PRGN_1251_SAVE_FIELD_VALUES`
- **Function Group**: `PRGN_PFCG`
- **Purpose**: Reads and updates authorization fields (`AGR_1251`) in role memory buffer.
- **Replaces**: `UPDATE agr_1251`.
- **Used in**: `Z_ROLE_03B_UPDATE_OBJECT`, `Z_ROLE_03A_UPDATE_ORG`, `Z_AUTH_SU53_ANALYZER`.

### `PRGN_1252_READ_ORG_LEVELS` & `PRGN_1252_SAVE_ORG_LEVELS`
- **Function Group**: `PRGN_PFCG`
- **Purpose**: Reads and updates organizational levels (`AGR_1252`).
- **Replaces**: `UPDATE agr_1252`.
- **Used in**: `Z_ROLE_01_CREATE_MASTER`, `Z_ROLE_03A_UPDATE_ORG`, `Z_AUTH_SU53_ANALYZER`.

### `PRGN_UPDATE_DATABASE`
- **Function Group**: `PRGN_PFCG`
- **Purpose**: Writes buffered PFCG changes (`1250`, `1251`, `1252`) directly to the physical database with complete integrity checks and change documents. Must be followed by `COMMIT WORK AND WAIT`.
- **Used in**: All role maintenance programs.

---

## 4. Profile Compilation & Diagnostics APIs

### `SUPRN_DARK_MANIPULATE_PROFILE`
- **Function Group**: `SUPRN`
- **Purpose**: Compiles authorization data into SAP user profiles in background (dark) mode.
- **Used in**: `Z_ROLE_01_CREATE_MASTER`, `Z_ROLE_02_CREATE_DERIVE`, `Z_ROLE_03A_UPDATE_ORG`, `Z_ROLE_03B_UPDATE_OBJECT`, `Z_AUTH_SU53_ANALYZER`.

### `PRGN_CHECK_PROFILE_STATUS`
- **Function Group**: `PRGN_PFCG`
- **Purpose**: Evaluates whether a role's profile status LED is Green (`OK`), Yellow (`Warning`), or Red (`Error`).
- **Used in**: `Z_ROLE_03A_UPDATE_ORG`, `Z_ROLE_03B_UPDATE_OBJECT`, `Z_AUTH_SU53_ANALYZER`.

---

## 5. User Administration APIs (SU01)

### `BAPI_USER_CREATE1` & `BAPI_USER_CHANGE`
- **Function Group**: `SU01`
- **Purpose**: Creates or updates SAP user accounts, address data, logon data, and defaults.
- **Used in**: `Z_USER_01_CREATE`.

### `BAPI_USER_ACTGROUPS_ASSIGN`
- **Function Group**: `SU01`
- **Purpose**: Assigns or modifies roles assigned to a user account.
- **Used in**: `Z_USER_02_ASSIGN_ROLE`.

### `SUSR_GENERATE_PASSWORD`
- **Function Group**: `SUSR`
- **Purpose**: Generates a secure, random initial password matching SAP security policy constraints.
- **Used in**: `Z_USER_01_CREATE`.

### `BAPI_TRANSACTION_COMMIT`
- **Function Group**: `BAPI`
- **Purpose**: Standard transactional commit for BAPI calls.
- **Used in**: `Z_USER_01_CREATE`, `Z_USER_02_ASSIGN_ROLE`.

---

## 6. Summary Usage Matrix across Programs

| Standard API / BAPI | Group | 01 Master | 02 Derive | 03A Org | 03B Obj | 04 Comp | User 01 | User 02 | SU53 |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `BAPI_USER_CREATE1` / `CHANGE` | `SU01` | | | | | | ✅ | | |
| `BAPI_USER_ACTGROUPS_ASSIGN` | `SU01` | | | | | | | ✅ | |
| `SUSR_GENERATE_PASSWORD` | `SUSR` | | | | | | ✅ | | |
| `BAPI_TRANSACTION_COMMIT` | `BAPI` | | | | | | ✅ | ✅ | |
| `PRGN_RFC_CREATE_AGR_MULTIPLE`| `PRGN_RFC` | ✅ | ✅ | | | ✅ | | | |
| `PRGN_RFC_CHANGE_TEXTS` | `PRGN_CATT`| ✅ | ✅ | | | ✅ | | | |
| `PRGN_RFC_CREATE_DERIVATION` | `PRGN_CATT`| | ✅ | | | | | | |
| `PRGN_STRU_SAVE_DEFINITION` | `PRGN_STRUCTURE` | | ✅ | | | | | | |
| `PRGN_RFC_ADD_ACTGROUPS` | `PRGN_RFC` | | | | | ✅ | | | |
| `PRGN_1250_READ`/`SAVE` | `PRGN_PFCG`| | | | | | | | ✅ |
| `PRGN_1251_READ`/`SAVE` | `PRGN_PFCG`| | | ✅ | ✅ | | | | ✅ |
| `PRGN_1252_READ`/`SAVE` | `PRGN_PFCG`| ✅ | | ✅ | | | | | ✅ |
| `PRGN_UPDATE_DATABASE` | `PRGN_PFCG`| ✅ | ✅ | ✅ | ✅ | | | | ✅ |
| `SUPRN_DARK_MANIPULATE_PROFILE`| `SUPRN` | ✅ | ✅ | ✅ | ✅ | | | | ✅ |
| `PRGN_CHECK_PROFILE_STATUS` | `PRGN_PFCG`| | | ✅ | ✅ | | | | ✅ |
| `PRGN_SET_ACTGROUP_TIMESTAMP`| `PRGN_CATT`| ✅ | ✅ | ✅ | ✅ | | | | ✅ |
