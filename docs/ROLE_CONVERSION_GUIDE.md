# 🔄 Guide: Preprocessing Excel Files to CSV for ABAP Role & User Automation

> **SAP Role & User Lifecycle Automation Toolset**  
> **Repository**: [https://github.com/luongdk18/SAPABAP](https://github.com/luongdk18/SAPABAP)

This guide explains how to prepare business authorization matrices in Excel and convert them into flat, standardized CSV files ready for direct import into the modular ABAP utilities:
1. **Module 1 (Role Management)**:
   - **01. Master Roles**: `convert_role_01_master.py` ➔ Import into **`Z_ROLE_01_CREATE_MASTER`**
   - **02. Derived Roles Mapping**: `convert_role_02_derive.py` ➔ Import into **`Z_ROLE_02_CREATE_DERIVE`**
   - **03. Organizational Levels**: `convert_role_03_org.py` ➔ Import into **`Z_ROLE_03_UPDATE_ORG`**
   - **04. Composite Roles**: `convert_role_04_composite.py` ➔ Import into **`Z_ROLE_04_COMPOSITE`**
2. **Module 2 (User Management)**:
   - **01. User Creation**: `convert_user_01_create.py` ➔ Import into **`Z_USER_01_CREATE`**
   - **02. User Role Assignment**: `convert_user_02_assign.py` ➔ Import into **`Z_USER_02_ASSIGN_ROLE`**

---

## 📌 Architecture & Conversion Pipeline

```mermaid
flowchart TD
    subgraph S1["1. Master Roles Matrix"]
        A1["Template_Role_01_Master.xlsx\n(Row 1: Desc, Row 2: Role, Col 1: TCodes)"] --> B1["convert_role_01_master.py\n(or npm run convert:role:01)"]
        B1 --> C1["Template_Role_01_Master_converted.csv\n(Role Name, Role Desc, TCode)"]
        C1 --> D1["ABAP Program: Z_ROLE_01_CREATE_MASTER\nCreates Master Roles & PFCG Menus"]
    end

    subgraph S2["2. Derived Roles Mapping"]
        A2["Template_Role_02_Derived.xlsx\n(Master Role, Derived Role, Description)"] --> B2["convert_role_02_derive.py\n(or npm run convert:role:02)"]
        B2 --> C2["Template_Role_02_Derived_converted.csv\n(Master Role, Derived Role, Description)"]
        C2 --> D2["ABAP Program: Z_ROLE_02_CREATE_DERIVE\nCreates Derived Roles & Links PARENT_AGR"]
    end

    subgraph S3["3. Organizational Levels Matrix"]
        A3["Template_Role_03_Org.xlsx\n(Roles in rows, Org Levels in columns)"] --> B3["convert_role_03_org.py\n(References Org_Levels.csv)"]
        B3 --> C3["Template_Role_03_Org_converted.csv\n(Role Name, Org Variable, Org Value)"]
        C3 --> D3["ABAP Program: Z_ROLE_03_UPDATE_ORG\nPopulates AGR_1252 & Generates Profiles"]
    end

    subgraph S4["4. Composite Roles Matrix"]
        A4["Template_Role_04_Composite.xlsx\n(Row 1: Desc, Row 2: Role, Col 1: Derived Roles)"] --> B4["convert_role_04_composite.py\n(or npm run convert:role:04)"]
        B4 --> C4["Template_Role_04_Composite_converted.csv\n(Composite Role, Description, Derived Role)"]
        C4 --> D4["ABAP Program: Z_ROLE_04_COMPOSITE\nCreates Composite Roles & Assigns Single Roles"]
    end

    subgraph S5["5. User Creation List"]
        A5["Template_User_01_Create.xlsx\n(Name, Email, Phone, Dept, Func)"] --> B5["convert_user_01_create.py\n(or npm run convert:user:01)"]
        B5 --> C5["Template_User_01_Create_converted.csv\n(Username, Password, Name, Email, Phone, Dept, Func)"]
        C5 --> D5["ABAP Program: Z_USER_01_CREATE\nCreates & Updates SAP Users via BAPI"]
    end

    subgraph S6["6. User Role Assignment Matrix"]
        A6["Template_User_02_Assign.xlsx\n(Users in Col 1, Roles in Row 1, X/Y flags)"] --> B6["convert_user_02_assign.py\n(or npm run convert:user:02)"]
        C6["Template_User_02_Assign_converted.csv\n(Username, Role)"]
        B6 --> C6
        C6 --> D6["ABAP Program: Z_USER_02_ASSIGN_ROLE\nAssigns Roles via BAPI_USER_ACTGROUPS_ASSIGN"]
    end
```

---

## 🚀 Quick Execution via npm Shortcuts

Convenient npm commands are preconfigured in `package.json`:

```bash
# Module 1: Role Management
npm run convert:role:01      # Master Roles Matrix
npm run convert:role:02      # Derived Roles Creation Mapping
npm run convert:role:03      # Derived Role Organizational Levels
npm run convert:role:04      # Composite Roles Matrix

# Module 2: User Management
npm run convert:user:01      # User Creation List
npm run convert:user:02      # User Role Assignment Matrix
```

> [!TIP]
> Each script automatically checks for candidate files in `excel-working/`, `excel-templates/`, and the repository root. You can also specify an exact file path as a CLI argument.

---

## 1. Master Roles Preprocessing (`convert_role_01_master.py`)

### 1.1. Excel Input Format (`Template_Role_01_Master.xlsx`)
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
* **Cells**: Mark with indicator flags: `Y`, `y`, `X`, or `x` (case-insensitive) to assign the TCode to that role.
* **Empty Columns / Roles without TCodes**: If a role has no indicator marks (`Y`/`X`), the script generates a single row with `TCode = 'N/A'`.

### 1.2. Running the Conversion
```bash
# Automatic candidate lookup:
python scripts/convert_role_01_master.py

# Or specify a custom file:
python scripts/convert_role_01_master.py excel-templates/Template_Role_01_Master.xlsx
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

## 2. Derived Roles Mapping (`convert_role_02_derive.py`)

### 2.1. Excel Input Format (`Template_Role_02_Derived.xlsx`)
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
python scripts/convert_role_02_derive.py

# Or specify a custom file:
python scripts/convert_role_02_derive.py excel-templates/Template_Role_02_Derived.xlsx
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

## 3. Organizational Levels Preprocessing (`convert_role_03_org.py`)

### 3.1. Excel Input Format (`Template_Role_03_Org.xlsx`)
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
python scripts/convert_role_03_org.py

# Or specify custom files:
python scripts/convert_role_03_org.py excel-templates/Template_Role_03_Org.xlsx excel-templates/Org_Levels.csv
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

## 4. Composite Roles Preprocessing (`convert_role_04_composite.py`)

### 4.1. Excel Input Format (`Template_Role_04_Composite.xlsx`)
Composite roles bundle multiple single/derived roles into operational job roles (e.g. Chief Financial Officer, General Accountant):

* **Sheet Name**: `COMPOSITE ROLES` (or the active sheet).
* **Row 1**: Composite Role Description (e.g. `Chief Financial Officer - Entity 1000`). Preserves exact whitespaces.
* **Row 2**: Composite Role Name (e.g. `Z_FI_COMP_CFO_1000`).
* **Column 1 (Row 3+)**: Single/Derived Role Name (e.g. `Z_FI_PERIOD_CONTROL_1000`).
* **Matrix Cells**: Mark with indicator flags: `'Y'`, `'y'`, `'X'`, or `'x'` (case-insensitive) to include the derived role in the composite role.
* **Empty Roles Fallback**: If a composite role column has no indicator marks (`Y`/`X`), the script outputs 1 row with `Derived Role = 'N/A'`.

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
python scripts/convert_role_04_composite.py

# Or specify a custom file:
python scripts/convert_role_04_composite.py excel-templates/Template_Role_04_Composite.xlsx
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

## 5. User Creation Preprocessing (`convert_user_01_create.py`)

### 5.1. Excel Input Format (`Template_User_01_Create.xlsx`)
Corporate user list collected during system implementation:

* **Sheet Name**: `User Asignment` (or `Users`, or active sheet).
* **Column 1**: `FULL NAME` (Employee full name).
* **Column 2**: `Email` (Corporate email, or employee username/account code).
* **Column 3**: `Phone No.` (Contact phone number in varying formats).
* **Column 4**: `Department` (Department/Division name).
* **Column 5**: `Function` (Job title/functional role).

| FULL NAME | Email | Phone No. | Department | Function |
| :--- | :--- | :--- | :--- | :--- |
| John Doe | `johnd@company.com` | `+84 981 234 567` | Finance & Accounting | Finance Controller |
| Jane Smith | `janes@company.com` | `+84 971 888 999` | Finance & Accounting | Senior Accountant |
| Alex Johnson | `alexj@company.com` | `+996 555 123 456` | PMU | Project Director |
| Emily Davis | `emilyd` | *(blank)* | Administration | HR Specialist |
| David Wilson | `davidw@company.com` | `0987654321` | operation | OM |

### 5.2. Transformation Rules
1. **Username Extraction**:
   * Reads from the `Email` column: takes all characters before `@`, strips whitespace, and converts to uppercase (`BNAME` format in SAP).
   * **Fallback**: If the value contains no `@`, uses the raw value directly as the Username.
2. **Initial Password Generation**:
   * Generates a 12-character cryptographically secure password compliant with SAP password policies.
   * Starts with an uppercase letter (`A-Z`), includes lowercase letters, digits, and safe special characters (`!@#$%*-_=+`), avoiding characters that interfere with CSV delimiters.
3. **Phone Number Normalization**:
   * Standardizes all phone numbers to unified format `(<CountryCode>)<Number>` (e.g. `(84)985176887`) without the `+` sign for SAP compatibility.
4. **Department & Function Cleanup**:
   * Corrects capitalization and common typos.

### 5.3. Running the Conversion
```bash
# Automatic candidate lookup (checks excel-working/ then excel-templates/):
python scripts/convert_user_01_create.py

# Or specify a custom file:
python scripts/convert_user_01_create.py excel-templates/Template_User_01_Create.xlsx
```

### 5.4. Output CSV Format (`*_converted.csv`)
Produces UTF-8 (with BOM) encoded CSV ready for batch user creation in SAP ABAP via `BAPI_USER_CREATE1`:
```csv
Username,Initial Password,Full Name,Email,Phone No.,Department,Function
JOHND,PVy6Dj2+1n$s,John Doe,johnd@company.com,(84)981234567,Finance & Accounting,Finance Controller
JANES,M*6SW3-fyNiS,Jane Smith,janes@company.com,(84)971888999,Finance & Accounting,Senior Accountant
ALEXJ,W+cKV89N-kvR,Alex Johnson,alexj@company.com,(996)555123456,PMU,Project Director
MICHAELB,ZM!0oHN!92h2,Michael Brown,michaelb@company.com,(996)500654321,PMU,Civil Engineer
EMILYD,P9*a!Lhib9OU,Emily Davis,emilyd,,Administration,HR Specialist
DAVIDW,YVi*5T!Ss4J_,David Wilson,davidw@company.com,(84)987654321,Operation,OM
```

---

## 6. User Role Assignment Preprocessing (`convert_user_02_assign.py`)

### 6.1. Excel Input Format (`Template_User_02_Assign.xlsx`)
Wide assignment matrix mapping system users to single or composite business roles:

* **Sheet Name**: `User Asignment` (or `Assignment`, or active sheet).
* **Row 1**: Role Names (Columns 2..N, e.g. `CR_COMMON`, `Z_FI_COMP_CFO_1000`).
* **Column 1 (Rows 2..N)**: Username (e.g. `JOHND`, `JANES`).
* **Matrix Cells**: Mark with indicator flags: `Y`, `y`, `X`, or `x` (case-insensitive) to assign the role to that user.

| Username | CR_COMMON | Z_FI_COMP_CFO_1000 | Z_FI_COMP_ACCOUNTANT_1000 | Z_FI_COMP_CONTROLLER_1000 | Z_MM_PURCHASER_1000 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `JOHND` | **X** | **X** | | | |
| `JANES` | **X** | | **X** | | |
| `ALEXJ` | **X** | | | **X** | |
| `MICHAELB` | **X** | | | | **X** |
| `EMPTY_USER` | | | | | |

### 6.2. Running the Conversion
```bash
# Automatic candidate lookup (checks excel-working/ then excel-templates/):
python scripts/convert_user_02_assign.py

# Or specify a custom file:
python scripts/convert_user_02_assign.py excel-templates/Template_User_02_Assign.xlsx
```

### 6.3. Output CSV Format (`*_converted.csv`)
Produces UTF-8 (with BOM) encoded 2-column CSV ready for direct upload into `Z_USER_02_ASSIGN_ROLE`:
```csv
Username,Role
JOHND,CR_COMMON
JOHND,Z_FI_COMP_CFO_1000
JANES,CR_COMMON
JANES,Z_FI_COMP_ACCOUNTANT_1000
ALEXJ,CR_COMMON
ALEXJ,Z_FI_COMP_CONTROLLER_1000
MICHAELB,CR_COMMON
MICHAELB,Z_MM_PURCHASER_1000
EMPTY_USER,N/A
```

---

## 🛠️ Best Practices & Troubleshooting

1. **UTF-8 with BOM Encoding**:
   * All CSV files exported by these scripts use `utf-8-sig` (UTF-8 with BOM). This prevents corruption of accented characters or foreign descriptions when uploaded into SAP GUI via `cl_gui_frontend_services=>gui_upload`.
2. **Confidentiality / Data Segregation**:
   * Keep real production or client authorization files in `excel-working/`. This folder is ignored by `.gitignore`.
   * Only anonymized template files should ever be placed in `excel-templates/`.
3. **Empty Org Level Values**:
   * Blank/empty cells in `Template_Role_03_Org.xlsx` are ignored by the script. In the ABAP program `Z_ROLE_03_UPDATE_ORG`, use parameter `p_astnon = 'X'` to automatically default any unlisted authorization org fields to `*` (wildcard) so profile generation remains **Green**.
