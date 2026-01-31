# Gets full name list
proc get_full_name_list {list} {
	set new_list ""
	  foreach value $list {
	    lappend new_list [get_full_name $value]
	  }	
	return $new_list
}
