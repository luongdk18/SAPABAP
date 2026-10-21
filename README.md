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
   - [7.1. Module 1: Role Management (Z_ROLE_...)](#71-module-1-role-management-z_role_)
     - [7.1.1. Z_ROLE_01_CREATE_MASTER](#711-z_role_01_create_master)
     - [7.1.2. Z_ROLE_02_CREATE_DERIVE](#712-z_role_02_create_derive)
     - [7.1.3. Z_ROLE_03_UPDATE_ORG](#713-z_role_03_update_org)
     - [7.1.4. Z_ROLE_04_COMPOSITE](#714-z_role_04_composite)
   - [7.2. Module 2: User Management (Z_USER_...)](#72-module-2-user-management-z_user_)
     - [7.2.1. Z_USER_01_CREATE](#721-z_user_01_create)
     - [7.2.2. Z_USER_02_ASSIGN_ROLE](#722-z_user_02_assign_role)
   - [7.3. Module 3: Diagnostics & Utilities (Z_AUTH_...)](#73-module-3-diagnostics--utilities-z_auth_)
     - [7.3.1. Z_AUTH_SU53_ANALYZER](#731-z_auth_su53_analyzer)
   - [7.4. Python Preprocessing Pipeline Guide](#74-python-preprocessing-pipeline-guide)
   - [7.5. Future Utilities Roadmap](#75-future-utilities-roadmap)
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
   └── ABAP Utilities (Z_ROLE_*, Z_USER_*, Z_AUTH_*)
```

### Repository Structure

```
.
├── assets/
│   └── logo.svg                # Repository brand logo
├── docs/
│   ├── ROLE_CONVERSION_GUIDE.md # Preprocessing guide for Excel-to-CSV converters
│   ├── Z_ROLE_01_CREATE_MASTER.md # Master single role batch creation & menu documentation
│   ├── Z_ROLE_02_CREATE_DERIVE.md # Derived role creation & inheritance documentation
│   ├── Z_ROLE_03_UPDATE_ORG.md    # Organizational levels batch update documentation
│   ├── Z_ROLE_04_COMPOSITE.md     # Composite role creation & single role assignment docs
│   ├── Z_USER_01_CREATE.md        # Batch user creation & update cockpit documentation
│   ├── Z_USER_02_ASSIGN_ROLE.md   # Batch user role assignment cockpit documentation
│   └── Z_AUTH_SU53_ANALYZER.md    # SU53 failure analyzer & role provisioning cockpit docs
├── excel-templates/            # Anonymized templates & sample data for batch upload
│   ├── Org_Levels.csv          # Standard SAP 71 Organizational Level definitions
│   ├── Template_Role_01_Master.xlsx
│   ├── Template_Role_01_Master_converted.csv
│   ├── Template_Role_02_Derived.xlsx
│   ├── Template_Role_02_Derived_converted.csv
│   ├── Template_Role_03_Org.xlsx
│   ├── Template_Role_03_Org_converted.csv
│   ├── Template_Role_04_Composite.xlsx
│   ├── Template_Role_04_Composite_converted.csv
│   ├── Template_User_01_Create.xlsx
│   ├── Template_User_01_Create_converted.csv
│   ├── Template_User_02_Assign.xlsx
│   └── Template_User_02_Assign_converted.csv
├── scripts/
│   ├── convert_role_01_master.py   # Preprocessing script: Master role matrix to CSV
│   ├── convert_role_02_derive.py   # Derived role creation mapping to flat CSV
│   ├── convert_role_03_org.py      # Derived role org matrix to flat CSV referencing Org_Levels.csv
│   ├── convert_role_04_composite.py# Composite roles matrix to flat CSV
│   ├── convert_user_01_create.py   # User creation Excel to normalized CSV with passwords
│   ├── convert_user_02_assign.py   # User role assignment matrix to flat CSV
│   ├── create_templates.py         # Generates anonymized sample Excel and CSV templates
│   ├── generate_org_levels_csv.py  # Generates standard Org_Levels.csv reference
│   └── deploy.js                   # CLI deployment engine via MCP ADT
├── src/
│   ├── z_role_01_create_master.prog.abap # Batch Master Role Creation & Menu Structuring
│   ├── z_role_02_create_derive.prog.abap # Batch Derived Role Creation & Inheritance
│   ├── z_role_03_update_org.prog.abap    # Batch Organizational Levels Maintenance
│   ├── z_role_04_composite.prog.abap     # Batch Composite Role Creation & Assignment
│   ├── z_user_01_create.prog.abap        # Batch SAP User Creation & Update Cockpit
│   ├── z_user_02_assign_role.prog.abap   # Batch User-Role Assignment Cockpit
│   └── z_auth_su53_analyzer.prog.abap    # SU53 Buffer Analyzer & Remediation Cockpit
├── .sap.env.example            # SAP ADT connection template (never commit .sap.env)
├── mcp-config.example.json     # MCP server configuration snippet
├── package.json                # Project metadata & npm scripts
├── LICENSE                     # MIT License
└── README.md                   # Project documentation & guides
```

---

## 2. Prerequisites

### Client Environment
- **Node.js**: `>= 22.0.0`
- **npm**: `>= 9.0.0`
- **Python**: `>= 3.9` with `openpyxl`
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
Deploy a chosen ABAP utility (e.g. `Z_ROLE_01_CREATE_MASTER`):
```bash
npm run deploy:role:01
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

In your ChatGPT MCP settings file:
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

### 4.3. Claude Desktop

In `%APPDATA%\Claude\claude_desktop_config.json`:
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

In Cursor Settings $\rightarrow$ Features $\rightarrow$ MCP Servers:
- **Name**: `sap-s4hana`
- **Type**: `command`
- **Command**: `cmd.exe /c mcp-abap-adt --transport=stdio --env-path=C:\path\to\SAPABAP\.sap.env`

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
| `GetProgram` / `GetClass` | Source inspection | *"Read the source code of report `Z_ROLE_01_CREATE_MASTER`"* |
| `UpdateProgram` / `UpdateClass` | Code authoring | *"Add a new subroutine to handle date filtering and save"* |
| `CheckProgram` / `CheckClass` | Syntax validation | *"Check syntax and report any compiler errors or warnings"* |
| `ActivateProgram` / `ActivateClass` | Object activation | *"Activate inactive objects after refactoring"* |
| `GetSqlQuery` | Data verification | *"Query 10 rows from table `USR02` to verify test accounts"* |
| `RuntimeGetDumpById` | Dump diagnostics | *"Inspect the latest ST22 dump and suggest a resolution"* |

---

## 6. Automated Program-by-Program Deployment

Deployment is explicitly designed to be **selective per program**—you choose exactly which ABAP program to upload and activate:

### Option 1: Direct CLI by Program Name
```bash
# Module 1: Role Management
npm run deploy:role:01      # Deploys Z_ROLE_01_CREATE_MASTER
npm run deploy:role:02      # Deploys Z_ROLE_02_CREATE_DERIVE
npm run deploy:role:03      # Deploys Z_ROLE_03_UPDATE_ORG
npm run deploy:role:04      # Deploys Z_ROLE_04_COMPOSITE
npm run deploy:role:all     # Deploys all Role Management programs

# Module 2: User Management
npm run deploy:user:01      # Deploys Z_USER_01_CREATE
npm run deploy:user:02      # Deploys Z_USER_02_ASSIGN_ROLE
npm run deploy:user:all     # Deploys all User Management programs

# Module 3: Diagnostics & Utilities
npm run deploy:su53         # Deploys Z_AUTH_SU53_ANALYZER

# Deploy Everything
npm run deploy:all

# Custom explicit command:
node scripts/deploy.js src/z_role_01_create_master.prog.abap Z_ROLE_01_CREATE_MASTER
```

### Option 2: Interactive Terminal Selection Menu
Run without arguments in an interactive terminal:
```bash
npm run deploy
```
The deploy script scans `src/`, lists all available ABAP programs, and asks you to select which one to deploy:
```text
📋 Select an ABAP program to deploy to SAP:
  [1] Z_AUTH_SU53_ANALYZER (z_auth_su53_analyzer.prog.abap)
  [2] Z_ROLE_01_CREATE_MASTER (z_role_01_create_master.prog.abap)
  [3] Z_ROLE_02_CREATE_DERIVE (z_role_02_create_derive.prog.abap)
  [4] Z_ROLE_03_UPDATE_ORG (z_role_03_update_org.prog.abap)
  [5] Z_ROLE_04_COMPOSITE (z_role_04_composite.prog.abap)
  [6] Z_USER_01_CREATE (z_user_01_create.prog.abap)
  [7] Z_USER_02_ASSIGN_ROLE (z_user_02_assign_role.prog.abap)

Enter number (1-7) or 'q' to cancel: 2
```

### Option 3: Deploy via Connected AI Assistant
In any MCP-connected AI assistant (Grok, ChatGPT/Codex, Claude, Cursor, Antigravity):
> *"Deploy `src/z_role_01_create_master.prog.abap` as program `Z_ROLE_01_CREATE_MASTER` to the connected SAP system and activate it."*

---

## 7. ABAP Utilities for SAP Basis

### 7.1. Module 1: Role Management (`Z_ROLE_...`)

#### 7.1.1. Z_ROLE_01_CREATE_MASTER
- **Source Code**: [`src/z_role_01_create_master.prog.abap`](src/z_role_01_create_master.prog.abap)
- **Documentation**: [`docs/Z_ROLE_01_CREATE_MASTER.md`](docs/Z_ROLE_01_CREATE_MASTER.md)
- **Companion Script**: [`scripts/convert_role_01_master.py`](scripts/convert_role_01_master.py)
- **Template**: [`excel-templates/Template_Role_01_Master.xlsx`](excel-templates/Template_Role_01_Master.xlsx) & `_converted.csv`
- **Purpose**: Batch PFCG Master Single Role Creation, Menu Folder Generation, and Authorization Profile Build from CSV.
- **Key Features**:
  - Converts role matrix spreadsheets into normalized CSV format (`Role Name`, `Role Description`, `TCode`).
  - Preserves exact formatting and whitespaces in role and folder descriptions.
  - Cleans up standard SAP boilerplate comments from `AGR_TEXTS`.
  - Defaults all Organizational Levels to `'-1'` to prevent wildcard security leakage.
  - Constructs structured menu hierarchies under dedicated role folders.
  - Features simulation mode, non-blocking TCode verification against `TSTC`, and one-click hotspot jump to `PFCG`.

#### 7.1.2. Z_ROLE_02_CREATE_DERIVE
- **Source Code**: [`src/z_role_02_create_derive.prog.abap`](src/z_role_02_create_derive.prog.abap)
- **Documentation**: [`docs/Z_ROLE_02_CREATE_DERIVE.md`](docs/Z_ROLE_02_CREATE_DERIVE.md)
- **Companion Script**: [`scripts/convert_role_02_derive.py`](scripts/convert_role_02_derive.py)
- **Template**: [`excel-templates/Template_Role_02_Derived.xlsx`](excel-templates/Template_Role_02_Derived.xlsx) & `_converted.csv`
- **Purpose**: Batch PFCG Derived Role Creation & Inheritance Synchronization from CSV.
- **Key Features**:
  - Validates that the imparting Master Role exists in SAP (`AGR_DEFINE`) and is a single role.
  - Automatically creates derived roles with `PARENT_AGR` link.
  - Inherits menu and authorizations via `PRGN_RFC_CREATE_DERIVATION`.
  - Initializes inherited Org Levels to `'-1'` to allow clean background profile generation.
  - Supports re-synchronizing authorizations when master roles are updated.
  - Interactive ALV cockpit with two-way hotspot navigation to `PFCG` for both derived and master roles.

#### 7.1.3. Z_ROLE_03_UPDATE_ORG
- **Source Code**: [`src/z_role_03_update_org.prog.abap`](src/z_role_03_update_org.prog.abap)
- **Documentation**: [`docs/Z_ROLE_03_UPDATE_ORG.md`](docs/Z_ROLE_03_UPDATE_ORG.md)
- **Companion Script**: [`scripts/convert_role_03_org.py`](scripts/convert_role_03_org.py)
- **Org Levels Reference**: [`excel-templates/Org_Levels.csv`](excel-templates/Org_Levels.csv)
- **Template**: [`excel-templates/Template_Role_03_Org.xlsx`](excel-templates/Template_Role_03_Org.xlsx) & `_converted.csv`
- **Purpose**: Batch Organizational Levels Maintenance & Profile Regeneration from CSV.
- **Key Features**:
  - Updates only the Organizational Levels (`AGR_1252`) relevant to each role's authorizations.
  - Restores corrupted variable bindings (`p_fix51 = 'X'`) in `AGR_1251` using table `USORG`.
  - Guaranteed Green Status (`p_astnon = 'X'`): defaults unlisted secondary Org Levels to `'*'` so profiles compile without warnings.
  - Compiles runtime authorization profiles in dark mode and verifies LED status (`PRGN_CHECK_PROFILE_STATUS`).

#### 7.1.4. Z_ROLE_04_COMPOSITE
- **Source Code**: [`src/z_role_04_composite.prog.abap`](src/z_role_04_composite.prog.abap)
- **Documentation**: [`docs/Z_ROLE_04_COMPOSITE.md`](docs/Z_ROLE_04_COMPOSITE.md)
- **Companion Script**: [`scripts/convert_role_04_composite.py`](scripts/convert_role_04_composite.py)
- **Template**: [`excel-templates/Template_Role_04_Composite.xlsx`](excel-templates/Template_Role_04_Composite.xlsx) & `_converted.csv`
- **Purpose**: Batch Composite Role Creation & Single Role Assignment from CSV.
- **Key Features**:
  - Creates collective role definitions (`AGR_DEFINE-ATTRIBUTES = 'COLLECTIVE'`, `AGR_FLAGS-COLL_AGR = 'X'`).
  - Validates member single roles in `AGR_DEFINE` and prevents nested composite roles.
  - Missing roles are isolated into a dedicated column with Warning status (`@09@`).
  - Supports placeholder composite roles (`N/A`) and synchronizes memberships (`p_sync = 'X'`).

---

### 7.2. Module 2: User Management (`Z_USER_...`)

#### 7.2.1. Z_USER_01_CREATE
- **Source Code**: [`src/z_user_01_create.prog.abap`](src/z_user_01_create.prog.abap)
- **Documentation**: [`docs/Z_USER_01_CREATE.md`](docs/Z_USER_01_CREATE.md)
- **Companion Script**: [`scripts/convert_user_01_create.py`](scripts/convert_user_01_create.py)
- **Template**: [`excel-templates/Template_User_01_Create.xlsx`](excel-templates/Template_User_01_Create.xlsx) & `_converted.csv`
- **Purpose**: Batch SAP User Creation & Master Data Update Cockpit from CSV.
- **Key Features**:
  - Maps **Full Name** entirely into SAP **Last Name** (`BAPIADDR3-LASTNAME`) to satisfy mandatory constraints without arbitrary splitting.
  - Binary UTF-8 upload with BOM stripping, preserving Vietnamese accents and international characters.
  - Automatically verifies email syntax (`SX_INTERNET_ADDRESS_TO_NORMAL`) and ignores invalid formats.
  - Displays initial logon passwords directly on the ALV grid for audit and distribution.
  - Supports simulation mode, in-place user updates (`p_upd = 'X'`), password resets (`p_pwd = 'X'`), and one-click jump to `SU01`.

#### 7.2.2. Z_USER_02_ASSIGN_ROLE
- **Source Code**: [`src/z_user_02_assign_role.prog.abap`](src/z_user_02_assign_role.prog.abap)
- **Documentation**: [`docs/Z_USER_02_ASSIGN_ROLE.md`](docs/Z_USER_02_ASSIGN_ROLE.md)
- **Companion Script**: [`scripts/convert_user_02_assign.py`](scripts/convert_user_02_assign.py)
- **Template**: [`excel-templates/Template_User_02_Assign.xlsx`](excel-templates/Template_User_02_Assign.xlsx) & `_converted.csv`
- **Purpose**: Batch User-to-Role Assignment Cockpit from CSV.
- **Key Features**:
  - Aggregates multi-role assignments per user into a single atomic call via `BAPI_USER_ACTGROUPS_ASSIGN`.
  - Validates user existence (`USR02`) and role definitions (`AGR_DEFINE`).
  - Default **Append Mode (`p_append = 'X'`)** preserves existing user roles; optional replace mode.
  - Seamlessly assigns Composite Roles (expanding to member single roles automatically) and Single Roles.
  - Interactive ALV grid with clickable hotspot on Username directly into transaction `SU01`.

---

### 7.3. Module 3: Diagnostics & Utilities (`Z_AUTH_...`)

#### 7.3.1. Z_AUTH_SU53_ANALYZER
- **Source Code**: [`src/z_auth_su53_analyzer.prog.abap`](src/z_auth_su53_analyzer.prog.abap)
- **Documentation**: [`docs/Z_AUTH_SU53_ANALYZER.md`](docs/Z_AUTH_SU53_ANALYZER.md)
- **Purpose**: Automated SU53 buffer analyzer & PFCG single-role remediation cockpit.
- **Key Features**:
  - Aggregates all authorization check failures from the SU53 buffer over the last 3 hours via `SUSR_USER_SU53_READ`.
  - Evaluates authorization coverage against user single roles in real time.
  - Incorporates all mandatory default fields from table `TOBJ` to maintain object integrity (no yellow triangles).
  - Resolves open Organizational Levels (`AGR_1252`) with wildcards.
  - Forces profile regeneration in background mode (`SUPRN_DARK_MANIPULATE_PROFILE`) without manual PFCG intervention.

---

### 7.4. Python Preprocessing Pipeline Guide

- **Documentation**: [`docs/ROLE_CONVERSION_GUIDE.md`](docs/ROLE_CONVERSION_GUIDE.md)
- **Purpose**: Complete guide on preparing Excel matrix sheets, converting them to normalized CSVs, and validating them before uploading to SAP.
- **Convenient npm Run Commands**:
  - `npm run convert:role:01`: Converts Master Role Matrix (`.xlsx`) to `_converted.csv`.
  - `npm run convert:role:02`: Converts Derived Role Creation Matrix (`.xlsx`) to `_converted.csv`.
  - `npm run convert:role:03`: Converts Derived Org Matrix (`.xlsx`) referencing `excel-templates/Org_Levels.csv`.
  - `npm run convert:role:04`: Converts Composite Roles Matrix (`.xlsx`) to `_converted.csv`.
  - `npm run convert:role:all`: Runs all role matrix converters sequentially.
  - `npm run convert:user:01`: Converts User Creation Excel to normalized CSV with secure passwords.
  - `npm run convert:user:02`: Converts User Role Assignment Matrix to flat `Username,Role` CSV format.
  - `npm run convert:user:all`: Runs both user converters sequentially.
  - `npm run convert:all`: Runs all role and user converters.
  - `npm run templates:generate`: Regenerates all masked templates in `excel-templates/`.
- **Smart Directory Resolution**: Scripts prioritize real files in `excel-working/` (git-ignored) first, then fallback to `excel-templates/`, preserving confidential corporate data.

---

### 7.5. Future Utilities Roadmap

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
5. **Data Confidentiality**: Maintain actual company data inside `excel-working/` (which is excluded from Git), and only commit anonymized data inside `excel-templates/`.

---

## 9. License

This project is licensed under the [MIT License](LICENSE).

---

## 10. Disclaimer & Trademark Notice

SAP, SAP S/4HANA, SAP NetWeaver, ABAP, and other SAP products and services mentioned herein are trademarks or registered trademarks of SAP SE in Germany and other countries. This repository is an independent open-source technical project and is not affiliated with, endorsed by, or sponsored by SAP SE.
