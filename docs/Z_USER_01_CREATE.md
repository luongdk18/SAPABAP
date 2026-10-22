# 👤 Z_USER_01_CREATE: Batch SAP User Creation & Update Cockpit

> **Source Code**: [`src/z_user_01_create.prog.abap`](../src/z_user_01_create.prog.abap)  
> **Companion Script**: [`scripts/convert_user_01_create.py`](../scripts/convert_user_01_create.py)  
> **Sample CSV**: [`excel-templates/converted/Template_User_01_Create_converted.csv`](../excel-templates/converted/Template_User_01_Create_converted.csv)

Automates mass SAP user onboarding and master data updates directly from normalized CSV files, supporting UTF-8 character preservation (Vietnamese diacritics), password compliance auditing, and interactive navigation to transaction `SU01`.

---

## 📌 Workflow

```
[ Input CSV: Username, Password, Full Name, Email, Phone, Dept, Func ]
            │
            ▼  Upload via GUI_UPLOAD (filetype = 'BIN' / UTF-8)
[ Strip BOM (U+FEFF) & Validate Records ]
  - Username <= 12 characters
  - Full Name is mandatory (mapped entirely to BAPIADDR3-LASTNAME)
  - Verify email syntax (SX_INTERNET_ADDRESS_TO_NORMAL)
            │
    ┌───────┴────────────────────────┐
    ▼ (Validation Failed)            ▼ (Validation Passed)
[ Report Error: @0A@ [ERR] ]         [ Check Existence in USR02 ]
                                       │
                ┌──────────────────────┴──────────────────────┐
                ▼ (New User)                                  ▼ (Existing User)
        [ BAPI_USER_CREATE1 ]                         [ BAPI_USER_CHANGE ]
          - Initial Password & Defaults                 - Update Name, Email, Phone
          - Status: @08@ [OK]                           - Optional Password Reset
                                                        - Status: @08@ [OK] / @09@ [WARN]
            │
            ▼
[ Interactive ALV Cockpit with One-Click SU01 Hotspot Jump ]
```

---

## ⚙️ Key Technical Features

1. **Full Name Mapping to `LASTNAME`**: Maps the complete full name directly into `BAPIADDR3-LASTNAME` (max 40 chars) without arbitrary splitting, satisfying SAP mandatory constraints while preserving full names intact.
2. **Vietnamese Diacritics Preservation**: Uploads via binary mode (`BIN`) and decodes via UTF-8 code page `4110` with BOM removal to prevent accent corruption (`Đào`, `Lê`, `Phạm`).
3. **Password Compliance & Auditing**: Displays initial generated passwords directly on the ALV grid for audit trails and secure distribution.
4. **Phone Formatting**: Standardized format `(<CountryCode>)<Number>` **without `+` sign** for native SAP BAPI compatibility.
5. **Safe In-Place Updates (`p_upd = 'X'`)**: Updates address, department, and function for existing users; optional password reset flag (`p_pwd`).

---

## 🎛️ Selection Screen

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `p_file` | `localfile` | Mandatory | Path to normalized CSV file |
| `p_test` | `checkbox` | `'X'` | Simulation mode (test run without writing to DB) |
| `p_upd` | `checkbox` | `' '` | Update existing user master records |
| `p_pwd` | `checkbox` | `' '` | Reset initial password when updating existing users |
| `p_ustyp`| `char1` | `'A'` | User Type (`A` = Dialog, `B` = System, `C` = Communication) |
| `p_gltgv`| `date` | `sy-datum`| Valid-from date |
| `p_gltgb`| `date` | `'99991231'`| Valid-to date |
| `p_langu`| `lang` | `sy-langu`| Default logon language |
| `p_spld` | `char4` | `'LP01'` | Default spool output device |

---

## 📊 Status Codes in ALV & Excel

| Status Code | GUI Display | Meaning | Action Taken |
| :--- | :--- | :--- | :--- |
| **`@08@ [OK]`** | Green LED | User created or updated successfully | `CREATED` / `UPDATED` / `SIM_NEW` / `SIM_UPD` |
| **`@09@ [WARN]`** | Yellow LED | User already exists and `p_upd` is unchecked | `SKIPPED` |
| **`@0A@ [ERR]`** | Red LED | Username empty/>12 chars, full name missing, or BAPI error | `ERROR` |

---

## 🔧 SAP Function Modules Used

- `BAPI_USER_CREATE1`: Creates new user with logon data, password, defaults, and address.
- `BAPI_USER_CHANGE`: Updates master data of existing users.
- `BAPI_TRANSACTION_COMMIT`: Commits database transactions.
- `SX_INTERNET_ADDRESS_TO_NORMAL`: Validates email syntax.

---

## 🚀 Deployment

```bash
npm run deploy:user:01
```
