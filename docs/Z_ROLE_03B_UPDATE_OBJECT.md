# 🛡️ Z_ROLE_03B_UPDATE_OBJECT: Batch Authorization Objects Maintenance

> **Source Code**: [`src/z_role_03b_update_object.prog.abap`](../src/z_role_03b_update_object.prog.abap)  
> **Companion Script**: [`scripts/convert_role_03_org_obj.py`](../scripts/convert_role_03_org_obj.py)  
> **Sample CSV**: [`excel-templates/converted/Template_Role_03b_Auth_Objects_converted.csv`](../excel-templates/converted/Template_Role_03b_Auth_Objects_converted.csv)

Automates the mass maintenance and update of **Authorization Objects & Fields** (`AGR_1251`) across Single and Derived Roles directly from flat CSV data, enforcing strict validation against unauthorized object injection and automatically regenerating authorization profiles.

---

## 📌 Workflow

```
[ Input CSV: Role Name, Object-Field (OBJECT-FIELD), Value-Low, Value-High ]
            │
            ▼  Upload via GUI_UPLOAD (UTF-8)
[ Validate Role Existence in AGR_DEFINE ]
            │
    ┌───────┴────────────────────────┐
    ▼ (Role Exists in SAP)           ▼ (Role Does Not Exist)
[ Validate Objects in AGR_1250 ]     [ Report Error: @0A@ [ERR] ]
    │
    ├─► If OBJECT does NOT exist in Role ──► SKIP (Do NOT add foreign objects!)
    │
    ├─► If FIELD does NOT exist in Object ─► SKIP
    │
    └─► If OBJECT & FIELD Exist in Role:
          ├─► Compare current value via PRGN_1251_READ_FIELD_VALUES
          ├─► Save updated LOW / HIGH via PRGN_1251_SAVE_FIELD_VALUES & PRGN_UPDATE_DATABASE
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

1. **Strict Object Existence Enforcement (Zero Injection)**:
   - Evaluates each row against the role's actual `AGR_1250` and `AGR_1251` data in SAP.
   - If an object or field from the CSV is not currently part of the role's business scope/transactions, it is **strictly skipped** and never injected into the role.
2. **Dual-Value Support (Low & High Values)**:
   - Standard 4-column CSV format: `Role,object-field,value-low,value-high`.
   - Accommodates single values (where `value-high` is empty) and explicit intervals/ranges (`value-low` and `value-high`).
   - Backwards compatible with 3-column CSV (`Role,object-field,value`) where intervals (`LOW - HIGH` or `LOW:HIGH`) are automatically split.
3. **Change Tracking & Audit Readiness**:
   - Updates modified authorization entries with `MODIFIED = 'G'` (Changed/Maintained status) and records timestamp via `PRGN_SET_ACTGROUP_TIMESTAMP`.
4. **Dark Profile Compilation**:
   - Automatically compiles and generates the authorization profile in background mode (`SUPRN_DARK_MANIPULATE_PROFILE`).
5. **Interactive ALV Grid**:
   - Detailed status reporting showing:
     - `Auth File Items`: Total lines in CSV for this role.
     - `Updated Fields`: Number of fields successfully updated.
     - `Skipped Items`: Number of object-fields skipped because they do not belong to the role.
     - `Updated Details` & `Skipped Details`: Explicit itemized summaries.
     - Single-click hotspot drill-down into transaction `PFCG`.

---

## 🎛️ Selection Screen

| Parameter | Type | Default | Description |
| :--- | :---: | :---: | :--- |
| `p_file` | File Path | - | Path to input CSV file (`..._03b_Auth_Objects_converted.csv`) |
| `p_test` | Checkbox | `'X'` | Simulation mode: parses file and validates against SAP data without modifying database |
| `p_genprf` | Checkbox | `'X'` | Automatically regenerate authorization profiles upon successful update |

---

## 📊 CSV File Format

Standard 4-column format:
```csv
Role,object-field,value-low,value-high
DRFI01_PERIOD_CONTROL_1100,F_FAGL_SEG-SEGMENT,*,
DRFI01_PERIOD_CONTROL_1100,F_BUK_BUPL-BUPLA,*,
DRFI01_PERIOD_CONTROL_1100,K_CSKS-KOSTL,1100*,
DRFI01_PERIOD_CONTROL_1100,K_ORDER-AUFART,*,
DRFI01_PERIOD_CONTROL_1100,A_S_ANLKL-ANLKL,*,
DRFI01_PERIOD_CONTROL_1100,F_UKM_SGMT-UKM_SGMNT,*,
DRFI01_PERIOD_CONTROL_1100,K_KEKO-KLVAR,*,
DRPS00_PRJ_STRUC_MAIN_1101_A,C_PROJ_VNR-PS_VERNR,00000000,00000080
```

---

## 🔧 SAP Function Modules Used

- `PRGN_1251_READ_FIELD_VALUES`: Reads active authorization fields into internal buffer.
- `PRGN_1251_SAVE_FIELD_VALUES`: Updates modified fields via standard PFCG engine.
- `PRGN_UPDATE_DATABASE`: Flushes PFCG buffers to database with audit change documents.
- `PRGN_SET_ACTGROUP_TIMESTAMP`: Updates role modification timestamp.
- `SUPRN_DARK_MANIPULATE_PROFILE`: Recompiles authorization profile in dark mode.
- `PRGN_CHECK_PROFILE_STATUS`: Verifies resulting profile LED indicator.

---

## 🚀 Deployment

```bash
npm run deploy:role:03b
# or deploy both 03a and 03b together:
npm run deploy:role:03
```
