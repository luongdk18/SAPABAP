# 🔄 Guide: Preprocessing Excel Files to CSV for ABAP Role Automation

> **SAP Role Lifecycle Automation Toolset**  
> **Repository**: [https://github.com/luongdk18/SAPABAP](https://github.com/luongdk18/SAPABAP)

This guide explains how to prepare business authorization matrices in Excel and convert them into flat, standardized CSV files ready for direct import into the ABAP utilities:
1. **Master Roles**: `convert_role_master_excel.py` ➔ Import into **`Z_AUTH_ROLE_CREATE`**
2. **Derived Roles Mapping**: `convert_role_derived_excel.py` ➔ Import into **`Z_AUTH_ROLE_DERIVE`**
3. **Organizational Levels**: `convert_role_org_excel.py` ➔ Import into **`Z_AUTH_ROLE_UPDATE_ORG`**
4. **Composite Roles**: `convert_role_composite_excel.py` ➔ Import into **`Z_AUTH_ROLE_COMPOSITE`**

---

## 📌 Architecture & Conversion Pipeline

```mermaid
flowchart TD
    subgraph S1["1. Master Roles Matrix"]
        A1["Template_Roles_Master.xlsx\n(Row 1: Desc, Row 2: Role, Col 1: TCodes)"] --> B1["convert_role_master_excel.py\n(or npm run convert:role:master)"]
        B1 --> C1["Template_Roles_Master_converted.csv\n(Role Name, Role Desc, TCode)"]
        C1 --> D1["ABAP Program: Z_AUTH_ROLE_CREATE\nCreates Master Roles & PFCG Menus"]
    end

    subgraph S2["2. Derived Roles Mapping"]
        A2["Template_Roles_Derived.xlsx\n(Master Role, Derived Role, Description)"] --> B2["convert_role_derived_excel.py\n(or npm run convert:role:derived)"]
        B2 --> C2["Template_Roles_Derived_converted.csv\n(Master Role, Derived Role, Description)"]
        C2 --> D2["ABAP Program: Z_AUTH_ROLE_DERIVE\nCreates Derived Roles & Links PARENT_AGR"]
    end

    subgraph S3["3. Organizational Levels Matrix"]
        A3["Template_Roles_Derived_Org.xlsx\n(Roles in rows, Org Levels in columns)"] --> B3["convert_role_org_excel.py\n(References Org_Levels.csv)"]
        B3 --> C3["Template_Roles_Derived_Org_converted.csv\n(Role Name, Org Variable, Org Value)"]
        C3 --> D3["ABAP Program: Z_AUTH_ROLE_UPDATE_ORG\nPopulates AGR_1252 & Generates Profiles"]
    end

    subgraph S4["4. Composite Roles Matrix"]
        A4["Template_Roles_Composite.xlsx\n(Row 1: Desc, Row 2: Role, Col 1: Derived Roles)"] --> B4["convert_role_composite_excel.py\n(or npm run convert:role:composite)"]
        B4 --> C4["Template_Roles_Composite_converted.csv\n(Composite Role, Description, Derived Role)"]
        C4 --> D4["ABAP Program: Z_AUTH_ROLE_COMPOSITE\nCreates Composite Roles & Assigns Single Roles"]
    end
```

---

## 🚀 Quick Execution via npm Shortcuts

Convenient npm commands are preconfigured in `package.json`:

```bash
# 1. Convert Master Role Matrix
npm run convert:role:master

# 2. Convert Derived Roles Creation Mapping
npm run convert:role:derived

# 3. Convert Derived Role Organizational Levels
npm run convert:role:org

# 4. Convert Composite Roles Matrix
npm run convert:role:composite
```

> [!TIP]
> Each script automatically checks for candidate files in `excel-working/`, `excel-templates/`, and the repository root. You can also specify an exact file path as a CLI argument.

---

## 1. Master Roles Preprocessing (`convert_role_master_excel.py`)

### 1.1. Excel Input Format (`Template_Roles_Master.xlsx`)
Business authorization matrices commonly lay out transaction codes along the vertical axis (rows) and functional roles across the horizontal axis (columns):

| TCode / Role Description | GL Period Control | GL Master Data Maintenance | GL Journal Posting | Custom Reporting (No TCodes) |
| :--- | :--- | :--- | :--- | :--- |
| **Role Name** | `Z_FI_PERIOD_CONTROL` | `Z_FI_GL_MASTER_MAINT` | `Z_FI_JOURNAL_POST` | `Z_FI_GL_REPORTS_EMPTY` |
| `OB52` | **Y** | | | |
| `FS00` | | **Y** | | |
| `FB01` | | | **Y** | |
| `FB02` | | | **Y** | |
| `FB03` | | | **Y** | |

* **Row 1**: Role Description (e.g., `GL Period Control`). Preserves exact whitespaces.
* **Row 2**: Master Role Name / ID (e.g., `Z_FI_PERIOD_CONTROL`).
* **Column 1 (Row 3+)**: SAP Transaction Code (`tcode`).
* **Cells**: Mark with `Y` (or `y`) to assign the TCode to that role.
* **Empty Columns / Roles without TCodes**: If a role has no `Y` marks, the script generates a single row with `TCode = 'N/A'`.

### 1.2. Running the Conversion
```bash
# Automatic candidate lookup:
python scripts/convert_role_master_excel.py

# Or specify a custom file:
python scripts/convert_role_master_excel.py excel-templates/Template_Roles_Master.xlsx
```

### 1.3. Output CSV Format (`*_converted.csv`)
Produces UTF-8 (with BOM) encoded CSV:
```csv
Role Name,Role Description,TCode
Z_FI_PERIOD_CONTROL,GL Period Control,OB52
Z_FI_PERIOD_CONTROL,GL Period Control,S_ALR_87003642
Z_FI_GL_MASTER_MAINT,GL Master Data Maintenance,FS00
Z_FI_GL_MASTER_MAINT,GL Master Data Maintenance,FSP0
Z_FI_JOURNAL_POST,General Ledger Journal Posting,FB01
Z_FI_GL_REPORTS_EMPTY,General Ledger Custom Reporting,N/A
```

---

## 2. Derived Roles Mapping (`convert_role_derived_excel.py`)

### 2.1. Excel Input Format (`Template_Roles_Derived.xlsx`)
Defines how Master template roles are specialized into operational Derived Single Roles:

* **Sheet Name**: `DERIVED ROLES` (or the active sheet).
* **Column Headers** (Row 1):
  * **Column 1**: `Master Role` (Imparting parent role).
  * **Column 2**: `Derived Role` (Target single role).
  * **Column 3**: `Derived Role Description` (Specialized description, e.g., company code or entity suffix).

| Master Role | Derived Role | Derived Role Description |
| :--- | :--- | :--- |
| `Z_FI_PERIOD_CONTROL` | `Z_FI_PERIOD_CONTROL_1000` | GL Period Control - US Entity 1000 |
| `Z_FI_PERIOD_CONTROL` | `Z_FI_PERIOD_CONTROL_2000` | GL Period Control - EU Entity 2000 |
| `Z_FI_JOURNAL_POST` | `Z_FI_JOURNAL_POST_1000` | GL Journal Posting - US Entity 1000 |
| `Z_FI_JOURNAL_POST` | `Z_FI_JOURNAL_POST_2000` | GL Journal Posting - EU Entity 2000 |

### 2.2. Running the Conversion
```bash
# Automatic candidate lookup:
python scripts/convert_role_derived_excel.py

# Or specify a custom file:
python scripts/convert_role_derived_excel.py excel-templates/Template_Roles_Derived.xlsx
```

### 2.3. Output CSV Format (`*_converted.csv`)
```csv
Master Role,Derived Role,Derived Role Description
Z_FI_PERIOD_CONTROL,Z_FI_PERIOD_CONTROL_1000,GL Period Control - US Entity 1000
Z_FI_PERIOD_CONTROL,Z_FI_PERIOD_CONTROL_2000,GL Period Control - EU Entity 2000
Z_FI_JOURNAL_POST,Z_FI_JOURNAL_POST_1000,GL Journal Posting - US Entity 1000
Z_FI_JOURNAL_POST,Z_FI_JOURNAL_POST_2000,GL Journal Posting - EU Entity 2000
```

---

## 3. Organizational Levels Preprocessing (`convert_role_org_excel.py`)

### 3.1. Excel Input Format (`Template_Roles_Derived_Org.xlsx`)
Typically prepared by authorization designers as a wide table with roles as rows and organizational levels as columns:

* **Sheet Name**: `DERIVED ROLES`
* **Column 1**: `Role Name` (Derived Single Role ID).
* **Columns 2..N**: Organizational Level variables or descriptions. Column headers can be formatted in multiple recognized formats:
  * **Exact Variable**: `$BUKRS`, `$WERKS`, `$KOKRS`, `$ERKRS`
  * **Parenthesized Variable/Field**: `Operating concern ($CEERKRS)`, `Company Code ($BUKRS)`
  * **Standard Description**: `Plant / Valuation Area`, `Profit Center`, `Cost center`, `Order type`, `Asset Class`

| Role Name | Operating concern ($CEERKRS) | Controlling area ($KOKRS) | Company Code ($BUKRS) | Plant / Valuation Area | Profit Center | Cost center |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `Z_FI_PERIOD_CONTROL_1000` | OP01 | 1000 | 1000 | 1000 | PC1000* | CC1000* |
| `Z_FI_PERIOD_CONTROL_2000` | OP01 | 2000 | 2000 | 2000 | PC2000* | CC2000* |
| `Z_FI_JOURNAL_POST_1000` | OP01 | 1000 | 1000 | 1000 | PC1000* | CC1000* |
| `Z_FI_JOURNAL_POST_2000` | OP01 | 2000 | 2000 | 2000 | PC2000* | CC2000* |

### 3.2. Reference File: `Org_Levels.csv`
The script references `excel-templates/Org_Levels.csv` (containing 71 SAP standard Organizational Levels from table `USVART`) to match headers to standard SAP `$VARBL` variables (such as `$BUKRS`, `$WERKS`, `$EKORG`, `$VKORG`).

### 3.3. Running the Conversion
```bash
# Automatic candidate lookup (reads excel-templates/Org_Levels.csv by default):
python scripts/convert_role_org_excel.py

# Or specify custom files:
python scripts/convert_role_org_excel.py excel-templates/Template_Roles_Derived_Org.xlsx excel-templates/Org_Levels.csv
```

### 3.4. Output CSV Format (`*_converted.csv`)
Converts the wide matrix into normalized 3-column flat records:
```csv
Role Name,Org Level Variable,Org Value
Z_FI_PERIOD_CONTROL_1000,$ERKRS,OP01
Z_FI_PERIOD_CONTROL_2000,$ERKRS,OP01
Z_FI_PERIOD_CONTROL_1000,$KOKRS,1000
Z_FI_PERIOD_CONTROL_2000,$KOKRS,2000
Z_FI_PERIOD_CONTROL_1000,$BUKRS,1000
Z_FI_PERIOD_CONTROL_2000,$BUKRS,2000
Z_FI_PERIOD_CONTROL_1000,$WERKS,1000
Z_FI_PERIOD_CONTROL_2000,$WERKS,2000
Z_FI_PERIOD_CONTROL_1000,$PRCTR,PC1000*
Z_FI_PERIOD_CONTROL_2000,$PRCTR,PC2000*
```

---

## 4. Composite Roles Preprocessing (`convert_role_composite_excel.py`)

### 4.1. Excel Input Format (`Template_Roles_Composite.xlsx` / `FICO_Roles_Composite.xlsx`)
Composite roles bundle multiple single/derived roles into operational job roles (e.g. Chief Financial Officer, General Accountant):

* **Sheet Name**: `COMPOSITE ROLES` (or the active sheet).
* **Row 1**: Composite Role Description (e.g. `Chief Financial Officer - Entity 1000`). Preserves exact whitespaces.
* **Row 2**: Composite Role Name (e.g. `Z_FI_COMP_CFO_1000`).
* **Column 1 (Row 3+)**: Single/Derived Role Name (e.g. `Z_FI_PERIOD_CONTROL_1000`).
* **Matrix Cells**: Mark with `'Y'` (case-insensitive) to include the derived role in the composite role.
* **Empty Roles Fallback**: If a composite role column has no `'Y'` values, the script outputs 1 row with `Derived Role = 'N/A'` (e.g., `Z_FI_COMP_EMPTY_1000,Empty Composite Role - Entity 1000,N/A`).

| Derived Role / Composite Role Description | Chief Financial Officer - Entity 1000 | General Accountant - Entity 1000 | Empty Composite Role - Entity 1000 |
| :--- | :--- | :--- | :--- |
| **Role Name** | `Z_FI_COMP_CFO_1000` | `Z_FI_COMP_ACCOUNTANT_1000` | `Z_FI_COMP_EMPTY_1000` |
| `Z_FI_PERIOD_CONTROL_1000` | **Y** | | |
| `Z_FI_GL_MASTER_MAINT_1000` | **Y** | | |
| `Z_FI_JOURNAL_POST_1000` | | **Y** | |
| `Z_FI_JOURNAL_DISPLAY_1000` | **Y** | **Y** | |
| `Z_FI_AP_INVOICE_PROCESS_1000` | | **Y** | |

### 4.2. Running the Conversion
```bash
# Automatic candidate lookup (checks excel-working/ then excel-templates/):
python scripts/convert_role_composite_excel.py

# Or specify a custom file:
python scripts/convert_role_composite_excel.py excel-templates/Template_Roles_Composite.xlsx
```

### 4.3. Output CSV Format (`*_converted.csv`)
Produces UTF-8 (with BOM) encoded CSV in the required column order (`Composite Role Name, Composite Role Description, Derived Role`):
```csv
Composite Role Name,Composite Role Description,Derived Role
Z_FI_COMP_CFO_1000,Chief Financial Officer - Entity 1000,Z_FI_PERIOD_CONTROL_1000
Z_FI_COMP_CFO_1000,Chief Financial Officer - Entity 1000,Z_FI_GL_MASTER_MAINT_1000
Z_FI_COMP_CFO_1000,Chief Financial Officer - Entity 1000,Z_FI_JOURNAL_DISPLAY_1000
...
Z_FI_COMP_EMPTY_1000,Empty Composite Role - Entity 1000,N/A
```

---

## 🛠️ Best Practices & Troubleshooting

1. **UTF-8 with BOM Encoding**:
   * All CSV files exported by these scripts use `utf-8-sig` (UTF-8 with BOM). This prevents corruption of accented characters or foreign descriptions when uploaded into SAP GUI via `cl_gui_frontend_services=>gui_upload`.
2. **Confidentiality / Data Segregation**:
   * Keep real production or client authorization files in `excel-working/`. This folder is ignored by `.gitignore`.
   * Only anonymized files should ever be placed in `excel-templates/`.
3. **Empty Org Level Values**:
   * Blank/empty cells in `Template_Roles_Derived_Org.xlsx` are ignored by the script. In the ABAP program `Z_AUTH_ROLE_UPDATE_ORG`, use parameter `p_astnon = 'X'` to automatically default any unlisted authorization org fields to `*` (wildcard) so profile generation remains **Green**.
