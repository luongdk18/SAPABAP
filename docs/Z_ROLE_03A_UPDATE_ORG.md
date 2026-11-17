# 🏢 Z_ROLE_03A_UPDATE_ORG: Batch Organizational Levels Maintenance

> **Source Code**: [`src/z_role_03a_update_org.prog.abap`](../src/z_role_03a_update_org.prog.abap)  
> **Companion Script**: [`scripts/convert_role_03_org_obj.py`](../scripts/convert_role_03_org_obj.py)  
> **Org Levels Reference**: [`excel-templates/Org_Levels.csv`](../excel-templates/Org_Levels.csv)  
> **Sample CSV**: [`excel-templates/converted/Template_Role_03a_Org_Levels_converted.csv`](../excel-templates/converted/Template_Role_03a_Org_Levels_converted.csv)

Automates the mass maintenance and update of **Organizational Levels** (`AGR_1252`) across Single and Derived Roles directly from flat CSV data, restores variable bindings in `AGR_1251`, and regenerates authorization profiles in background mode.

---

## 📌 Workflow

```
[ Input CSV: Role Name, Org Variable ($VARBL), Org Value-Low, Org Value-High ]
            │
            ▼  Upload via GUI_UPLOAD (UTF-8)
[ Validate Role Existence in AGR_DEFINE ]
            │
    ┌───────┴────────────────────────┐
    ▼ (Role Exists in SAP)           ▼ (Role Does Not Exist)
[ Process Org Level Updates ]        [ Report Error: @0A@ [ERR] ]
    │
    ├─► Restore Variable Bindings in AGR_1251 (p_fix51 = 'X')
    ├─► Save Org Values to AGR_1252 (PRGN_1252_SAVE_ORG_LEVELS)
    ├─► Default Unlisted Org Levels to '*' (p_astnon = 'X')
    ├─► Dark Profile Generation (SUPRN_DARK_MANIPULATE_PROFILE)
    ├─► Status Verification (PRGN_CHECK_PROFILE_STATUS)
    │     ├─► Green  ➔ @08@ [OK]
    │     ├─► Yellow ➔ @09@ [WARN]
    │     └─► Red    ➔ @0A@ [ERR]
            │
            ▼
[ Interactive ALV Cockpit with Hotspot Jump to PFCG ]
```

---

## ⚙️ Key Technical Features

1. **Automatic Variable Normalization**: Supports variable formats like `$BUKRS`, `$WERKS`, or auto-prefixes missing `$` signs.
2. **Variable Binding Restoration (`p_fix51 = 'X'`)**: Restores corrupted literal strings (such as `'-1'`) or mistakenly manual fields (`MODIFIED = 'U'`) in `AGR_1251` back to their dynamic Org Variable pointers (e.g. `$BUKRS`) with Standard status (`MODIFIED = 'S'`, `NEU = 'O'`), and restores `AGR_1250` authorization headers to Standard (`MODIFIED = 'S'`) using standard FMs `PRGN_1251_READ_FIELD_VALUES`, `PRGN_1251_SAVE_FIELD_VALUES`, `PRGN_1250_READ_AUTH_DATA`, and `PRGN_1250_SAVE_AUTH_DATA`.
3. **Guaranteed Green Status (`p_astnon = 'X'`)**: Defaults secondary unmaintained Org Levels to `'*'` so profiles compile cleanly without yellow/red authorization warnings.
4. **Standard Database Persistence**: Utilizes standard SAP function `PRGN_1252_SAVE_ORG_LEVELS` to guarantee data integrity across cluster tables.
5. **Dark Profile Compilation**: Compiles profiles in the background and verifies the resulting traffic light status using `PRGN_CHECK_PROFILE_STATUS`.

---

## 🎛️ Selection Screen

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `p_file` | `localfile` | Mandatory | Path to normalized CSV file |
| `p_test` | `checkbox` | `'X'` | Simulation mode (test run without updating database) |
| `p_genprf`| `checkbox` | `'X'` | Automatically regenerate authorization profiles |
| `p_sync` | `checkbox` | `'X'` | **Sync Mode**: Reset unlisted Org Levels to template (`-1`) or wildcard (`*`) |
| `p_astnon`| `checkbox` | `'X'` | Default unlisted Org Levels to `'*'` (Guaranteed Green) |
| `p_fix51` | `checkbox` | `'X'` | Heal/restore corrupted Org Variable bindings in `AGR_1251` |

---

## 📊 Status Codes in ALV & Excel

| Status Code | GUI Display | Meaning | Action Taken |
| :--- | :--- | :--- | :--- |
| **`@08@ [OK]`** | Green LED | Org Levels updated and profile compiled successfully (Green status) | `UPDATED` / `UP-TO-DATE` / `SIMULATE` |
| **`@09@ [WARN]`** | Yellow LED | Profile compiled with Yellow status (minor open auth warning) | `UPDATED` |
| **`@0A@ [ERR]`** | Red LED | Role does not exist in SAP or profile compilation failed (Red status) | `ERROR` / `WARNING` |

---

## 🔧 SAP Function Modules Used

- `PRGN_1252_SAVE_ORG_LEVELS`: Saves organizational level values into `AGR_1252`.
- `SUPRN_DARK_MANIPULATE_PROFILE`: Rebuilds auth data and compiles profile in dark mode.
- `PRGN_CHECK_PROFILE_STATUS`: Verifies profile traffic light LED status (`GREEN`/`YELLOW`/`RED`).

---

## 📊 CSV File Format

```csv
Role,Org_Level,value-low,value-high
Z_FI_PERIOD_CONTROL_1000,$CEERKRS,1000,
Z_FI_PERIOD_CONTROL_1000,$KOKRS,1000,
Z_FI_PERIOD_CONTROL_1000,$BUKRS,1000,
Z_FI_PERIOD_CONTROL_1000,$WERKS,1000,
Z_FI_PERIOD_CONTROL_1000,$PRCTR,1000*,
Z_FI_JOURNAL_POST_2000,$KOKRS,1000,
Z_FI_JOURNAL_POST_2000,$BUKRS,2000,
Z_FI_JOURNAL_POST_2000,$WERKS,*,
```

---

## 🔧 SAP Function Modules Used

- `PRGN_1252_READ_ORG_LEVELS`: Reads active organizational levels into buffer.
- `PRGN_1252_SAVE_ORG_LEVELS`: Saves maintained Org Levels via standard PFCG engine.
- `PRGN_1251_READ_FIELD_VALUES` & `PRGN_1251_SAVE_FIELD_VALUES`: Restores Org variable references in authorization fields to Standard status (`p_fix51`).
- `PRGN_1250_READ_AUTH_DATA` & `PRGN_1250_SAVE_AUTH_DATA`: Restores authorization headers in `AGR_1250` to Standard status (`MODIFIED = 'S'`).
- `PRGN_UPDATE_DATABASE`: Flushes PFCG buffers to database with audit change documents.
- `PRGN_SET_ACTGROUP_TIMESTAMP`: Updates role modification timestamp.
- `SUPRN_DARK_MANIPULATE_PROFILE`: Recompiles authorization profile in dark mode.
- `PRGN_CHECK_PROFILE_STATUS`: Verifies resulting profile LED indicator.

---

## 🚀 Deployment

```bash
npm run deploy:role:03a
# or deploy both 03a and 03b together:
npm run deploy:role:03
```
