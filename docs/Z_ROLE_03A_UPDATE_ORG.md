# 🏢 Z_ROLE_03A_UPDATE_ORG: Batch Organizational Levels Maintenance

> **Source Code**: [`src/z_role_03a_update_org.prog.abap`](../src/z_role_03a_update_org.prog.abap)  
> **Companion Script**: [`scripts/convert_role_03_org_obj.py`](../scripts/convert_role_03_org_obj.py)  
> **Org Levels Reference**: [`excel-templates/Org_Levels.csv`](../excel-templates/Org_Levels.csv)  
> **Sample CSV**: [`excel-templates/converted/Template_Role_03a_Org_Levels_converted.csv`](../excel-templates/converted/Template_Role_03a_Org_Levels_converted.csv)

Automates the mass maintenance and update of **Organizational Levels** (`AGR_1252`) across Single and Derived Roles directly from flat CSV data (supporting both **Two-Way Sync** and **Append Only** modes), and integrates the **Repair `$VARBL` Bindings** workflow (formerly `Z_ROLE_03A_UPDATE_ORG_FIX`) to heal broken `AGR_1251`/`AGR_1250` bindings, auto-heal parent Master Roles, and regenerate authorization profiles in dark mode.

---

## 📌 Workflow

```
[ Operation Mode Selection ]
    ├─► Mode 1: Update Org Levels from CSV (rb_m_csv = 'X')
    │     ├─► Two-Way Sync (rb_sync): Replace listed Org Levels with CSV values;
    │     │     unlisted Org Levels -> '*' (if p_astnon = 'X') or '-1'
    │     ├─► Append Only (rb_app): Merge CSV values into existing Org Levels
    │     │     (never deletes existing values); fill empty/'-1' -> '*' if p_astnon = 'X'
    │     ├─► Auto-Heal Parent Master Role & Rebind AGR_1251 -> $VARBL (p_fix51 = 'X')
    │     └─► Dark Profile Generation (SUPRN_DARK_MANIPULATE_PROFILE) & Status Check
    │
    └─► Mode 2: Repair $VARBL Bindings Only (rb_m_fix = 'X', merged from 03A_FIX)
          ├─► Select target roles via Role Select-Option (s_role) and/or CSV file (p_file)
          ├─► Auto-Heal Parent Master Role AGR_1251 -> $VARBL (p_parhea = 'X')
          ├─► Rebind Target Role AGR_1251 -> $VARBL (MODIFIED='S', NEU='O'), fix AGR_1250
          ├─► Preserve existing AGR_1252 values; set empty/'-1' -> '*' on Derived Roles
          └─► Dark Profile Generation & Traffic-Light Verification
            │
            ▼
[ Interactive ALV Cockpit with Hotspot Jump to PFCG ]
```

---

## ⚙️ Key Technical Features

1. **Dual Operation Modes (`rb_m_csv` / `rb_m_fix`)**:
   - **CSV Org Level Maintenance (`rb_m_csv`)**: Mass-update `AGR_1252` from normalized CSV with **Two-Way Sync (`rb_sync`)** or **Append Only (`rb_app`)**.
   - **Repair `$VARBL` Bindings Only (`rb_m_fix`)**: Diagnose and repair roles with Red traffic lights or broken `"Manually"` (`MODIFIED = 'U'`) Org Level bindings directly by `s_role` range or CSV file without altering valid Org Level values.
2. **Automatic Variable Normalization**: Supports `$BUKRS`, `$WERKS`, or auto-prefixes missing `$` signs, and applies SAP ALPHA zero-padding for numeric 10-char Cost Centers (`$KOSTL`) and Profit Centers (`$PRCTR`).
3. **Variable Binding Restoration (`p_fix51 = 'X'`) & Parent Master Auto-Heal (`p_parhea = 'X'`)**: Restores broken literal strings or manual flags on Org Level fields in `AGR_1251` back to `$VARBL` (`MODIFIED = 'S'`, `NEU = 'O'`) and aligns `AGR_1250` headers via standard PFCG FMs (`PRGN_1251_*`, `PRGN_1250_*`).
4. **Guaranteed Green Org Levels (`p_astnon = 'X'`)**: Defaults empty / unmaintained Org Levels (`AGR_1252`) to `'*'` on Derived Roles without wildcarding unrelated non-org authorization fields (`fill_fields_with_star = space`).
5. **Standard Locking & Dark Profile Compilation**: Enforces per-role `S_USER_AGR` authority checks, `PRGN_ACTIVITY_GROUP_ENQUEUE` / `DEQUEUE` lifecycle, `PRGN_1252_SAVE_ORG_LEVELS`, `SUPRN_DARK_MANIPULATE_PROFILE`, and `PRGN_CHECK_PROFILE_STATUS`.

---

## 🎛️ Selection Screen

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `rb_m_csv` | Radio (`MOD`) | `'X'` | Mode 1: Update Org Levels from CSV file |
| `rb_m_fix` | Radio (`MOD`) | `' '` | Mode 2: Repair `$VARBL` bindings only (merged from `03A_FIX`) |
| `p_file` | `localfile` | Optional* | Path to normalized CSV file (mandatory in CSV mode; optional in Repair mode) |
| `s_role` | Select-Option | Optional* | Target Role range (used in Repair `$VARBL` mode) |
| `p_test` | Checkbox | `'X'` | Simulation mode (validates all rules without updating database) |
| `rb_sync` | Radio (`UPD`) | `'X'` | **Two-Way Sync**: Replace listed Org Levels; unlisted -> `'*'` (`p_astnon`) or `'-1'` |
| `rb_app` | Radio (`UPD`) | `' '` | **Append Only**: Merge CSV values into existing Org Levels without deleting existing values |
| `p_genprf` | Checkbox | `'X'` | Automatically regenerate authorization profiles |
| `p_astnon` | Checkbox | `'X'` | Default unmaintained/empty Org Levels to `'*'` |
| `p_fix51` | Checkbox | `'X'` | Heal/restore corrupted Org Variable bindings in `AGR_1251` |
| `p_parhea` | Checkbox | `'X'` | Auto-heal parent Master Role `$VARBL` bindings before fixing Derived Roles |

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
