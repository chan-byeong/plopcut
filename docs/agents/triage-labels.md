# Triage labels

Map canonical triage roles to these Linear labels.

| Role              | Linear label      | Meaning                            |
| ----------------- | ----------------- | ---------------------------------- |
| `needs-triage`    | `needs-triage`    | Needs maintainer evaluation        |
| `needs-info`      | `needs-info`      | Needs more information             |
| `ready-for-agent` | `ready-for-agent` | Specified for agent implementation |
| `ready-for-human` | `ready-for-human` | Requires human implementation      |
| `wontfix`         | `wontfix`         | Will not be implemented            |

Use these labels when a skill refers to a canonical triage role. Inspect
the destination team's available labels before applying them. Preserve
unrelated labels when updating triage readiness.

These mappings configure the skills; setup does not create labels in
Linear. Workflow state changes follow the issue tracker rules.
