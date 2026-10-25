# Logger (Nebula Logger)

Nexus Core uses the **unlocked** (no-namespace) edition of [Nebula Logger](https://github.com/jongpie/NebulaLogger),
so Apex calls `Logger.error(...)` / `Logger.saveLog()` directly.

- Package: `Nebula Logger - Core@4.19.5` (`04tg7000000IzRdAAK`), declared in `sfdx-project.json` `packageAliases`.
- Installed by `scripts/org-init/setup-scratch-headless.sh` before source deploy.
- Admins get `LoggerAdmin`; the Admin Cockpit error feed needs at least `LoggerLogViewer`.

This folder intentionally holds no metadata: the logger ships as a package dependency of `00-foundation`.
