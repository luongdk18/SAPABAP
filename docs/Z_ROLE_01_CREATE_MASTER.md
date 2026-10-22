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
3. **Template Org Level Architecture (`-1`)**: Defaults all Org Levels to `'-1'` to prevent dangerous wildcard (`*`) access leakage in template roles.
4. **Non-Blocking TCode Validation**: If a TCode does not exist in `TSTC`, it is excluded from the menu and reported in a dedicated `Invalid TCodes` column with `@09@ [WARN]` instead of aborting role creation.
5. **Idempotent Updates (`p_upd = 'X'`)**: Updates existing roles, synchronizes titles, and appends only missing valid TCodes without creating duplicates.

---

## 🎛️ Selection Screen

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `p_file` | `localfile` | Mandatory | Path to normalized CSV file |
| `p_test` | `checkbox` | `'X'` | Simulation mode (validates without writing to database) |
| `p_upd` | `checkbox` | `'X'` | Update existing roles (synchronize description & missing TCodes) |
| `p_genprf`| `checkbox` | `'X'` | Automatically generate authorization profiles in dark mode |
| `p_chktc` | `checkbox` | `'X'` | Verify transaction codes against table `TSTC` |

---

## 📊 Status Codes in ALV & Excel

| Status Code | GUI Display | Meaning | Action Taken |
| :--- | :--- | :--- | :--- |
| **`@08@ [OK]`** | Green LED | Role created / updated successfully with valid TCodes | `CREATED` / `UPDATED` |
| **`@09@ [WARN]`** | Yellow LED | Role has no TCodes (`N/A`), invalid TCodes excluded, or role skipped | `SIMULATED` / `UP-TO-DATE` / `SKIPPED` |
| **`@0A@ [ERR]`** | Red LED | Role creation failed (BAPI exception or locking error) | `ERROR` |

---

## 🔧 SAP Function Modules Used

- `PRGN_RFC_CREATE_ACTIVITY_GROUP`: Creates role with menu nodes.
- `PRGN_RFC_CREATE_AGR_MULTIPLE`: Creates empty role definition.
- `SUPRN_DARK_MANIPULATE_PROFILE`: Compiles authorization profile in background.

---

## 🚀 Deployment

```bash
npm run deploy:role:01
```
