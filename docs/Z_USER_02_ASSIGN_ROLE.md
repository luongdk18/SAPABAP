# 👥 Z_USER_02_ASSIGN_ROLE: Batch User Role Assignment Cockpit

> **Source Code**: [`src/z_user_02_assign_role.prog.abap`](../src/z_user_02_assign_role.prog.abap)  
> **Companion Script**: [`scripts/convert_user_02_assign.py`](../scripts/convert_user_02_assign.py)  
> **Sample CSV**: [`excel-templates/converted/Template_User_02_Assign_converted.csv`](../excel-templates/converted/Template_User_02_Assign_converted.csv)

Automates the mass assignment of SAP authorization roles (Single, Derived, and Composite Roles) to user master records directly from flat CSV data.

---

## 📌 Workflow

```
[ Input CSV: Username, Role ]
            │
            ▼  Upload via GUI_UPLOAD (UTF-8)
[ Group Roles by Username & Validate in USR02 / AGR_DEFINE ]
            │
    ┌───────┴────────────────────────┐
    ▼ (User Exists in USR02)         ▼ (User Does Not Exist)
[ Prepare Role Assignment Buffer ]   [ Report Error: @0A@ [ERR] ]
    │
    ├─► Safe Append Mode (p_append = 'X'): Preserve existing roles
    ├─► Check Role Existence in AGR_DEFINE (p_chkrol = 'X')
    ├─► Isolate missing roles to Warning column
    ├─► Execute BAPI_USER_ACTGROUPS_ASSIGN & BAPI_TRANSACTION_COMMIT
    │     ├─► Success without missing roles ➔ @08@ [OK]
    │     └─► Partial (some roles missing)   ➔ @09@ [WARN]
            │
            ▼
[ Interactive ALV Cockpit with One-Click SU01 Hotspot Jump ]
```

---

## ⚙️ Key Technical Features

1. **Atomic Multi-Role Assignments**: Groups multiple role lines per user and assigns them in a single call to `BAPI_USER_ACTGROUPS_ASSIGN`.
2. **Safe Append Mode (`p_append = 'X'`)**: Preserves pre-existing user authorizations by fetching current roles from table `AGR_USERS` and appending only new assignments.
3. **Missing Role Isolation**: If specific roles are missing from `AGR_DEFINE`, valid roles are still assigned, while missing roles are listed in a separate column with `@09@ [WARN]`.
4. **Empty Role Support (`N/A`)**: Gracefully handles placeholder records without generating errors.
5. **Interactive Navigation**: Clickable hotspot on the Username column opens transaction `SU01` directly.

---

## 🎛️ Selection Screen

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `p_file` | `localfile` | Mandatory | Path to normalized CSV file |
| `p_test` | `checkbox` | `'X'` | Simulation mode (test run without writing to DB) |
| `p_append` | `checkbox` | `'X'` | Safe Append Mode (preserves pre-existing user roles) |
| `p_chkrol` | `checkbox` | `'X'` | Validate role existence against table `AGR_DEFINE` |
| `p_from` | `date` | `sy-datum`| Assignment valid-from date |
| `p_to` | `date` | `'99991231'`| Assignment valid-to date |

---

## 📊 Status Codes in ALV & Excel

| Status Code | GUI Display | Meaning | Action Taken |
| :--- | :--- | :--- | :--- |
| **`@08@ [OK]`** | Green LED | Roles assigned or simulated successfully | `ASSIGNED` / `SIMULATED` |
| **`@09@ [WARN]`** | Yellow LED | Some roles missing from SAP or user has no roles (`N/A`) | `WARNING` |
| **`@0A@ [ERR]`** | Red LED | User does not exist in `USR02`, all roles invalid, or BAPI error | `ERROR` |

---

## 🔧 SAP Function Modules Used

- `BAPI_USER_ACTGROUPS_ASSIGN`: Assigns roles to user master record.
- `BAPI_TRANSACTION_COMMIT`: Commits database updates.

---

## 🚀 Deployment

```bash
npm run deploy:user:02
```
