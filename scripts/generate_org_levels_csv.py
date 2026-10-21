#!/usr/bin/env python3
"""
Generate standardized SAP Organizational Levels reference (Org_Levels.csv).
Extracted from SAP S/4HANA table USVART (Language: 'E').
Sorted strictly by standard SAP primary key order: VARBL ascending (matching SORT T_STORG BY VARBL and table USVAR).

Output:
- excel-templates/Org_Levels.csv (UTF-8 with BOM for SAP GUI and script consumption)

Usage:
    python scripts/generate_org_levels_csv.py
"""

import os
import sys
import csv

# --- Safe Console Output on Windows ---
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

# --- Standard SAP S/4HANA Organizational Levels Reference Data (71 levels) ---
SAP_ORG_LEVELS = [
    ("Business Partner for Provider of Information", "$/ECRS/POIB"),
    ("Activity Area", "$/SCWM/AREA"),
    ("Authorized Drawer", "$/SCWM/ENTL"),
    ("Warehouse number / warehouse complex", "$/SCWM/LGNU"),
    ("Storage type", "$/SCWM/LGTY"),
    ("Chart of Depreciation", "$AFAPL"),
    ("Asset Class", "$ANLKL"),
    ("Applicant Group", "$APGRP"),
    ("Applicant Range", "$APTYP"),
    ("Work Center", "$ARBPL"),
    ("Aspect (application area)", "$ASPET"),
    ("Order Type", "$AUFART"),
    ("Bank Area", "$BKKRS"),
    ("Company Code", "$BUKRS"),
    ("Consolidation Unit", "$BUNIT"),
    ("Valuation area", "$BWKEY"),
    ("Aspect", "$CFASPET"),
    ("User Group", "$CLASS"),
    ("Condition Area", "$CONDAREA"),
    ("Consolidation Group", "$CONGR"),
    ("View", "$DIMEN"),
    ("MRP Controller", "$DISPO"),
    ("Purchasing Group", "$EKGRP"),
    ("Purchasing Organization", "$EKORG"),
    ("Operating Concern", "$ERKRS"),
    ("FM area", "$FIKRS"),
    ("Functional Area", "$FKBER"),
    ("Business Area", "$GSBER"),
    ("User Group", "$HIEID"),
    ("Maintenance planning plant", "$IWERK"),
    ("Credit Control Area", "$KKBER"),
    ("Costing Variant", "$KLVAR"),
    ("Account Type", "$KOART"),
    ("Controlling Area", "$KOKRS"),
    ("Cost Element", "$KSTAR"),
    ("Contact Type", "$KTAAR"),
    ("Chart of Accounts", "$KTOPL"),
    ("Cost Object Category", "$KTRAT"),
    ("Warehouse Number / Warehouse Complex", "$LGNUM"),
    ("Storage type", "$LGTYP"),
    ("Location", "$LTRM_LOCAT"),
    ("Personnel Area", "$PERSA"),
    ("Employee Group", "$PERSG"),
    ("Employee Subgroup", "$PERSK"),
    ("Plan Version", "$PLVAR"),
    ("Profit Centers", "$PRCTR"),
    ("Company", "$RCOMP"),
    ("Personnel officer for the job application", "$RESRF"),
    ("Ledger", "$RLDNR"),
    ("Payroll Administrator", "$SACHA"),
    ("Administrator for HR Master Data", "$SACHP"),
    ("Administrator for Time Recording", "$SACHZ"),
    ("Administrator Group", "$SBMOD"),
    ("Division", "$SPART"),
    ("Maintenance plant", "$SWERK"),
    ("Transportation Planning Point", "$TPLST"),
    ("Organizational Key", "$VDSK1"),
    ("Sales Office", "$VKBUR"),
    ("Sales Group", "$VKGRP"),
    ("Sales Organization", "$VKORG"),
    ("Shipping Point", "$VSTEL"),
    ("Distribution Channel", "$VTWEG"),
    ("Plant", "$WERKS"),
    ("Enterprise Organization", "$XCORG"),
    ("Planning and Execution Group", "$XEGRP"),
    ("Planning and Execution Organization", "$XEORG"),
    ("Purchasing Group", "$XPGRP"),
    ("Purchasing Organization", "$XPORG"),
    ("Sales Group", "$XSGRP"),
    ("Sales Office", "$XSOFF"),
    ("Sales Organization", "$XSORG"),
]


def generate_org_levels_csv():
    output_csv = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'excel-templates', 'Org_Levels.csv')
    os.makedirs(os.path.dirname(output_csv), exist_ok=True)

    with open(output_csv, 'w', newline='', encoding='utf-8-sig') as f:
        writer = csv.writer(f)
        writer.writerow(['Org Level Description', 'Org Level Variable'])
        for desc, var in SAP_ORG_LEVELS:
            writer.writerow([desc, var])

    print(f"\n--- Execution Summary ---")
    print(f"[OK] Reference File   : {output_csv}")
    print(f"[OK] Total Levels     : {len(SAP_ORG_LEVELS)} SAP Org Levels (sorted by VARBL ascending)")


# --- CLI Entrypoint ---
if __name__ == "__main__":
    generate_org_levels_csv()
