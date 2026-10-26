# 🛡️ Z_AUTH_SU53_ANALYZER: SU53 Authorization Analyzer & Remediation Cockpit

> **Source Code**: [`src/z_auth_su53_analyzer.prog.abap`](../src/z_auth_su53_analyzer.prog.abap)  
> **Transaction Code**: `ZAT`  
> **End-User Guide**: [📘 User Guide (MD)](./Z_AUTH_SU53_ANALYZER_USER_GUIDE_EN.md) \| [📄 PDF Guide](./Z_AUTH_SU53_ANALYZER_USER_GUIDE_EN.pdf)  
> **Repository**: [https://github.com/luongdk18/SAPABAP](https://github.com/luongdk18/SAPABAP)

Interactive dual-grid operational cockpit for SAP Security Administrators. Automates SU53 failure extraction, evaluates coverage across user single roles, and injects missing objects into PFCG roles with 100% mandatory `TOBJ` field completeness and background profile regeneration.

---

## 📌 Dual-Grid Cockpit Architecture

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ TOP DOCKING CONTAINER (cl_gui_docking_container): SINGLE ROLES & LEADING ROLES LIST    │
│ [Add to Role]  [Select All]  [Deselect All]  [Refresh from SU53]                       │
├────┬──────────────────┬──────────────────────────┬─────────────────────────────────────┤
│Opt │ Assigned Role    │ Leading Role             │ Role Description                    │
├────┼──────────────────┼──────────────────────────┼─────────────────────────────────────┤
│🔘  │ DRFI01_PERIOD_110│ LRFI01_PERIOD_CONTROL    │ GL Period Control - CC 1100         │
│⚪  │ DRMM01_PO_MAIN   │ LRMM01_PO_MAIN           │ Purchasing Operations               │
│⚪  │ CR_COMMON        │                          │ Common End User Baseline Role       │
└────┴──────────────────┴──────────────────────────┴─────────────────────────────────────┘
                                  ▼
┌────────────────────────────────────────────────────────────────────────┐
│ BOTTOM FULLSCREEN GRID: MISSING AUTHORIZATIONS & TCODES (SU53 BUFFER)   │
├────┬──────┬──────┬──────────┬──────────────────────┬───────────────────┤
│Sel │Status│TCode │Object    │Object Description    │Field Values       │
├────┼──────┼──────┼──────────┼──────────────────────┼───────────────────┤
│ ☑  │ @0A@ │FB01  │F_BKPF_BUK│Accounting Document   │ACTVT=01; BUKRS=100│
│ ☐  │ @08@ │FS00  │S_TCODE   │Transaction Code      │TCD=FS00           │
└────┴──────┴──────┴──────────┴──────────────────────┴───────────────────┘
```

---

## ⚙️ Key Technical Features

1. **Multi-Failure SU53 History**: Aggregates all failure records from the past 3 hours via `SUSR_USER_SU53_READ`, unlike standard `SU53` which shows only the single last failed check.
2. **Real-Time Role Coverage Check**: Dynamically cross-references missing checks against active user single roles (`AGR_USERS` ➔ `AGR_1251`), marking satisfied objects with `@08@ [OK]` and missing objects with `@0A@ [ERR]`.
3. **Leading Role Target & Selective Derivation**: If the selected role is a **Derived Role** (`PARENT_AGR` is present), ZAT automatically updates the **Leading Role (Master Role)** and propagates **ONLY the newly added object(s)** down to its child derived roles. All existing authorizations, custom field values, and organizational levels (`AGR_1252`) in the derived roles remain completely untouched!
4. **100% Default Field Pass from `TOBJ`**: When adding an authorization object, all mandatory default fields defined in table `TOBJ` are populated. This eliminates unmaintained authorization fields (no Yellow Triangles in PFCG).
5. **Deactivated Object Reactivation**: Detects and reactivates deactivated objects (`DELETED = 'X'`) in `AGR_1251` rather than generating duplicate conflicting authorizations.
6. **Forced Profile Regeneration**: Automatically compiles the authorization profile in dark mode (`SUPRN_DARK_MANIPULATE_PROFILE`) and defaults open Org Levels (`AGR_1252`) to `'*'`, allowing immediate re-testing without opening `PFCG`.

---

## 🎛️ Selection Screen

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `p_user` | `bapibname-bapibname` | `sy-uname` | SAP Target User ID |
| `p_hours`| `i` | `3` | Time window to inspect in SU53 buffer (hours) |

---

## 📊 Status Codes in ALV & Excel

| Status Code | GUI Display | Meaning | Action Taken |
| :--- | :--- | :--- | :--- |
| **`@08@ [OK]`** | Green LED | Permission already covered by user's assigned roles | Informational |
| **`@09@ [WARN]`** | Yellow LED | Partially matched or warning during role injection | Warning |
| **`@0A@ [ERR]`** | Red LED | Missing authorization causing SU53 failure | Selectable for remediation |

---

## 🔧 SAP Function Modules Used

- `SUSR_USER_SU53_READ`: Reads SU53 buffer failure history.
- `PRGN_STRU_LOAD_NODES`: Loads menu hierarchy nodes to locate the first folder.
- `PRGN_STRU_SAVE_NODES`: Saves updated menu hierarchy with new TCodes nested under the first folder.
- `PRGN_1250_SAVE_AUTH_DATA`: Saves authorization header data.
- `PRGN_1251_SAVE_FIELD_VALUES`: Saves authorization objects and fields.
- `SUPRN_DARK_MANIPULATE_PROFILE`: Background profile generation.

---

## 🚀 Deployment

```bash
npm run deploy:su53
```
