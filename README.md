<div align="center">

# 🌐 SAP ABAP Enterprise Toolkit & AI Development Hub
### *Part of the LuongDoan Ecosystem for SAP Engineering & Knowledge Sharing*

[![Author: Luong Doan](https://img.shields.io/badge/Author-Luong%20Doan%20(@luongdk18)-blue.svg)](https://github.com/luongdk18)
[![Ecosystem: LuongDoan](https://img.shields.io/badge/Ecosystem-LuongDoan-8A2BE2.svg)](https://github.com/luongdk18)
[![SAP: NetWeaver / S/4HANA](https://img.shields.io/badge/SAP-NetWeaver%20%7C%20S%2F4HANA-0070BA.svg)](https://www.sap.com)
[![ABAP: 7.50+](https://img.shields.io/badge/ABAP-7.50%2B-orange.svg)]()
[![Protocol: MCP](https://img.shields.io/badge/Protocol-Model%20Context%20Protocol-green.svg)](https://modelcontextprotocol.io/)
[![Node.js: >=22](https://img.shields.io/badge/Node.js-%3E%3D22.0.0-brightgreen.svg)](https://nodejs.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

<p align="center">
  <b>A unified open-source solution empowering SAP Developers, Basis Engineers, and Security Administrators:</b><br/>
  🛡️ <b>Z_AUTH_TEST</b>: Instant SU53 trace analysis, single-role evaluation, and automated PFCG role remediation with forced profile generation.<br/>
  🤖 <b>AI-Powered ABAP via MCP</b>: Turn cutting-edge AI assistants (Grok Build, Claude, Cursor, Google Antigravity) into full-fledged SAP development copilots over standard ADT APIs.<br/>
  🚀 <b>CLI & CI/CD Deployment</b>: Deploy and activate ABAP source code directly from Git without opening SAP GUI.
</p>

[📌 Quick Start](#-quick-start-in-3-minutes) • [🛡️ Z_AUTH_TEST Cockpit](#-pillar-1-z_auth_test---authorization-automation-cockpit) • [🤖 AI MCP Setup](#-pillar-2-modern-ai-development-via-mcp) • [🚀 Automated Deployment](#-automated-deployment) • [📖 Detailed Docs (Tiếng Việt)](docs/Z_AUTH_TEST.md)

</div>

---

## 📑 Table of Contents

1. [Architectural Overview](#-architectural-overview)
2. [Pillar 1: Z_AUTH_TEST - Authorization Automation Cockpit](#-pillar-1-z_auth_test---authorization-automation-cockpit)
3. [Pillar 2: Modern AI Development via MCP](#-pillar-2-modern-ai-development-via-mcp)
4. [Quick Start in 3 Minutes](#-quick-start-in-3-minutes)
5. [AI Client Configuration](#-ai-client-configuration)
   - [5.1. Grok Build (Latest Version)](#51-grok-build-latest-version)
   - [5.2. Claude Desktop](#52-claude-desktop)
   - [5.3. Cursor IDE](#53-cursor-ide)
   - [5.4. Google Antigravity](#54-google-antigravity)
   - [5.5. VS Code (Cline / Roo Code / Continue)](#55-vs-code-cline--roo-code--continue)
6. [Automated Deployment Tooling](#-automated-deployment-tooling)
7. [Repository Structure](#-repository-structure)
8. [Security & Governance](#-security--governance)
9. [About LuongDoan Ecosystem](#-about-luongdoan-ecosystem)

---

## 🏛️ Architectural Overview

This repository bridges traditional SAP ABAP enterprise systems with modern AI-driven developer workflows through standard, secure protocols:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        AI ASSISTANTS & DEVELOPERS                      │
│      [Grok Build]    [Claude Desktop]    [Cursor IDE]   [Antigravity]  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Model Context Protocol (stdio / JSON-RPC)
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                   SAP ABAP ADT MCP SERVER (@mcp-abap-adt/core)         │
│          Handles Authentication, Object Locking & REST Payloads        │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ HTTPS (SAP ADT REST / SICF)
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                   SAP S/4HANA / SAP NETWEAVER SYSTEM                   │
│  ┌─────────────────────────┐         ┌──────────────────────────────┐  │
│  │    ABAP ADT Services    │         │    Z_AUTH_TEST Application   │  │
│  │  - Source Read/Write    │         │  - SU53 3h Buffer Analyzer   │  │
│  │  - Syntax Check         │         │  - PFCG Single Role Simulator│  │
│  │  - Object Activation    │         │  - 100% TOBJ Field Integrity │  │
│  │  - Data Preview (SQL)   │         │  - Auto Profile Generation   │  │
│  └─────────────────────────┘         └──────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 🛡️ Pillar 1: Z_AUTH_TEST - Authorization Automation Cockpit

### The Challenge with Traditional SAP Authorization:
- **`SU53` is fragile and volatile**: It only captures the *single last failed check* on the current Application Server. Testing complex multi-step transactions (e.g., `ME21N`, `MIGO`, approvals) requires endless cycles of failing, screenshotting, and re-testing.
- **`PFCG` manual maintenance is error-prone**:
  - Adding manual authorization objects often misses default fields registered in `TOBJ`, leaving the object in a "yellow/unmaintained" state.
  - Adding transactions to menus creates open Organizational Levels (`AGR_1252`), blocking Profile Generation with `open_auths` errors.
  - Deactivated authorization objects (`DELETED = 'X'`) cause cryptic collisions when re-added.

### The Solution: `Z_AUTH_TEST` Cockpit
`Z_AUTH_TEST` (`src/z_auth_test.prog.abap`) is an interactive **Dual-Grid Cockpit** combining:

```
┌────────────────────────────────────────────────────────────────────────┐
│ TOP DOCKING CONTAINER (cl_gui_docking_container): SINGLE ROLES LIST   │
│ [Add to Role]  [Select All]  [Deselect All]  [Refresh from SU53]       │
├────┬──────────────────┬────────────────────────────────────────────────┤
│Radio│ Role Name        │ Role Description                               │
├────┼──────────────────┼────────────────────────────────────────────────┤
│🔘  │ Z_ROLE_TEST      │ Purchasing Authorization Role                  │
│⚪  │ Z_MM_BUYER       │ Material Buyer Operations                      │
└────┴──────────────────┴────────────────────────────────────────────────┘
┌────────────────────────────────────────────────────────────────────────┐
│ BOTTOM ALV GRID (REUSE_ALV_GRID_DISPLAY_LVC): MISSING SU53 TRACE       │
├───┬──────┬────────────┬─────────────┬──────────────┬───────────────────┤
│Sel│Status│ Object     │ Field       │ Val Required │ Current in Role   │
├───┼──────┼────────────┼─────────────┼──────────────┼───────────────────┤
│[X]│ 🔴   │ S_ALV_LAYR │ ACTVT       │ 23           │                   │
│[X]│ 🔴   │ S_USER_GRP │ ACTVT       │ 03           │                   │
│[ ]│ 🟢   │ S_TCODE    │ TCD         │ ME23N        │ ME23N             │
└───┴──────┴────────────┴─────────────┴──────────────┴───────────────────┘
```

#### Core Capabilities:
1. **Full 3-Hour SU53 Buffer Capture**: Calls `SUSR_USER_SU53_READ` to fetch all recent authorization check failures across the system.
2. **Real-time Role Coverage Simulation**: Function `eval_auths_for_role` inspects the selected role and tags missing checks with 🔴 (Red) and already satisfied checks with 🟢 (Green).
3. **100% `TOBJ` Field Integrity Pass**: Inspects standard metadata table `TOBJ` and automatically incorporates all default fields for the object (filling wildcards `*` for non-faulted fields), guaranteeing complete structural integrity.
4. **Deactivated Object Auto-Reactivation**: Detects previously deleted objects in `AGR_1251` and reactivates them (`DELETED = ' '`) instead of creating duplicates.
5. **Organizational Level Auto-Populate**: Automatically populates unmaintained Organizational Levels (`AGR_1252`) with `*`.
6. **Forced Background Profile Generation**: Invokes `SUPRN_DARK_MANIPULATE_PROFILE` with `fill_fields_with_star = 'X'` and `fill_orgs_with_star = 'X'`, generating the authorization profile immediately without interactive PFCG dialogs.

> 📖 **Comprehensive Technical Guide**: For an exhaustive deep-dive, subroutine analysis, and screenshots in Vietnamese, see [docs/Z_AUTH_TEST.md](docs/Z_AUTH_TEST.md).

---

## 🤖 Pillar 2: Modern AI Development via MCP

The **Model Context Protocol (MCP)** transforms your AI assistants into active participants in your SAP development lifecycle. Using `@mcp-abap-adt/core`, your AI gains native tools to interact directly with your SAP system:

### Available AI MCP Tools:
| Tool Category | Tool Name | Description |
| :--- | :--- | :--- |
| **Search & Discovery** | `SearchObject` | Find repository objects (`PROG`, `CLAS`, `TABL`, `DDLS`, `FUGR`) |
| **Code Inspection** | `GetProgram`, `GetClass` | Read active ABAP report or OO class source code |
| **Code Modification** | `UpdateProgram`, `UpdateClass` | Edit and deploy ABAP code directly to SAP |
| **Lifecycle Control** | `ActivateProgram`, `ActivateClass` | Remotely trigger ABAP object activation |
| **Syntax Validation** | `CheckProgram`, `CheckClass` | Execute remote syntax checks against SAP dictionary |
| **Data Preview** | `GetSqlQuery` | Query SAP database tables via ADT Data Preview API |
| **Metadata Inspection**| `GetTable`, `GetStructure` | Inspect DDIC table definitions, fields, and types |
| **Troubleshooting** | `RuntimeGetDumpById` | Retrieve and diagnose `ST22` ABAP short dumps in real time |

---

## ⚡ Quick Start in 3 Minutes

Follow these steps to clone the repo, connect your AI assistant, and deploy `Z_AUTH_TEST` to your SAP server.

### Step 1: Clone the Repository
```bash
git clone https://github.com/luongdk18/SAPABAP.git
cd SAPABAP
```

### Step 2: Install Node.js & MCP CLI
Ensure you have **Node.js >= 22.0.0** installed, then install the MCP server globally:
```bash
npm install -g @mcp-abap-adt/core
```

### Step 3: Configure Your SAP Credentials
Copy `.sap.env.example` to `.sap.env`:
- **Windows PowerShell**:
  ```powershell
  Copy-Item .sap.env.example .sap.env
  ```
- **macOS / Linux**:
  ```bash
  cp .sap.env.example .sap.env
  ```

Fill in your SAP server connection details in `.sap.env`:
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
> 🔒 **Security Notice**: `.sap.env` is strictly ignored by `.gitignore`. Never commit credentials to version control.

### Step 4: Deploy Program to SAP with One Command
```bash
npm run deploy
```
The deploy script connects via ADT, checks syntax, uploads `src/z_auth_test.prog.abap`, and activates program `Z_AUTH_TEST` automatically on SAP.

### Step 5: Run in SAP GUI
Open SAP GUI and execute transaction:
```text
/nZAT
```
*(Or run program `Z_AUTH_TEST` directly via `SE38` / `SA38`).*

---

## ⚙️ AI Client Configuration

Connect your favorite AI assistant to the SAP ADT MCP server:

### 5.1. Grok Build (Latest Version)

#### Option A: Quick CLI Command
- **Windows (PowerShell / Command Prompt)**:
  ```bash
  grok mcp add sap-s4hana -- cmd.exe /c mcp-abap-adt --transport=stdio --env-path=d:\PROJECTS\SAPABAP\.sap.env
  ```
- **macOS / Linux**:
  ```bash
  grok mcp add sap-s4hana -- mcp-abap-adt --transport=stdio --env-path=/absolute/path/to/SAPABAP/.sap.env
  ```

#### Option B: Global `~/.grok/config.toml`
```toml
[mcp_servers.sap-s4hana]
command = "cmd.exe"
args = ["/c", "mcp-abap-adt", "--transport=stdio", "--env-path=d:\\PROJECTS\\SAPABAP\\.sap.env"]
```
*(On macOS/Linux, set `command = "mcp-abap-adt"` and pass `--transport=stdio` and `--env-path`).*

---

### 5.2. Claude Desktop

Add to your `claude_desktop_config.json`:
- **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`
- **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "sap-s4hana": {
      "command": "cmd.exe",
      "args": [
        "/c",
        "mcp-abap-adt",
        "--transport=stdio",
        "--env-path=d:\\PROJECTS\\SAPABAP\\.sap.env"
      ]
    }
  }
}
```

---

### 5.3. Cursor IDE

1. Open **Settings** -> **Features** -> **MCP Servers** -> **Add New MCP Server**.
2. Set **Name**: `sap-s4hana`
3. Set **Type**: `command`
4. Set **Command**:
   ```bash
   mcp-abap-adt --transport=stdio --env-path=d:\PROJECTS\SAPABAP\.sap.env
   ```

---

### 5.4. Google Antigravity

Add to `%USERPROFILE%\.gemini\config\mcp_config.json`:
```json
{
  "mcpServers": {
    "sap-s4hana": {
      "command": "cmd.exe",
      "args": [
        "/c",
        "mcp-abap-adt",
        "--transport=stdio",
        "--env-path=d:\\PROJECTS\\SAPABAP\\.sap.env"
      ]
    }
  }
}
```

---

### 5.5. VS Code (Cline / Roo Code / Continue)

Add to `cline_mcp_settings.json` or `.vscode/mcp.json`:
```json
{
  "mcpServers": {
    "sap-s4hana": {
      "command": "cmd.exe",
      "args": [
        "/c",
        "mcp-abap-adt",
        "--transport=stdio",
        "--env-path=d:\\PROJECTS\\SAPABAP\\.sap.env"
      ]
    }
  }
}
```

---

## 🚀 Automated Deployment Tooling

The built-in deployment tool [`scripts/deploy.js`](scripts/deploy.js) provides CI/CD-grade deployment directly to SAP over ADT REST endpoints:

```bash
# Deploy default program (Z_AUTH_TEST)
npm run deploy

# Deploy any custom ABAP program file
node scripts/deploy.js src/your_program.prog.abap YOUR_PROG_NAME
```

### Deployment Lifecycle:
```text
1. Lock Program (ADT Lock Enqueue)
2. Remote Syntax Verification
3. Source Code Upload (ADT Update/Create)
4. Unlock Program
5. Inactive Object Check
6. Remote Activation
```

---

## 📂 Repository Structure

```text
SAPABAP/
├── .github/                     # GitHub workflows and templates (if applicable)
├── docs/
│   └── Z_AUTH_TEST.md           # Comprehensive technical specification & operational guide (Tiếng Việt)
├── scripts/
│   └── deploy.js                # Universal Node.js ADT deployer (JSON-RPC / stdio)
├── src/
│   └── z_auth_test.prog.abap    # Production-ready ABAP source code (SU53 + PFCG Cockpit)
├── .gitignore                   # Excludes .sap.env, logs, and temporary caches
├── .sap.env.example             # Clean environment template for SAP connection
├── mcp-config.example.json      # Template configuration for MCP clients
├── package.json                 # Project manifest & npm deployment commands
└── README.md                    # Primary repository documentation & ecosystem hub
```

---

## 🔒 Security & Governance

1. **Credentials Isolation**: Never hardcode credentials in source code. `.sap.env` is excluded via `.gitignore`.
2. **Principle of Least Privilege**:
   - For **Development**: Ensure developer users have `S_DEVELOP`, `S_ADT_RES`, `S_RFC`, and `S_TABU_DIS`.
   - For **Production Diagnostics**: Assign read-only ADT authorizations (`S_TABU_DIS` read-only, read-only program inspection).
3. **Role Safety**:
   - `Z_AUTH_TEST` targets **Single Roles** only (`AGR_DEFINE-PARENT_AGR = space`).
   - Profile generation strictly respects system authorization boundaries.

---

## 🌟 About LuongDoan Ecosystem

This repository is maintained as an open-source initiative within the **LuongDoan Engineering Ecosystem** by **Luong Doan** ([@luongdk18](https://github.com/luongdk18)).

### Core Objectives:
- **Knowledge Sharing**: Demystifying complex SAP authorization mechanisms (`AGR_1250/1251/1252`, `TOBJ`, `SUSR_USER_SU53_READ`, `SUPRN_DARK_MANIPULATE_PROFILE`).
- **Modernizing ABAP**: Bridging legacy SAP environments with state-of-the-art AI tooling and modern software development practices.
- **Community Empowerment**: Providing ready-to-run, tested, and reliable tools for the global SAP community.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE) — feel free to use, modify, and distribute it in your SAP projects.

<div align="center">
  <b>Made with ❤️ for the SAP & ABAP Developer Community by Luong Doan</b>
</div>
