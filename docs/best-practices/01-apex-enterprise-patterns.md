# Nexus Core Engineering Standard: Apex Clean Architecture & Separation of Concerns

- **Standard Code:** `BP-APEX-001`
- **Module Target:** `modules/10-core-domain/`
- **Related ADR:** `docs/adr/0001-pragmatic-clean-architecture.md`

---

## 1. Core Architectural Standard
To ensure maximum maintainability, performance, and AI-agent compatibility, Nexus Core enforces **Pragmatic Clean Architecture** instead of heavyweight Java-style reflection frameworks (`fflib`).

Business logic is strictly decoupled across three explicit tiers:
1. **Lightweight Trigger Handlers:** Extend `TriggerHandler.cls`. Responsible only for routing execution contexts (`beforeInsert`, `beforeUpdate`, etc.) and delegating to Services. No business calculations or inline SOQL in handlers.
2. **Selector Tier (`*Selector.cls`):** Sole authority for SOQL queries. Enforces field selection, user mode (`WITH USER_MODE`), and subqueries.
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
public with sharing class OpportunitiesSelector {
    public static List<Opportunity> selectByIdWithDetails(Set<Id> oppIds) {
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

### 2.3 Domain Service Implementation (`OpportunityService.cls`)
Contains the business validation rules and logic:

```apex
public with sharing class OpportunityService {
    /**
     * @description Enforces: 1) Primary Contact Role required to Close/Win. 2) No closing on credit hold.
     */
    public static void validateStageProgression(List<Opportunity> newOpps, Map<Id, Opportunity> oldOppMap) {
        Set<Id> closingOppIds = new Set<Id>();
        for (Opportunity opp : newOpps) {
            Opportunity oldOpp = oldOppMap != null ? oldOppMap.get(opp.Id) : null;
            if (opp.StageName == 'Closed Won' && (oldOpp == null || oldOpp.StageName != 'Closed Won')) {
                closingOppIds.add(opp.Id);
            }
        }

        if (closingOppIds.isEmpty()) return;

        Map<Id, Opportunity> detailedOpps = new Map<Id, Opportunity>(
            OpportunitiesSelector.selectByIdWithDetails(closingOppIds)
        );

        for (Opportunity opp : newOpps) {
            if (!detailedOpps.containsKey(opp.Id)) continue;
            Opportunity details = detailedOpps.get(opp.Id);

            if (details.Account != null && details.Account.Credit_Hold__c == true) {
                opp.addError('Cannot Close/Win an Opportunity when parent Account has an active Credit Hold.');
            }

            Boolean hasPrimaryContact = false;
            for (OpportunityContactRole ocr : details.OpportunityContactRoles) {
                if (ocr.IsPrimary) {
                    hasPrimaryContact = true;
                    break;
                }
            }
            if (!hasPrimaryContact) {
                opp.addError('Cannot Close/Win an Opportunity without a Primary Contact Role assigned.');
            }
        }
    }
}
```

### 2.4 Service Orchestration (`CaseEscalationService.cls`)
```apex
public with sharing class CaseEscalationService {
    public static void escalateCases(Set<Id> caseIds, String escalationReason) {
        if (caseIds == null || caseIds.isEmpty()) return;

        List<Case> casesToEscalate = CasesSelector.selectById(caseIds);
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