# New Project Wizard

New Project Wizard is a local developer tool for bootstrapping new software projects through a polished PowerShell command-line workflow.

## Language

**Wizard**:
A guided command-line workflow that collects project choices, validates them, and applies setup steps in a predictable order.
_Avoid_: Generator, scaffolder

**Project Type**:
A named project category with its own initialization behavior, generated files, and optional toolchain commands.
_Avoid_: Template, preset

**Launcher**:
A thin script or profile entry that starts the wizard without containing the wizard's core implementation.
_Avoid_: Main script, wrapper
