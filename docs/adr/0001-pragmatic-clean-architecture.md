# ADR 0001: Pragmatic Clean Architecture over fflib Enterprise Patterns

* **Status:** Accepted (Supersedes previous fflib proposal)
* **Deciders:** Enterprise Architecture Lead & Platform Engineers
* **Date:** 2026-10-22

## Context and Problem Statement
Enterprise Salesforce codebases require clear separation of concerns (SoC), testability, and bulkification. For many years, the `fflib-apex-common` library was considered the standard enterprise pattern. However, real-world experience and modern ecosystem analysis highlight significant drawbacks:
1. **Excessive Boilerplate & Cognitive Tax:** A single entity often demands 5 to 7 separate classes and interfaces (`IOpportunities`, `Opportunities`, `IOpportunitiesSelector`, `OpportunitiesSelector`, `IOpportunitiesService`, `OpportunitiesServiceImpl`, and registration in `Application.cls`).
2. **Pre-Modern Apex Anachronism:** `fflib` was modeled after early Java Spring/Hibernate paradigms. Dynamic reflection (`Type.forName()`), instantiate-heavy reflection factories, and multi-layered wrapper objects add CPU overhead during high-volume bulk transactions ($200\text{--}2000$ records).
3. **Outdated SOQL Mechanics:** `fflib_QueryFactory` was created before native `WITH USER_MODE`, `Database.queryWithBinds()`, and cursor-based SOQL existed. Modern native SOQL is faster, safer, and cleaner.
4. **All-or-Nothing Interdependence:** Tight coupling between Domain, Selector, and Unit of Work makes partial adoption difficult.

## Decision Drivers
* Retain strict Separation of Concerns: Service Layer $\rightarrow$ Selector Layer $\rightarrow$ Lightweight Trigger Handler.
* Eliminate 60%+ of redundant interface/factory boilerplate to maximize developer velocity and AI coding assistant accuracy.
* Rely on native platform capabilities (`WITH USER_MODE`, `Database.SaveResult`, built-in transactional boundaries).

## Considered Options
1. **fflib Enterprise Patterns:** Full fflib suite (`Application`, `Domain`, `Selector`, `Service`, `UnitOfWork`).
2. **Modern Fluent Libraries (e.g. Apex Fluently / SOQL Lib):** Fluent query syntax.
3. **Pragmatic Clean Architecture:** A lightweight, dependency-free pattern using:
   - Base `TriggerHandler.cls` (virtual context methods, recursion guard, bypass integration).
   - Dedicated `*Selector.cls` (encapsulating SOQL with native `WITH USER_MODE`).
   - Domain `*Service.cls` (orchestrating business logic, cross-object transactions, and validations).

## Decision Outcome
Chosen Option: **Option 3 (Pragmatic Clean Architecture)**.
- Drop `fflib-apex-common` dependencies and the monolithic `Application.cls` factory.
- Adopt a simple, robust `TriggerHandler` base class in `00-foundation`.
- Encapsulate all database queries inside `*Selector.cls` using native SOQL and `WITH USER_MODE`.
- Centralize transactional logic in static/instance Domain Services (`OpportunityService.cls`, `CaseEscalationService.cls`).

### Positive Consequences
* **Massive Boilerplate Reduction:** Eliminates dozens of wrapper interfaces and factory binding registrations.
* **Peak Governor Limit Efficiency:** Zero CPU wasted on reflection or factory lookups during bulk triggers.
* **AI-Agent Friendly:** Highly predictable, clean class structures that prevent token saturation and hallucinated factory bindings in LLM workflows.
* **Preserved Testability:** Selectors and Services remain easily mockable via dependency injection or StubProvider where needed.