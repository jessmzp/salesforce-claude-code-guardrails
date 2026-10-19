# Migration mapping: `legacy` → `practice`

Source: `legacy` org (`Customer__c`, `Deal__c`). Target: `practice` org (Account, Contact, Opportunity).
Status: approved design (decisions D1–D10 accepted). Any write to either org is run or approved by a human.

## 1. Discovery summary

- `Customer__c` mixes company and person data; there is no Contact object. All fields are free text except `Legacy_Id__c` (External ID, unique).
- `Deal__c` is master-detail to `Customer__c` and has Amount, Stage (text) and Close Date only. It has no name and no legacy ID field.
- Practice required fields: Account `Name`; Contact `LastName`; Opportunity `Name`, `StageName`, `CloseDate`.
- **State/Country picklists are enabled** in practice (`BillingCountryCode`, `BillingStateCode`, `MailingCountryCode`), so addresses must be loaded as ISO codes. The source has no state data, so state stays blank.
- Practice `StageName` values: Prospecting, Qualification, Needs Analysis, Value Proposition, Id. Decision Makers, Perception Analysis, Proposal/Price Quote, Negotiation/Review, Closed Won, Closed Lost.
- `Account.Active__c` is a Yes/No picklist. There is no "customer since" field.
- Existing practice data: 5 Accounts (each with 1 Contact) and 1 Opportunity ("Prueba Onboarding", Closed Won). The only real user is the load user; no user matches a `@legacyco.example` rep.
- Automation that fires on load:
  - `OpportunityTrigger` / `OpportunityTriggerHandler` creates 3 Tasks per won Opportunity (on insert, or when `IsWon` flips). The 24 won deals would create 72 unwanted tasks.
  - Active standard duplicate rules on Account and Contact.
  - No custom flows, workflow rules or validation rules.

## 2. Object mapping

| Legacy        | Target      | Rule                                                                         |
| ------------- | ----------- | ---------------------------------------------------------------------------- |
| `Customer__c` | Account     | One per surviving company (`Company_Name__c`)                                |
| `Customer__c` | Contact     | One per surviving person (`Full_Name__c`, `Email__c`), child of that Account |
| `Deal__c`     | Opportunity | One per deal; AccountId = surviving Account of its customer                  |

## 3. Field mapping

Fields marked _(new)_ do not exist in practice yet (see section 9, prerequisites).

| Source                           | Target                                                           | Transformation                                                                                                                                          |
| -------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Customer__c.Company_Name__c`    | Account.Name                                                     | Trim, collapse spaces                                                                                                                                   |
| `Customer__c.Legacy_Id__c`       | Account.Legacy_Id__c _(new)_                                     | Survivor's ID. Merged IDs go to `Legacy_Merged_Ids__c` _(new)_                                                                                          |
| `Customer__c.Legacy_Id__c`       | Contact.Legacy_Id__c _(new)_                                     | Survivor's ID                                                                                                                                           |
| `Customer__c.Full_Name__c`       | Contact.FirstName / LastName                                     | "Last, First" is flipped; otherwise split on the last space; a single token goes to LastName. Initials ("J. Castillo") lose to the fuller survivor name |
| `Customer__c.Email__c`           | Contact.Email                                                    | Trim, lowercase. Blank stays null                                                                                                                       |
| `Customer__c.Phone__c`           | Account.Phone, Contact.Phone                                     | Trim and normalise whitespace only; no country-code guessing                                                                                            |
| `Customer__c.Country__c`         | Account.BillingCountryCode, Contact.MailingCountryCode           | Value map in section 4; no match goes to exceptions                                                                                                     |
| `Customer__c.Status__c`          | Account.Active__c                                                | Value map in section 4                                                                                                                                  |
| `Customer__c.Annual_Revenue__c`  | Account.AnnualRevenue                                            | Strip `$`, `USD`, commas; `K` ×1,000; `M` ×1,000,000; blank becomes null                                                                                |
| `Customer__c.Customer_Since__c`  | Account.Customer_Since__c _(new, Date)_                          | Unambiguous parses only. Year-only becomes Jan 1 of that year. Ambiguous day/month (e.g. 08/06/2018) becomes null and goes to the review list           |
| `Customer__c.Sales_Rep_Email__c` | Account/Opportunity `Legacy_Sales_Rep_Email__c` _(new)_; OwnerId | See section 7                                                                                                                                           |
| `Deal__c` record Id (18-char)    | Opportunity.Legacy_Id__c _(new)_                                 | Deal has no business key, so the legacy record Id is used                                                                                               |
| `Deal__c.Amount__c`              | Opportunity.Amount                                               | As-is                                                                                                                                                   |
| `Deal__c.Close_Date__c`          | Opportunity.CloseDate                                            | As-is; null goes to exceptions                                                                                                                          |
| `Deal__c.Stage__c`               | Opportunity.StageName                                            | Value map in section 4                                                                                                                                  |
| (none)                           | Opportunity.Name                                                 | `<Account Name> – <CloseDate YYYY-MM-DD> – <Stage>`. Names need not be unique; `Legacy_Id__c` is the key                                                |
| `Deal__c.Customer__c`            | Opportunity.AccountId                                            | Resolved through `Account.Legacy_Id__c` of the survivor                                                                                                 |

## 4. Value maps

Matching is case-insensitive and ignores surrounding whitespace (and hyphen vs space for stages). Any value outside a map goes to the exceptions file; nothing is defaulted silently.

**Status → `Account.Active__c`**

| Legacy                   | Target                                              |
| ------------------------ | --------------------------------------------------- |
| Activo, active, ACT      | Yes                                                 |
| Inactive, inactivo       | No                                                  |
| (blank) LEG-010, LEG-019 | **Unmapped**: `Active__c` left null, record flagged |

**Country → ISO code**

| Legacy             | Target                                                         |
| ------------------ | -------------------------------------------------------------- |
| El Salvador, SV    | SV                                                             |
| USA, United States | US                                                             |
| Mexico, MX         | MX                                                             |
| Wakanda            | **Unmapped**: not a valid ISO country (LEG-030, see section 6) |

**Stage → `StageName`**

| Legacy                      | Target                                                             |
| --------------------------- | ------------------------------------------------------------------ |
| Open                        | Prospecting                                                        |
| In progress                 | Proposal/Price Quote                                               |
| Won, Closed-Won, closed won | Closed Won                                                         |
| Lost                        | Closed Lost                                                        |
| On hold                     | **Unmapped**: 2 deals held out (LEG-016, 122,000; LEG-026, 53,500) |

## 5. Deduplication

### Inside legacy

- Key: lowercased, trimmed email. When the email is blank, fall back to normalised company name + country.
- Name normalisation flips "Last, First" and ignores case and punctuation.
- **Survivor rule.** For this practice, the survivor is the **lowest LEG ID**. In a real project the default would be the **most complete record** (most populated fields, most recent activity), with the lowest ID only as a tie-breaker.
- Deals of a merged customer are repointed to the survivor. Merged IDs are kept in `Legacy_Merged_Ids__c`.
- Expected merges (all three pairs share the same rep, so there is no owner conflict):
  - LEG-007 ← LEG-026 (Agroexport; "J. Castillo")
  - LEG-012 ← LEG-027 (Martinez Pharma; upper-case email, "Martinez, Elena")
  - LEG-020 ← LEG-028 (Santos Importaciones)
- 30 customers − 3 merges = 27 survivors.

### Against existing practice records

- Match order: (1) Contact by lowercased email, then its Account; (2) normalised Account name (strip S.A./SA/LLC and punctuation).
- Expected matches (5): LEG-003 Cafe Santa Tecla; LEG-007 Agroexport (name differs by "SA"); LEG-011 Torres Automotriz (name differs by "S.A."); LEG-015 Hernandez Tech (email differs by case); LEG-019 Davis Software Group.
- Matched records are not recreated. The legacy ID is stamped on the existing Account and Contact, and Opportunities attach to it.
- Conflicting field values: fill blanks only, never overwrite existing values, log every difference.
- Name-only (ambiguous) matches go to review and are never auto-merged.
- Standard duplicate rules stay active. After pre-dedup they should not fire; a hit is a finding to investigate, not something to bypass.

## 6. Error handling

| Case                                      | Behaviour                                                                                                                                                       |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **LEG-029** (no email)                    | Load Account and Contact with email null. Dedup by normalised name + country (no practice match). Flag in the exceptions report for follow-up. Its 2 deals load |
| **LEG-030** (Wakanda)                     | Invalid country for the picklist. Quarantine the customer **and its 2 deals** to `migration/exceptions/`; do not load                                           |
| **"On hold" deals** (2)                   | Not loaded; written to `migration/exceptions/` with the reason                                                                                                  |
| Blank Status                              | Account loads with `Active__c` null; flagged                                                                                                                    |
| Unparseable or ambiguous date, or revenue | Field left null, row flagged, record still loads                                                                                                                |
| Orphan deal (no customer)                 | Rejected (none in the data)                                                                                                                                     |

Nothing is silently dropped: loaded + merged + quarantined + excluded = source rows.

## 7. Owner mapping (`Sales_Rep_Email__c`)

- Four reps in the data: rep.diego (9 customers), rep.ana (8), rep.sofia (7), rep.luis (6). None exist as users in practice.
- Every migrated record is owned by the load user. The rep email is preserved in `Legacy_Sales_Rep_Email__c` on Account and Opportunity, so a later reassignment is one update per rep.
- Future rule: if `User.Email` matches the rep email (case-insensitive), use that user as owner.
- Existing practice records keep their current owner.

## 8. Traceability and reruns

- New External ID fields, Unique and case-insensitive: `Account.Legacy_Id__c`, `Contact.Legacy_Id__c`, `Opportunity.Legacy_Id__c`.
- All loads are **upserts on those IDs**, so a rerun updates instead of duplicating. Opportunities and Contacts resolve their parent Account through the Account external ID, so no Salesforce Ids are needed in the load files.
- Each load writes a result file keyed by legacy ID. Exceptions go to `migration/exceptions/`.

## 9. Preventing onboarding tasks on historical won deals

`OpportunityTrigger` creates 3 Tasks (due +1, +3, +7 days from today) for every Opportunity inserted as won. A bypass is needed for the load.

Chosen approach: a **Custom Permission** `Bypass_Onboarding_Tasks`, checked at the top of `createOnboardingTasks` with `FeatureManagement.checkPermission('Bypass_Onboarding_Tasks')`. A permission set grants it to the load user only, and it is removed after the load.

- Why: no data to flip, scoped to one user (normal users still get tasks), auditable.
- Needs: handler change, new tests (bypass on creates 0 tasks, including a 200-record bulk case; bypass off still creates 3 per won Opportunity), Apex review, and a **human deploy**.
- Rejected: loading as open then flipping to Won (the update path still fires), deleting the tasks afterwards (noisy data cleanup), deactivating the trigger (affects everyone).

### Prerequisites (human-deployed, not yet done)

1. New fields: the three `Legacy_Id__c`, `Account.Legacy_Merged_Ids__c`, `Legacy_Sales_Rep_Email__c` (Account and Opportunity), `Account.Customer_Since__c`.
2. Custom Permission, permission set, and the handler change with tests.
3. Assign the permission set to the load user; run Apex tests.

## 10. Load order

0. Prerequisites above, deployed by a human.
1. Accounts (upsert on `Legacy_Id__c`), including stamping the 5 matched Accounts.
2. Contacts (parent by Account `Legacy_Id__c`).
3. Opportunities (parent by Account `Legacy_Id__c`).

A pilot of about 5 records runs first, then the full load. A human runs or approves every load. The bypass permission is removed afterwards.

## 11. Reconciliation checks

### Accounts and Contacts

30 legacy customers → 27 survivors → 26 after quarantining LEG-030 → **21 new + 5 matched existing**. Practice total after load: 26 Accounts and 26 Contacts.

### Opportunities

| Step                                                        | Count  |
| ----------------------------------------------------------- | ------ |
| Legacy deals                                                | 60     |
| Minus quarantined with LEG-030 (both In progress)           | −2     |
| Minus "On hold" (LEG-016, LEG-026; no overlap with LEG-030) | −2     |
| **New Opportunities loaded**                                | **56** |
| Existing in practice ("Prueba Onboarding")                  | +1     |
| **Total Opportunities in practice**                         | **57** |

The math was checked against the seed data: 60 deals; LEG-030 has 2 deals; the On hold deals belong to LEG-016 and LEG-026; the two sets do not overlap. Merging LEG-026 into LEG-007 repoints deals but does not remove any, so it does not change the count.

### Other checks

- Won: 24 legacy won deals (Won 12, Closed-Won 10, closed won 2) → 24 migrated Opportunities with `IsWon = true`. Lost 10 → Closed Lost 10.
- Amounts: `SUM(Amount)` by mapped stage in legacy equals practice (excluding exceptions).
- **Tasks: 0** Tasks whose WhatId is a migrated Opportunity.
- No null `Legacy_Id__c` on migrated rows; no duplicate lowercased Contact emails; every migrated Opportunity has an Account.
- Country code distribution matches the map.
- A rerun of the same upsert produces 0 inserts.
- Source rows = loaded + merged + quarantined + excluded.

## 12. Decisions taken

|     | Decision                                                                     |
| --- | ---------------------------------------------------------------------------- |
| D1  | Add the new fields listed in section 9, human-deployed                       |
| D2  | Load LEG-029 flagged; quarantine LEG-030 and its deals                       |
| D3  | Blank Status leaves `Active__c` null and flagged                             |
| D4  | Open → Prospecting; In progress → Proposal/Price Quote; On hold held out     |
| D5  | Opportunity name `<Account> – <CloseDate> – <Stage>`                         |
| D6  | Unambiguous dates only; year-only → Jan 1; ambiguous → null plus review list |
| D7  | Existing practice records: fill blanks only, log differences                 |
| D8  | Duplicate rules stay active; a hit is a finding                              |
| D9  | Load user owns all records; rep emails preserved for later reassignment      |
| D10 | No OpportunityContactRole in this pass                                       |
