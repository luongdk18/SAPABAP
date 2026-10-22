<p align="center">
  <img src="assets/logo.svg" width="64" height="64" alt="SAP ABAP Logo">
</p>

# SAP ABAP with AI & Model Context Protocol (MCP)

> Enterprise ABAP utilities developed with AI agents via ABAP Development Tools (ADT) MCP to streamline SAP Basis and Security operations.

---

## Table of Contents

1. [Overview & Architecture](#1-overview--architecture)
2. [Quick Start](#2-quick-start)
3. [AI Agent Setup (MCP)](#3-ai-agent-setup-mcp)
4. [Deployment Commands](#4-deployment-commands)
5. [Python Preprocessing Pipeline](#5-python-preprocessing-pipeline)
6. [ABAP Utilities for SAP Basis](#6-abap-utilities-for-sap-basis)
   - [Role Management (Z_ROLE_*)](#61-role-management-z_role_)
   - [User Management (Z_USER_*)](#62-user-management-z_user_)
   - [Diagnostics (Z_AUTH_*)](#63-diagnostics-z_auth_)
7. [Security & Best Practices](#7-security--best-practices)

---

## 1. Overview & Architecture

This repository connects AI coding assistants directly to live **SAP S/4HANA** and **SAP ECC** systems using the **Model Context Protocol (MCP)** via **ABAP Development Tools (ADT)**.

```
[ AI Agents: Antigravity / Cursor / Claude / ChatGPT / Grok ]
                           │
                           │  stdio / JSON-RPC (MCP)
                           ▼
              [ @mcp-abap-adt/core CLI ]
                           │
                           │  HTTPS (SAP ADT REST API)
                           ▼
              [ SAP S/4HANA / NetWeaver ]
         ├── ADT Services (/sap/bc/adt)
         └── Utilities: Z_ROLE_*, Z_USER_*, Z_AUTH_*
```

### Repository Structure

```text
.
├── docs/                 # Streamlined technical documentation
├── excel-templates/      # Anonymized templates & sample data
│   ├── Org_Levels.csv    # Standard SAP 55 Org Level definitions (USORG)
│   ├── Object_Levels.csv # Standard SAP 13,457 Authorization Object definitions
│   ├── Template_Role.xlsx # All-in-one consolidated role template (Sheets 1, 2, 3)
│   ├── *.xlsx            # Standalone matrix templates (Roles & Users)
│   └── converted/        # Sample converted CSVs for batch upload
├── excel-working/        # Real business matrices (Git-ignored)
│   └── converted/        # Converted CSV outputs (Git-ignored)
├── scripts/              # Python preprocessors & Node.js deployer
│   ├── convert_role_01_master.py    # Master Role matrix -> CSV
│   ├── convert_role_02_derive.py    # Derived Role mapping -> CSV
│   ├── convert_role_03_org_obj.py   # Unified Org & Object classifier -> 2 CSVs
│   ├── convert_role_04_composite.py # Composite Role matrix -> CSV
│   ├── convert_user_01_create.py    # User list -> normalized CSV
│   ├── convert_user_02_assign.py    # User-Role matrix -> CSV
│   ├── create_templates.py          # Regenerates templates
│   └── deploy.js                    # Automated ADT deployer
├── src/                  # Production-ready ABAP source programs
│   ├── z_role_01_create_master.prog.abap
│   ├── z_role_02_create_derive.prog.abap
│   ├── z_role_03_update_org.prog.abap
│   ├── z_role_03_update_object.prog.abap
│   ├── z_role_04_composite.prog.abap
│   ├── z_user_01_create.prog.abap
│   ├── z_user_02_assign_role.prog.abap
│   └── z_auth_su53_analyzer.prog.abap
├── .sap.env.example      # Connection config template
└── package.json          # npm task runner scripts
```

---

## 2. Quick Start

### 1. Prerequisites
- **Node.js**: `>= 22.0.0` | **npm**: `>= 9.0.0`
- **Python**: `>= 3.9` with `openpyxl`
- **SAP**: NetWeaver 7.50+ / S/4HANA with active `/sap/bc/adt` in `SICF`

### 2. Setup
```bash
# Clone repository
git clone https://github.com/luongdk18/SAPABAP.git
cd SAPABAP

# Install ADT MCP globally
npm install -g @mcp-abap-adt/core

# Copy & configure credentials (never commit .sap.env!)
cp .sap.env.example .sap.env
```

### 3. Configure `.sap.env`
```ini
SAP_URL=https://your-sap-host:44310
SAP_CLIENT=100
SAP_AUTH_TYPE=basic
SAP_USERNAME=YOUR_USER
SAP_PASSWORD=YOUR_PASSWORD
SAP_LANGUAGE=EN
NODE_TLS_REJECT_UNAUTHORIZED=0
SAP_PACKAGE=$TMP
# SAP_TRANSPORT_REQUEST=DEVK900001 # Required if SAP_PACKAGE != $TMP
```

---

## 3. AI Agent Setup (MCP)

Add to your AI agent's MCP configuration (`mcpServers` object):

```json
{
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
```
*(On macOS/Linux, replace `cmd.exe /c` with direct `mcp-abap-adt`).*

---

## 4. Deployment Commands

Deploy and activate ABAP programs selectively to the connected SAP system:

| Command | Deploys Program | Description |
| :--- | :--- | :--- |
| `npm run deploy:role:01` | `Z_ROLE_01_CREATE_MASTER` | Batch Master Role & Menu Creation |
| `npm run deploy:role:02` | `Z_ROLE_02_CREATE_DERIVE` | Batch Derived Role Derivation |
| `npm run deploy:role:03` | *Both 03a & 03b Programs* | Full Org & Object Maintenance |
| `npm run deploy:role:03a` | `Z_ROLE_03_UPDATE_ORG` | Batch Organizational Levels Maintenance |
| `npm run deploy:role:03b` | `Z_ROLE_03_UPDATE_OBJECT` | Batch Authorization Objects Maintenance |
| `npm run deploy:role:04` | `Z_ROLE_04_COMPOSITE` | Batch Composite Role Bundling |
| `npm run deploy:role:all` | *All 5 Role Programs* | Full Role Lifecycle Deployment |
| `npm run deploy:user:01` | `Z_USER_01_CREATE` | Batch SAP User Creation & Update |
| `npm run deploy:user:02` | `Z_USER_02_ASSIGN_ROLE` | Batch User-to-Role Assignment |
| `npm run deploy:user:all` | *Both User Programs* | Full User Management Deployment |
| `npm run deploy:su53` | `Z_AUTH_SU53_ANALYZER` | SU53 Buffer Diagnostics Cockpit |
| `npm run deploy:all` | *All 8 Programs* | Complete Project Deployment |
| `npm run deploy` | *Interactive Menu* | Select program from terminal prompt |

---

## 5. Python Preprocessing Pipeline

Convert business Excel matrices into flat, normalized CSV files.

- **All-in-One Role Workbook**: Supports a single consolidated workbook (`*_Role.xlsx`, e.g. `FICO_Role.xlsx` or `Template_Role.xlsx`):
  - **Sheet 1**: Master Roles (Menu & TCodes)
  - **Sheet 2**: Derived Roles & Org + Object Levels (Cols 1-3: Role mapping, Cols 4+: Org & Object mixed)
  - **Sheet 3**: Composite Roles (Role bundling)
- **Unified Org & Object Separation**: `convert_role_03_org_obj.py` automatically distinguishes Org Levels (`*_03a_Org_Levels_converted.csv`) from Authorization Objects (`*_03b_Auth_Objects_converted.csv`) with zero overlap and excludes `S_TCODE-TCD`.
- **Legacy Compatibility**: Standalone files (`*_01_Master.xlsx`, etc.) remain fully supported.
- **Output Destination**: Automatically saves to `<parent_dir>/converted/<name>_converted.csv`.
- **Confidentiality**: Files in `excel-working/` and `excel-working/converted/` are protected by `.gitignore`.

| npm Shortcut | Script | Input Matrix | Output CSV |
| :--- | :--- | :--- | :--- |
| `npm run convert:role:01` | `convert_role_01_master.py` | Sheet 1 / Master Roles Matrix | `*_Role_01_Master_converted.csv` |
| `npm run convert:role:02` | `convert_role_02_derive.py` | Sheet 2 / Derived Roles Mapping | `*_Role_02_Derived_converted.csv` |
| `npm run convert:role:03` | `convert_role_03_org_obj.py` | Sheet 2 / Org & Object Mixed | `*_Role_03a_Org_Levels_converted.csv`<br>`*_Role_03b_Auth_Objects_converted.csv` |
| `npm run convert:role:04` | `convert_role_04_composite.py`| Sheet 3 / Composite Roles Matrix | `*_Role_04_Composite_converted.csv` |
| `npm run convert:role:all`| *Runs all 4 Role converters* | Consolidated `*_Role.xlsx` or separate | All Role CSVs in `converted/` |
| `npm run convert:user:01` | `convert_user_01_create.py` | User Creation List (Phones without `+`) | `User_01_Create_converted.csv` |
| `npm run convert:user:02` | `convert_user_02_assign.py` | User Role Assignment Matrix | `User_02_Assign_converted.csv` |
| `npm run convert:all` | *Runs Role & User converters* | All Role & User Matrices | All CSVs in `converted/` |
| `npm run templates:generate`| `create_templates.py` | Generates sample Excel files | `excel-templates/converted/*.csv` |

Detailed guide: [`docs/ROLE_CONVERSION_GUIDE.md`](docs/ROLE_CONVERSION_GUIDE.md).

---

## 6. ABAP Utilities for SAP Basis

All utilities feature:
- **Simulation Mode (`p_test = 'X'`)**: Validates data without updating the database.
- **ALV Cockpit**: Hotspot navigation directly to `PFCG` or `SU01`.
- **Standardized Status Column**: Dual-mode display supporting GUI icons and Excel export:
  - `@08@ [OK]` : Success / Simulated OK
  - `@09@ [WARN]` : Warning / Skipped / Already Exists
  - `@0A@ [ERR]` : Error / Missing required data

### 6.1. Role Management (`Z_ROLE_*`)

| Program | Documentation | Key Highlights |
| :--- | :--- | :--- |
| **`Z_ROLE_01_CREATE_MASTER`** | [`docs/Z_ROLE_01_CREATE_MASTER.md`](docs/Z_ROLE_01_CREATE_MASTER.md) | Mass creates Master Roles from CSV; builds menu folders; defaults Org Levels to `'-1'`; strips boilerplate PFCG comments. |
| **`Z_ROLE_02_CREATE_DERIVE`** | [`docs/Z_ROLE_02_CREATE_DERIVE.md`](docs/Z_ROLE_02_CREATE_DERIVE.md) | Batch creates Derived Roles with `PARENT_AGR` link; inherits authorizations; initializes Org Levels to `'-1'`. |
| **`Z_ROLE_03_UPDATE_ORG`** | [`docs/Z_ROLE_03_UPDATE_ORG.md`](docs/Z_ROLE_03_UPDATE_ORG.md) | Maintains Org Levels (`AGR_1252`); strictly validates existing role org levels (skips unassigned); compiles authorization profiles in dark mode. |
| **`Z_ROLE_03_UPDATE_OBJECT`** | [`docs/Z_ROLE_03_UPDATE_OBJECT.md`](docs/Z_ROLE_03_UPDATE_OBJECT.md) | Mass updates Authorization Objects & Fields (`AGR_1251`); strictly checks object & field existence before update (zero foreign object injection); compiles profiles. |
| **`Z_ROLE_04_COMPOSITE`** | [`docs/Z_ROLE_04_COMPOSITE.md`](docs/Z_ROLE_04_COMPOSITE.md) | Creates Composite Roles (`COLL_AGR = 'X'`); validates and assigns Single Roles atomically; isolates missing roles. |

### 6.2. User Management (`Z_USER_*`)

| Program | Documentation | Key Highlights |
| :--- | :--- | :--- |
| **`Z_USER_01_CREATE`** | [`docs/Z_USER_01_CREATE.md`](docs/Z_USER_01_CREATE.md) | Batch creates/updates users via `BAPI_USER_CREATE1` / `BAPI_USER_CHANGE`; maps Full Name to `LASTNAME`; UTF-8 safe (Vietnamese accents); displays initial passwords in ALV. |
| **`Z_USER_02_ASSIGN_ROLE`** | [`docs/Z_USER_02_ASSIGN_ROLE.md`](docs/Z_USER_02_ASSIGN_ROLE.md) | Mass assigns Single & Composite Roles via `BAPI_USER_ACTGROUPS_ASSIGN`; safe Append Mode (`p_append = 'X'`); validates `USR02` and `AGR_DEFINE`. |

### 6.3. Diagnostics (`Z_AUTH_*`)

| Program | Documentation | Key Highlights |
| :--- | :--- | :--- |
| **`Z_AUTH_SU53_ANALYZER`** | [`docs/Z_AUTH_SU53_ANALYZER.md`](docs/Z_AUTH_SU53_ANALYZER.md)<br>📘 [**User Guide (EN)**](docs/Z_AUTH_SU53_ANALYZER_USER_GUIDE_EN.md) \| [**PDF**](docs/Z_AUTH_SU53_ANALYZER_USER_GUIDE_EN.pdf)<br>🇻🇳 [**User Guide (VN)**](docs/Z_AUTH_SU53_ANALYZER_USER_GUIDE_VN.md) \| [**PDF**](docs/Z_AUTH_SU53_ANALYZER_USER_GUIDE_VN.pdf) | Dual-ALV cockpit (`TCode: ZAT`); extracts SU53 failures from last 3 hours; evaluates user role coverage; injects missing objects with mandatory `TOBJ` fields; regenerates profiles. |

---

## 7. Security & Best Practices

1. **Credentials Safety**: Never commit `.sap.env` to Git (enforced via `.gitignore`).
2. **Business Data Isolation**: Keep actual corporate matrices in `excel-working/` (Git-ignored). Only commit anonymized templates in `excel-templates/`.
3. **Transport Requests**: Target `$TMP` during development; set `SAP_PACKAGE` and `SAP_TRANSPORT_REQUEST` for transportable packages.
4. **Principle of Least Privilege**: Use a dedicated service account for ADT with appropriate authorizations (`S_DEVELOP`, `S_RFC`, `S_TABU_DIS`).

---

## License

This project is licensed under the [MIT License](LICENSE).
