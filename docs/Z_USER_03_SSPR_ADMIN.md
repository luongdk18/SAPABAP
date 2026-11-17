# 🛡️ Z_USER_03_SSPR_ADMIN: Self-Service Password Reset (SSPR) Admin Cockpit

> **Source Code**: [`src/z_user_03_sspr_admin.prog.abap`](../src/z_user_03_sspr_admin.prog.abap)  
> **Related Class**: [`src/zcl_sspr_http_handler.clas.abap`](../src/zcl_sspr_http_handler.clas.abap)  
> **Comprehensive Guide**: [**SAP SSPR & Account Unlock Guide**](SSPR_USER_GUIDE.md)  
> **Deployment Command**: `npm run deploy:user:03`

Centralized monitoring, audit, and maintenance console for the **SAP Self-Service Password Reset (SSPR) & Account Unlock** portal (`/reset`).

---

## 📌 Features & Capabilities

1. **Token Lifecycle Monitoring**:
   - Real-time visibility into all password reset and account unlock requests recorded in transparent table `ZSSPR_TOKENS`.
   - Clear visual status indicators:
     - `@08@ [USED]` : Token successfully consumed and action executed.
     - `@09@ [PENDING]` : Active valid token awaiting user action.
     - `@0A@ [EXPIRED]` : Token expired without being used.
2. **Security & Audit Tracking**:
   - Captures request timestamps (`CREATED_DATE`, `CREATED_TIME`), expiration timestamps, and usage timestamps.
   - Records client IP addresses for Basis and security auditing behind enterprise reverse proxies.
3. **Interactive Navigation**:
   - Single-click hotspot jump on SAP Username directly into transaction **`SU01`** (User Maintenance).
4. **Automated Token Cleanup**:
   - Built-in maintenance routine to purge expired or legacy tokens based on a configurable retention period (default: 7 days).
5. **SICF Endpoint Status**:
   - Header comments display active SICF service node (`/sap/bc/z_sspr`) and handler class status (`ZCL_SSPR_HTTP_HANDLER`).

---

## 🎛️ Selection Screen

| Parameter | Type | Default | Description |
| :--- | :---: | :---: | :--- |
| `s_date` | Select-Option | `sy-datum` | Filter by token creation date |
| `s_user` | Select-Option | - | Filter by SAP username |
| `p_act` | Dropdown | `'ALL'` | Filter by Action Type (`ALL`, `RESET`, `UNLOCK`) |
| `p_stat` | Dropdown | `'ALL'` | Filter by Status (`ALL`, `PENDING`, `USED`, `EXPIRED`) |
| `p_clean` | Checkbox | `' '` | Execute token cleanup routine |
| `p_days` | Integer | `7` | Retention threshold in days for token purging |

---

## 🔗 Related Components

- **HTTP Handler Class**: [`ZCL_SSPR_HTTP_HANDLER`](../src/zcl_sspr_http_handler.clas.abap) - Serves the web interface and executes reset/unlock BAPIs.
- **Database Table**: `ZSSPR_TOKENS` - Transparent table storing tokens, timestamps, and IP addresses.
- **Detailed Setup & Configuration**: Refer to the complete [**SSPR User Guide**](SSPR_USER_GUIDE.md) for full SICF, external alias, and mail server instructions.
