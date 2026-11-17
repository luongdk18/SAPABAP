# 📊 Z_EXPORT_OBJ_LEVELS: Export Authorization Objects & Fields Reference Catalog

> **Source Code**: [`src/z_export_obj_levels.prog.abap`](../src/z_export_obj_levels.prog.abap)  
> **Output Artifact**: [`excel-templates/Object_Levels.csv`](../excel-templates/Object_Levels.csv)  
> **Deployment Command**: `npm run deploy:export:obj`

Utility report to extract the complete catalog of SAP Standard Authorization Objects and their corresponding authorization fields directly from SAP DDIC tables (`TOBJ`, `TOBJT`, `TOBCT`).

---

## 📌 Purpose & Architecture

In SAP authorization management, distinguishing between Organizational Levels (stored in `AGR_1252` / `USORG`) and Authorization Objects & Fields (stored in `AGR_1251`) is critical for batch preprocessing.

This utility scans:
1. **`TOBJ`**: Authorization Objects and their assigned fields (`FIEL1` .. `FIEL0`) and Object Class (`OCLSS`).
2. **`TOBJT`**: Authorization Object texts in English (`LANGU = 'E'`).
3. **`TOBCT`**: Authorization Class texts in English (`LANGU = 'E'`).

The resulting data stream is formatted with `###` delimiters, enabling the generation and periodic refresh of the reference catalog [`excel-templates/Object_Levels.csv`](../excel-templates/Object_Levels.csv) (13,400+ standard SAP object-field definitions).

---

## 🚀 Execution & Usage

1. Run report `Z_EXPORT_OBJ_LEVELS` via transaction `SE38` or `SA38`.
2. Output is displayed as a wide text list (`LINE-SIZE 1023`).
3. Export the list to a text or CSV file using standard SAP GUI list export (`System` $\longrightarrow$ `List` $\longrightarrow$ `Save` $\longrightarrow$ `Local File`).
4. Used by Python preprocessing scripts ([`scripts/convert_role_03_org_obj.py`](../scripts/convert_role_03_org_obj.py)) to automatically classify columns in Excel business matrices.
