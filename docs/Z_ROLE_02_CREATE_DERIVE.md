# 🧬 Z_ROLE_02_CREATE_DERIVE: Batch Derived Role Creation

> **Source Code**: [`src/z_role_02_create_derive.prog.abap`](../src/z_role_02_create_derive.prog.abap)  
> **Companion Script**: [`scripts/convert_role_02_derive.py`](../scripts/convert_role_02_derive.py)  
> **Sample CSV**: [`excel-templates/converted/Template_Role_02_Derived_converted.csv`](../excel-templates/converted/Template_Role_02_Derived_converted.csv)

Automates the batch creation of **Derived Single Roles** from parent **Master Roles** directly from CSV data, links `PARENT_AGR`, inherits menus and authorizations, initializes Organizational Levels to template defaults (`-1`), and compiles runtime profiles.

---

## 📌 Workflow

```
[ Input CSV: Master Role, Derived Role, Description ]
            │
            ▼  Upload via GUI_UPLOAD (UTF-8)
[ Validate Master Role in AGR_DEFINE & AGR_FLAGS ]
            │
    ┌───────┴────────────────────────┐
    ▼ (Master Role Valid)            ▼ (Master Invalid / Collective)
[ Check Derived Role Existence ]     [ Report Error: @0A@ [ERR] ]
    │
    ├─► Exists & p_upd = Space: Skip ➔ @09@ [WARN]
    ├─► Exists & p_upd = 'X'   : Synchronize ➔ @08@ [OK]
    └─► New Derived Role       :
          1. Create shell (PRGN_RFC_CREATE_AGR_MULTIPLE)
          2. Transfer auths (PRGN_RFC_CREATE_DERIVATION)
          3. Default Org Levels to '-1' (AGR_1252)
          4. Background profile generation (SUPRN_DARK_MANIPULATE_PROFILE)
          5. Report Success ➔ @08@ [OK]
            │
            ▼
[ Interactive ALV Cockpit with Two-Way PFCG Navigation ]
```

---

## ⚙️ Key Technical Features

1. **Master Role Integrity Check**: Ensures the parent role exists and is NOT a collective role (`AGR_FLAGS-COLL_AGR = 'X'`).
2. **Clean Text Maintenance**: Preserves original description formatting while stripping automatic SAP boilerplate comments.
3. **`-1` Org Level Safety Architecture**: Initializes inherited Org Levels to `'-1'` so derived roles can compile profiles cleanly without triggering unmaintained dumps.
4. **Idempotent Synchronization (`p_upd = 'X'`)**: Re-synchronizes auths from master roles when templates are updated.
5. **Two-Way Hotspot Navigation**: Clicking Derived Role or Master Role in ALV opens transaction `PFCG` directly for that role.

---

## 🎛️ Selection Screen

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `p_file` | `localfile` | Mandatory | Path to normalized CSV file |
| `p_test` | `checkbox` | `'X'` | Simulation mode (test run without writing to DB) |
| `p_upd` | `checkbox` | `'X'` | Update/synchronize existing derived roles |
| `p_adjust` | `checkbox` | `'X'` | Adjust authorization data during derivation transfer |
| `p_orgdef` | `checkbox` | `'X'` | Initialize Org Levels to `'-1'` |
| `p_genprf` | `checkbox` | `'X'` | Automatically generate authorization profiles in dark mode |

---

## 📊 Status Codes in ALV & Excel

| Status Code | GUI Display | Meaning | Action Taken |
| :--- | :--- | :--- | :--- |
| **`@08@ [OK]`** | Green LED | Derived role created or updated/synchronized successfully | `CREATED` / `UPDATED` / `SIMULATE` |
| **`@09@ [WARN]`** | Yellow LED | Role already exists and `p_upd` is unchecked | `SKIPPED` / `SIMULATE` |
| **`@0A@ [ERR]`** | Red LED | Master role missing/collective, name > 30 chars, or BAPI error | `ERROR` |

---

## 🔧 SAP Function Modules Used

- `PRGN_RFC_CREATE_AGR_MULTIPLE`: Creates derived role definition with `PARENT_AGR`.
- `PRGN_RFC_CREATE_DERIVATION`: Inherits menu and authorization data from master.
- `SUPRN_DARK_MANIPULATE_PROFILE`: Generates runtime authorization profile.
- `PRGN_SET_ACTGROUP_TIMESTAMP`: Updates role modification timestamp.

---

## 🚀 Deployment

```bash
npm run deploy:role:02
```
