---
name: mcp-token-optimization
description: >-
  Token-efficiency standards and operational guidelines for working with SAP ABAP ADT via
  @mcp-abap-adt MCP servers. Activate whenever configuring MCP servers, inspecting live SAP
  objects, querying DDIC/ABAP sources, or deploying ABAP programs/classes to minimize LLM
  context overhead and round-trip token costs.
---

# ⚡ SAP ABAP ADT MCP Token Optimization Guide

> **Applies to**: All AI agent sessions interacting with SAP via `@mcp-abap-adt/*`  
> **Goal**: Minimize per-turn tool schema overhead, response payload size, and tool round-trips without sacrificing accuracy or safety.

---

## 📊 1. Choose the Right MCP Binary (Biggest Token Savings)

From `@mcp-abap-adt` v19+, the exposed tool set is fixed by the **binary** you install (`--exposition` is deprecated and rejected). Choosing the compact variants cuts per-turn tool schema overhead by **70% to 87%**:

| Package | Binary | Tool Count (`onprem`) | JSON Schema Size | Approx. Overhead / Turn | Recommended Use Case |
| :--- | :--- | :---: | :---: | :---: | :--- |
| `@mcp-abap-adt/core` | `mcp-abap-adt` | 272 | ~402 KB | **~100,400 tokens** | CLI deploy scripts (`scripts/deploy.js`) only; avoid loading directly into chat |
| `@mcp-abap-adt/compact` | `mcp-abap-adt-compact` | 38 | ~120 KB | **~29,900 tokens** (-70%) | Full read/write/debug interactive IDE work |
| `@mcp-abap-adt/compact` + `--deny-actions=HandlerDebug*` | `mcp-abap-adt-compact` | 33 | ~101 KB | **~25,300 tokens** (-75%) | **Default interactive IDE dev** (no debugger tools loaded) |
| `@mcp-abap-adt/compact-ro` | `mcp-abap-adt-compact-ro` | 20 | ~53 KB | **~13,200 tokens** (-87%) | **Read-only research / code inspection** |

### Recommended Global Installation
```bash
# Required for local CLI deploy scripts (scripts/deploy.js, deploy_class.js):
npm install -g @mcp-abap-adt/core

# Recommended for interactive AI IDE sessions (low token footprint):
npm install -g @mcp-abap-adt/compact @mcp-abap-adt/compact-ro
```

> [!IMPORTANT]
> Do **NOT** uninstall `@mcp-abap-adt/core` if you use `npm run deploy:*` (`scripts/deploy.js` / `scripts/deploy_class.js`), because those scripts spawn `mcp-abap-adt` directly in Node.js outside the LLM context (consuming **0 LLM tokens** for schemas or ABAP payloads).

---

## 🛠️ 2. Primary Coding Workflow: Local Diff Edit + CLI Deploy (Zero MCP Token Cost)

Whenever authoring, refactoring, or debugging repository ABAP code (`src/*.prog.abap`, `src/*.clas.abap`):

1. **Edit locally first**: Always modify `src/*.abap` files using local file-editing tools (small targeted diffs) instead of calling MCP `UpdateProgram` / `UpdateClass` (which forces the LLM to emit the entire 1,000–2,000 line source file into JSON tool arguments).
2. **Validate locally before deploying**: Run `node scripts/check_nesting.js <file>` for syntax/block balance checks.
3. **Deploy via CLI script**: Run `npm run deploy:<target>` (or `node scripts/deploy.js <file> <NAME>`). The Node script reads the file from disk, updates & activates on SAP via ADT, and prints only a concise status message.
4. **Use live IDE MCP only when needed**: Turn on or call live MCP tools specifically when inspecting standard SAP objects, DDIC definitions, function module signatures, or system diagnostics that do not exist locally.

---

## 🎯 3. Optimal MCP Server Flags & Environment Settings

Configure your IDE MCP server (see `mcp-config.example.json`) and `.sap.env` with these flags:

1. **Enable `--deferred-logon`** (`MCP_DEFERRED_LOGON=true`, available in v24+):
   - Starts the MCP server immediately without contacting SAP at IDE startup.
   - Prevents unnecessary logon attempts or accidental user lockouts when working offline or on pure local edits.
2. **Unregister unused tool groups with `--deny-actions`** (v24+):
   - Example: `--deny-actions=HandlerDebug*` removes debugger tools when you are not actively debugging.
   - Example: `--deny-actions=HandlerDebug*,HandlerDelete` adds extra safety while trimming schema size.
3. **Keep data tools off unless required**:
   - `--enable-data-tools` (`MCP_ENABLE_DATA_TOOLS`) is `false` by default in v24+; leave it off unless explicitly reading table/SQL data.
4. **Silence verbose logs**:
   - Always set `HANDLER_LOG_SILENT=true`.
   - Keep `DEBUG_HANDLERS`, `DEBUG_CONNECTORS`, `DEBUG_CONNECTION_MANAGER`, `DEBUG_AUTH_LOG`, and `--auth-debug` **unset/disabled** in normal sessions (saves output tokens and avoids leaking auth headers into logs).
5. **Keep Batch raw parts off**:
   - Keep `--batch-keep-raw-parts` at default `false` so batch responses omit raw HTTP headers and raw XML bodies.
6. **Per-Workspace MCP Isolation (Recommended for Antigravity / Multi-Repo Setups)**:
   - Keep the global `~/.gemini/config/mcp_config.json` empty (`{"mcpServers": {}}`) so SAP MCP tools are never loaded into unrelated non-SAP workspaces.
   - Store this workspace's local MCP server inside a gitignored workspace plugin (`.agent/plugins/sap-adt-sapabap/plugin.json` + `mcp_config.json`, ignored via `.agent/plugins/` in `.gitignore`), pointing exclusively to this repository's `.sap.env` with a workspace-specific server name (e.g., `sap-sapabap`). This guarantees zero cross-repo credential mixing and zero token overhead in other workspaces.

---

## 📦 4. Query Discipline & Context Hygiene for AI Agents

When calling live SAP ADT MCP tools:

1. **Check local documentation first**:
   - Before querying standard SAP Function Module signatures (`PRGN_*`, `BAPI_USER_*`, `SUPRN_*`, `SUSR_*`), check `.agent/skills/01_sap-security-api-guidelines.md` and `docs/SAP_STANDARD_APIS_CATALOG.md` first.
2. **Batch independent reads**:
   - When inspecting multiple SAP objects (e.g., 3–6 tables, FMs, or classes), group them using `HandlerBatch` (`begin` → read calls → `end` → `answers`) instead of sequential single-tool turns.
3. **Always scope queries narrowly**:
   - **Search**: Always specify `object_type` and/or `package` filters rather than broad wildcards.
   - **Function Modules / Classes**: Fetch only the specific Function Module or class `definition`/relevant include rather than downloading an entire Function Group.
   - **Table Reads** (when enabled): Always supply tight `WHERE` clauses and small `max_rows` limits (e.g., `10–20` rows).
4. **Keep conversations focused**:
   - Start a fresh session when switching to a different ABAP program or task, or compact context (`/compact`) after heavy SAP inspection steps so large raw ADT payloads are not re-sent on every subsequent turn.
