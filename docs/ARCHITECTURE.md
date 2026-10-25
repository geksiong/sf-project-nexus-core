# Nexus Core: System Architecture & Layer Boundaries

Nexus Core uses a Pragmatic Clean Architecture:
- `TriggerHandler.cls`: Context-based dispatching.
- `*Service.cls`: Business logic, validations, orchestration.
- `*Selector.cls`: SOQL queries with `WITH USER_MODE`.