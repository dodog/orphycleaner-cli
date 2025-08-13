# Clean Config Orphans
A simple script to remove configuration files from uninstalled applications in the user's home folder.

**What it does:**

* Prints each folder path with one of these labels:

* Installed (package match) — folder name matches an installed package exactly

*  Installed (executable found) — executable with the same name is in your PATH.

* Maybe Installed (partial package name match) — folder name partially found inside package names.

*  Orphaned — likely no installed package or executable linked to this folder.
