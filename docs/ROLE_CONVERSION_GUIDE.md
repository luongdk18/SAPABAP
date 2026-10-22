# 🔄 Preprocessing Excel Matrices to CSV for ABAP Automation

> Complete guide on converting business authorization and user matrices from Excel (`.xlsx`) to normalized CSV format ready for SAP batch upload.

---

## 📌 Pipeline Overview

```
[ Excel Business Matrices ]
(excel-working/*.xlsx or excel-templates/*.xlsx)
            │
            ▼  python scripts/convert_*.py (or npm run convert:all)
[ Normalized Flat CSV Files ]
(excel-working/converted/*.csv or excel-templates/converted/*.csv)
            │
            ▼  SAP GUI Upload (GUI_UPLOAD / UTF-8 with BOM)
[ Modular ABAP Utilities ]
(Z_ROLE_01..04, Z_USER_01..02 Cockpits)
```

### Universal Rules across all Converters
1. **Indicator Flags**: Case-insensitive `Y`, `y`, `X`, `x` mark assignments.
2. **Output Location**: Saved into `<parent_dir>/converted/<stem>_converted.csv`.
3. **Encoding**: UTF-8 with BOM (`utf-8-sig`) for native SAP GUI diacritic support (Vietnamese accents).
4. **Data Isolation**: Files in `excel-working/` and `excel-working/converted/` are protected by `.gitignore`.

---

## 🚀 Quick Execution via npm

| Command | Executes | Input Candidate Priority |
| :--- | :--- | :--- |
| `npm run convert:role:01` | `convert_role_01_master.py` | `excel-working/*_Role.xlsx` (Sheet 1) ➔ `excel-templates/` |
| `npm run convert:role:02` | `convert_role_02_derive.py` | `excel-working/*_Role.xlsx` (Sheet 2) ➔ `excel-templates/` |
| `npm run convert:role:03` | `convert_role_03_org_obj.py`| `excel-working/*_Role.xlsx` (Sheet 2) ➔ `excel-templates/` |
| `npm run convert:role:04` | `convert_role_04_composite.py` | `excel-working/*_Role.xlsx` (Sheet 3) ➔ `excel-templates/` |
| `npm run convert:role:all` | *All 4 Role Converters* | All role matrices in working directory |
| `npm run convert:user:01` | `convert_user_01_create.py` | `excel-working/User_01_Create.xlsx` ➔ `excel-templates/` |
| `npm run convert:user:02` | `convert_user_02_assign.py` | `excel-working/User_02_Assign.xlsx` ➔ `excel-templates/` |
| `npm run convert:user:all` | *Both User Converters* | All user matrices in working directory |
| `npm run convert:all` | *All 6 Converters* | Complete batch preprocessing |
| `npm run templates:generate` | `create_templates.py` | Regenerates sample files in `excel-templates/converted/` |

---

## 1. Master Roles (`convert_role_01_master.py`)

- **Input**: Matrix with Roles in columns (Row 1: Description, Row 2: Role Name) and TCodes in rows.
- **Dynamic Detection**: Automatically scans row 3+ to identify the TCode column (handles column shifts between FICO, PS, MM) and finds role columns.
- **Empty Roles**: Roles without `X`/`Y` flags are assigned `TCode = 'N/A'`.
- **Target ABAP**: `Z_ROLE_01_CREATE_MASTER`
- **Output CSV Columns**:
  ```csv
  Role Name,Role Description,TCode
  Z_FI_PERIOD_CONTROL,GL Period Control,OB52
  Z_FI_GL_REPORTS_EMPTY,Custom Reporting (No TCodes),N/A
  ```

---

## 2. Derived Roles Mapping (`convert_role_02_derive.py`)

- **Input**: Tabular list with Master Role, Derived Role, and Derived Role Description.
- **Header Matching**: Automatically matches columns containing `master`/`leading`/`parent`, `derive`, and `desc`.
- **Target ABAP**: `Z_ROLE_02_CREATE_DERIVE`
- **Output CSV Columns**:
  ```csv
  Master Role,Derived Role,Derived Role Description
  Z_FI_MASTER_GL,Z_FI_DRV_GL_1000,GL Accounting - Company Code 1000
  ```

---

## 3. Organizational Levels & Authorization Objects (`convert_role_03_org_obj.py`)

Reads Sheet 2 of the consolidated role workbook (where Derived Roles and mixed Org / Object columns reside) and automatically splits them into **two strictly complementary, non-overlapping flat CSV files**:

### 3a. Organizational Levels (`*_03a_Org_Levels_converted.csv`)
- **Purpose**: Batch maintenance of SAP Organizational Level variables in table `AGR_1252` via report `Z_ROLE_03_UPDATE_ORG`.
- **Classification**: Matches against standard SAP 55 Org Level definitions in [`excel-templates/Org_Levels.csv`](../excel-templates/Org_Levels.csv) (e.g., Company Code ➔ `$BUKRS`, Plant ➔ `$WERKS`, Controlling Area ➔ `$KOKRS`, Purchasing Org ➔ `$EKORG`).
- **Target ABAP**: `Z_ROLE_03_UPDATE_ORG`
- **Output CSV Format** (4 columns: `Role,Org_Level,value-low,value-high`):
  ```csv
  Role,Org_Level,value-low,value-high
  Z_FI_DRV_GL_1000,$BUKRS,1000,
  Z_FI_DRV_GL_1000,$KOKRS,1000,
  ```

### 3b. Authorization Objects & Fields (`*_03b_Auth_Objects_converted.csv`)
- **Purpose**: Batch maintenance of authorization objects & fields in table `AGR_1251` (e.g., Cost Center, Order Type, Asset Class, Segment, Business Place, Credit Segment, Costing Variant, Release Group/Code).
- **Classification**: Resolves non-Org headers against [`excel-templates/Object_Levels.csv`](../excel-templates/Object_Levels.csv) (13,457 SAP standard object-field pairs). Supports multi-object expansion (e.g. Person Responsible in `C_PROJ_VNR` & `C_PRPS_VNR`).
- **Strict Boundary**: If a field belongs to Org Levels (e.g. `BUKRS`), it is NEVER output here. TCode checks (`S_TCODE-TCD`) are excluded (maintained via Menu).
- **Value Parsing & Data Integrity**: Single values have empty `value-high`. Ranges (`LOW - HIGH`, `00000000-00000080`) and pairs (`00000000; 00000080`) are placed in `value-low` and `value-high` on a single row, strictly preserving leading zeros.
- **Output CSV Format** (4 columns: `Role,object-field,value-low,value-high`):
  ```csv
  Role,object-field,value-low,value-high
  Z_FI_PERIOD_CONTROL_1000,F_FAGL_SEG-SEGMENT,*,
  Z_FI_PERIOD_CONTROL_1000,K_CSKS-KOSTL,1100*,
  DRPS00_PRJ_STRUC_MAIN_1101_A,C_PROJ_VNR-PS_VERNR,00000000,00000080
  ```

---

## 4. Composite Roles (`convert_role_04_composite.py`)

- **Input**: Matrix with Composite Roles in columns (Row 1: Description, Row 2: Composite Role ID) and Member Single Roles in Column 1.
- **Empty Composite Roles**: Roles with no assigned members produce a row with `Derived Role = 'N/A'`.
- **Target ABAP**: `Z_ROLE_04_COMPOSITE`
- **Output CSV Columns**:
  ```csv
  Composite Role Name,Composite Role Description,Derived Role
  CR_FI_ACCOUNTANT_1000,Chief Accountant - Entity 1000,Z_FI_DRV_GL_1000
  CR_FI_EMPTY_ROLE,Placeholder Role Without Members,N/A
  ```

---

## 5. User Creation (`convert_user_01_create.py`)

- **Input**: User roster containing Full Name, Email, Phone, Department, Function.
- **Key Transformations**:
  - **Username**: Extracted from Email prefix before `@` (uppercase, max 12 chars).
  - **Password**: Cryptographically secure 12-character SAP-compliant password (`A-Z`, `a-z`, `0-9`, special chars).
  - **Phone Number**: Normalized to `(<CountryCode>)<Number>` **without `+` sign** (e.g. `(84)981234567`) for native SAP compatibility.
  - **Full Name**: Cleaned for direct mapping into `BAPIADDR3-LASTNAME`.
- **Target ABAP**: `Z_USER_01_CREATE`
- **Output CSV Columns**:
  ```csv
  Username,Initial Password,Full Name,Email,Phone No.,Department,Function
  JOHND,N8l0%GO_UVkK,John Doe,johnd@company.com,(84)981234567,Finance,Finance Manager
  ```

---

## 6. User Role Assignment (`convert_user_02_assign.py`)

- **Input**: Assignment matrix with Usernames in Column 1 and Roles in Row 1.
- **Filtering**: Extracts all cells marked with `Y`, `y`, `X`, `x` into flat row pairs.
- **Empty Users**: Users without any role assignments produce `Role = 'N/A'`.
- **Target ABAP**: `Z_USER_02_ASSIGN_ROLE`
- **Output CSV Columns**:
  ```csv
  Username,Role
  JOHND,CR_FI_ACCOUNTANT_1000
  JOHND,CR_COMMON
  EMPTY_USER,N/A
  ```
