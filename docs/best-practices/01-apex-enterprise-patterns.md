# Nexus Core Engineering Standard: Apex Clean Architecture & Separation of Concerns

- **Standard Code:** `BP-APEX-001`
- **Module Target:** `modules/10-core-domain/`
- **Related ADR:** `docs/adr/0001-pragmatic-clean-architecture.md`

---

## 1. Core Architectural Standard
To ensure maximum maintainability, performance, and AI-agent compatibility, Nexus Core enforces **Pragmatic Clean Architecture** instead of heavyweight Java-style reflection frameworks (`fflib`).

Business logic is strictly decoupled across three explicit tiers:
1. **Lightweight Trigger Handlers:** Extend `TriggerHandler.cls`. Responsible only for routing execution contexts (`beforeInsert`, `beforeUpdate`, etc.) and delegating to Services. No business calculations or inline SOQL in handlers.
2. **Selector Tier (`*Selector.cls`):** Sole authority for SOQL queries. Enforces field selection, user mode (`WITH USER_MODE`), and subqueries. Rule facts read by triggers use a `*FactsSelector` in system mode (2.3).
3. **Domain Service Tier (`*Service.cls`):** Encapsulates multi-object business logic, validation rules, state machines, and transactional boundaries.

```text
[ Trigger ] ──► [ TriggerHandler ] ──► [ Domain Service ] ──► [ Database (DML) ]
                                             │
                                             ▼
                                     [ Selector Layer ] ──► [ SOQL WITH USER_MODE ]
```

---

## 2. Concrete Reference Implementations

### 2.1 Selector Implementation (`OpportunitiesSelector.cls`)
Selectors provide clean, reusable SOQL queries with user mode:

```apex
public virtual with sharing class OpportunitiesSelector {
    @TestVisible
    private static OpportunitiesSelector instance;

    // Unit tests replace `instance` with a TestStub mock (see 04-testing-and-mocking.md)
    public static OpportunitiesSelector newInstance() {
        if (instance == null) {
            instance = new OpportunitiesSelector();
        }
        return instance;
    }

    public virtual List<Opportunity> selectByIdWithDetails(Set<Id> oppIds) {
        if (oppIds == null || oppIds.isEmpty()) return new List<Opportunity>();
        return [
            SELECT Id, Name, AccountId, StageName, Amount, CloseDate, Discount_Percentage__c,
                   Account.Credit_Hold__c,
                   (SELECT Id, ContactId, Role, IsPrimary FROM OpportunityContactRoles),
                   (SELECT Id, Quantity, UnitPrice, TotalPrice, PricebookEntry.Product2.Name FROM OpportunityLineItems)
            FROM Opportunity
            WHERE Id IN :oppIds
            WITH USER_MODE
        ];
    }
}
```

### 2.2 Trigger Handler Implementation (`OpportunityTriggerHandler.cls`)
Extends `TriggerHandler` and delegates immediately:

```apex
public with sharing class OpportunityTriggerHandler extends TriggerHandler {
    protected override void beforeUpdate(List<SObject> updatedRecords, Map<Id, SObject> oldRecordMap) {
        OpportunityService.validateStageProgression(
            (List<Opportunity>) updatedRecords, 
            (Map<Id, Opportunity>) oldRecordMap
        );
    }
}
```

### 2.3 Facts Selector for Rule Enforcement (`SalesEngineFactsSelector.cls`)
Access mode follows purpose. A data-access selector (2.1) runs `WITH USER_MODE` because its records go back to a
user. A business rule evaluated in a trigger must give the same answer whoever saves the record (sales rep,
integration user, partner, agent), so the facts it needs come from a `*FactsSelector`:

```apex
public virtual without sharing class SalesEngineFactsSelector {   // SYSTEM_MODE still applies class sharing
    @TestVisible
    private static SalesEngineFactsSelector instance;

    public static SalesEngineFactsSelector newInstance() {
        if (instance == null) {
            instance = new SalesEngineFactsSelector();
        }
        return instance;
    }

    /** Narrow question, minimal answer: Ids only, never records that could reach a caller. */
    public virtual Set<Id> selectAccountIdsOnCreditHold(Set<Id> accountIds) {
        Set<Id> onHold = new Set<Id>();
        for (Account acc : [
            SELECT Id FROM Account WHERE Id IN :accountIds AND Credit_Hold__c = TRUE WITH SYSTEM_MODE
        ]) {
            onHold.add(acc.Id);
        }
        return onHold;
    }
}
```

Guardrails (PMD + `npm run audit:metadata`): `*FactsSelector` queries must declare `WITH SYSTEM_MODE`, the class must
be `without sharing`, `WITH SYSTEM_MODE` is rejected in any other class, and entry points (`@AuraEnabled`,
`@InvocableMethod`, REST) may not call a facts selector directly.

### 2.4 Domain Service Implementation (`OpportunityService.cls`)
Contains the business validation rules and logic, reading rule facts in system mode:

```apex
public with sharing class OpportunityService {
    /**
     * @description Enforces: 1) Primary Contact Role required to Close/Win. 2) No closing on credit hold.
     */
    public static void validateStageProgression(List<Opportunity> newOpps, Map<Id, Opportunity> oldOppMap) {
        List<Opportunity> closingWon = new List<Opportunity>();
        Set<Id> accountIds = new Set<Id>();
        Set<Id> existingOppIds = new Set<Id>();
        for (Opportunity opp : newOpps) {
            Opportunity oldOpp = oldOppMap != null ? oldOppMap.get(opp.Id) : null;
            if (opp.StageName == 'Closed Won' && (oldOpp == null || oldOpp.StageName != 'Closed Won')) {
                closingWon.add(opp);
                accountIds.add(opp.AccountId);
                if (opp.Id != null) existingOppIds.add(opp.Id);
            }
        }
        if (closingWon.isEmpty()) return;

        SalesEngineFactsSelector facts = SalesEngineFactsSelector.newInstance();
        Set<Id> accountsOnHold = facts.selectAccountIdsOnCreditHold(accountIds);
        Set<Id> oppsWithPrimaryContact = facts.selectOpportunityIdsWithPrimaryContact(existingOppIds);

        for (Opportunity opp : closingWon) {
            if (accountsOnHold.contains(opp.AccountId)) {
                opp.addError('Cannot Close/Win an Opportunity when parent Account has an active Credit Hold.');
            }
            if (opp.Id != null && !oppsWithPrimaryContact.contains(opp.Id)) {
                opp.addError('Cannot Close/Win an Opportunity without a Primary Contact Role assigned.');
            }
        }
    }
}
```

### 2.5 Service Orchestration (`CaseEscalationService.cls`)
```apex
public with sharing class CaseEscalationService {
    public static void escalateCases(Set<Id> caseIds, String escalationReason) {
        if (caseIds == null || caseIds.isEmpty()) return;

        List<Case> casesToEscalate = CasesSelector.newInstance().selectById(caseIds);
        Group escalationQueue = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Tier_2_Technical_Escalations' WITH USER_MODE LIMIT 1];
        CaseTeamRole smeRole = [SELECT Id FROM CaseTeamRole WHERE Name = 'Technical SME' WITH USER_MODE LIMIT 1];
        Id defaultSmeUserId = UserInfo.getUserId();

        List<CaseTeamMember> teamMembers = new List<CaseTeamMember>();
        for (Case c : casesToEscalate) {
            c.Priority = 'Critical';
            c.Status = 'Escalated';
            c.OwnerId = escalationQueue.Id;

            teamMembers.add(new CaseTeamMember(
                ParentId = c.Id,
                MemberId = defaultSmeUserId,
                TeamRoleId = smeRole.Id
            ));
        }

        update as user casesToEscalate;
        if (!teamMembers.isEmpty()) {
            insert as user teamMembers;
        }
    }
}
```