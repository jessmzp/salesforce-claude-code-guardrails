@IsTest
private class OpportunityTriggerHandlerTest {
  private static final Integer BULK_SIZE = 200;

  @TestSetup
  static void setup() {
    List<Opportunity> opps = new List<Opportunity>();
    for (Integer i = 0; i < BULK_SIZE; i++) {
      opps.add(buildOpp('Setup Opp ' + i, 'Prospecting'));
    }
    insert opps;
  }

  private static Opportunity buildOpp(String name, String stage) {
    return new Opportunity(
      Name = name,
      StageName = stage,
      CloseDate = Date.today().addDays(30)
    );
  }

  @IsTest
  static void updateToClosedWonCreatesThreeTasks() {
    Opportunity opp = [
      SELECT Id, OwnerId
      FROM Opportunity
      WHERE Name = 'Setup Opp 0'
      LIMIT 1
    ];

    Test.startTest();
    opp.StageName = 'Closed Won';
    update opp;
    Test.stopTest();

    List<Task> tasks = [
      SELECT Subject, ActivityDate, OwnerId, WhatId
      FROM Task
      WHERE WhatId = :opp.Id
      ORDER BY ActivityDate
    ];
    System.assertEquals(3, tasks.size(), 'Expected three onboarding tasks');
    System.assertEquals(
      'Kickoff call with client',
      tasks[0].Subject,
      'First task subject'
    );
    System.assertEquals(
      Date.today().addDays(1),
      tasks[0].ActivityDate,
      'Kickoff due in 1 day'
    );
    System.assertEquals(
      'Send welcome package',
      tasks[1].Subject,
      'Second task subject'
    );
    System.assertEquals(
      Date.today().addDays(3),
      tasks[1].ActivityDate,
      'Welcome package due in 3 days'
    );
    System.assertEquals(
      'Schedule onboarding session',
      tasks[2].Subject,
      'Third task subject'
    );
    System.assertEquals(
      Date.today().addDays(7),
      tasks[2].ActivityDate,
      'Onboarding session due in 7 days'
    );
    for (Task t : tasks) {
      System.assertEquals(
        opp.OwnerId,
        t.OwnerId,
        'Task owner should be the Opportunity owner'
      );
    }
  }

  @IsTest
  static void insertAsClosedWonCreatesThreeTasks() {
    Opportunity opp = buildOpp('Inserted Won', 'Closed Won');

    Test.startTest();
    insert opp;
    Test.stopTest();

    System.assertEquals(
      3,
      [SELECT COUNT() FROM Task WHERE WhatId = :opp.Id],
      'Expected three tasks for an Opportunity inserted as Closed Won'
    );
  }

  @IsTest
  static void otherStageChangeCreatesNoTasks() {
    Opportunity opp = [
      SELECT Id
      FROM Opportunity
      WHERE Name = 'Setup Opp 1'
      LIMIT 1
    ];

    Test.startTest();
    opp.StageName = 'Qualification';
    update opp;
    Test.stopTest();

    System.assertEquals(
      0,
      [SELECT COUNT() FROM Task WHERE WhatId = :opp.Id],
      'No tasks expected for a non-Closed Won stage'
    );
  }

  @IsTest
  static void resavingClosedWonDoesNotDuplicateTasks() {
    Opportunity opp = [
      SELECT Id
      FROM Opportunity
      WHERE Name = 'Setup Opp 2'
      LIMIT 1
    ];
    opp.StageName = 'Closed Won';
    update opp;

    Test.startTest();
    opp.Description = 'Updated after close';
    update opp;
    Test.stopTest();

    System.assertEquals(
      3,
      [SELECT COUNT() FROM Task WHERE WhatId = :opp.Id],
      'Re-saving a Closed Won Opportunity must not create more tasks'
    );
  }

  @IsTest
  static void bulkClosedWonCreatesSixHundredTasks() {
    List<Opportunity> opps = [SELECT Id FROM Opportunity];
    System.assertEquals(
      BULK_SIZE,
      opps.size(),
      'Test setup should provide 200 Opportunities'
    );
    for (Opportunity opp : opps) {
      opp.StageName = 'Closed Won';
    }

    Test.startTest();
    update opps;
    Test.stopTest();

    Map<Id, Integer> taskCounts = new Map<Id, Integer>();
    for (Task t : [SELECT WhatId FROM Task WHERE WhatId IN :opps]) {
      Integer current = taskCounts.get(t.WhatId);
      taskCounts.put(t.WhatId, current == null ? 1 : current + 1);
    }
    System.assertEquals(
      BULK_SIZE,
      taskCounts.size(),
      'Every Opportunity should have tasks'
    );
    for (Opportunity opp : opps) {
      System.assertEquals(
        3,
        taskCounts.get(opp.Id),
        'Each Opportunity should have exactly three tasks'
      );
    }
  }

  @IsTest
  static void tasksAreAssignedToOpportunityOwnerNotCreator() {
    Profile standard = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    String uniqueKey = String.valueOf(System.currentTimeMillis());
    User otherOwner = new User(
      Alias = 'othown',
      Email = 'othown' + uniqueKey + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Owner',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = standard.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      UserName = 'othown' + uniqueKey + '@example.com'
    );
    insert otherOwner;

    Opportunity opp = buildOpp('Other Owner Opp', 'Prospecting');
    opp.OwnerId = otherOwner.Id;
    insert opp;

    Test.startTest();
    opp.StageName = 'Closed Won';
    update opp;
    Test.stopTest();

    List<Task> tasks = [SELECT OwnerId FROM Task WHERE WhatId = :opp.Id];
    System.assertEquals(3, tasks.size(), 'Expected three onboarding tasks');
    for (Task t : tasks) {
      System.assertEquals(
        otherOwner.Id,
        t.OwnerId,
        'Task owner should be the Opportunity owner'
      );
      System.assertNotEquals(
        UserInfo.getUserId(),
        t.OwnerId,
        'Task owner should differ from the running user'
      );
    }
  }
}
