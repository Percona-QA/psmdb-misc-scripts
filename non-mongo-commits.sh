#!/bin/bash

if [ "$2" == "" ]; then
  echo "Usage: ./non-mongo-commits.sh {mongodb rev} {psmdb rev}"
  exit 1;
fi

mongodb_rev=$1
psmdb_rev=$2

if [ ! -d 'percona-server-mongodb' ]; then
  git clone https://github.com/percona/percona-server-mongodb.git
fi
cd percona-server-mongodb
git fetch origin

if ! git remote -v 2>/dev/null | grep -q '\/mongodb\/'; then
  git remote add upstream https://github.com/mongodb/mongo.git
fi
git fetch upstream

title=$(echo -n "Differences between upstream MongoDB: ${mongodb_rev} and Percona PSMDB: ${psmdb_rev}")

# commits

echo ${title} > ../commits.txt
echo -e "Commits not in upstream\n" >> ../commits.txt
git cherry -v ${mongodb_rev} ${psmdb_rev} | awk '{print $2}' | xargs -n1 -i{} git show {} --name-status >> ../commits.txt

# authors

echo -e "${title}\n" > ../authors.txt

echo "commits author" >> ../authors.txt
echo "------- ----------------------------------------------------------------" >> ../authors.txt
grep '^Author: ' ../commits.txt  | sed 's/^Author: //' | sort | uniq -c | sort -nr >> ../authors.txt

# files

echo -e "${title}\n" > ../files.txt

echo "Files Added:" >> ../files.txt
echo "------------" >> ../files.txt

grep -E '^A\s' ../commits.txt | sed 's/^.\s//' | sort | uniq >> ../files.txt

echo -e "\nFiles Modified:" >> ../files.txt
echo "---------------" >> ../files.txt

grep -E '^M\s' ../commits.txt | sed 's/^.\s//' | sort | uniq >> ../files.txt

echo -e "\nFiles Deleted:" >> ../files.txt
echo "---------------" >> ../files.txt

grep -E '^D\s' ../commits.txt | sed 's/^.\s//' | sort | uniq >> ../files.txt

