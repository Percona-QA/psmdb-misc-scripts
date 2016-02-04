
NODES=8192;
SECONDS=10;
THREADS=16;

load('jstests/libs/parallelTester.js');

charset='0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
function randomString(length, chars) {
  var result = '';
  if (typeof(chars) === "undefined")
    chars=charset;
  for (var i = length; i > 0; --i) result += chars[Math.floor(Math.random() * chars.length)];
  return result;
}

function hotNode(nodes,seconds) {
  this.nodes=nodes;
  this.seconds=seconds;
  this.get = function() {
    date = new Date();
    seg = date.getTime() / 1000 / this.seconds;
    node = (seg % this.nodes);
    return Math.floor(node);
  }
}

function primeTheCollection() {
  db.hotNodeCollection.drop();
  for (i=0; i<NODES; i++) {
    db.hotNodeCollection.insert({_id:i, updated:0, data:randomString(1024)});
  }
}

primeTheCollection();

var threads=[];
for(i=0; i<16; i++) {
  var t = new ScopedThread(function(hotNode){
    var retval={};
    try {
      currNode=hotNode.get();
      while (hotNode.get() == currNode) {}
      freshNode=hotNode.get();
      //upd=db.hotNodeCollection.findOne({_id:freshNode}).updated;
      upd=0;
      updret = db.runCommand({
        findAndModify: 'hotNodeCollection',
        query: { _id: freshNode, updated: upd },
        update: { $set: { updated: upd + 1 } },
        new: true
      });
    } finally {
      db = null;
      gc();
    }
    return({node:freshNode, updatedBefore: upd, result: updret});
  },new hotNode(NODES,SECONDS));
  threads.push(t);
  t.start();
}

for (var i in threads) { 
  var t = threads[i];
  t.join();
  printjson(t.returnData());
}

