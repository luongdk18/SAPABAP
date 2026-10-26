# 📘 End-User Guide: ZAT (Z_AUTH_SU53_ANALYZER)
## Self-Service Authorization Remediation Cockpit for Role Testers & UAT Teams

> **Transaction Code**: `ZAT`  
> **ABAP Program**: [`src/z_auth_su53_analyzer.prog.abap`](../src/z_auth_su53_analyzer.prog.abap)  
> **Print-Ready PDF Guide**: [📄 `docs/Z_AUTH_SU53_ANALYZER_USER_GUIDE_EN.pdf`](./Z_AUTH_SU53_ANALYZER_USER_GUIDE_EN.pdf)  
> **Cockpit Version**: v2.0 (Dual-Grid ALV Architecture)

---

## 1. Introduction & Business Purpose

During SAP S/4HANA testing cycles (Unit Testing, Integration Testing, UAT), testers frequently encounter authorization failures (blocked transactions or missing business document authorizations). 
Conventionally, testers capture screenshots of standard transaction `SU53`, send them to Security Administrators, and wait for manual profile adjustments in `PFCG`. This causes substantial test delays and project bottlenecks.

The **`Z_AUTH_SU53_ANALYZER` (Transaction Code: `ZAT`)** utility is an automated cockpit designed to empower testers:
- **Multi-Failure SU53 History**: Aggregates all failure records from the past **3 hours** directly from kernel buffers (unlike standard SU53 which displays only the single last failed check).
- **Live Role Coverage Analysis**: Automatically cross-references missing checks against the tester's assigned Single Roles (`@08@ [OK]` or `@0A@ [ERR]`).
- **1-Click Instant Remediation**: Enables testers to select missing permissions and inject them directly into their test Single Role. The program **regenerates authorization profiles in background**, enabling immediate test resumption!

### 📊 Feature Comparison: Standard SU53 vs ZAT Cockpit

| Comparison Criteria | Standard SAP `SU53` Transaction | Advanced `ZAT` Cockpit |
| :--- | :--- | :--- |
| **Failure Retention Scope** | Stores only the **very last authorization failure**. Executing any other action completely overwrites the buffer. | **3-Hour History**: Extracts and aggregates all failed authorization checks over 3 hours via `SUSR_USER_SU53_READ`. |
| **Assigned Role Evaluation** | Displays no role information. Testers cannot identify which role is supposed to grant the missing permission. | Evaluates active Single Roles assigned to the user in real time, displaying status with intuitive visual indicators. |
| **Remediation Capability** | Read-only display. Requires manual ticket submission to Security Admin for PFCG configuration. | **Integrated `[Add to Role]` action**: Automatically updates role menu, populates 100% mandatory fields from `TOBJ`, and compiles profiles. |

---

## 2. How to Launch the Program

Testers can execute the cockpit via either of the following methods in SAP GUI:

1. **Option 1 (Recommended)**: Enter transaction code `ZAT` or `/nZAT` into the Command Field at the top-left corner and press `Enter`.
2. **Option 2**: Open transaction `SE38` or `SA38`, enter program name `Z_AUTH_SU53_ANALYZER`, and click **Execute (F8)**.

---

## 3. Selection Screen & Parameters

```
┌────────────────────────────────────────────────────────────────────────┐
│  SAP GUI: Z_AUTH_SU53_ANALYZER - SU53 Authorization Analyzer & Cockpit │
├────────────────────────────────────────────────────────────────────────┤
│ [Execute (F8)]   [Cancel]                                              │
├────────────────────────────────────────────────────────────────────────┤
│ ┌─ 1. User Selection ────────────────────────────────────────────────┐ │
│ │ User Name:                 [TEST_USER01     ]                      │ │
│ └────────────────────────────────────────────────────────────────────┘ │
│ ┌─ 2. Filter Options ────────────────────────────────────────────────┐ │
│ │ [X] Active Single Roles Only                                       │ │
│ └────────────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────┘
```

- **`User Name`**: Target SAP user account; defaults to the currently logged-on user. Test Leads can enter another tester's account to diagnose issues collaboratively.
- **`Active Single Roles Only`**: Restricts analysis to valid Single Roles, automatically filtering out expired roles and Composite Roles to ensure precision.

---

## 4. Dual-Grid Cockpit Architecture

Upon executing (**F8**), the cockpit opens a dual-level operational workbench:

```
┌────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ 1. ASSIGNED SINGLE ROLES OF USER (CLICK RADIO ICON TO SELECT TARGET ROLE)                              │
│ [➕ Add to Role]   [☑️ Select All]   [⬜ Deselect All]   [🔄 Refresh from SU53]                        │
├─────────┬──────────────────────┬──────────────────────────┬────────────────────────────────┬───────────┤
│ Target  │ Assigned Role        │ Leading Role (Hotspot)   │ Role Description               │ Valid To  │
├─────────┼──────────────────────┼──────────────────────────┼────────────────────────────────┼───────────┤
│ 🔘 (Sel)│ DRFI01_PERIOD_1100   │ LRFI01_PERIOD_CONTROL    │ GL Period Control - CC 1100    │ 31.12.9999│
│ ⚪      │ DRMM01_PO_MAIN_1100  │ LRMM01_PO_MAIN           │ Purchasing Operations - CC 1100│ 31.12.9999│
│ ⚪      │ CR_COMMON            │                          │ Common End User Baseline Role  │ 31.12.9999│
└─────────┴──────────────────────┴──────────────────────────┴────────────────────────────────┴───────────┘
                                            ▼ (Real-time Cross Match)
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ 2. FAILED AUTHORIZATION CHECKS (SELECT ITEMS VIA CHECKBOX TO ADD TO TARGET ROLE)       │
├────┬───────────┬──────┬──────────┬──────────────────────┬──────────────────────────────┤
│Sel │Status     │TCode │Object    │Object Description    │Checked Fields & Values       │
├────┼───────────┼──────┼──────────┼──────────────────────┼──────────────────────────────┤
│ ☑  │ @0A@ [ERR]│FB01  │F_BKPF_BUK│Accounting Document   │ACTVT = '01', BUKRS = '1000'  │
│ ☑  │ @0A@ [ERR]│FS00  │S_TCODE   │Transaction Code Check│TCD = 'FS00'                  │
│ ☐  │ @08@ [OK] │FB03  │F_BKPF_BUK│Accounting Document   │ACTVT = '03', BUKRS = '1000'  │
└────┴───────────┴──────┴──────────┴──────────────────────┴──────────────────────────────┘
```

### 🎛️ Toolbar Actions & Navigation Controls

| Action / Button | Shortcut / Icon | Functional Description |
| :--- | :--- | :--- |
| **`[Add to Role]`** | `➕` | Injects all checked authorizations and TCodes into the target Leading Role, selectively derives only the newly added objects down to child derived roles, and triggers background profile regeneration. |
| **`[Select All]`** | `☑️` | Selects all missing authorization items (`@0A@ [ERR]`). Items already satisfied (`@08@ [OK]`) are automatically bypassed. |
| **`[Deselect All]`** | `⬜` | Clears all selected checkboxes in the bottom grid. |
| **`[Refresh from SU53]`** | `🔄` (F8) | Re-reads system failure buffers when the tester performs additional transaction actions in another session. |
| **Click Radio Button** | `Target` column | Switches the active assigned role. ZAT automatically identifies its Leading Role and re-evaluates failure coverage in the bottom grid. |
| **Click Leading Role** | `Leading Role` column | Hotspot link that opens transaction `PFCG` directly for the Leading Role (Master Role). |

---

## 5. Standard 5-Step Remediation Workflow for Testers

Follow this standardized 5-step procedure when blocked by an authorization failure during business scenario execution:

1. **Step 1 - Encounter authorization failure in business transaction**:
   - While executing your scenario (e.g. `FB01`, `ME21N`, `FS00`), SAP halts execution and outputs a red status bar message:  
     `You are not authorized to use transaction FB01` or `No authorization for Company Code 1000 (Object F_BKPF_BUK)`.
2. **Step 2 - Launch ZAT in a new parallel session**:
   - Open a new SAP GUI window by typing `/oZAT` in the Command Field (preserves your working transaction).
   - Verify your User Name and press **F8** to retrieve failure buffer logs.
3. **Step 3 - Select the target Assigned Role in Top Grid**:
   - Click the circular radio button in the `Target` column corresponding to the functional role you are validating (e.g. `DRFI01_PERIOD_1100`).
   - The Top Grid displays the role's **Leading Role** (Master Role, e.g. `LRFI01_PERIOD_CONTROL`).
   - The failure rows in the bottom grid instantly recalculate their coverage status.
4. **Step 4 - Select the missing authorizations in Bottom Grid**:
   - Tick the checkboxes in the `Select` column for rows marked with red indicator `@0A@ [ERR]`.
   - Alternatively, click the **`[Select All]`** toolbar button to select all valid remediation items at once.
5. **Step 5 - Click [Add to Role] for automated Leading Role remediation & selective derivation**:
   - Click the **`[Add to Role]`** button on the Top Grid toolbar. The utility automatically executes in background:
     - **Leading Role Injection**: Adds the TCode to menu (for `S_TCODE`) or injects the missing object into the **Leading Role** (`LRFI01_PERIOD_CONTROL`).
     - **Selective Child Derivation**: Propagates **ONLY the newly added object(s) / TCodes** down to all child derived roles of that Leading Role.
     - **Zero Unwanted Impact**: All existing authorizations, custom fields, and Organizational Levels (`AGR_1252`) in derived roles remain **100% untouched**!
     - **Profile Compilation**: Automatically regenerates runtime authorization profiles for both the Leading Role and all its child derived roles.
   - The status bar displays a green confirmation message:  
     `Leading Role LRFI01_PERIOD_CONTROL updated & derived to X child role(s): 1 object(s) / 2 value(s) added.`
   - **Outcome**: Return to your original transaction window (`FB01`) and press `Enter` to resume testing immediately without logging off!

---

## 6. Status Code Reference & Advanced Features

### 🚦 ALV Grid Status Indicators

| Status Code | Indicator | Technical Meaning | Recommended Action |
| :--- | :--- | :--- | :--- |
| **`@08@ [OK]`** | 🟢 Green | The authorization object and checked values **already exist** in the selected role. Selection checkbox is disabled. | No action required. The failure is already satisfied by this role or granted previously. |
| **`@0A@ [ERR]`** | 🔴 Red | The authorization object or field values are **missing** in the selected role. This is the direct cause of the block. | Tick the checkbox and click **`[Add to Role]`** to resolve the failure immediately. |
| **`@09@ [WARN]`** | 🟡 Yellow | Partial match; or the SU53 buffer contains no failed authorization checks within the last 3 hours. | Re-perform the failing transaction step in your business window, then click **`[Refresh from SU53]`**. |

### 🔍 Advanced Operational Features

- **Authorization Object Jump (`SU03`)**: Double-click any entry in the `Auth Object` column (e.g. `F_BKPF_BUK`). The cockpit automatically opens transaction `SU03`, displaying official SAP documentation and technical field definitions for that object.
- **Spreadsheet Export for Audit & Reporting**: Press `Ctrl + Shift + F7` or navigate to `List ➔ Export ➔ Spreadsheet`. Because status codes include explicit text tags (`@08@ [OK]`, `@0A@ [ERR]`), exported Excel files can be filtered cleanly by test leads or PMO teams.

---

## 7. Frequently Asked Questions & Troubleshooting (FAQ)

> **Q1: Why does [Add to Role] display "Role is locked (Edit mode)"?**  
> **Answer:** The target role is currently opened in Change Mode in transaction `PFCG` by another administrator or your own user. Exit edit mode in `PFCG` (enter `/n`), return to `ZAT`, and re-click `[Add to Role]`.

> **Q2: Why is the newly added transaction not visible in the SAP Easy Access tree?**  
> **Answer:** ZAT successfully injects the TCode into the role menu and generates the technical `S_TCODE` authorization. To refresh the visual SAP Easy Access tree on the initial screen, simply type `/n` or start the transaction directly from the Command Field.

> **Q3: Are the injected authorizations permanent?**  
> **Answer:** Yes. Authorizations are written directly into standard SAP tables (`AGR_1250`, `AGR_1251`, `AGR_1252`) and compiled into the generated profile. They persist permanently until the role is deliberately modified in a subsequent release cycle.
