set pagination off

break mongo::TokuFTDictionary::insert(mongo::OperationContext*, mongo::Slice const&, mongo::Slice const&, bool) 
commands
bt
cont
end

break mongo::TokuFTDictionary::get(mongo::OperationContext*, mongo::Slice const&, mongo::Slice&, bool) const
commands
bt
cont
end

break mongo::TokuFTDictionary::update(mongo::OperationContext*, mongo::Slice const&, mongo::KVUpdateMessage const&)
commands
bt
cont
end

break mongo::TokuFTDictionary::remove(mongo::OperationContext*, mongo::Slice const&) 
commands
bt
cont
end
