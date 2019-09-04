j=30000;
prefix='test_many_db_';

for(i=1; i <= j; i++) {
  database=prefix+i;
  db.getSiblingDB(database).testColl.insert({name: "John", surname: "Doe"})
  if (i % 5000 === 0) {
    print('Created database: ' + prefix + i);
  }
}

for(i=1; i <= j; i++) {
  database=prefix+i;
  db.getSiblingDB(database).dropDatabase()
  if (i % 5000 === 0) {
    print('Dropped database: ' + prefix + i);
  }
}
