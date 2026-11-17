# 🏗️ Z_ROLE_01_CREATE_MASTER: Batch Master Role Creation

> **Source Code**: [`src/z_role_01_create_master.prog.abap`](../src/z_role_01_create_master.prog.abap)  
> **Companion Script**: [`scripts/convert_role_01_master.py`](../scripts/convert_role_01_master.py)  
> **Sample CSV**: [`excel-templates/converted/Template_Role_01_Master_converted.csv`](../excel-templates/converted/Template_Role_01_Master_converted.csv)

Automates the mass creation and updating of **Master Single Roles** directly from CSV, builds structured menu folder hierarchies, validates TCodes in `TSTC`, defaults Organizational Levels to `'-1'`, suppresses generic PFCG comments, and compiles runtime authorization profiles in dark mode.

---

## 📌 Workflow

```
[ Input CSV: Role Name, Role Desc, TCode ]
            │
            ▼  Upload via GUI_UPLOAD (UTF-8)
[ Group TCodes & Validate against TSTC ]
            │
    ┌───────┴────────────────────────┐
    ▼ (Valid TCodes Exist)           ▼ (No Valid TCodes / N/A)
[ PRGN_RFC_CREATE_ACTIVITY_GROUP ]   [ PRGN_RFC_CREATE_AGR_MULTIPLE ]
  - Create Role & Menu Folder          - Create Empty Role Shell
  - Nest Valid TCodes                  - Clean AGR_TEXTS
  - Default AGR_1252 to '-1'           - Default AGR_1252 to '-1'
  - Dark Profile Generation            - Status: @09@ [WARN]
  - Status: @08@ [OK] / @09@ [WARN]
            │
            ▼
[ Interactive ALV Cockpit with One-Click PFCG Hotspot ]
```

---

## ⚙️ Key Technical Features

1. **Exact Description Spacing**: Reads role descriptions without destructive `CONDENSE`, preserving whitespace in role titles and menu folder names.
2. **Comment Suppression**: Automatically removes the default SAP comment line (`"The role was created automatically..."`) from `AGR_TEXTS`.
3. **Template Org Level Architecture (`-1`) & Full Green Profile Generation**:
   - Defaults all Org Levels to `'-1'` to prevent dangerous wildcard (`*`) access leakage in template roles.
   - Org Levels are initialized in `AGR_1252` **prior** to runtime profile compilation via `SUPRN_DARK_MANIPULATE_PROFILE`, followed by role timestamp synchronization (`PRGN_SET_ACTGROUP_TIMESTAMP`). This ensures the Master Role always achieves a **100% GREEN status (Generated and Current)** in PFCG.
   - Post-compilation, all Org Level fields in `AGR_1251` are immediately restored and bound to their dynamic variable pointers (`$VARBL`) with Standard status (`MODIFIED = 'S'`, `NEU = 'O'`), ensuring the template definition is 100% clean and ready for derivation.
4. **Automatic Child Derived Role Synchronization (`p_adjder = 'X'`)**:
   - Automatically detects all inheriting Derived Single Roles linked in `AGR_DEFINE` (`parent_agr = master_role`).
   - Propagates updated authorization objects down to child roles using `PRGN_RFC_CREATE_DERIVATION`.
   - **Strictly preserves and restores** all existing child Organizational Levels (`AGR_1252`) and safeguards `AGR_1251` org variable bindings (`MODIFIED = 'S'`), preventing customized Company Codes, Plants, or Orgs from being overwritten.
   - Automatically regenerates child runtime authorization profiles in dark mode and reports child role names in dedicated ALV column `DERIVED_ROLES`.
5. **Non-Blocking TCode Validation**: If a TCode does not exist in `TSTC`, it is excluded from the menu and reported in a dedicated `Invalid TCodes` column with `@09@ [WARN]` instead of aborting role creation.
6. **Two-Way Menu Synchronization (`p_upd = 'X'`)**:
   - Compares existing role menu TCodes in `AGR_TCODES` against incoming CSV entries.
   - **Adds Missing TCodes** (`lt_tcodes_to_add`): appends new TCode nodes to the folder hierarchy.
   - **Removes Surplus TCodes** (`lt_tcodes_to_del`): prunes obsolete nodes from `AGR_SHIER` / `AGR_SHIERT`.
   - Rebuilds authorizations (`rebuild_auth_data = 'X'`) to strip orphaned auth objects from removed transactions.
   - Reports added and deleted transaction lists in dedicated ALV columns (`TCODES_ADD`, `TCODES_DEL`).

---

## 🎛️ Selection Screen

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `p_file` | `localfile` | Mandatory | Path to normalized CSV file |
| `p_test` | `checkbox` | `'X'` | Simulation mode (validates without writing to database) |
| `p_upd` | `checkbox` | `'X'` | Update existing roles (synchronize description & missing TCodes) |
| `p_sync` | `checkbox` | `'X'` | Two-Way Sync Menu: when checked (`'X'`), removes surplus TCodes not in CSV; when unchecked (`' '`), appends missing TCodes only |
| `p_genprf`| `checkbox` | `'X'` | Automatically generate authorization profiles in dark mode |
| `p_chktc` | `checkbox` | `'X'` | Verify transaction codes against table `TSTC` |
| `p_adjder`| `checkbox` | `'X'` | Automatically push updated auth objects to child derived roles (preserves Org Levels) |

---

## 📊 Status Codes in ALV & Excel

| Status Code | GUI Display | Meaning | Action Taken |
| :--- | :--- | :--- | :--- |
| **`@08@ [OK]`** | Green LED | Role created / updated successfully with valid TCodes | `CREATED` / `UPDATED` |
| **`@09@ [WARN]`** | Yellow LED | Role has no TCodes (`N/A`), invalid TCodes excluded, or role skipped | `SIMULATED` / `UP-TO-DATE` / `SKIPPED` |
| **`@0A@ [ERR]`** | Red LED | Role creation failed (BAPI exception or locking error) | `ERROR` |

---

## 🔧 SAP Function Modules Used

- `PRGN_RFC_CREATE_ACTIVITY_GROUP`: Creates role structure and menu folder with transactions.
- `PRGN_RFC_CREATE_AGR_MULTIPLE`: Creates empty role shell definition.
- `PRGN_RFC_CHANGE_TEXTS`: Standard FM to maintain role description and strip automatic comment lines.
- `PRGN_1252_READ_ORG_LEVELS` & `PRGN_1252_SAVE_ORG_LEVELS`: Maintains Org Levels with template default `'-1'`.
- `PRGN_UPDATE_DATABASE`: Commits PFCG authorization buffers with full change documents.
- `SUPRN_DARK_MANIPULATE_PROFILE`: Compiles authorization profile in dark mode.

---

## 🚀 Deployment

```bash
npm run deploy:role:01
```
