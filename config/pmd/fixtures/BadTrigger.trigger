trigger BadTrigger on Account (before insert) {
    for (Account a : Trigger.new) { a.Name = 'x'; }
}
