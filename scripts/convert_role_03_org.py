#!/usr/bin/env python3
"""
Compatibility wrapper for convert_role_03_org.py.
Forwards execution to unified convert_role_03_org_obj.py.
"""
import sys
import subprocess
import os

if __name__ == "__main__":
    script_dir = os.path.dirname(__file__)
    target_script = os.path.join(script_dir, "convert_role_03_org_obj.py")
    cmd = [sys.executable, target_script] + sys.argv[1:]
    sys.exit(subprocess.call(cmd))
