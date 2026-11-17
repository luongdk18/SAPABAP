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
[ Read Current Direct Roles in AGR_USERS ] [ Report Error: @0A@ [ERR] ]
    │
    ├─► Two-Way Synchronize Mode (rb_sync = 'X'):
    │     - Detect Roles to Add (in CSV, not in SAP)
    │     - Detect Roles to Remove (in SAP, not in CSV)
    │     - Detect Roles to Keep (in both, refresh validity)
    │     - Handles N/A (removes all direct roles if desired)
    │
    ├─► Append Mode (rb_app = 'X'): Preserve all existing, append new
    │
    ├─► Simulation Mode (p_test = 'X'): Compute & display full diff without DB commit
    │
    ├─► Execute BAPI_USER_ACTGROUPS_ASSIGN & BAPI_TRANSACTION_COMMIT
    │     ├─► Up-to-date (no changes needed) ➔ @08@ [OK] / UP-TO-DATE
    │     ├─► Synchronized / Appended        ➔ @08@ [OK] / SYNCHRONIZED
    │     └─► Partial (some roles missing)   ➔ @09@ [WARN]
            │
            ▼
[ Interactive ALV Cockpit with One-Click SU01 Hotspot Jump ]
```

---

## ⚙️ Key Technical Features

1. **Two-Way Synchronization (`rb_sync = 'X'`)**: Performs automated diff comparison between existing roles in `AGR_USERS` and incoming CSV records:
   - **Adds Missing Roles**: assigns newly granted roles.
   - **Removes Surplus Roles**: safely revokes direct roles not listed in the CSV.
   - **Retains Existing Roles**: keeps matching roles and refreshes validity period.
2. **Safe Append Mode (`rb_app = 'X'`)**: Preserves all existing roles and only appends new valid roles from CSV.
3. **Missing Role Isolation**: If specific roles are missing from `AGR_DEFINE`, valid roles are still processed, while missing roles are reported in `Missing Roles` with `@09@ [WARN]`.
4. **Empty Role Support (`N/A`)**: Gracefully handles placeholder records. In Synchronize mode, assigning `N/A` cleanly revokes all direct roles for that user.
5. **Interactive Navigation**: Clickable hotspot on the Username column opens transaction `SU01` directly.
6. **Detailed ALV Audit Cockpit**: Displays granular diff columns: `Roles Added (Count & List)`, `Roles Removed (Count & List)`, `Roles Retained (Count & List)`, and `Active Roles in SAP`.

---

## 🎛️ Selection Screen

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `p_file` | `localfile` | Mandatory | Path to normalized CSV file |
| `p_test` | `checkbox` | `'X'` | Simulation mode (test run without writing to DB) |
| `p_chkrol` | `checkbox` | `'X'` | Validate role existence against table `AGR_DEFINE` |
| `rb_sync` | `radiobutton` | `'X'` | **Two-Way Synchronize**: Add missing roles and remove surplus roles |
| `rb_app` | `radiobutton` | `' '` | **Append Only**: Preserve all existing roles, only add new roles |
| `p_from` | `date` | `sy-datum`| Assignment valid-from date |
| `p_to` | `date` | `'99991231'`| Assignment valid-to date |

---

## 📊 Status Codes in ALV & Excel

| Status Code | GUI Display | Meaning | Action Taken |
| :--- | :--- | :--- | :--- |
| **`@08@ [OK]`** | Green LED | Roles synchronized, appended, or simulated successfully | `SYNCHRONIZED` / `APPENDED` / `SIMULATED` / `UP-TO-DATE` |
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
