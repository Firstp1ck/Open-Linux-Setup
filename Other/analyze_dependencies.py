#!/usr/bin/env python3
"""
Script to find explicitly installed packages that are also dependencies.
Groups packages by category and shows which packages depend on them.

WHAT THIS SCRIPT DOES:
=====================
This script identifies packages that you explicitly installed (using pacman -S or similar)
but are also required as dependencies by other explicitly installed packages.

For example:
- You explicitly installed 'python'
- You also explicitly installed 'inkscape' and 'libreoffice-fresh'
- Both 'inkscape' and 'libreoffice-fresh' depend on 'python'
- Therefore, 'python' appears in the output because it's both explicitly installed
  AND a dependency of other explicitly installed packages

OUTPUT FORMAT:
=============
The script generates a categorized list showing:
- Each explicitly installed package that is also a dependency
- Which other explicitly installed packages depend on it
- Packages are grouped by category (PYTHON, PERL, DEVELOPMENT_TOOLS, etc.)

Example output:
  python                    # Required by 32 package(s) (explicitly installed)
    → inkscape (explicit)
    → libreoffice-fresh (explicit)
    → lutris (explicit)

WHY THIS IS USEFUL:
==================
1. System setup: If you only install "leaf" packages (packages nothing depends on),
   this script will output nothing, as there are no explicitly installed packages
   that are also dependencies.

2. Package management: These packages can be safely removed if you remove the
   packages that depend on them, but they will be reinstalled as dependencies.

3. Understanding dependencies: Helps you understand which explicitly installed
   packages are shared dependencies across multiple applications.

HOW IT WORKS:
============
1. Gets all explicitly installed packages using 'pacman -Qeq'
2. For each explicitly installed package, uses 'pactree -r' to find reverse
   dependencies (what depends on it)
3. Filters to only show dependencies where the dependers are also explicitly
   installed (not just implicit dependencies)
4. Categorizes packages by type (Python, Perl, development tools, etc.)
5. Outputs a formatted, categorized list

OUTPUT FILE:
===========
The script writes to: ~/.dotfiles/.config/explicit_dependencies.txt

You can modify the OUTPUT_FILE variable to change the output location.
"""

import subprocess
import re
import os
from collections import defaultdict

OUTPUT_FILE = os.path.expanduser("~/.dotfiles/.config/explicit_dependencies.txt")

# Get all explicitly installed packages
print("Getting explicitly installed packages...")
explicit_packages = set(subprocess.check_output(['pacman', '-Qeq']).decode().strip().split('\n'))

# Build reverse dependency map: dependency -> list of packages that depend on it
dependency_map = defaultdict(list)

print("Analyzing dependencies...")
count = 0
for pkg in explicit_packages:
    if not pkg:
        continue
    count += 1
    if count % 50 == 0:
        print(f"  Processed {count} packages...")
    
    try:
        # Get reverse dependencies using pactree
        result = subprocess.run(['pactree', '-r', '-u', '-d', '1', pkg], 
                              capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            reverse_deps = result.stdout.strip().split('\n')[1:]  # Skip first line
            for depender in reverse_deps:
                depender = depender.strip()
                if depender and depender != pkg:
                    dependency_map[pkg].append(depender)
    except:
        pass

print(f"\nFound {len(dependency_map)} explicitly installed packages that are also dependencies")

# Categorize packages
def categorize(pkg):
    if 'python' in pkg.lower() or pkg.startswith('python-'):
        return 'PYTHON'
    elif 'perl' in pkg.lower():
        return 'PERL'
    elif pkg in ['git', 'openssh', 'rsync', 'sudo', 'which', 'diffutils']:
        return 'DEVELOPMENT_TOOLS'
    elif 'bluez' in pkg.lower():
        return 'BLUETOOTH'
    elif 'pipewire' in pkg.lower() or 'alsa' in pkg.lower():
        return 'AUDIO'
    elif 'device-mapper' in pkg.lower() or 'cryptsetup' in pkg.lower():
        return 'STORAGE'
    elif 'xdg' in pkg.lower() or 'desktop' in pkg.lower():
        return 'DESKTOP'
    elif 'kde' in pkg.lower() or 'kio' in pkg.lower() or 'plasma' in pkg.lower():
        return 'KDE'
    elif 'gtk' in pkg.lower() or 'qt' in pkg.lower():
        return 'GUI_LIBS'
    elif 'gnome-keyring' in pkg.lower():
        return 'SECURITY'
    elif 'jdk' in pkg.lower() or 'java' in pkg.lower():
        return 'JAVA'
    elif 'openxr' in pkg.lower():
        return 'VR'
    elif 'e2fsprogs' in pkg.lower() or 'dosfstools' in pkg.lower() or 'mtools' in pkg.lower():
        return 'FILESYSTEM'
    elif 'systemd' in pkg.lower():
        return 'SYSTEM'
    elif 'texinfo' in pkg.lower() or 'hwinfo' in pkg.lower():
        return 'SYSTEM_INFO'
    elif 'unzip' in pkg.lower():
        return 'ARCHIVE'
    else:
        return 'OTHER'

# Group by category, filtering to only explicitly installed dependers
categories = defaultdict(lambda: defaultdict(list))
for dep, dependers in dependency_map.items():
    # Filter to only explicitly installed packages
    explicit_dependers = [d for d in dependers if d in explicit_packages]
    if explicit_dependers:  # Only include if there are explicitly installed dependers
        cat = categorize(dep)
        categories[cat][dep] = explicit_dependers

# Write output
with open(OUTPUT_FILE, 'w') as f:
    f.write("# Explicitly Installed Packages That Are Also Dependencies\n")
    f.write("# =========================================================\n")
    f.write("# This file lists packages that you explicitly installed but are also\n")
    f.write("# required as dependencies by other installed packages.\n")
    f.write("# Packages are grouped by category, then by the dependency package.\n")
    f.write("# Under each dependency, all packages that require it are listed.\n")
    f.write("#\n")
    f.write("# Note: These packages can be safely removed if you remove the packages\n")
    f.write("# that depend on them, but they will be reinstalled as dependencies.\n")
    f.write("\n")
    
    # Category order
    cat_order = ['PYTHON', 'PERL', 'DEVELOPMENT_TOOLS', 'BLUETOOTH', 'AUDIO', 
                 'STORAGE', 'DESKTOP', 'KDE', 'GUI_LIBS', 'SECURITY', 'JAVA',
                 'VR', 'FILESYSTEM', 'SYSTEM', 'SYSTEM_INFO', 'ARCHIVE', 'OTHER']
    
    for cat in cat_order:
        if cat not in categories or not categories[cat]:
            continue
        
        f.write(f"\n# ============================================================================\n")
        f.write(f"# {cat.replace('_', ' ')} ({len(categories[cat])} packages)\n")
        f.write(f"# ============================================================================\n")
        
        # Sort dependencies in this category
        for dep in sorted(categories[cat].keys()):
            all_dependers = sorted(set(categories[cat][dep]))
            # Filter to only explicitly installed packages
            dependers = [d for d in all_dependers if d in explicit_packages]
            
            # Skip if no explicitly installed packages depend on this
            if not dependers:
                continue
            
            f.write(f"\n{dep}                    # Required by {len(dependers)} package(s) (explicitly installed)\n")
            
            for depender in dependers:
                f.write(f"  → {depender} (explicit)\n")

print(f"\nAnalysis complete. Results written to: {OUTPUT_FILE}")

