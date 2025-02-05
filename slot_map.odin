package slot_map

// Both Slot Maps should be usable right now, but only with Key(uint, x, y)

// TODO Test when passing Key(u16/u32, x, y) to slot maps
// TODO Allow explicit passing of allocator to dynamic_slot_map ? To be able to make all the procs "contextless"
// TODO Add return to dynamic_slot_map_delete() proc to see if alloc failed

// Proc groups

insert :: proc {
	fixed_slot_map_insert,
	dynamic_slot_map_insert,
}


insert_set :: proc {
	fixed_slot_map_insert_set,
	dynamic_slot_map_insert_set,
}


insert_get_ptr :: proc {
	fixed_slot_map_insert_get_ptr,
	dynamic_slot_map_insert_get_ptr,
}


remove :: proc {
	fixed_slot_map_remove,
	dynamic_slot_map_remove,
}


remove_value :: proc {
	fixed_slot_map_remove_value,
	dynamic_slot_map_remove_value,
}


set :: proc {
	fixed_slot_map_set,
	dynamic_slot_map_set,
}


get :: proc {
	fixed_slot_map_get,
	dynamic_slot_map_get,
}


get_ptr :: proc {
	fixed_slot_map_get_ptr,
	dynamic_slot_map_get_ptr,
}


is_valid :: proc {
	fixed_slot_map_is_valid,
	dynamic_slot_map_is_valid,
}
