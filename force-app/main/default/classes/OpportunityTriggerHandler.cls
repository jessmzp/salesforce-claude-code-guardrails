public with sharing class OpportunityTriggerHandler {
  public static void afterInsert(List<Opportunity> newOpps) {
    createOnboardingTasks(newOpps, null);
  }

  public static void afterUpdate(
    List<Opportunity> newOpps,
    Map<Id, Opportunity> oldMap
  ) {
    createOnboardingTasks(newOpps, oldMap);
  }

  private static void createOnboardingTasks(
    List<Opportunity> newOpps,
    Map<Id, Opportunity> oldMap
  ) {
    List<Task> tasks = new List<Task>();

    for (Opportunity opp : newOpps) {
      if (!opp.IsWon) {
        continue;
      }
      if (oldMap != null && oldMap.get(opp.Id).IsWon) {
        continue;
      }
      tasks.add(buildTask(opp, 'Kickoff call with client', 1));
      tasks.add(buildTask(opp, 'Send welcome package', 3));
      tasks.add(buildTask(opp, 'Schedule onboarding session', 7));
    }

    if (!tasks.isEmpty()) {
      Database.insert(tasks, AccessLevel.USER_MODE);
    }
  }

  private static Task buildTask(
    Opportunity opp,
    String subject,
    Integer daysUntilDue
  ) {
    return new Task(
      Subject = subject,
      WhatId = opp.Id,
      OwnerId = opp.OwnerId,
      ActivityDate = Date.today().addDays(daysUntilDue),
      Status = 'Not Started',
      Priority = 'Normal'
    );
  }
}
