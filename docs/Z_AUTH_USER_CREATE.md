# 👤 Z_AUTH_USER_CREATE: Batch SAP User Creation & Update Cockpit

> **SAP Basis Utilities & AI-Assisted ABAP Development via Model Context Protocol (MCP)**  
> **Source Code**: [`src/z_auth_user_create.prog.abap`](../src/z_auth_user_create.prog.abap)  
> **Companion Script**: [`scripts/convert_users_excel.py`](../scripts/convert_users_excel.py)  
> **CSV Template**: [`excel-templates/Template_Users_Create_converted.csv`](../excel-templates/Template_Users_Create_converted.csv)  
> **Repository**: [https://github.com/luongdk18/SAPABAP](https://github.com/luongdk18/SAPABAP)

The ABAP utility **`Z_AUTH_USER_CREATE`** is an enterprise-grade automation tool built for SAP Basis Administrators, Security Specialists, and User Management Teams. It automates mass user onboarding and master data updates directly from normalized CSV files.

The program handles **UTF-8 character preservation** (including Vietnamese names and accents), maps **Full Name entirely into SAP Last Name** (`BAPIADDR3-LASTNAME`), supports simulation mode (`p_test = 'X'`), supports in-place user updates (`p_upd = 'X'`) and password resets (`p_pwd = 'X'`), and presents results in an interactive ALV cockpit with **hotspot jump to transaction `SU01`**.

---

## 📌 Table of Contents
1. [Business Context & Problem Statement](#1-business-context--problem-statement)
2. [End-to-End Processing Workflow](#2-end-to-end-processing-workflow)
3. [Key Architectural & Functional Features](#3-key-architectural--functional-features)
   - [3.1. Full Name Mapping to SAP Last Name](#31-full-name-mapping-to-sap-last-name)
   - [3.2. Binary UTF-8 Upload & Diacritics Preservation](#32-binary-utf-8-upload--diacritics-preservation)
   - [3.3. Dual Execution Modes: Simulation vs. Live Provisioning](#33-dual-execution-modes-simulation-vs-live-provisioning)
   - [3.4. Updating Existing Users & Password Reset Support](#34-updating-existing-users--password-reset-support)
   - [3.5. Atomic BAPI Execution & Explicit Commit Work](#35-atomic-bapi-execution--explicit-commit-work)
   - [3.6. Interactive ALV Cockpit with One-Click SU01 Navigation](#36-interactive-alv-cockpit-with-one-click-su01-navigation)
4. [Selection Screen & Operational Parameters](#4-selection-screen--operational-parameters)
5. [Standard SAP Function Modules & Tables](#5-standard-sap-function-modules--tables)
6. [Operational Step-by-Step Guide](#6-operational-step-by-step-guide)
7. [Troubleshooting & Frequently Asked Questions (FAQ)](#7-troubleshooting--frequently-asked-questions-faq)

---

## 1. Business Context & Problem Statement

During SAP S/4HANA implementations, rollouts, corporate reorganizations, or go-lives, provisioning hundreds of business users manually in transaction `SU01` is tedious, error-prone, and time-consuming.

### Operational Bottlenecks in Standard User Administration:
1. **Manual Entry in `SU01`**: Creating a user requires maintaining tabs for Address, Logon Data, Defaults, and Roles. Manual data entry for 100+ users takes days.
2. **Vietnamese & Special Character Corruption**: Standard ASCII uploads or legacy transactions often garble Vietnamese accents (`Đào Việt Hùng`, `Lê Văn Nam`, `Phạm Quốc Tuấn`) into question marks `?` or corrupt bytes.
3. **Naming Convention Discrepancies**: In Vietnamese and Asian culture, single "First Name" and "Last Name" splitting is ambiguous. Standardizing the user's complete name into **Last Name** (`LASTNAME`) satisfies SAP mandatory field requirements while preserving the full legal name intact on business documents and audit logs.
4. **Password Compliance & Security**: Generating and distributing compliant initial logon passwords that satisfy SAP password policies requires automated cryptographic generation.

`Z_AUTH_USER_CREATE` bridges this gap by pairing a Python cleaning script with a high-performance ABAP BAPI cockpit.

---

## 2. End-to-End Processing Workflow

```mermaid
flowchart TD
    A["Raw User List / Excel (.xlsx)"] --> B["Python Converter: scripts/convert_users_excel.py\n- Extracts Username from Email\n- Generates SAP-compliant 12-char Passwords\n- Normalizes Phone (+CountryCode)\n- Formats UTF-8 CSV with BOM"]
    B --> C["Users_Create_converted.csv"]
    C --> D["SAP Program: Z_AUTH_USER_CREATE\nUpload via GUI_UPLOAD (filetype = 'BIN')"]
    D --> E["SCMS_BINARY_TO_STRING (Code page 4110 / UTF-8)\nStrip BOM (U+FEFF) & Parse CSV Lines"]
    E --> F["Validation:\n- Username <= 12 characters\n- Full Name is Mandatory\n- Initial Password for New Users"]
    
    F -->|Validation Failed| G["Report Error in ALV: Red LED @0A@"]
    F -->|Validation Passed| H{"User Exists in USR02?"}

    H -->|No (New User)| I{"Simulation Mode?\n(p_test = 'X')"}
    I -->|Yes| J["Preview Action: SIM_NEW (Green LED @08@)"]
    I -->|No| K["Call BAPI_USER_CREATE1\n- Address: LASTNAME = Full Name\n- Logon: Dialog 'A', Valid From/To\n- Defaults: Language, Spool LP01\n- Password: Initial Password"]
    K --> L["BAPI_TRANSACTION_COMMIT (wait = 'X')\nReport Action: CREATED (Green LED @08@)"]

    H -->|Yes (Existing User)| M{"Update Allowed?\n(p_upd = 'X')"}
    M -->|No| N["Report Status: SKIPPED (Yellow LED @09@)\n'User already exists. Check Update flag to modify'"]
    M -->|Yes| O{"Simulation Mode?\n(p_test = 'X')"}
    O -->|Yes| P["Preview Action: SIM_UPD (Green LED @08@)"]
    O -->|No| Q["Call BAPI_USER_CHANGE\n- Update Address fields (BAPIADDR3X)\n- Optional Password Reset (p_pwd = 'X')"]
    Q --> R["BAPI_TRANSACTION_COMMIT (wait = 'X')\nReport Action: UPDATED (Green LED @08@)"]

    J --> S["Interactive ALV Grid Cockpit\nHotspot Click on Username -> SU01"]
    L --> S
    N --> S
    P --> S
    R --> S
    G --> S
```

---

## 3. Key Architectural & Functional Features

### 3.1. Full Name Mapping to SAP Last Name
In standard SAP user master records (`BAPIADDR3`), `LASTNAME` is the mandatory primary name field, whereas `FIRSTNAME` is optional. To avoid arbitrary name fragmentation across culturally diverse name formats (e.g. Vietnamese 3-part or 4-part names), `Z_AUTH_USER_CREATE` assigns the entire **Full Name** directly to `BAPIADDR3-LASTNAME`.

```abap
" Address - Full Name mapped entirely into Last Name (BAPIADDR3-LASTNAME)
ls_address-lastname   = is_user-fullname.
ls_address-e_mail     = is_user-email.
ls_address-tel1_numbr = is_user-phone.
ls_address-department = is_user-department.
ls_address-function   = is_user-function.
```

### 3.2. Binary UTF-8 Upload & Diacritics Preservation
To prevent SAP GUI or operating system code pages from substituting non-Latin or accented characters with `#` or `?`, the file is read in **binary mode (`'BIN'`)** and converted into ABAP Unicode strings using `SCMS_BINARY_TO_STRING` with encoding `'4110'` (UTF-8). Byte Order Marks (`U+FEFF`) are stripped cleanly before string tokenization.

```abap
cl_gui_frontend_services=>gui_upload(
  EXPORTING
    filename = lv_filepath
    filetype = 'BIN'
  IMPORTING
    filelength = lv_length
  CHANGING
    data_tab   = lt_binary_tab ).

CALL FUNCTION 'SCMS_BINARY_TO_STRING'
  EXPORTING
    input_length = lv_length
    encoding     = '4110' " UTF-8
  IMPORTING
    text_buffer  = lv_content
  TABLES
    binary_tab   = lt_binary_tab.
```

### 3.3. Dual Execution Modes: Simulation vs. Live Provisioning
- **Simulation Mode (`p_test = 'X'`)**: Performs all data validations, checks user existence in table `USR02`, checks field constraints (username $\le$ 12 chars, full name present), and displays the expected actions (`SIM_NEW`, `SIM_UPD`, `SKIPPED`) without changing any database records.
- **Live Execution Mode (`p_test = ' '`)**: Calls standard SAP BAPIs to create/update users and records commit timestamps.

### 3.4. Updating Existing Users & Password Reset Support
- When an input record corresponds to an existing user in `USR02` and `p_upd = ' '`, the user is safely **SKIPPED** (marked with a Yellow LED `@09@`), preventing accidental overwrites.
- When `p_upd = 'X'`, existing users are updated in-place via `BAPI_USER_CHANGE`.
- The checkbox `p_pwd` controls whether the user's password is reset to the initial password in the CSV file during an update. By default, `p_pwd = ' '` preserves the user's existing password.

### 3.5. Atomic BAPI Execution & Explicit Commit Work
After successful invocation of `BAPI_USER_CREATE1` or `BAPI_USER_CHANGE`, the program issues an explicit `BAPI_TRANSACTION_COMMIT` with `WAIT = 'X'` to ensure database consistency across address tables (`ADRP`, `ADCP`, `ADRC`) and logon tables (`USR02`).

### 3.6. Interactive ALV Cockpit with One-Click SU01 Navigation
The output report is rendered with `CL_SALV_TABLE`. The **Username** column is configured as an interactive hotspot. Clicking any username immediately navigates to transaction `SU01` for that user:

```abap
METHOD on_link_click.
  READ TABLE gt_results INTO DATA(ls_row) INDEX row.
  IF sy-subrc = 0 AND column = 'USERNAME' AND ls_row-username IS NOT INITIAL.
    SET PARAMETER ID 'USR' FIELD ls_row-username.
    CALL TRANSACTION 'SU01' AND SKIP FIRST SCREEN.
  ENDIF.
ENDMETHOD.
```

---

## 4. Selection Screen & Operational Parameters

```
╔════════════════════════════════════════════════════════════════════════════╗
║                        Batch User Creation Cockpit                         ║
╠════════════════════════════════════════════════════════════════════════════╣
║ Input CSV File (.csv)                                                      ║
║   File Path:                  [                                    ] [F4]  ║
╠════════════════════════════════════════════════════════════════════════════╣
║ Execution & Update Options                                                 ║
║   [X] Simulation (Test Run)                                                ║
║   [ ] Update Existing Users                                                ║
║   [ ] Reset Password on Update                                             ║
╠════════════════════════════════════════════════════════════════════════════╣
║ User Defaults (Logon & Defaults)                                           ║
║   User Type (A=Dialog):       [A ]                                         ║
║   Valid From:                 [21.10.2026]                                 ║
║   Valid To:                   [31.12.9999]                                 ║
║   Logon Language:             [EN]                                         ║
║   Default Output Device:      [LP01]                                       ║
╚════════════════════════════════════════════════════════════════════════════╝
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `p_file` | `localfile` | Mandatory | Full path to the `.csv` file on the client machine. Supports F4 dialog. |
| `p_test` | `abap_bool` | `'X'` | Simulation mode. Validates and displays actions without committing changes. |
| `p_upd` | `abap_bool` | `' '` | Update existing users in SAP if already present in table `USR02`. |
| `p_pwd` | `abap_bool` | `' '` | Reset logon password when updating existing users. |
| `p_ustyp` | `bapilogond-ustyp` | `'A'` | User Type (`A` = Dialog, `B` = System, `C` = Communication, `S` = Service). |
| `p_gltgv` | `bapilogond-gltgv` | `sy-datum` | User Validity Start Date. |
| `p_gltgb` | `bapilogond-gltgb` | `'99991231'` | User Validity End Date. |
| `p_langu` | `bapidefaul-langu`| `sy-langu` | Default Logon Language. |
| `p_spld` | `bapidefaul-spld` | `'LP01'` | Default Spool Output Device. |

---

## 5. Standard SAP Function Modules & Tables

| Object Name | Type | Purpose |
|---|---|---|
| `BAPI_USER_CREATE1` | Function Module | Standard SAP BAPI to create user master record, logon data, address, and defaults. |
| `BAPI_USER_CHANGE` | Function Module | Standard SAP BAPI to update existing user attributes and address data. |
| `BAPI_TRANSACTION_COMMIT` | Function Module | Commits LUW changes synchronously (`WAIT = 'X'`). |
| `SCMS_BINARY_TO_STRING` | Function Module | Converts binary byte buffer into Unicode string under code page `4110` (UTF-8). |
| `USR02` | Database Table | SAP Logon data and user existence check. |
| `ADRP` / `ADCP` / `ADRC` | Database Tables | Business Address Services (BAS) tables storing personal and company address data. |
| `S_USER_GRP` | Authorization Object | Checked during `START-OF-SELECTION` for activity `01` (Create) and `02` (Change). |

---

## 6. Operational Step-by-Step Guide

### Step 1: Prepare Excel Data and Convert to CSV
1. Populate your user list into an Excel file or use the provided template [`Template_Users_Create.xlsx`](../excel-templates/Template_Users_Create.xlsx).
2. Run the companion Python conversion script:
   ```bash
   # Convert working file
   npm run convert:user:create
   # Or with explicit path
   python scripts/convert_users_excel.py excel-working/Users_Create.xlsx
   ```
3. The script verifies data integrity, cleans phone numbers, generates cryptographically secure SAP passwords, and writes `excel-working/Users_Create_converted.csv`.

### Step 2: Deploy the ABAP Program (One-Time)
Deploy and activate the program directly to your SAP system via the automated deployer:
```bash
npm run deploy:user
# or
node scripts/deploy.js src/z_auth_user_create.prog.abap Z_AUTH_USER_CREATE
```

### Step 3: Run Simulation in SAP GUI
1. Open transaction `SE38` or `SA38` and execute `Z_AUTH_USER_CREATE`.
2. Select your `Users_Create_converted.csv` file.
3. Keep **Simulation (Test Run)** checked (`p_test = 'X'`).
4. Click **Execute (`F8`)**.
5. Verify that all records show Green LED `@08@` (`SIM_NEW` or `SIM_UPD`). Resolve any Red LED `@0A@` issues (e.g., duplicate/invalid usernames).

### Step 4: Execute Live User Provisioning
1. Return to the selection screen (`F3`).
2. Uncheck **Simulation (Test Run)**.
3. If modifying existing users, check **Update Existing Users** (`p_upd = 'X'`).
4. Click **Execute (`F8`)**.
5. The ALV report displays Green LED `@08@` (`CREATED` or `UPDATED`) for each user.
6. Click any **Username** cell to jump directly into transaction `SU01` and verify the created user record.

---

## 7. Troubleshooting & Frequently Asked Questions (FAQ)

### Q1: Why is Full Name mapped to Last Name rather than First Name?
In standard SAP Business Address Services, `BAPIADDR3-LASTNAME` is the mandatory primary name field, while `FIRSTNAME` is optional. Putting the full name into `LASTNAME` ensures that the user's complete legal name is always visible across all SAP modules, report footers, purchase orders, and audit logs without accidental truncation or awkward name inversions.

### Q2: Why does an existing user show Yellow LED `@09@` (`SKIPPED`)?
By default, `Z_AUTH_USER_CREATE` protects existing user master records from accidental modification. If a user in the CSV already exists in table `USR02`, the program skips them with a warning message. To allow updates, check the **Update Existing Users** (`p_upd = 'X'`) parameter on the selection screen.

### Q3: How are passwords handled during user update?
When **Update Existing Users** is active, passwords are **not** changed by default (`p_pwd = ' '`). If you also wish to force-reset existing users' passwords to the values in the CSV file, select the **Reset Password on Update** checkbox (`p_pwd = 'X'`).

### Q4: Does the program support Vietnamese characters?
Yes. The program uploads the CSV file in binary mode (`'BIN'`) and explicitly decodes the raw byte sequence as UTF-8 (`encoding = '4110'`). Accented characters like `Đ`, `ệ`, `ư`, `ơ`, `ạ`, `ấ` are completely preserved in the SAP user master record.

---
*Maintained by the SAP Basis & Security Engineering Team.*
