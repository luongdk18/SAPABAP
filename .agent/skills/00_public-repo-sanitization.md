---
name: public-repo-sanitization
description: >-
  Strict privacy, data sanitization, and open-source compliance guidelines for public SAP ABAP
  repositories. Enforces zero hardcoded customer data, zero proprietary company names, zero real
  domain names, zero specific Transport Request numbers, zero internal IP addresses or hostnames,
  zero concrete SAP user IDs, and zero system IDs across all code, comments, documentation, and scripts.
---

# 🛡️ Public Repository Data Sanitization & Anonymization Policy

> **Applies to**: Entire repository (`d:\PROJECTS\SAPABAP`)  
> **Mandatory Policy**: This repository is **publicly hosted on GitHub**. Under no circumstances shall any customer-specific, proprietary, internal, or identifying information be stored in source code, comments, documentation, scripts, or commit history.

---

## 🚫 1. Absolute Prohibitions: Zero Specific Data

All developers and AI pair-programming agents must strictly comply with the following 7 Zero-Data principles:

### 1.1 Zero Specific Transport Request Numbers
- **Forbidden**: Hardcoding real internal transport request numbers.
- **Standard**:
  - In documentation: Use `<TRANSPORT_REQUEST>` or state `assign to your Transport Request (or local object $TMP)`.
  - In deploy scripts (`scripts/*.js`): Default `transportRequest` to `''` or read from environment variable `process.env.SAP_TRANSPORT_REQUEST`.
  - In example config (`.sap.env.example`): Use generic placeholder `DEVK900001`.
  - In ABAP program headers: Use `*& Package: $TMP (Local Object) or Custom Package`.

### 1.2 Zero Proprietary Company & Entity Names
- **Forbidden**: Hardcoding real company names, subsidiaries, or customer abbreviations.
- **Standard**:
  - In selection screens: Parameters such as `p_comp` (Company Address) MUST be left **blank by default** (`PARAMETERS: p_comp TYPE bapiuscomp-company.`) and equipped with F4 Search Help (`F4IF_INT_TABLE_VALUE_REQUEST` from `USCOMPANY`) so the user selects their company directly from the active SAP system.
  - In documentation & code comments: Use generic business examples such as `'ACME Corporation'` or `'Example Corp'`.

### 1.3 Zero Real Domain Names, URLs & Hostnames
- **Forbidden**: Hardcoding real corporate domains, subdomains, reverse proxies, or internal server URLs, private IP addresses, or hostnames.
- **Standard**:
  - Always use RFC 2606 / RFC 6761 reserved example domains or generic placeholders:
    - `https://<your-sap-domain>/reset`
    - `https://erp.example.com`
    - `https://<sap-host>:<port>/sap/bc/z_sspr`
  - In email examples: Use `johnd@example.com`, `user@example.com`, or `admin@example.org`.

### 1.4 Zero Concrete Personnel & Employee User IDs
- **Forbidden**: Hardcoding real internal usernames, employee codes, or individual names.
- **Standard**:
  - Always use standard generic persona IDs: `JOHND`, `JANES`, `ALEXJ`, `MICHAELB`, or `<USERNAME>`.
  - Full names in samples: `'John Doe'`, `'Jane Smith'`, `'Alex Johnson'`, `'Michael Brown'`.

### 1.5 Zero Hardcoded Client Numbers & System IDs (SIDs)
- **Forbidden**: Hardcoding concrete client numbers or specific SIDs in program logic, selection screen defaults, or UI elements.
- **Standard**:
  - Always dynamically resolve the current client via `sy-mandt` and current SID via `sy-sysid`.
  - In selection screens, allow user input with F4 help or leave client selection to the system context.
  - In documentation: Refer to clients generically as `<client>` (e.g., Client 100/110 only as generic illustrative examples of Dev/Test environments).

### 1.6 Zero Hardcoded Passwords, Secrets & Tokens
- **Forbidden**: Committing real passwords, password hashes, API keys, or active session tokens.
- **Standard**:
  - All credentials belong exclusively in `.sap.env` (which must be permanently ignored by `.gitignore`).
  - Example files (`.sap.env.example`) must contain obvious dummy tokens: `InitPass@2026`, `secret_token_here`.

### 1.7 Documentation & Codebase Reality Alignment
- **Policy**: Documentation must always accurately reflect the current state of ABAP programs.
- When an option or parameter is removed from an ABAP program (e.g., removing a technical user restore feature), the corresponding documentation (`docs/*.md`) must be immediately updated to remove that feature and reflect reality.

---

## 🔍 Pre-Commit Sanitization Checklist (MANDATORY GATE)

Before EVERY `git commit` and `git push`, you **MUST** run the automated sanitization audit script and verify **0 violations**:

```bash
python scripts/check_sanitization.py
# or:
npm run check:sanitization
```

In addition, perform a manual review of `git diff --cached` against these criteria:
1. **Personal Data**: No real names, real phone numbers, real emails, real employee IDs, real SAP usernames, or local OS user paths (`C:\Users\<user>`).
2. **Company / Organization / Project-Specific Codes**: No real company/subsidiary names, client-specific role prefixes, or real production/UAT company codes (`BUKRS`), controlling areas (`KOKRS`), or plants (`WERKS`). Use only generic IDES examples (`1000`, `2000`, `Z_FI_*`, `Z_MM_*`).
3. **System Names / SIDs / Domains / IPs / TRs**: No real SAP System IDs, client numbers, internal hostnames, private IP addresses, corporate domains, or real Transport Request numbers.
4. **Secrets & Ignored Files**: Ensure `.sap.env`, `.env`, and `excel-working/` are never staged or committed.

If **any** check fails or leaks are suspected, immediately sanitize all affected files (code, comments, docs, Excel metadata/cells, CSV samples) before committing.
