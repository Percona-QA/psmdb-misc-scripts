set pagination off

break mongo::TokuFTDictionary::insert(mongo::OperationContext*, mongo::Slice const&, mongo::Slice const&, bool) 
break mongo::TokuFTDictionary::get(mongo::OperationContext*, mongo::Slice const&, mongo::Slice&, bool) const
break mongo::TokuFTDictionary::update(mongo::OperationContext*, mongo::Slice const&, mongo::KVUpdateMessage const&)
break mongo::TokuFTDictionary::remove(mongo::OperationContext*, mongo::Slice const&)
