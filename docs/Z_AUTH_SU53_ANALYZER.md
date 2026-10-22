# 🛡️ Z_AUTH_SU53_ANALYZER: SU53 Authorization Analyzer & Remediation Cockpit

> **Source Code**: [`src/z_auth_su53_analyzer.prog.abap`](../src/z_auth_su53_analyzer.prog.abap)  
> **Repository**: [https://github.com/luongdk18/SAPABAP](https://github.com/luongdk18/SAPABAP)

Interactive dual-grid operational cockpit for SAP Security Administrators. Automates SU53 failure extraction, evaluates coverage across user single roles, and injects missing objects into PFCG roles with 100% mandatory `TOBJ` field completeness and background profile regeneration.

---

## 📌 Dual-Grid Cockpit Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│ TOP DOCKING CONTAINER (cl_gui_docking_container): SINGLE ROLES LIST     │
│ [Add to Role]  [Select All]  [Deselect All]  [Refresh from SU53]       │
├────┬──────────────────┬────────────────────────────────────────────────┤
│Radio│ Role Name        │ Role Description                               │
├────┼──────────────────┼────────────────────────────────────────────────┤
│🔘  │ Z_FI_GL_ACCOUNT  │ General Ledger Accounting Role                 │
│⚪  │ Z_MM_PURCHASER   │ Purchasing Operations                          │
└────┴──────────────────┴────────────────────────────────────────────────┘
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
3. **100% Default Field Pass from `TOBJ`**: When adding an authorization object, all mandatory default fields defined in table `TOBJ` are populated. This eliminates unmaintained authorization fields (no Yellow Triangles in PFCG).
4. **Deactivated Object Reactivation**: Detects and reactivates deactivated objects (`DELETED = 'X'`) in `AGR_1251` rather than generating duplicate conflicting authorizations.
5. **Forced Profile Regeneration**: Automatically compiles the authorization profile in dark mode (`SUPRN_DARK_MANIPULATE_PROFILE`) and defaults open Org Levels (`AGR_1252`) to `'*'`, allowing immediate re-testing without opening `PFCG`.

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
- `PRGN_RFC_MODIFY_ACTIVITY_GROUP`: Injects transactions into role menu.
- `PRGN_1251_SAVE_FIELD_VALUES`: Saves authorization objects and fields.
- `SUPRN_DARK_MANIPULATE_PROFILE`: Background profile generation.

---

## 🚀 Deployment

```bash
npm run deploy:su53
```
