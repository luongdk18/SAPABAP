# 🛡️ Z_ROLE_03C_UPDATE_ACTIVITY: Batch Authorization Activity Maintenance

> **Source Code**: [`src/z_role_03c_update_activity.prog.abap`](../src/z_role_03c_update_activity.prog.abap)  
> **Target Objects**: Authorization Activity Fields (`ACTVT`, `PS_ACTVT`, etc.)  
> **Deployment Command**: `npm run deploy:role:03c`

Automates the mass maintenance and update of **Activity fields** (`ACTVT`, `PS_ACTVT`) across Single and Derived Roles directly from flat CSV data, preserving all other authorization fields and automatically regenerating authorization profiles.

---

## 📌 Workflow

```
[ Input CSV: Role Name, Field, Value-Low, Value-High ]
            │
            ▼  Upload via GUI_UPLOAD (UTF-8)
[ Validate Role Existence in AGR_DEFINE ]
            │
    ┌───────┴────────────────────────┐
    ▼ (Role Exists in SAP)           ▼ (Role Does Not Exist)
[ Read Auth Objects & Fields via     [ Report Error: @0A@ [ERR] ]
  PRGN_1251_READ_FIELD_VALUES ]
    │
    ├─► If OBJECT does NOT contain target field (e.g., ACTVT) ──► KEPT UNTOUCHED
    │
    ├─► All other authorization fields (BUKRS, WERKS, etc.)   ──► STRICTLY PRESERVED
    │
    └─► If OBJECT contains target field:
          ├─► Compare current activity value(s)
          ├─► Update matching field values via PRGN_1251_SAVE_FIELD_VALUES
          ├─► Flush changes with PRGN_UPDATE_DATABASE
          ├─► Set Role Timestamp (PRGN_SET_ACTGROUP_TIMESTAMP)
          ├─► Dark Profile Generation (SUPRN_DARK_MANIPULATE_PROFILE)
          └─► Status Verification (PRGN_CHECK_PROFILE_STATUS)
                ├─► Green  ➔ @08@ [OK]
                ├─► Yellow ➔ @09@ [WARN]
                └─► Red    ➔ @0A@ [ERR]
            │
            ▼
[ Interactive ALV Cockpit with Hotspot Jump to PFCG ]
```

---

## ⚙️ Key Technical Features

1. **Selective Field Targeting**:
   - Scans all authorization objects and authorizations (`AUTH`) in each role.
   - Only updates the specified activity field (e.g., `ACTVT`, `PS_ACTVT`).
   - If an object in the role does not contain the target field, it remains completely untouched.
2. **Preservation of Organizational and Business Data**:
   - Non-target authorization fields (e.g., `BUKRS`, `WERKS`, `KOSTL`, `AUFART`) under the same object are strictly preserved.
3. **100% SAP Standard API Compliance**:
   - Zero direct database modifications.
   - Saves updates via `PRGN_1251_SAVE_FIELD_VALUES` and commits via `PRGN_UPDATE_DATABASE`.
4. **Dark Profile Compilation**:
   - Automatically compiles and generates authorization profiles in background mode (`SUPRN_DARK_MANIPULATE_PROFILE`).
5. **Interactive ALV Grid**:
   - Displays detailed status reporting:
     - `Objects Scanned`: Total objects checked in role.
     - `Objects with Field`: Number of objects containing the target activity field.
     - `Objects Updated`: Number of objects whose activity values were changed.
     - `New Values`: Summary string of applied activities (e.g., `03`, `08`, `F4`, `*`).
     - `Updated Objects`: Itemized list of modified objects (e.g., `F_BKPF_BUK`, `F_BKPF_KOA`).
     - Single-click hotspot drill-down to transaction `PFCG`.

---

## 🎛️ Selection Screen

| Parameter | Type | Default | Description |
| :--- | :---: | :---: | :--- |
| `p_file` | File Path | - | Path to input CSV file (`..._03c_Activity_converted.csv`) |
| `rb_sync` | Radio | `'X'` | **Two-Way Synchronize (Replace Activity Values with CSV)** |
| `rb_app` | Radio | `' '` | **Append Only (Add New Activities, Keep Existing Activities)** |
| `p_test` | Checkbox | `'X'` | Simulation mode: parses file and validates against SAP data without modifying database |
| `p_genprf` | Checkbox | `'X'` | Automatically regenerate authorization profiles upon successful update |

---

## 📊 CSV File Format

Standard 4-column format:
```csv
Role Name,Field,Value-Low,Value-High
Z_FI_GL_MASTER_MAINT_1000,ACTVT,03,
Z_FI_GL_MASTER_MAINT_1000,ACTVT,08,
Z_FI_GL_MASTER_MAINT_1000,ACTVT,F4,
Z_PS_PROJECT_MAINT_1000,PS_ACTVT,*,
```

Column definitions:
1. **Col 1 (Role Name)**: Target Single or Derived Role in SAP.
2. **Col 2 (Field)**: Target Activity field name (`ACTVT`, `PS_ACTVT`).
3. **Col 3 (Value-Low)**: Activity value (e.g., `01` Create, `02` Change, `03` Display, `08` Display Change Docs, `*` All).
4. **Col 4 (Value-High)**: Optional high value for ranges.

---

## 🔧 SAP Function Modules Used

- `PRGN_1251_READ_FIELD_VALUES`: Reads active authorization fields into internal buffer.
- `PRGN_1251_SAVE_FIELD_VALUES`: Updates modified fields via standard PFCG engine.
- `PRGN_UPDATE_DATABASE`: Flushes PFCG buffers to database with audit change documents.
- `PRGN_SET_ACTGROUP_TIMESTAMP`: Updates role modification timestamp.
- `SUPRN_DARK_MANIPULATE_PROFILE`: Recompiles authorization profile in dark mode.
- `PRGN_CHECK_PROFILE_STATUS`: Verifies resulting profile LED indicator.
