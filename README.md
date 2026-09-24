# SAP ABAP ADT Model Context Protocol (MCP) Server Setup

This repository provides the configuration, environment templates, and setup guide to connect AI coding assistants (such as **Grok Build**, **Claude Desktop**, **Cursor**, **Google Antigravity**, and **VS Code**) directly to **SAP S/4HANA** and **SAP ECC** systems using the **Model Context Protocol (MCP)** via **ABAP Development Tools (ADT)**.

---

## Table of Contents
1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
   - [Client Environment](#21-client-environment)
   - [SAP System Requirements](#22-sap-system-requirements)
3. [Installation & Setup](#3-installation--setup)
   - [Step 1: Install Node.js](#step-1-install-nodejs)
   - [Step 2: Install MCP Server CLI](#step-2-install-mcp-server-cli)
   - [Step 3: Configure Environment Variables](#step-3-configure-environment-variables)
4. [AI Client Configuration](#4-ai-client-configuration)
   - [Grok Build (Latest Version)](#41-grok-build-latest-version)
   - [Claude Desktop](#42-claude-desktop)
   - [Cursor IDE](#43-cursor-ide)
   - [Google Antigravity](#44-google-antigravity)
   - [VS Code (Cline / Continue / Roo Code)](#45-vs-code-cline--continue--roo-code)
5. [Verification & Available Tools](#5-verification--available-tools)
6. [Deploying ABAP Programs to SAP](#6-deploying-abap-programs-to-sap)
7. [Security & Best Practices](#7-security--best-practices)

---

## 1. Overview

The **SAP ABAP ADT MCP Server** (`@mcp-abap-adt/core`) bridges AI assistants and SAP systems over standard ADT REST endpoints. Once configured, your AI assistant gains native tools to:
- **Search & Explore**: Find repository objects (programs, classes, tables, CDS views, function modules).
- **Read & Write Code**: View and edit ABAP source code, DDIC structures, CDS Data Definitions, and table contents.
- **Syntax Check & Activate**: Execute syntax checks and activate inactive ABAP objects.
- **Data Preview**: Run ad-hoc SQL queries against SAP database tables via ADT Data Preview API.
- **Diagnostics**: Analyze short dumps (`ST22`), trace logs, and system messages.

---

## 2. Prerequisites

### 2.1. Client Environment
- **Operating System**: Windows 10/11, macOS, or Linux.
- **Node.js**: **>= 22.0.0** (required by `@mcp-abap-adt/core` v10+).
- **npm**: **>= 9.0.0** (bundled with Node.js).
- **Git**: Installed and available in your `PATH`.

### 2.2. SAP System Requirements
- **SAP Release**: SAP NetWeaver 7.50+ or SAP S/4HANA (On-Premise, Private Cloud, or BTP ABAP Environment).
- **ADT SICF Services Active**:
  - In transaction `SICF`, ensure the sub-tree `/default_host/sap/bc/adt` is **Active**.
- **HTTPS Port Reachability**:
  - The SAP Web Dispatcher / ICM HTTPS port (e.g. `44300`, `44310`) must be accessible from your workstation.
- **SAP User Authorizations**:
  - Technical or developer user with ADT authorizations:
    - `S_ADT_RES` (ADT Resource Access)
    - `S_RFC` (RFC authorization)
    - `S_DEVELOP` (ABAP Workbench object development & activation)
    - `S_TABU_DIS` (Data Preview / table queries)

---

## 3. Installation & Setup

### Step 1: Install Node.js
Verify that Node.js 22+ is installed:
```bash
node -v
npm -v
```
If your version is below 22, download the current LTS/latest release from [nodejs.org](https://nodejs.org/).

### Step 2: Install MCP Server CLI
Install the SAP ABAP ADT MCP Server globally via npm:
```bash
npm install -g @mcp-abap-adt/core
```

Verify that the CLI executable is detected:
- **Windows (Command Prompt / PowerShell)**:
  ```cmd
  where.exe mcp-abap-adt
  ```
- **macOS / Linux**:
  ```bash
  which mcp-abap-adt
  ```

### Step 3: Configure Environment Variables
1. Copy the provided template file `.sap.env.example` to `.sap.env`:
   - **Windows PowerShell**:
     ```powershell
     Copy-Item .sap.env.example .sap.env
     ```
   - **Linux / macOS**:
     ```bash
     cp .sap.env.example .sap.env
     ```
2. Open `.sap.env` and enter your SAP system credentials:
   ```ini
   # SAP HTTPS Base URL (including ADT port)
   SAP_URL=https://saps4dev.example.com:44310

   # SAP Client (Mandant)
   SAP_CLIENT=100

   # Authentication Type: 'basic' (on-premise user/password) or 'xsuaa' (SAP BTP)
   SAP_AUTH_TYPE=basic
   SAP_SYSTEM_TYPE=onprem

   # SAP User Credentials
   SAP_USERNAME=YOUR_SAP_USER
   SAP_PASSWORD=YOUR_SAP_PASSWORD

   # System ID & Language
   SAP_MASTER_SYSTEM=DEV
   SAP_LANGUAGE=EN

   # Set to 0 if connecting to a dev/sandbox system with self-signed SSL certificates
   NODE_TLS_REJECT_UNAUTHORIZED=0
   ```

> ⚠️ **IMPORTANT**: `.sap.env` contains sensitive passwords and is listed in `.gitignore`. **Never commit `.sap.env` to version control!**

---

## 4. AI Client Configuration

### 4.1. Grok Build (Latest Version)

**Grok Build** (the xAI terminal coding agent) natively supports Model Context Protocol servers via the `grok mcp` command or configuration files.

#### Option A: Using the CLI Command (Fastest)

- **Windows (PowerShell / Command Prompt)**:
  ```bash
  grok mcp add sap-s4hana -- cmd.exe /c mcp-abap-adt --transport=stdio --env-path=d:\PROJECTS\SAPABAP\.sap.env
  ```
- **macOS / Linux**:
  ```bash
  grok mcp add sap-s4hana -- mcp-abap-adt --transport=stdio --env-path=/absolute/path/to/.sap.env
  ```

#### Option B: Using `config.toml`
Add the server definition to your global Grok configuration file at `~/.grok/config.toml` (or project-level `.grok/config.toml`):

- **Windows**:
  ```toml
  [mcp_servers.sap-s4hana]
  command = "cmd.exe"
  args = ["/c", "mcp-abap-adt", "--transport=stdio", "--env-path=d:\\PROJECTS\\SAPABAP\\.sap.env"]
  ```

- **macOS / Linux**:
  ```toml
  [mcp_servers.sap-s4hana]
  command = "mcp-abap-adt"
  args = ["--transport=stdio", "--env-path=/absolute/path/to/.sap.env"]
  ```

#### Managing MCP in Grok Build:
- Open the interactive MCP manager inside the Grok TUI: `/mcps`
- List active MCP servers: `grok mcp list`
- Run diagnostic tests: `grok mcp doctor`

---

### 4.2. Claude Desktop

Edit your `claude_desktop_config.json`:
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
*(On macOS/Linux, set `"command": "mcp-abap-adt"` and pass `args: ["--transport=stdio", "--env-path=/path/to/.sap.env"]`).*

---

### 4.3. Cursor IDE

1. Open **Settings** -> **Features** -> **MCP Servers** -> **Add New MCP Server**.
2. Fill in the parameters:
   - **Name**: `sap-s4hana`
   - **Type**: `command`
   - **Command**:
     ```bash
     mcp-abap-adt --transport=stdio --env-path=d:\PROJECTS\SAPABAP\.sap.env
     ```

---

### 4.4. Google Antigravity

Add the server to your Antigravity configuration file located at:
`%USERPROFILE%\.gemini\config\mcp_config.json`:

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

### 4.5. VS Code (Cline / Continue / Roo Code)

In your extension MCP configuration file (`cline_mcp_settings.json` or `.vscode/mcp.json`):

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

## 5. Verification & Available Tools

Once connected, ask your AI assistant to run a quick test prompt:
> *"Query 5 rows from table T001 using GetSqlQuery"*
> or
> *"Search for program Z* using SearchObject"*

### Core MCP Tools Provided:
| Tool Name | Description |
| :--- | :--- |
| `SearchObject` | Search repository objects by pattern or type (`PROG`, `CLAS`, `TABL`, `DDLS`, etc.) |
| `GetProgram` / `UpdateProgram` | Read and deploy ABAP report source code |
| `ActivateProgram` / `ActivateClass` | Activate ABAP objects |
| `GetClass` / `UpdateClass` | Read and update ABAP OO classes |
| `GetSqlQuery` | Run ad-hoc ABAP SQL queries via ADT Data Preview |
| `GetTable` / `GetStructure` | Inspect DDIC table and structure definitions |
| `RuntimeGetDumpById` | Retrieve ST22 short dump details for troubleshooting |
| `CheckProgram` / `CheckClass` | Run remote ABAP syntax checks |

---

## 6. Deploying ABAP Programs to SAP

Programs located in the `src/` directory (such as `src/z_auth_test.prog.abap`) can be deployed directly to your connected SAP server.

### Option 1: Automated Script (`npm run deploy`)
Ensure your `.sap.env` file is properly configured, then run:

```bash
# Deploy default program (Z_AUTH_TEST)
npm run deploy

# Or deploy any specific ABAP file
node scripts/deploy.js src/z_auth_test.prog.abap Z_AUTH_TEST
```
The script communicates with the MCP server over stdio, checks if the program exists on SAP, creates or updates the source code, and activates it automatically.

### Option 2: Using Your AI Assistant
In any MCP-connected AI assistant (Grok Build, Claude, Cursor, Antigravity), simply instruct:
> *"Read `src/z_auth_test.prog.abap` and deploy/activate it to the connected SAP system as program `Z_AUTH_TEST`."*

### Option 3: Manual Deployment (SAP GUI / SE38)
1. Open transaction `SE38` in SAP GUI.
2. Enter program name `Z_AUTH_TEST` and choose **Create** (Type: *Executable program*, Status: *SAP Standard Production Program* or *Test Program*).
3. Copy the contents of `src/z_auth_test.prog.abap` and paste into the editor.
4. Save (`Ctrl + S`) and Activate (`Ctrl + F3`).

> 📖 **Program Documentation**: For complete technical specifications and functional logic of `Z_AUTH_TEST`, see [docs/Z_AUTH_TEST.md](docs/Z_AUTH_TEST.md).

---

## 7. Security & Best Practices

1. **Credentials Isolation**:
   - Keep `.sap.env` local. Verify it matches the `.gitignore` rule before staging or committing changes.
   - For shared CI/CD pipelines, inject environment variables through secret management systems rather than plain files.
2. **Dedicated User Account**:
   - Connect using a designated developer user rather than `SAP*` or `DDIC`.
   - In quality or production systems, restrict user authorizations to read-only (`S_TABU_DIS`, read-only ADT).
3. **SSL / TLS**:
   - If using `NODE_TLS_REJECT_UNAUTHORIZED=0` for internal development servers, ensure you only communicate across a secure private network or VPN.
