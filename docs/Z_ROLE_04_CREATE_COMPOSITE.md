# 📦 Z_ROLE_04_CREATE_COMPOSITE: Batch Composite Role Creation

> **Source Code**: [`src/z_role_04_create_composite.prog.abap`](../src/z_role_04_create_composite.prog.abap)  
> **Companion Script**: [`scripts/convert_role_04_composite.py`](../scripts/convert_role_04_composite.py)  
> **Sample CSV**: [`excel-templates/converted/Template_Role_04_Composite_converted.csv`](../excel-templates/converted/Template_Role_04_Composite_converted.csv)

Automates the mass creation and updating of **Composite Roles** (Collective Roles / *Sammelrollen*) and bundles member **Single Roles** directly from flat CSV data.

---

## 📌 Workflow

```
[ Input CSV: Composite Role, Description, Single Role ]
            │
            ▼  Upload via GUI_UPLOAD (UTF-8)
[ Validate Role Name Length (<= 30) & Single Role Collisions ]
            │
    ┌───────┴────────────────────────┐
    ▼ (Validation Passed)            ▼ (Collision: Exists as Single Role)
[ Validate Member Single Roles ]     [ Report Error: @0A@ [ERR] ]
    │
    ├─► Valid Single Roles  ➔ Add to Assignment Buffer
    └─► Missing from SAP    ➔ Isolate into Missing Roles Column
            │
    ┌───────┴────────────────────────┐
    ▼ (Role Exists & p_upd = Space)  ▼ (New Role / p_upd = 'X')
[ Report Skipped: @09@ [WARN] ]     [ Create Composite Shell & Assign ]
                                      1. PRGN_RFC_CREATE_AGR_MULTIPLE
                                      2. Clean AGR_TEXTS comments
                                      3. PRGN_RFC_ADD_AGRS_TO_COLL_AGR
                                      4. Status: @08@ [OK] / @09@ [WARN]
            │
            ▼
[ Interactive ALV Cockpit with One-Click PFCG Hotspot ]
```

---

## ⚙️ Key Technical Features

1. **Native Composite Definition**: Sets `AGR_DEFINE-ATTRIBUTES = 'COLLECTIVE'` and `AGR_FLAGS-COLL_AGR = 'X'` to properly configure collective role behavior.
2. **Single Role Collision Protection**: Prevents accidentally overwriting an existing Single Role as a Composite Role.
3. **Non-Blocking Missing Role Isolation**: If member single roles are missing from SAP, valid roles are still assigned, while missing roles are listed in a dedicated column with `@09@ [WARN]`.
4. **Empty Role Support (`N/A`)**: Gracefully handles placeholder composite roles that currently have no assigned single roles.
5. **Membership Synchronization (`p_sync = 'X'`)**: Removes obsolete single roles from existing composite roles to mirror the CSV matrix exactly.

---

## 🎛️ Selection Screen

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `p_file` | `localfile` | Mandatory | Path to normalized CSV file |
| `p_test` | `checkbox` | `'X'` | Simulation mode (test run without writing to DB) |
| `p_upd` | `checkbox` | `'X'` | Update existing composite roles |
| `p_sync` | `checkbox` | `'X'` | Synchronize members (remove roles no longer in CSV) |
| `p_chkrol`| `checkbox` | `'X'` | Validate member single roles against table `AGR_DEFINE` |

---

## 📊 Status Codes in ALV & Excel

| Status Code | GUI Display | Meaning | Action Taken |
| :--- | :--- | :--- | :--- |
| **`@08@ [OK]`** | Green LED | Composite role created / updated with all member roles assigned | `CREATED` / `UPDATED` / `SIMULATE` |
| **`@09@ [WARN]`** | Yellow LED | Missing single roles excluded, role skipped, or placeholder (`N/A`) | `SIMULATE` / `SKIPPED` / `WARNING` |
| **`@0A@ [ERR]`** | Red LED | Single role collision, name > 30 chars, or BAPI error | `ERROR` |

---

## 🔧 SAP Function Modules Used

- `PRGN_RFC_CREATE_AGR_MULTIPLE`: Creates collective role shell definition.
- `PRGN_RFC_ADD_AGRS_TO_COLL_AGR`: Bundles member single roles into composite role.
- `PRGN_SET_ACTGROUP_TIMESTAMP`: Updates role modification timestamp.

---

## 🚀 Deployment

```bash
npm run deploy:role:04
```
