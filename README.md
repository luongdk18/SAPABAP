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
   - [7.2. Future Utilities Roadmap](#72-future-utilities-roadmap)
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
# Specify the program name
npm run deploy -- Z_AUTH_TEST

# Or pass file path directly
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

### 7.2. Future Utilities Roadmap

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
