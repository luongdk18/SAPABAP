# SAP ABAP Security & Standard Architecture Rules

> **Applies to**: Entire repository (`d:\PROJECTS\SAPABAP`)  
> **Target Systems**: SAP S/4HANA / SAP ECC / SAP NetWeaver  
> **Mandatory Policy**: Strict compliance with SAP Enterprise Architecture and Basis/Security Audit Standards.

---

## 🚫 1. STRICT PROHIBITION: Zero Direct Database Updates

Under **NO circumstances** shall any ABAP program or script perform direct OpenSQL modifications (`UPDATE`, `INSERT INTO`, `MODIFY`, `DELETE FROM`) on standard SAP tables.

### Prohibited Standard Tables Include (but are not limited to):
- **Role & Authorization Tables**: `AGR_DEFINE`, `AGR_TEXTS`, `AGR_1250`, `AGR_1251`, `AGR_1252`, `AGR_AGRS`, `AGR_USERS`, `AGR_FLAGS`, `AGR_HIER`, `AGR_TCODES`, `AGR_BUFFI`.
- **User Master Tables**: `USR02`, `USR21`, `UST04`, `USRAUTH`, `USRBF2`, `USR04`.
- **Address & Master Tables**: `ADRP`, `ADCP`, `ADR6`, `DEVCLASS`, `TSTC`.

### Why Direct DB Modifications Are Forbidden:
1. **Bypasses Enqueue Locks**: Causes database deadlock and race conditions with concurrent transactions (`PFCG`, `SU01`).
2. **Missing Change Documents**: Fails to trigger `PRGN_CHANGEDOCUMENT_WRITE` or `S_USER_CHG`, violating SOX, ISO 27001, and SAP security compliance audits.
3. **Broken PFCG Consistency**: PFCG internal buffers, timestamp indices, and profile compilation status flags become out-of-sync or corrupted.
4. **Transport Failures**: Direct DB updates bypass automatic recording into Transport Requests (`TRKORR`).

---

## ✅ 2. MANDATORY USE: Standard SAP BAPIs & Function Modules

All business logic involving users, roles, authorizations, organizational levels, and profiles must exclusively use official SAP APIs and Function Modules (primarily from packages `S_PROFGEN`, `S_USER_API`, and `SUSR`).

### Standard API Mapping Matrix

| Business Requirement | Standard Function Module / BAPI | Replaces OpenSQL |
| :--- | :--- | :--- |
| **Role Descriptions & Texts** | `PRGN_RFC_CHANGE_TEXTS` | `UPDATE agr_texts`, `DELETE FROM agr_texts` |
| **Role Inheritance & Definition** | `PRGN_STRU_SAVE_DEFINITION`, `PRGN_RFC_CREATE_DERIVATION` | `UPDATE agr_define SET parent_agr = ...` |
| **Authorization Objects & Fields** | `PRGN_1251_READ_FIELD_VALUES`<br>`PRGN_1251_SAVE_FIELD_VALUES` | `UPDATE agr_1251`, `MODIFY agr_1251` |
| **Organizational Levels** | `PRGN_1252_READ_ORG_LEVELS`<br>`PRGN_1252_SAVE_ORG_LEVELS` | `UPDATE agr_1252 SET low = ...` |
| **Create Single/Composite Roles** | `PRGN_RFC_CREATE_AGR_MULTIPLE` | `INSERT INTO agr_define` |
| **Assign Single Roles to Composite** | `PRGN_RFC_ADD_ACTGROUPS` | `INSERT INTO agr_agrs` |
| **Generate Authorization Profile** | `SUPRN_DARK_MANIPULATE_PROFILE` | Manual profile DB generation |
| **Commit PFCG Changes** | `PRGN_UPDATE_DATABASE` + `COMMIT WORK AND WAIT` | Raw DB commit |
| **Role Timestamp & Invalidation** | `PRGN_SET_ACTGROUP_TIMESTAMP` | Direct timestamp update |
| **User Creation & Maintenance** | `BAPI_USER_CREATE1`, `BAPI_USER_CHANGE` | `INSERT/UPDATE USR02`, `USR21` |
| **User Role Assignment** | `BAPI_USER_ACTGROUPS_ASSIGN` | `INSERT/UPDATE AGR_USERS` |
| **Password Generation** | `SUSR_GENERATE_PASSWORD` | Hardcoded or direct password hash |

---

## 🔒 3. Transaction Lifecycle Best Practices

1. **Locking (Enqueue / Dequeue)**:
   - For role authorization manipulation, enqueue the role using `PRGN_ACTIVITY_GROUP_ENQUEUE` if modifying multiple structures.
   - **Crucial**: Always call `PRGN_ACTIVITY_GROUP_DEQUEUE` **before** calling `SUPRN_DARK_MANIPULATE_PROFILE` because profile generation manages its own lock lifecycle.
2. **Database Updates**:
   - Always call `PRGN_UPDATE_DATABASE` followed by `COMMIT WORK AND WAIT` after PFCG save FMs (`PRGN_1250_SAVE_AUTH_DATA`, `PRGN_1251_SAVE_FIELD_VALUES`, `PRGN_1252_SAVE_ORG_LEVELS`).
   - For BAPIs (`BAPI_USER_*`), always call `BAPI_TRANSACTION_COMMIT` with `WAIT = 'X'`.
3. **Simulation Mode**:
   - Every program must support `p_test` simulation mode (`p_test = 'X'`), validating all business rules without committing data.
