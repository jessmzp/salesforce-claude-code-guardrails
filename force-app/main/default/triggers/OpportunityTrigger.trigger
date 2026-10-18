trigger OpportunityTrigger on Opportunity(after insert, after update) {
  if (Trigger.isInsert) {
    OpportunityTriggerHandler.afterInsert(Trigger.new);
  } else if (Trigger.isUpdate) {
    OpportunityTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
  }
}
