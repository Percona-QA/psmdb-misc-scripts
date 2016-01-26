var gtidHexString='';

db=db.getSiblingDB('local');

db.oplog.rs.find().sort({$natural:-1}).limit(1).forEach(function(o){
  gtidHexString = o._id.hex();
});

if (gtidHexString == '') {
  print("GTID not found.");
  quit();
}

var uuid=gtidHexString.substring(16);
var seq=gtidHexString.substring(0,16);

print(gtidHexString);
print('0x'+seq+':'+'0x'+uuid);

