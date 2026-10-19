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

  private static final String BYPASS_PERMISSION = 'Bypass_Onboarding_Tasks';

  private static List<Opportunity> buildOpps(String prefix, String stage) {
    List<Opportunity> opps = new List<Opportunity>();
    for (Integer i = 0; i < BULK_SIZE; i++) {
      opps.add(buildOpp(prefix + i, stage));
    }
    return opps;
  }

  private static User createStandardUser(String alias, Boolean withBypass) {
    return createUser(alias, 'Standard User', withBypass);
  }

  // Admin profile so it can edit the admin-owned @TestSetup Opportunities;
  // it has no Migration_Load_User, so the bypass permission is never granted.
  private static User createAdminControlUser() {
    User controlUser = createUser('control', 'System Administrator', false);
    System.runAs(controlUser) {
      System.assertEquals(
        false,
        FeatureManagement.checkPermission(BYPASS_PERMISSION),
        'Admin control user must not hold the bypass permission'
      );
    }
    return controlUser;
  }

  private static User createUser(
    String alias,
    String profileName,
    Boolean withBypass
  ) {
    Profile userProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = :profileName
      LIMIT 1
    ];
    String uniqueKey = UUID.randomUUID().toString();
    User u = new User(
      Alias = alias,
      Email = alias + uniqueKey + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = alias,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = userProfile.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      UserName = alias + uniqueKey + '@example.com'
    );
    insert u;

    if (withBypass) {
      PermissionSet loadPermSet = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'Migration_Load_User'
        LIMIT 1
      ];
      insert new PermissionSetAssignment(
        AssigneeId = u.Id,
        PermissionSetId = loadPermSet.Id
      );
    }
    return u;
  }

  @IsTest
  static void updateToClosedWonCreatesThreeTasks() {
    User controlUser = createAdminControlUser();
    Opportunity opp = [
      SELECT Id, OwnerId
      FROM Opportunity
      WHERE Name = 'Setup Opp 0'
      LIMIT 1
    ];

    Test.startTest();
    System.runAs(controlUser) {
      opp.StageName = 'Closed Won';
      update opp;
    }
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
    User controlUser = createAdminControlUser();
    Opportunity opp = buildOpp('Inserted Won', 'Closed Won');

    Test.startTest();
    System.runAs(controlUser) {
      insert opp;
    }
    Test.stopTest();

    System.assertEquals(
      3,
      [SELECT COUNT() FROM Task WHERE WhatId = :opp.Id],
      'Expected three tasks for an Opportunity inserted as Closed Won'
    );
  }

  @IsTest
  static void otherStageChangeCreatesNoTasks() {
    User controlUser = createAdminControlUser();
    Opportunity opp = [
      SELECT Id
      FROM Opportunity
      WHERE Name = 'Setup Opp 1'
      LIMIT 1
    ];

    Test.startTest();
    System.runAs(controlUser) {
      opp.StageName = 'Qualification';
      update opp;
    }
    Test.stopTest();

    System.assertEquals(
      0,
      [SELECT COUNT() FROM Task WHERE WhatId = :opp.Id],
      'No tasks expected for a non-Closed Won stage'
    );
  }

  @IsTest
  static void resavingClosedWonDoesNotDuplicateTasks() {
    User controlUser = createAdminControlUser();
    Opportunity opp = [
      SELECT Id
      FROM Opportunity
      WHERE Name = 'Setup Opp 2'
      LIMIT 1
    ];
    System.runAs(controlUser) {
      opp.StageName = 'Closed Won';
      update opp;
    }

    Test.startTest();
    System.runAs(controlUser) {
      opp.Description = 'Updated after close';
      update opp;
    }
    Test.stopTest();

    System.assertEquals(
      3,
      [SELECT COUNT() FROM Task WHERE WhatId = :opp.Id],
      'Re-saving a Closed Won Opportunity must not create more tasks'
    );
  }

  @IsTest
  static void bulkClosedWonCreatesSixHundredTasks() {
    User controlUser = createAdminControlUser();
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
    System.runAs(controlUser) {
      update opps;
    }
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
    User controlUser = createAdminControlUser();
    User otherOwner = createStandardUser('othown', false);

    Opportunity opp = buildOpp('Other Owner Opp', 'Prospecting');
    opp.OwnerId = otherOwner.Id;
    System.runAs(controlUser) {
      insert opp;
    }

    Test.startTest();
    System.runAs(controlUser) {
      opp.StageName = 'Closed Won';
      update opp;
    }
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
        controlUser.Id,
        t.OwnerId,
        'Task owner should differ from the user who closed the Opportunity'
      );
    }
  }

  @IsTest
  static void bypassPermissionComesOnlyFromMigrationPermissionSet() {
    User bypassUser = createStandardUser('bypass', true);
    User controlUser = createStandardUser('control', false);

    System.runAs(bypassUser) {
      System.assertEquals(
        true,
        FeatureManagement.checkPermission(BYPASS_PERMISSION),
        'User with Migration_Load_User should have the bypass permission'
      );
    }
    System.runAs(controlUser) {
      System.assertEquals(
        false,
        FeatureManagement.checkPermission(BYPASS_PERMISSION),
        'User without the permission set must not have the bypass permission'
      );
    }
  }

  @IsTest
  static void bypassUserInsertAsClosedWonCreatesNoTasks() {
    User bypassUser = createStandardUser('bypass', true);
    Opportunity opp = buildOpp('Bypass Inserted Won', 'Closed Won');

    Test.startTest();
    System.runAs(bypassUser) {
      insert opp;
    }
    Test.stopTest();

    System.assertEquals(
      1,
      [SELECT COUNT() FROM Opportunity WHERE Id = :opp.Id AND IsWon = TRUE],
      'Opportunity should still be saved as won'
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Task WHERE WhatId = :opp.Id],
      'Bypass user must not create onboarding tasks on insert'
    );
  }

  @IsTest
  static void bypassUserUpdateToClosedWonCreatesNoTasks() {
    User bypassUser = createStandardUser('bypass', true);
    Opportunity opp = buildOpp('Bypass Updated Won', 'Prospecting');
    System.runAs(bypassUser) {
      insert opp;
    }

    Test.startTest();
    System.runAs(bypassUser) {
      opp.StageName = 'Closed Won';
      update opp;
    }
    Test.stopTest();

    System.assertEquals(
      1,
      [SELECT COUNT() FROM Opportunity WHERE Id = :opp.Id AND IsWon = TRUE],
      'Opportunity should be won after the update'
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Task WHERE WhatId = :opp.Id],
      'Bypass user must not create onboarding tasks on update'
    );
  }

  @IsTest
  static void bypassUserBulkInsertAsClosedWonCreatesNoTasks() {
    User bypassUser = createStandardUser('bypass', true);
    List<Opportunity> opps = buildOpps('Bypass Bulk Insert ', 'Closed Won');

    Test.startTest();
    System.runAs(bypassUser) {
      insert opps;
    }
    Test.stopTest();

    System.assertEquals(
      BULK_SIZE,
      [SELECT COUNT() FROM Opportunity WHERE Id IN :opps AND IsWon = TRUE],
      'All 200 Opportunities should be saved as won'
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Task WHERE WhatId IN :opps],
      'Bypass user must not create tasks for a 200-record insert'
    );
  }

  @IsTest
  static void bypassUserBulkUpdateToClosedWonCreatesNoTasks() {
    User bypassUser = createStandardUser('bypass', true);
    List<Opportunity> opps = buildOpps('Bypass Bulk Update ', 'Prospecting');
    System.runAs(bypassUser) {
      insert opps;
    }
    for (Opportunity opp : opps) {
      opp.StageName = 'Closed Won';
    }

    Test.startTest();
    System.runAs(bypassUser) {
      update opps;
    }
    Test.stopTest();

    System.assertEquals(
      BULK_SIZE,
      [SELECT COUNT() FROM Opportunity WHERE Id IN :opps AND IsWon = TRUE],
      'All 200 Opportunities should be won after the update'
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Task WHERE WhatId IN :opps],
      'Bypass user must not create tasks for a 200-record update'
    );
  }

  @IsTest
  static void userWithoutBypassStillGetsThreeTasksPerWonOpportunity() {
    User controlUser = createStandardUser('control', false);
    Opportunity opp = buildOpp('Control Inserted Won', 'Closed Won');

    Test.startTest();
    System.runAs(controlUser) {
      insert opp;
    }
    Test.stopTest();

    System.assertEquals(
      3,
      [SELECT COUNT() FROM Task WHERE WhatId = :opp.Id],
      'User without the bypass permission should still get three tasks'
    );
  }

  @IsTest
  static void userWithoutBypassUpdateToClosedWonCreatesThreeTasks() {
    User controlUser = createStandardUser('control', false);
    Opportunity opp = buildOpp('Control Updated Won', 'Prospecting');
    System.runAs(controlUser) {
      insert opp;
    }

    Test.startTest();
    System.runAs(controlUser) {
      opp.StageName = 'Closed Won';
      update opp;
    }
    Test.stopTest();

    System.assertEquals(
      3,
      [SELECT COUNT() FROM Task WHERE WhatId = :opp.Id],
      'User without the bypass permission should get three tasks on update'
    );
  }

  @IsTest
  static void userWithoutBypassBulkInsertCreatesSixHundredTasks() {
    User controlUser = createStandardUser('control', false);
    List<Opportunity> opps = buildOpps('Control Bulk Insert ', 'Closed Won');

    Test.startTest();
    System.runAs(controlUser) {
      insert opps;
    }
    Test.stopTest();

    System.assertEquals(
      BULK_SIZE * 3,
      [SELECT COUNT() FROM Task WHERE WhatId IN :opps],
      'Three tasks per Opportunity expected for a 200-record insert'
    );
  }

  @IsTest
  static void bypassDoesNotAffectOtherUsersInTheSameTransaction() {
    User bypassUser = createStandardUser('bypass', true);
    User controlUser = createStandardUser('control', false);
    Opportunity bypassOpp = buildOpp('Bypass Load Opp', 'Closed Won');
    Opportunity controlOpp = buildOpp('Control Live Opp', 'Closed Won');

    Test.startTest();
    System.runAs(bypassUser) {
      insert bypassOpp;
    }
    System.runAs(controlUser) {
      insert controlOpp;
    }
    Test.stopTest();

    System.assertEquals(
      0,
      [SELECT COUNT() FROM Task WHERE WhatId = :bypassOpp.Id],
      'Bypassed load must create no tasks'
    );
    System.assertEquals(
      3,
      [SELECT COUNT() FROM Task WHERE WhatId = :controlOpp.Id],
      'A normal user after a bypassed load must still get three tasks'
    );
  }
}
