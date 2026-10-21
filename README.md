<p align="center">
  <img src="assets/logo.svg" width="64" height="64" alt="SAP ABAP Logo">
</p>

# SAP ABAP with AI & Model Context Protocol (MCP)

> Guides on connecting AI Agents via ABAP MCP to live SAP systems, featuring practical ABAP utilities coded with AI to assist SAP Basis operations.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [Quick Start](#3-quick-start)
4. [AI Agent Configuration](#4-ai-agent-configuration)
   - [4.1. Grok Build](#41-grok-build)
   - [4.2. ChatGPT (Desktop & Codex)](#42-chatgpt-desktop--codex)
   - [4.3. Claude Desktop](#43-claude-desktop)
   - [4.4. Cursor IDE](#44-cursor-ide)
   - [4.5. Google Antigravity](#45-google-antigravity)
   - [4.6. VS Code](#46-vs-code-cline--roo-code--continue)
5. [AI-Assisted ABAP Workflow](#5-ai-assisted-abap-workflow)
6. [Automated Program-by-Program Deployment](#6-automated-program-by-program-deployment)
7. [ABAP Utilities for SAP Basis](#7-abap-utilities-for-sap-basis)
   - [7.1. Current Utility: Z_AUTH_TEST](#71-current-utility-z_auth_test)
   - [7.2. Current Utility: Z_AUTH_ROLE_CREATE](#72-current-utility-z_auth_role_create)
   - [7.3. Current Utility: Z_AUTH_ROLE_DERIVE](#73-current-utility-z_auth_role_derive)
   - [7.4. Current Utility: Z_AUTH_ROLE_UPDATE_ORG](#74-current-utility-z_auth_role_update_org)
   - [7.5. Current Utility: Z_AUTH_ROLE_COMPOSITE](#75-current-utility-z_auth_role_composite)
   - [7.6. Current Utility: Z_AUTH_USER_CREATE](#76-current-utility-z_auth_user_create)
   - [7.7. Current Utility: Z_AUTH_USER_ASSIGN_ROLE](#77-current-utility-z_auth_user_assign_role)
   - [7.8. Python Preprocessing Pipeline Guide](#78-python-preprocessing-pipeline-guide)
   - [7.9. Future Utilities Roadmap](#79-future-utilities-roadmap)
8. [Security & Best Practices](#8-security--best-practices)
9. [License](#9-license)

---

## 1. Overview

This repository provides instructions and configuration templates to connect AI coding agents to live **SAP S/4HANA** and **SAP ECC** systems using the **Model Context Protocol (MCP)** via **ABAP Development Tools (ADT)**.

It also serves as a codebase for practical ABAP utility tools developed with AI to support **SAP Basis operations** and administration tasks.

### Architecture

```
[ AI Coding Agents ]  (Grok Build, ChatGPT/Codex, Claude, Cursor, Antigravity, VS Code)
         │
         │  stdio / JSON-RPC (Model Context Protocol)
         ▼
[ SAP ABAP ADT MCP Server ]  (@mcp-abap-adt/core)
         │
         │  HTTPS (SAP ADT REST / SICF)
         ▼
[ SAP S/4HANA / NetWeaver System ]
   ├── ADT Endpoints (Read, Write, Syntax Check, Activate, SQL Query)
   └── ABAP Utilities (e.g., Z_AUTH_TEST, Basis tools)
```

### Repository Structure

```
.
├── assets/
│   └── logo.svg                # Repository brand logo
├── docs/
│   ├── ROLE_CONVERSION_GUIDE.md # Guide for Python Excel-to-CSV converters
│   ├── Z_AUTH_ROLE_COMPOSITE.md # Composite role creation & single role assignment documentation
│   ├── Z_AUTH_ROLE_CREATE.md    # Master single role batch creation & menu documentation
│   ├── Z_AUTH_ROLE_DERIVE.md    # Derived role creation & inheritance documentation
│   ├── Z_AUTH_ROLE_UPDATE_ORG.md# Organizational levels batch update documentation
│   ├── Z_AUTH_TEST.md          # Technical analysis & SU53 remediation cockpit documentation
│   ├── Z_AUTH_USER_CREATE.md    # Batch user creation & update cockpit documentation
│   └── Z_AUTH_USER_ASSIGN_ROLE.md # Batch user role assignment cockpit documentation
├── excel-templates/            # Anonymized templates & sample data for role upload
│   ├── Org_Levels.csv          # Standard SAP 71 Organizational Level definitions
│   ├── Template_Roles_Master.xlsx
│   ├── Template_Roles_Master_converted.csv
│   ├── Template_Roles_Derived.xlsx
│   ├── Template_Roles_Derived_converted.csv
│   ├── Template_Roles_Derived_Org.xlsx
│   ├── Template_Roles_Derived_Org_converted.csv
│   ├── Template_Roles_Composite.xlsx
│   ├── Template_Roles_Composite_converted.csv
│   ├── Template_Users_Create.xlsx
│   ├── Template_Users_Create_converted.csv
│   ├── Template_User_Assign_Role.xlsx
│   └── Template_User_Assign_Role_converted.csv
├── scripts/
│   ├── convert_role_master_excel.py # Preprocessing script: converts matrix Excel to row format CSV
│   ├── convert_role_derived_excel.py # Converts derived role creation Excel to flat CSV format
│   ├── convert_role_org_excel.py    # Converts derived role org matrix to flat CSV referencing Org_Levels.csv
│   ├── convert_role_composite_excel.py # Converts composite roles matrix to flat CSV format
│   ├── convert_users_excel.py       # Converts user creation Excel to normalized CSV with secure passwords
│   ├── convert_users_assign_roles_excel.py # Converts user role assignment matrix to flat CSV format
│   ├── generate_org_levels_csv.py   # Generates standard Org_Levels.csv reference
│   └── deploy.js               # CLI deployment engine via MCP ADT
├── src/
│   ├── z_auth_role_composite.prog.abap  # Batch Composite Role Creation & Assignment tool
│   ├── z_auth_role_create.prog.abap     # Batch Master Role Creation & Menu Structuring tool
│   ├── z_auth_role_derive.prog.abap     # Batch Derived Role Creation & Inheritance Synchronization
│   ├── z_auth_role_update_org.prog.abap # Batch Organizational Levels Maintenance tool
│   ├── z_auth_test.prog.abap            # ABAP operational cockpit source code
│   ├── z_auth_user_create.prog.abap     # Batch SAP User Creation & Update tool
│   └── z_auth_user_assign_role.prog.abap # Batch User-Role Assignment tool
├── .sap.env.example            # SAP ADT connection template (never commit .sap.env)
├── mcp-config.example.json     # MCP server configuration snippet
├── package.json                # Project metadata & npm deploy scripts
├── LICENSE                     # MIT License
└── README.md                   # Project documentation & guides
```

---

## 2. Prerequisites

### Client Environment
- **Node.js**: `>= 22.0.0`
- **npm**: `>= 9.0.0`
- **Git**: Installed and available in `PATH`

### SAP System Requirements
- **Release**: SAP NetWeaver 7.50+ or SAP S/4HANA (On-Premise, Private Cloud, or BTP ABAP Environment)
- **Active SICF Service**: Sub-tree `/default_host/sap/bc/adt` must be active in transaction `SICF`
- **Network Reachability**: Workstation must reach SAP HTTPS port (e.g. `44300`, `44310`)
- **Authorizations**: SAP developer/technical user with `S_ADT_RES`, `S_RFC`, `S_DEVELOP`, and `S_TABU_DIS`

---

## 3. Quick Start

### Step 1: Clone Repository
```bash
git clone https://github.com/luongdk18/SAPABAP.git
cd SAPABAP
```

### Step 2: Install MCP Server CLI
```bash
npm install -g @mcp-abap-adt/core
```

### Step 3: Configure Environment Variables
Copy `.sap.env.example` to `.sap.env`:

- **Windows**:
  ```powershell
  Copy-Item .sap.env.example .sap.env
  ```
- **macOS / Linux**:
  ```bash
  cp .sap.env.example .sap.env
  ```

Update `.sap.env` with your SAP connection parameters:
```ini
SAP_URL=https://your-sap-host:44310
SAP_CLIENT=100
SAP_AUTH_TYPE=basic
SAP_SYSTEM_TYPE=onprem
SAP_USERNAME=YOUR_USER
SAP_PASSWORD=YOUR_PASSWORD
SAP_MASTER_SYSTEM=DEV
SAP_LANGUAGE=EN
NODE_TLS_REJECT_UNAUTHORIZED=0
```

> **Note**: `.sap.env` is excluded via `.gitignore`. Do not commit credentials to Git.

### Step 4: Deploy a Selected Program
Deploy a chosen ABAP utility (e.g. `Z_AUTH_TEST`):
```bash
npm run deploy -- Z_AUTH_TEST
```
*(Or run `npm run deploy` without arguments to choose interactively from the menu of available programs in `src/`).*

---

## 4. AI Agent Configuration

Connect your AI coding assistant to the SAP ADT MCP server:

### 4.1. Grok Build

**CLI command (fastest):**
- **Windows**:
  ```bash
  grok mcp add sap-s4hana -- cmd.exe /c mcp-abap-adt --transport=stdio --env-path=C:\path\to\SAPABAP\.sap.env
  ```
- **macOS / Linux**:
  ```bash
  grok mcp add sap-s4hana -- mcp-abap-adt --transport=stdio --env-path=/path/to/.sap.env
  ```

**Or in `~/.grok/config.toml`:**
```toml
[mcp_servers.sap-s4hana]
command = "cmd.exe"
args = ["/c", "mcp-abap-adt", "--transport=stdio", "--env-path=C:\\path\\to\\SAPABAP\\.sap.env"]
```

---

### 4.2. ChatGPT (Desktop & Codex)

#### ChatGPT Desktop App (macOS & Windows)
Add the server to your ChatGPT configuration file (`%APPDATA%\OpenAI\ChatGPT\mcp.json` on Windows or `~/.config/chatgpt/mcp.json` on macOS/Linux):
```json
{
  "mcpServers": {
    "sap-s4hana": {
      "command": "cmd.exe",
      "args": [
        "/c",
        "mcp-abap-adt",
        "--transport=stdio",
        "--env-path=C:\\path\\to\\SAPABAP\\.sap.env"
      ]
    }
  }
}
```
*(On macOS/Linux, set `"command": "mcp-abap-adt"` and pass `args: ["--transport=stdio", "--env-path=/path/to/.sap.env"]`).*

#### OpenAI Codex CLI
Add the server via the Codex CLI:
- **Windows**:
  ```bash
  codex mcp add sap-s4hana -- cmd.exe /c mcp-abap-adt --transport=stdio --env-path=C:\path\to\SAPABAP\.sap.env
  ```
- **macOS / Linux**:
  ```bash
  codex mcp add sap-s4hana -- mcp-abap-adt --transport=stdio --env-path=/path/to/.sap.env
  ```

---

### 4.3. Claude Desktop

In `claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "sap-s4hana": {
      "command": "cmd.exe",
      "args": [
        "/c",
        "mcp-abap-adt",
        "--transport=stdio",
        "--env-path=C:\\path\\to\\SAPABAP\\.sap.env"
      ]
    }
  }
}
```

---

### 4.4. Cursor IDE

In **Settings** -> **Features** -> **MCP Servers** -> **Add New MCP Server**:
- **Name**: `sap-s4hana`
- **Type**: `command`
- **Command**: `mcp-abap-adt --transport=stdio --env-path=C:\path\to\SAPABAP\.sap.env`

---

### 4.5. Google Antigravity

In `%USERPROFILE%\.gemini\config\mcp_config.json`:
```json
{
  "mcpServers": {
    "sap-s4hana": {
      "command": "cmd.exe",
      "args": [
        "/c",
        "mcp-abap-adt",
        "--transport=stdio",
        "--env-path=C:\\path\\to\\SAPABAP\\.sap.env"
      ]
    }
  }
}
```

---

### 4.6. VS Code (Cline / Roo Code / Continue)

In `cline_mcp_settings.json` or `.vscode/mcp.json`:
```json
{
  "mcpServers": {
    "sap-s4hana": {
      "command": "cmd.exe",
      "args": [
        "/c",
        "mcp-abap-adt",
        "--transport=stdio",
        "--env-path=C:\\path\\to\\SAPABAP\\.sap.env"
      ]
    }
  }
}
```

---

## 5. AI-Assisted ABAP Workflow

Once connected, AI agents can read, write, validate, and query SAP systems directly:

| Tool | Action | Example AI Usage |
| :--- | :--- | :--- |
| `SearchObject` | Object search | *"Search for function modules related to `SUSR_USER`"* |
| `GetProgram` / `GetClass` | Source inspection | *"Read the source code of report `Z_AUTH_TEST`"* |
| `UpdateProgram` / `UpdateClass` | Code authoring | *"Add a new subroutine to handle date filtering and save"* |
| `CheckProgram` / `CheckClass` | Syntax validation | *"Check syntax and report any compiler errors or warnings"* |
| `ActivateProgram` / `ActivateClass` | Object activation | *"Activate inactive objects after refactoring"* |
| `GetSqlQuery` | Data verification | *"Query 10 rows from table `USR02` to verify test accounts"* |
| `RuntimeGetDumpById` | Dump diagnostics | *"Inspect the latest ST22 dump and suggest a resolution"* |

---

## 6. Automated Program-by-Program Deployment

Deployment is explicitly designed to be **selective per program**—you choose exactly which ABAP program to upload and activate, rather than pushing everything in bulk:

### Option 1: Direct CLI by Program Name
```bash
# Convenient npm scripts defined in package.json:
npm run deploy:auth       # Deploys Z_AUTH_TEST
npm run deploy:role       # Deploys Z_AUTH_ROLE_CREATE
npm run deploy:derive     # Deploys Z_AUTH_ROLE_DERIVE
npm run deploy:org        # Deploys Z_AUTH_ROLE_UPDATE_ORG
npm run deploy:composite  # Deploys Z_AUTH_ROLE_COMPOSITE
npm run deploy:user       # Deploys Z_AUTH_USER_CREATE
npm run deploy:assign     # Deploys Z_AUTH_USER_ASSIGN_ROLE

# Or pass custom arguments:
npm run deploy -- Z_AUTH_TEST
node scripts/deploy.js src/z_auth_test.prog.abap Z_AUTH_TEST
```

### Option 2: Interactive Terminal Selection Menu
Run without arguments in an interactive terminal:
```bash
npm run deploy
```
The deploy script scans `src/`, lists all available ABAP programs, and asks you to select which one to deploy:
```text
📋 Select an ABAP program to deploy to SAP:
  [1] Z_AUTH_TEST (z_auth_test.prog.abap)
  ...
Enter number (1-1) or 'q' to cancel: 1
```

### Option 3: Deploy via Connected AI Assistant
In any MCP-connected AI assistant (Grok, ChatGPT/Codex, Claude, Cursor, Antigravity):
> *"Deploy `src/z_auth_test.prog.abap` as program `Z_AUTH_TEST` to the connected SAP system and activate it."*

### Execution Lifecycle:
1. Enqueue program lock via ADT
2. Run remote syntax check
3. Upload source code (Update or Create in `$TMP`)
4. Release lock
5. Verify inactive state and trigger remote activation

---

## 7. ABAP Utilities for SAP Basis

A primary objective of this repository is to build and maintain open-source ABAP utilities created with AI assistance to support SAP Basis administration and security operations.

### 7.1. Current Utility: Z_AUTH_TEST

- **Source Code**: [`src/z_auth_test.prog.abap`](src/z_auth_test.prog.abap)
- **Documentation**: [`docs/Z_AUTH_TEST.md`](docs/Z_AUTH_TEST.md) (Comprehensive technical reference & code analysis)
- **Purpose**: Automated SU53 buffer analyzer & PFCG single-role remediation cockpit.
- **Key Features**:
  - Aggregates all authorization check failures from the SU53 buffer over the last 3 hours via `SUSR_USER_SU53_READ`.
  - Evaluates authorization coverage against user single roles in real time.
  - Automatically incorporates all default fields from table `TOBJ` to maintain object integrity.
  - Resolves open Organizational Levels (`AGR_1252`) with wildcards.
  - Forces profile regeneration in background mode (`SUPRN_DARK_MANIPULATE_PROFILE`) without manual PFCG intervention.

### 7.2. Current Utility: Z_AUTH_ROLE_CREATE

- **Source Code**: [`src/z_auth_role_create.prog.abap`](src/z_auth_role_create.prog.abap)
- **Documentation**: [`docs/Z_AUTH_ROLE_CREATE.md`](docs/Z_AUTH_ROLE_CREATE.md) (Complete technical reference & workflow)
- **Companion Script**: [`scripts/convert_role_master_excel.py`](scripts/convert_role_master_excel.py)
- **Conversion Guide**: [`docs/ROLE_CONVERSION_GUIDE.md`](docs/ROLE_CONVERSION_GUIDE.md)
- **Purpose**: Batch PFCG Master Single Role Creation, Menu Folder Generation, and Authorization Profile Build from CSV (`.csv`).
- **Workflow & Key Features**:
  - **Excel Preprocessing**: `convert_role_master_excel.py` converts role matrix spreadsheets (columns containing TCodes with 'Y' checkmarks) into normalized CSV format (`Role Name`, `Role Description`, `TCode`). If a master role column has no TCodes marked with 'Y', it creates a single row with `TCode = 'N/A'`.
  - **Preserves Exact Spacing**: Role Description and Menu Folders preserve original whitespaces without stripping or condensing.
  - **Clean PFCG Descriptions**: Automatically cleans up default SAP generated comment lines (`"The role was created automatically and can be processed manually."`) from `AGR_TEXTS`.
  - **Master Role Architecture (Org Levels Defaulted to `-1`)**:
    - Avoids assigning wildcard `'*'` to Organizational Levels (`AGR_1252` and related authorization fields in `AGR_1251`).
    - Defaults all Organizational Levels to `'-1'` (standard template architecture for Master Roles), ensuring zero unintended authorization leakage while readying template roles for subsequent derivation into specialized operational roles.
  - **PFCG Menu Hierarchy**:
    - Automatically creates a dedicated **Menu Folder** named after the **Role Description** (e.g. `Folder = "GL Period Control"`).
    - Links all assigned TCodes as children under that folder.
  - **Automated Profile Generation**: Calls `PRGN_RFC_CREATE_ACTIVITY_GROUP` and `SUPRN_DARK_MANIPULATE_PROFILE` in background mode.
  - **Interactive ALV Grid**: Interactive execution cockpit with simulation mode (Test Run), non-blocking TCode verification against `TSTC` (isolating invalid TCodes to a separate column), Warning status (`@09@`) for roles without TCodes (`N/A`), and hotspot links to open `PFCG` directly.

### 7.3. Current Utility: Z_AUTH_ROLE_DERIVE

- **Source Code**: [`src/z_auth_role_derive.prog.abap`](src/z_auth_role_derive.prog.abap)
- **Documentation**: [`docs/Z_AUTH_ROLE_DERIVE.md`](docs/Z_AUTH_ROLE_DERIVE.md) (Complete technical reference & workflow)
- **Companion Script**: [`scripts/convert_role_derived_excel.py`](scripts/convert_role_derived_excel.py)
- **Conversion Guide**: [`docs/ROLE_CONVERSION_GUIDE.md`](docs/ROLE_CONVERSION_GUIDE.md)
- **Purpose**: Batch PFCG Derived Role Creation & Inheritance Synchronization from CSV (`.csv`).
- **Workflow & Key Features**:
  - **Upload Format**: Reads mapping CSV file (`Master Role`, `Derived Role`, `Derived Role Description`), generated via `convert_role_derived_excel.py`.
  - **Master Role Validation**: Validates that the imparting Master Role exists in SAP (`AGR_DEFINE`) and is a single role (rejects collective roles).
  - **Derived Role Creation**: Calls `PRGN_RFC_CREATE_AGR_MULTIPLE` to generate the derived role shell with `PARENT_AGR = master_role` and custom description without automatic comments.
  - **Authorization Inheritance & Profile Generation**: Calls `PRGN_RFC_CREATE_DERIVATION` to synchronize all authorization data from the Master Role and compile the authorization profile.
  - **Organizational Level Defaults**: Automatically defaults all inherited organizational levels to `"-1"` in `AGR_1252` and `AGR_1251`, readying roles for subsequent organization value specialization without triggering missing org errors.
  - **Interactive ALV Cockpit**: Features Simulation Mode (Test Run), Update Existing Roles option, and clickable hotspot links to jump directly into transaction `PFCG` for both Derived Roles and Master Roles.

### 7.4. Current Utility: Z_AUTH_ROLE_UPDATE_ORG

- **Source Code**: [`src/z_auth_role_update_org.prog.abap`](src/z_auth_role_update_org.prog.abap)
- **Documentation**: [`docs/Z_AUTH_ROLE_UPDATE_ORG.md`](docs/Z_AUTH_ROLE_UPDATE_ORG.md) (Complete technical reference & workflow)
- **Companion Script**: [`scripts/convert_role_org_excel.py`](scripts/convert_role_org_excel.py)
- **Org Levels Reference**: [`excel-templates/Org_Levels.csv`](excel-templates/Org_Levels.csv)
- **Conversion Guide**: [`docs/ROLE_CONVERSION_GUIDE.md`](docs/ROLE_CONVERSION_GUIDE.md)
- **Purpose**: Batch Update Organizational Levels in PFCG Roles from CSV (`.csv`).
- **Workflow & Key Features**:
  - **Upload Format**: Reads 3-column flat CSV format (`Role Name`, `Org Level Variable`, `Org Value`), generated from matrix sheets via `convert_role_org_excel.py`.
  - **Selective Role Org Maintenance**: Matches Org Level variables (`$BUKRS`, `$KOKRS`, `$ERKRS`, `$PRCTR`, etc.) against existing entries in `AGR_1252`, updating only the fields relevant to each role's authorization scope.
  - **Field Synchronization & Variable Restoration (`AGR_1251`)**: Restores corrupted variable bindings (`p_fix51 = 'X'`) mapped via table `USORG` to ensure consistency between Org Level headers and concrete field authorization values.
  - **Guaranteed Green Status (`p_astnon = 'X'`)**: Defaults unlisted secondary Org Levels to `'*'` so that the role achieves a 100% Green status in PFCG.
  - **Profile Regeneration & Verification**: Calls `SUPRN_DARK_MANIPULATE_PROFILE` without dialog and verifies the resulting status via `PRGN_CHECK_PROFILE_STATUS`.
  - **Interactive ALV Cockpit**: Displays simulation mode (Test Run), counts of file vs. updated Org levels, detail summary of updated values, and clickable hotspot links to inspect roles in `PFCG`.

### 7.5. Current Utility: Z_AUTH_ROLE_COMPOSITE

- **Source Code**: [`src/z_auth_role_composite.prog.abap`](src/z_auth_role_composite.prog.abap)
- **Documentation**: [`docs/Z_AUTH_ROLE_COMPOSITE.md`](docs/Z_AUTH_ROLE_COMPOSITE.md) (Complete technical reference & workflow)
- **Companion Script**: [`scripts/convert_role_composite_excel.py`](scripts/convert_role_composite_excel.py)
- **Conversion Guide**: [`docs/ROLE_CONVERSION_GUIDE.md`](docs/ROLE_CONVERSION_GUIDE.md)
- **Purpose**: Batch PFCG Composite Role Creation & Single Role Assignment from CSV (`.csv`).
- **Workflow & Key Features**:
  - **Upload Format**: Reads 3-column flat CSV format (`Composite Role Name`, `Composite Role Description`, `Derived / Single Role`), generated via `convert_role_composite_excel.py`.
  - **Native Composite Architecture**: Creates collective role definitions (`AGR_DEFINE-ATTRIBUTES = 'COLLECTIVE'`, `AGR_FLAGS-COLL_AGR = 'X'`) and strips intrusive automatic comments from `AGR_TEXTS`.
  - **Validation & Non-Blocking Isolation**: Validates member single roles in `AGR_DEFINE` and prevents nested composite roles. Missing roles are reported in the `MISSING_ROLES` column with a Warning status (`@09@`).
  - **Empty Composite Roles (`N/A`)**: Supports creating placeholder composite job roles with status `@09@` when marked as `N/A`.
  - **Atomic Assignment & Synchronization**: Assigns single roles via `PRGN_RFC_ADD_AGRS_TO_COLL_AGR` and synchronizes obsolete assignments via `PRGN_RFC_DEL_AGRS_IN_COLL_AGR` when `p_sync = 'X'`.
  - **Interactive ALV Cockpit**: Displays simulation mode (Test Run), counts of total vs. valid vs. assigned single roles, list of missing roles, and clickable hotspot links to inspect composite roles in `PFCG`.

### 7.6. Current Utility: Z_AUTH_USER_CREATE

- **Source Code**: [`src/z_auth_user_create.prog.abap`](src/z_auth_user_create.prog.abap)
- **Documentation**: [`docs/Z_AUTH_USER_CREATE.md`](docs/Z_AUTH_USER_CREATE.md) (Complete technical reference & workflow)
- **Companion Script**: [`scripts/convert_users_excel.py`](scripts/convert_users_excel.py)
- **CSV Template**: [`excel-templates/Template_Users_Create_converted.csv`](excel-templates/Template_Users_Create_converted.csv)
- **Purpose**: Batch SAP User Creation & Update Cockpit from CSV (`.csv`).
- **Workflow & Key Features**:
  - **Upload Format**: Reads 7-column flat CSV format (`Username`, `Initial Password`, `Full Name`, `Email`, `Phone No.`, `Department`, `Function`), preprocessed and validated via `convert_users_excel.py`.
  - **Full Name Mapping Rule**: Maps **Full Name** entirely into SAP **Last Name** (`BAPIADDR3-LASTNAME`), fulfilling SAP mandatory field constraints while keeping full employee names intact.
  - **UTF-8 Character Integrity**: Uploads in binary mode (`'BIN'`) and decodes via `SCMS_BINARY_TO_STRING` with encoding `'4110'`, flawlessly supporting Vietnamese accents (`Đào Việt Hùng`, `Lê Văn Nam`, etc.) and stripping UTF-8 BOM (`U+FEFF`).
  - **Dual Operation Modes**: Supports Simulation Mode (Test Run) to preview actions without database commit, and Live Mode calling `BAPI_USER_CREATE1` or `BAPI_USER_CHANGE` with `BAPI_TRANSACTION_COMMIT`.
  - **Safe Update Handling**: Skips existing users with a Yellow LED (`@09@`) by default; in-place update and password reset can be explicitly enabled via `p_upd = 'X'` and `p_pwd = 'X'`.
  - **Interactive ALV Cockpit**: Features formatted LED status indicators (`@08@` Green, `@09@` Yellow, `@0A@` Red), comprehensive execution messages, and one-click hotspot navigation on the **Username** column directly into transaction `SU01`.

### 7.7. Current Utility: Z_AUTH_USER_ASSIGN_ROLE

- **Source Code**: [`src/z_auth_user_assign_role.prog.abap`](src/z_auth_user_assign_role.prog.abap)
- **Documentation**: [`docs/Z_AUTH_USER_ASSIGN_ROLE.md`](docs/Z_AUTH_USER_ASSIGN_ROLE.md) (Complete technical reference & workflow)
- **Companion Script**: [`scripts/convert_users_assign_roles_excel.py`](scripts/convert_users_assign_roles_excel.py)
- **CSV Template**: [`excel-templates/Template_User_Assign_Role_converted.csv`](excel-templates/Template_User_Assign_Role_converted.csv)
- **Conversion Guide**: [`docs/ROLE_CONVERSION_GUIDE.md`](docs/ROLE_CONVERSION_GUIDE.md)
- **Purpose**: Batch User-to-Role Assignment Cockpit from CSV (`.csv`).
- **Workflow & Key Features**:
  - **Upload Format**: Reads 2-column flat CSV format (`Username`, `Role`), preprocessed and extracted from role assignment matrices via `convert_users_assign_roles_excel.py`.
  - **Multi-Role Aggregation**: Automatically groups and consolidates multiple role entries per user into a single structured assignment list.
  - **Repository & User Validation**: Validates user existence against table `USR02` and role definitions against `AGR_DEFINE` (supporting single roles, derived roles, and composite roles). Missing roles are isolated into a dedicated `MISSING_ROLES` column with Yellow LED (`@09@`).
  - **Safe Append Mode**: Default **Append Mode (`p_append = 'X'`)** queries `AGR_USERS` for currently assigned direct roles (`COL_FLAG = space`) and merges them with the new roles, safely preserving existing user authorizations. Full replace mode can be activated by unchecking the option.
  - **Graceful Empty Handling (`N/A`)**: Gracefully handles users without assigned roles (`N/A`) with a Warning status (`@09@`), avoiding unintended error blocks.
  - **Direct Assignment & Composite Expansion**: Automatically handles composite roles: assigning a composite role prompts SAP to provision and manage all underlying single roles.
  - **Interactive ALV Cockpit**: Features formatted LED status indicators (`@08@` Green, `@09@` Yellow, `@0A@` Red), counts of CSV vs. valid vs. assigned roles, and one-click hotspot navigation on the **Username** column directly into transaction `SU01`.

### 7.8. Python Preprocessing Pipeline Guide

- **Documentation**: [`docs/ROLE_CONVERSION_GUIDE.md`](docs/ROLE_CONVERSION_GUIDE.md)
- **Purpose**: Complete guide on preparing Excel matrix sheets, converting them to normalized 3-column CSVs, and validating them before uploading to the SAP ABAP programs.
- **Convenient npm Run Commands**:
  - `npm run convert:role:master`: Converts Master Role Matrix (`.xlsx`) to `_converted.csv`.
  - `npm run convert:role:derived`: Converts Derived Role Creation Matrix (`.xlsx`) to `_converted.csv`.
  - `npm run convert:role:org`: Converts Derived Org Matrix (`.xlsx`) referencing `excel-templates/Org_Levels.csv` to `_converted.csv`.
  - `npm run convert:role:composite`: Converts Composite Roles Matrix (`.xlsx`) to `_converted.csv`.
  - `npm run convert:role:all`: Runs all role matrix converters sequentially.
  - `npm run convert:user:create`: Converts User Creation Excel (`.xlsx`) to normalized CSV with auto-generated initial passwords and (<country>)<number> phone numbers.
  - `npm run convert:user:assign`: Converts User Role Assignment Matrix (`.xlsx`) to flat `Username,Role` CSV format.
- **Smart Directory Resolution**: Scripts prioritize real files in `excel-working/` (git-ignored) first, then fallback to `excel-templates/`, preserving confidential corporate data.

### 7.9. Future Utilities Roadmap

Additional ABAP utilities for SAP Basis will be developed and added to this repository:
- **Authorization & User Governance**: Role assignment analyzer, dormant user cleanup, and unassigned profile auditing.
- **System Monitoring & Health**: Buffer utilization monitor, table size diagnostic tools, and ST22 dump pattern aggregators.
- **Operations & Batch Jobs**: Background job dependency inspector and enqueue lock (`SM12`) automation helpers.

---

## 8. Security & Best Practices

1. **Keep `.sap.env` Private**: Never commit `.sap.env` to source control.
2. **Dedicated User Account**: Use a designated developer user rather than `SAP*` or `DDIC`.
3. **Target Package**: Default deployment targets local package `$TMP`. For transportable developments, specify appropriate development packages and transport requests.
4. **Production Safeguards**: Restrict production ADT endpoints to read-only access.

---

## 9. License

This project is licensed under the [MIT License](LICENSE).

---

## 10. Disclaimer & Trademark Notice

SAP, SAP S/4HANA, SAP NetWeaver, ABAP, and other SAP products and services mentioned herein are trademarks or registered trademarks of SAP SE in Germany and other countries. This repository is an independent open-source technical project and is not affiliated with, endorsed by, or sponsored by SAP SE.

