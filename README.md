<div align="center">

# 🤖 SAP ABAP with AI & Model Context Protocol (MCP)
### *Connecting AI Coding Agents to SAP S/4HANA & ECC + Practical ABAP Tools for SAP Basis*

[![SAP: NetWeaver / S/4HANA](https://img.shields.io/badge/SAP-NetWeaver%20%7C%20S%2F4HANA-0070BA.svg)](https://www.sap.com)
[![ABAP: 7.50+](https://img.shields.io/badge/ABAP-7.50%2B-orange.svg)]()
[![Protocol: MCP](https://img.shields.io/badge/Protocol-Model%20Context%20Protocol-green.svg)](https://modelcontextprotocol.io/)
[![Target: SAP Basis & Developers](https://img.shields.io/badge/Focus-SAP%20Basis%20%26%20Developers-blueviolet.svg)]()
[![Node.js: >=22](https://img.shields.io/badge/Node.js-%3E%3D22.0.0-brightgreen.svg)](https://nodejs.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

<p align="center">
  <b>A comprehensive guide to connecting AI Coding Agents (Grok Build, Claude Desktop, Cursor IDE, Google Antigravity, VS Code) directly to SAP via the Model Context Protocol (MCP) to develop, inspect, and deploy ABAP code.</b><br/>
  <i>This repository also builds and open-sources practical ABAP utility tools for <b>SAP Basis administrators</b> — starting with <b>Z_AUTH_TEST</b> for automated SU53 trace analysis and PFCG role remediation.</i>
</p>

[⚡ Quick Start](#-quick-start-in-3-minutes) • [🤖 AI Client Setup](#-1-ai-client-configuration-via-mcp) • [🛠️ AI ABAP Capabilities](#-2-what-ai-coding-agents-can-do-on-sap) • [🛡️ SAP Basis Tools: Z_AUTH_TEST](#-3-sap-basis-tools-showcase-z_auth_test) • [🚀 CLI Deployment](#-4-automated-cli-deployment) • [📖 Docs (Tiếng Việt)](docs/Z_AUTH_TEST.md)

</div>

---

## 📑 Table of Contents

1. [Architectural Overview](#-architectural-overview)
2. [Quick Start in 3 Minutes](#-quick-start-in-3-minutes)
3. [1. AI Client Configuration via MCP](#-1-ai-client-configuration-via-mcp)
   - [1.1. Grok Build (Latest Version)](#11-grok-build-latest-version)
   - [1.2. Claude Desktop](#12-claude-desktop)
   - [1.3. Cursor IDE](#13-cursor-ide)
   - [1.4. Google Antigravity](#14-google-antigravity)
   - [1.5. VS Code (Cline / Roo Code / Continue)](#15-vs-code-cline--roo-code--continue)
4. [2. What AI Coding Agents Can Do on SAP](#-2-what-ai-coding-agents-can-do-on-sap)
5. [3. SAP Basis Tools Showcase: Z_AUTH_TEST](#-3-sap-basis-tools-showcase-z_auth_test)
6. [4. Automated CLI Deployment](#-4-automated-cli-deployment)
7. [Repository Structure](#-repository-structure)
8. [Project Vision & SAP Basis Roadmap](#-project-vision--sap-basis-roadmap)
9. [Security & Governance](#-security--governance)

---

## 🏛️ Architectural Overview

This repository establishes a secure, standardized pipeline between modern AI coding assistants and SAP application servers via the **Model Context Protocol (MCP)**:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        AI CODING ASSISTANTS                            │
│      [Grok Build]    [Claude Desktop]    [Cursor IDE]   [Antigravity]  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Model Context Protocol (stdio / JSON-RPC)
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                   SAP ABAP ADT MCP SERVER (@mcp-abap-adt/core)         │
│          Manages Auth, Enqueue Locks, Transport & ADT REST Calls       │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ HTTPS (SAP ADT REST / SICF Services)
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                   SAP S/4HANA / SAP NETWEAVER SYSTEM                   │
│  ┌─────────────────────────┐         ┌──────────────────────────────┐  │
│  │    ABAP ADT Services    │         │      SAP Basis Tools Hub     │  │
│  │  - Source Read/Write    │         │  - Z_AUTH_TEST (SU53 / PFCG) │  │
│  │  - Remote Syntax Check  │         │  - Role & Authorization Fix  │  │
│  │  - Object Activation    │         │  - Buffer & Memory Utilities │  │
│  │  - SQL Data Preview     │         │  - System Health Diagnostics │  │
│  └─────────────────────────┘         └──────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## ⚡ Quick Start in 3 Minutes

Follow these 4 simple steps to connect your AI assistant to SAP and deploy programs:

### Step 1: Clone the Repository
```bash
git clone https://github.com/luongdk18/SAPABAP.git
cd SAPABAP
```

### Step 2: Install Node.js & MCP Server CLI
Ensure you have **Node.js >= 22.0.0** installed, then install the SAP ADT MCP server:
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

### Step 4: Deploy Program to SAP in One Command
```bash
npm run deploy
```
The deploy script connects via ADT, checks syntax, uploads `src/z_auth_test.prog.abap`, and activates program `Z_AUTH_TEST` automatically on SAP.

---

## 🤖 1. AI Client Configuration via MCP

Configure your favorite AI assistant to interact natively with your SAP system:

### 1.1. Grok Build (Latest Version)

#### Option A: Quick CLI Command (Fastest)
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
*(On macOS/Linux, set `command = "mcp-abap-adt"` and pass `["--transport=stdio", "--env-path=/path/to/.sap.env"]`).*

---

### 1.2. Claude Desktop

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

### 1.3. Cursor IDE

1. Open **Settings** -> **Features** -> **MCP Servers** -> **Add New MCP Server**.
2. Set **Name**: `sap-s4hana`
3. Set **Type**: `command`
4. Set **Command**:
   ```bash
   mcp-abap-adt --transport=stdio --env-path=d:\PROJECTS\SAPABAP\.sap.env
   ```

---

### 1.4. Google Antigravity

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

### 1.5. VS Code (Cline / Roo Code / Continue)

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

## 🛠️ 2. What AI Coding Agents Can Do on SAP

Once connected over MCP, your AI assistant can execute full-lifecycle ABAP development tasks directly from chat prompts:

> 💬 *"Search for function module `SUSR_USER*` and show me its import/export parameters."*  
> 💬 *"Check report `Z_AUTH_TEST` for any syntax errors or obsolete statements."*  
> 💬 *"Write an ABAP report that queries table `USR02` to list locked users and activate it."*  
> 💬 *"Query 5 rows from table `AGR_1251` where OBJECT = 'S_TCODE' using GetSqlQuery."*  
> 💬 *"Inspect the latest ST22 short dump for user SAPADMIN and suggest a fix."*

### Core MCP Tools Available:
| Category | Tool | Description |
| :--- | :--- | :--- |
| **Search & Discovery** | `SearchObject` | Searches programs, classes, CDS views, DDIC structures by name or wildcards |
| **Code Inspection** | `GetProgram`, `GetClass` | Reads active source code directly from the SAP repository |
| **Code Authoring** | `UpdateProgram`, `UpdateClass` | Writes, modifies, and locks ABAP source code on SAP |
| **Activation** | `ActivateProgram`, `ActivateClass` | Remotely activates inactive ABAP repository objects |
| **Syntax Check** | `CheckProgram`, `CheckClass` | Validates ABAP syntax and returns compiler errors with line numbers |
| **Data Preview** | `GetSqlQuery` | Runs ad-hoc ABAP SQL queries to inspect live test data via ADT API |
| **Dictionary** | `GetTable`, `GetStructure` | Retrieves fields, data elements, domains, and check tables |
| **Diagnostics** | `RuntimeGetDumpById` | Pulls ST22 short dumps to diagnose runtime exceptions immediately |

---

## 🛡️ 3. SAP Basis Tools Showcase: Z_AUTH_TEST

A core goal of this repository is to build and maintain **production-ready ABAP tools for SAP Basis & Security teams**.

The flagship tool in this suite is **`Z_AUTH_TEST`** (`src/z_auth_test.prog.abap`) — an automated **SU53 Trace Analyzer & PFCG Role Remediation Cockpit**:

### The Problem in SAP Basis Operations:
- Standard `SU53` only captures the *single last failed check* on the current Application Server, requiring endless cycles of failing, screenshotting, and re-testing.
- Manual `PFCG` maintenance often omits default fields defined in `TOBJ` or leaves Organizational Levels unmaintained (`AGR_1252`), preventing authorization profile generation.

### The Solution:
`Z_AUTH_TEST` provides an interactive **Dual-Grid Cockpit**:
1. **3-Hour Buffer Aggregation**: Reads all recent trace records via `SUSR_USER_SU53_READ`.
2. **Single-Role Coverage Simulation**: Evaluates role coverage and flags satisfied checks (🟢) vs. missing checks (🔴).
3. **100% `TOBJ` Field Integrity Pass**: Incorporates all default fields for authorization objects automatically.
4. **Org Level Auto-Populate**: Fills open Organizational Levels in `AGR_1252` with `*`.
5. **Forced Profile Generation**: Triggers `SUPRN_DARK_MANIPULATE_PROFILE` in background mode without interactive PFCG dialogs.

> 📖 **Comprehensive Technical Guide**: For an exhaustive deep-dive, subroutine analysis, and screenshots in Vietnamese, see [docs/Z_AUTH_TEST.md](docs/Z_AUTH_TEST.md).

---

## 🚀 4. Automated CLI Deployment

The included script [`scripts/deploy.js`](scripts/deploy.js) automates uploading and activating ABAP code directly from terminal / Git workflows:

```bash
# Deploy default showcase (Z_AUTH_TEST)
npm run deploy

# Deploy any custom ABAP program
node scripts/deploy.js src/your_program.prog.abap YOUR_PROG_NAME
```

### Automated Deployment Flow:
```text
Lock Program -> Remote Syntax Check -> Upload Code -> Unlock -> Verify Inactive -> Activate
```

---

## 📂 Repository Structure

```text
SAPABAP/
├── docs/
│   └── Z_AUTH_TEST.md           # Comprehensive technical specification & operational guide (Tiếng Việt)
├── scripts/
│   └── deploy.js                # Universal Node.js ADT deployer (JSON-RPC / stdio)
├── src/
│   └── z_auth_test.prog.abap    # Production-ready ABAP Basis tool (SU53 Trace Analyzer & PFCG Cockpit)
├── .gitignore                   # Excludes .sap.env, logs, and temporary caches
├── .sap.env.example             # Clean environment template for SAP connection
├── mcp-config.example.json      # Template configuration for MCP clients
├── package.json                 # Project manifest & npm deployment commands
└── README.md                    # Primary repository documentation & setup guide
```

---

## 🎯 Project Vision & SAP Basis Roadmap

This repository serves two complementary purposes:

1. **Practical AI + MCP Enablement**:
   - Providing concrete, battle-tested setup guides for connecting modern AI agents (Grok, Claude, Cursor, Antigravity) to SAP ABAP development.
   - Demonstrating how to use AI for prompt-driven ABAP development, automated refactoring, and CI/CD deployment.

2. **Open-Source ABAP Utility Suite for SAP Basis**:
   - Building lightweight, independent ABAP reports and transactions to streamline day-to-day SAP Basis administration:
     - 🛡️ **Security & Roles**: SU53 trace automation, PFCG role cleanup, unassigned auth detection (`Z_AUTH_TEST`).
     - 📊 **Monitoring & Diagnostics**: Trace analysis, dump investigation helpers, buffer and table size diagnostics.
     - ⚙️ **Operation Automations**: Background job monitoring, lock entry inspection (`SM12`), user session management.

Contributions, feature requests, and new Basis tool ideas are warmly welcome!

---

## 🔒 Security & Governance

1. **Credentials Isolation**: Never commit `.sap.env` to Git. Keep credentials local or in secure vault runners.
2. **Dedicated User Account**: Use a designated developer user with `S_DEVELOP`, `S_ADT_RES`, `S_RFC`, and `S_TABU_DIS`.
3. **Role Safety**: Restrict production access to read-only tools (`GetSqlQuery`, read-only inspection).

---

## 📄 License

This project is licensed under the [MIT License](LICENSE) — free for use, modification, and community sharing.

<div align="center">
  <b>Made with ❤️ for SAP Developers & Basis Administrators by luongdk18</b>
</div>
