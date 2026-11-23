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
├── src/                  # Production-ready ABAP source programs & classes
│   ├── z_role_01_create_master.prog.abap    # Batch Master Role & Menu Creation
│   ├── z_role_02_create_derive.prog.abap    # Batch Derived Role Inheritance
│   ├── z_role_03a_update_org.prog.abap      # Batch Org Levels Maintenance
│   ├── z_role_03a_update_org_fix.prog.abap  # Batch Fix & Rebind Org Level Variables ($VARBL)
│   ├── z_role_03b_update_object.prog.abap   # Batch Auth Objects Maintenance
│   ├── z_role_03c_update_activity.prog.abap # Batch Activity Fields Maintenance
│   ├── z_role_04_create_composite.prog.abap # Batch Composite Role Bundling
│   ├── z_user_01_create.prog.abap           # Batch User Creation & Maintenance
│   ├── z_user_02_assign_role.prog.abap      # Batch User-to-Role Assignment
│   ├── z_user_03_sspr_admin.prog.abap       # SSPR Token Admin & Cleanup Cockpit
│   ├── zcl_sspr_http_handler.clas.abap      # SSPR HTTP Extension Handler Class
│   ├── z_auth_su53_analyzer.prog.abap       # SU53 Buffer Diagnostics Cockpit
│   └── z_export_obj_levels.prog.abap        # Standard Objects & Fields Exporter
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

# Install ADT MCP packages globally:
# - @mcp-abap-adt/core: required by local CLI deploy scripts (npm run deploy:*)
# - @mcp-abap-adt/compact & compact-ro: recommended for AI IDE chat (70-87% lower token usage)
npm install -g @mcp-abap-adt/core @mcp-abap-adt/compact @mcp-abap-adt/compact-ro

# Copy & configure credentials (never commit .sap.env!)
cp .sap.env.example .sap.env
```

### 3. Configure `.sap.env`
```ini
SAP_URL=https://your-sap-host:44310
SAP_CLIENT=100
SAP_AUTH_TYPE=basic
SAP_SYSTEM_TYPE=onprem
SAP_CONNECTION_TYPE=http
SAP_USERNAME=YOUR_USER
SAP_PASSWORD='YOUR_PASSWORD'
SAP_LANGUAGE=EN
NODE_TLS_REJECT_UNAUTHORIZED=0
HANDLER_LOG_SILENT=true
SAP_PACKAGE=$TMP
# SAP_TRANSPORT_REQUEST=DEVK900001 # Required if SAP_PACKAGE != $TMP
```
> **Note:** Always wrap `SAP_PASSWORD` in single quotes (`'...'`) so characters like `#` are not truncated by dotenv.

---

## 3. AI Agent Setup (MCP — Token-Optimized)

Use **`@mcp-abap-adt/compact`** (or **`@mcp-abap-adt/compact-ro`** for read-only inspection) in your AI IDE instead of `@mcp-abap-adt/core` to cut tool-schema token usage by **70–87%** per turn:

| Binary | Tools (`onprem`) | Schema Overhead / Turn | Best For |
| :--- | :---: | :---: | :--- |
| `mcp-abap-adt` (`@mcp-abap-adt/core`) | 272 | ~100,400 tokens | Local CLI scripts (`npm run deploy:*`) — **0 LLM tokens** |
| `mcp-abap-adt-compact` | 38 | ~29,900 tokens (-70%) | Interactive IDE dev + ABAP Debugger |
| `mcp-abap-adt-compact --deny-actions=HandlerDebug*` | 33 | ~25,300 tokens (-75%) | **Default AI IDE dev** (without debugger tools) |
| `mcp-abap-adt-compact-ro` | 20 | ~13,200 tokens (-87%) | **Read-only inspection & analysis** |

Add to your AI agent's MCP configuration (`mcpServers` object — full template in [`mcp-config.example.json`](mcp-config.example.json)):

```json
{
  "sap-s4hana": {
    "command": "cmd.exe",
    "args": [
      "/c",
      "mcp-abap-adt-compact",
      "--env-path=C:\\path\\to\\SAPABAP\\.sap.env",
      "--connection-type=http",
      "--deferred-logon",
      "--deny-actions=HandlerDebug*"
    ],
    "env": {
      "HANDLER_LOG_SILENT": "true"
    }
  }
}
```
*(On macOS/Linux, replace `cmd.exe /c` with direct `mcp-abap-adt-compact`. `--deferred-logon` delays SAP logon until the first tool call; `--deny-actions=HandlerDebug*` unregisters debugger tools when not needed. For coding ABAP programs in `src/`, edit locally and deploy via `npm run deploy:*` to avoid passing full ABAP files through LLM tool calls — see [`.agent/skills/02_mcp-token-optimization.md`](.agent/skills/02_mcp-token-optimization.md)).*

---

## 4. Deployment Commands

Deploy and activate ABAP programs selectively to the connected SAP system:

| Command | Deploys Target | Type | Description |
| :--- | :--- | :---: | :--- |
| `npm run deploy:role:01` | `Z_ROLE_01_CREATE_MASTER` | Report | Batch Master Role & Menu Creation |
| `npm run deploy:role:02` | `Z_ROLE_02_CREATE_DERIVE` | Report | Batch Derived Role Derivation |
| `npm run deploy:role:03` | *03a, 03b & 03c Programs* | Bundle | Full Org, Object & Activity Maintenance |
| `npm run deploy:role:03a` | `Z_ROLE_03A_UPDATE_ORG` | Report | Batch Organizational Levels Maintenance |
| `npm run deploy:role:03a:fix` | `Z_ROLE_03A_UPDATE_ORG_FIX` | Report | Batch Fix & Rebind Org Level Variables ($VARBL) |
| `npm run deploy:role:03b` | `Z_ROLE_03B_UPDATE_OBJECT` | Report | Batch Authorization Objects Maintenance |
| `npm run deploy:role:03c` | `Z_ROLE_03C_UPDATE_ACTIVITY` | Report | Batch Authorization Activity Maintenance |
| `npm run deploy:role:04` | `Z_ROLE_04_CREATE_COMPOSITE` | Report | Batch Composite Role Bundling |
| `npm run deploy:role:all` | *All 6 Role Programs* | Bundle | Full Role Lifecycle Deployment |
| `npm run deploy:user:01` | `Z_USER_01_CREATE` | Report | Batch SAP User Creation & Update |
| `npm run deploy:user:02` | `Z_USER_02_ASSIGN_ROLE` | Report | Batch User-to-Role Assignment |
| `npm run deploy:user:03` | `Z_USER_03_SSPR_ADMIN` | Report | SSPR Token Management & Cleanup Cockpit |
| `npm run deploy:class:sspr` | `ZCL_SSPR_HTTP_HANDLER` | Class | SSPR SICF HTTP Service Extension Handler |
| `npm run deploy:user:all` | *All 3 User Tools + SSPR Class* | Bundle | Complete User & SSPR Suite |
| `npm run deploy:su53` | `Z_AUTH_SU53_ANALYZER` | Report | SU53 Buffer Diagnostics Cockpit |
| `npm run deploy:export:obj` | `Z_EXPORT_OBJ_LEVELS` | Report | Export TOBJ/TOBJT Authorization Catalog |
| `npm run deploy:all` | *All 12 Programs & Classes* | Full | Complete Project Deployment |
| `npm run deploy` | *Interactive Menu* | Interactive | Select program from terminal prompt |

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
| `npm run convert:user`    | `convert_user.py` (Consolidated) | Unified User & Role Matrix (`User.xlsx` / `Template_User.xlsx`) | `*_01_Create_converted.csv`<br>`*_02_Assign_converted.csv` (Both in 1 run) |
| `npm run convert:user:01` | `convert_user_01_create.py` | User Creation List (Phones without `+`) | `*_01_Create_converted.csv` |
| `npm run convert:user:02` | `convert_user_02_assign.py` | User Role Assignment Matrix | `*_02_Assign_converted.csv` |
| `npm run convert:user:all`| `convert_user.py` | Consolidated or separate User files | Both User CSVs in `converted/` |
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
| **`Z_ROLE_03A_UPDATE_ORG`** | [`docs/Z_ROLE_03A_UPDATE_ORG.md`](docs/Z_ROLE_03A_UPDATE_ORG.md) | Maintains Org Levels (`AGR_1252`); strictly validates existing role org levels (skips unassigned); compiles authorization profiles in dark mode. |
| **`Z_ROLE_03A_UPDATE_ORG_FIX`** | [`docs/Z_ROLE_03A_UPDATE_ORG_FIX.md`](docs/Z_ROLE_03A_UPDATE_ORG_FIX.md) | Diagnoses and repairs roles with Red traffic lights or "Manually" (`MODIFIED = 'U'/'M'`) statuses on Org Level fields; rebinds `$VARBL` (`MODIFIED = 'S'`, `NEU = 'O'`); auto-heals parent Master Roles. |
| **`Z_ROLE_03B_UPDATE_OBJECT`** | [`docs/Z_ROLE_03B_UPDATE_OBJECT.md`](docs/Z_ROLE_03B_UPDATE_OBJECT.md) | Mass updates Authorization Objects & Fields (`AGR_1251`); strictly checks object & field existence before update (zero foreign object injection); compiles profiles. |
| **`Z_ROLE_03C_UPDATE_ACTIVITY`** | [`docs/Z_ROLE_03C_UPDATE_ACTIVITY.md`](docs/Z_ROLE_03C_UPDATE_ACTIVITY.md) | Mass updates Authorization Activity fields (`ACTVT`, `PS_ACTVT`); preserves non-target authorization fields under matching objects; compiles profiles. |
| **`Z_ROLE_04_CREATE_COMPOSITE`** | [`docs/Z_ROLE_04_CREATE_COMPOSITE.md`](docs/Z_ROLE_04_CREATE_COMPOSITE.md) | Creates Composite Roles (`COLL_AGR = 'X'`); validates and assigns Single Roles atomically; isolates missing roles. |

### 6.2. User Management (`Z_USER_*`)

| Program / Class | Documentation | Key Highlights |
| :--- | :--- | :--- |
| **`Z_USER_01_CREATE`** | [`docs/Z_USER_01_CREATE.md`](docs/Z_USER_01_CREATE.md) | Batch creates/updates users via `BAPI_USER_CREATE1` / `BAPI_USER_CHANGE`; maps Full Name to `LASTNAME`; UTF-8 safe (Vietnamese accents); dynamically generates initial passwords and displays them in ALV. |
| **`Z_USER_02_ASSIGN_ROLE`** | [`docs/Z_USER_02_ASSIGN_ROLE.md`](docs/Z_USER_02_ASSIGN_ROLE.md) | Mass assigns Single & Composite Roles via `BAPI_USER_ACTGROUPS_ASSIGN`; safe Append Mode (`p_append = 'X'`); validates `USR02` and `AGR_DEFINE`. |
| **`Z_USER_03_SSPR_ADMIN`** | [`docs/Z_USER_03_SSPR_ADMIN.md`](docs/Z_USER_03_SSPR_ADMIN.md) \| [`docs/SSPR_USER_GUIDE.md`](docs/SSPR_USER_GUIDE.md) | Audit & management console for password reset/unlock requests (`ZSSPR_TOKENS`); client IP tracking; automated retention cleanup; SU01 hotspot. |
| **`ZCL_SSPR_HTTP_HANDLER`** | [`docs/SSPR_USER_GUIDE.md`](docs/SSPR_USER_GUIDE.md) | Native SSPR HTTP handler (`IF_HTTP_EXTENSION`) serving `/reset`; client-bound context; email notification via `CL_BCS`; productive password generation. |

### 6.3. Diagnostics (`Z_AUTH_*`)

| Program | Documentation | Key Highlights |
| :--- | :--- | :--- |
| **`Z_AUTH_SU53_ANALYZER`** | [`docs/Z_AUTH_SU53_ANALYZER.md`](docs/Z_AUTH_SU53_ANALYZER.md)<br>📘 [**User Guide (EN)**](docs/Z_AUTH_SU53_ANALYZER_USER_GUIDE_EN.md) \| [**PDF**](docs/Z_AUTH_SU53_ANALYZER_USER_GUIDE_EN.pdf) | Dual-ALV cockpit (`TCode: ZAT`); extracts SU53 failures from last 3 hours; evaluates user role coverage; injects missing objects with mandatory `TOBJ` fields; regenerates profiles. |

### 6.4. Data Dictionary & System Utilities

| Program | Documentation | Key Highlights |
| :--- | :--- | :--- |
| **`Z_EXPORT_OBJ_LEVELS`** | [`docs/Z_EXPORT_OBJ_LEVELS.md`](docs/Z_EXPORT_OBJ_LEVELS.md) | Extracts standard SAP Authorization Objects and Fields from `TOBJ`, `TOBJT`, and `TOBCT` to generate reference matrix catalog (`Object_Levels.csv`). |

---

## 7. Security & Best Practices

1. **100% SAP Standard API & BAPI Architecture**: All utilities strictly adhere to SAP enterprise architecture guidelines by prohibiting direct database modifications (`UPDATE`, `MODIFY`, `DELETE FROM` on standard SAP tables). All operations are executed through certified BAPIs and PFCG Function Modules. See the comprehensive [**SAP Standard APIs & Function Modules Catalog**](docs/SAP_STANDARD_APIS_CATALOG.md) and project [**Architecture Rules**](AGENTS.md).
2. **Credentials Safety**: Never commit `.sap.env` to Git (enforced via `.gitignore`).
3. **Business Data Isolation**: Keep actual corporate matrices in `excel-working/` (Git-ignored). Only commit anonymized templates in `excel-templates/`.
4. **Transport Requests**: Target `$TMP` during development; set `SAP_PACKAGE` and `SAP_TRANSPORT_REQUEST` for transportable packages.
5. **Principle of Least Privilege**: Use a dedicated service account for ADT with appropriate authorizations (`S_DEVELOP`, `S_RFC`, `S_TABU_DIS`).

---

## License

This project is licensed under the [MIT License](LICENSE).
