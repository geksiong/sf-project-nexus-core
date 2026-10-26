# ADR 0004: Dual Experience Cloud Runtimes

* **Status:** Accepted
* **Deciders:** Enterprise Architecture Lead & Platform Engineers
* **Date:** 2026-10-22 (implemented in Phase 6, 2026-10-26)

## Context and Problem Statement
Nexus Core needs two very different external audiences: anonymous visitors reading hospitality content
(Demo App 5) and authenticated B2B partners registering deals (Demo App 6). Salesforce offers two site runtimes,
LWR (Lightning Web Runtime) and Aura, with different metadata formats, component models and strengths.

## Decision Drivers
* Public pages must be fast, cacheable and secure by default for guest users.
* Partner pages need standard record layouts, flows, list views and partner-relationship features out of the box.
* Both must deploy from source (no manual Experience Builder steps) and be reviewable in git.

## Considered Options
1. **One Aura site** for both audiences.
2. **One LWR site** for both audiences, rebuilding partner features as custom LWCs.
3. **LWR for the public portal, Aura (Partner Central template) for partners.**

## Decision
Option 3.

* **Nexus Hospitality (LWR, `DigitalExperienceBundle`)**: Build Your Own (LWR) template, public access enabled
  (`authenticationType = AUTHENTICATED_WITH_PUBLIC_ACCESS_ENABLED`). Custom components use **Light DOM**
  (`hospitalityArticles`) and Lightning Web Security. Data reaches guests only through `with sharing` Apex and a
  `WITH USER_MODE` selector, so the **guest sharing rule** (Published articles only) and the guest profile's
  object/field access are the security boundary: no `without sharing` shortcut for guests.
* **Nexus Partner Central (Aura, `ExperienceBundle`)**: Partner Central template with PRM enabled. Partners register
  deals through a screen flow (`Partner_Deal_Registration`) calling `SubmitDealRegistrationAction` (result envelope).
  `Deal_Registration__c` is Private: partners see their own records and their team's through the **partner role
  hierarchy** (portal roles sit under the partner account owner, the channel manager, who therefore sees them too).
  Partner users have a custom profile (`Nexus Partner User`); feature access is in permission sets.

## Consequences
* **Positive:** each audience gets the runtime it suits; guest access is enforced by sharing, not code; partner
  features come from the platform (layouts, approvals, list views, role hierarchy).
* **Negative:** two metadata formats to maintain; site bundles contain org-specific values (handled with
  `sfdx-project.json` replacements) and platform-regenerated content Ids (drift is advisory for them); guest and
  criteria sharing rules are written at commit, so their positive cases are verified in an org, not in Apex tests.
* **Operational:** sites are published by the setup script (`sf community publish`); re-retrieving a site after
  Experience Builder edits needs the cleanup described in `docs/known-issues.md` (KI-032).
