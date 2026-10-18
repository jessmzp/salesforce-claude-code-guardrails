---
name: apex-test-class
description: Use when creating or updating an Apex test class for any Apex class or trigger in this project.
---

Create test classes that:

1. Use a @TestSetup method with test data.
2. Test positive, negative and bulk (200 records) scenarios.
3. Use System.assertEquals with clear messages; never test only for coverage.
4. Run the tests with the CLI and report the results.
