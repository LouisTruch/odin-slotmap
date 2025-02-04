package slot_map


// Fixed Size Dense Slot Map of size N ( > 0 ) ! It can't be full, max used slots is N - 1 \
// Not protected against gen overflow \
// Uses key.gen = 0 as error value \
// It makes 0 allocation so you should be careful about stack overflows if you don't alloc it on the heap
FixedSlotMap :: struct($N: uint, $T: typeid, $KeyType: typeid) where N > 1 {
	// Used for itering on the dense part of the data array
	size:           uint,
	free_list_head: uint,
	free_list_tail: uint,
	// Array of every possible Key
	// Unused Keys are used as an in place free list
	keys:           [N]KeyType,
	// Used to keep track of the data of a given Key when deleting
	erase:          [N]uint,
	data:           [N]T,
}


// Returns an initialized slot map
@(require_results)
fixed_slot_map_make :: #force_inline proc "contextless" (
	$N: uint,
	$T: typeid,
	$KT: typeid,
) -> (
	slot_map: FixedSlotMap(N, T, KT),
) {
	fixed_slot_map_init(&slot_map)
	return slot_map
}


// Can also be used to reset the Slot Map
fixed_slot_map_init :: #force_inline proc "contextless" (m: ^FixedSlotMap($N, $T, $KT/Key)) {
	m.size = 0

	i: uint
	for &key in m.keys {
		key.idx = i + 1
		key.gen = 1
		i += 1
	}

	m.free_list_head = 0
	m.free_list_tail = N - 1

	// Last element points on itself 
	m.keys[m.free_list_tail].idx = N - 1

	m.data = {}
	m.erase = 0
}


// Asks the slot map for a new Key
// Return said Key and a boolean indicating the success or not of the operation
@(require_results)
fixed_slot_map_insert :: proc "contextless" (
	m: ^FixedSlotMap($N, $T, $KT/Key),
) -> (
	KT,
	bool,
) #optional_ok {
	if is_slot_map_full(m) {
		return KT{}, false
	}

	user_key := generate_new_user_key(m)

	create_slot(m, &user_key)

	return user_key, true
}


// Asks the slot map for a new Key and put the data you pass in the slot map
// Return said Key and a boolean indicating the success or not of the operation
@(require_results)
fixed_slot_map_insert_set :: proc "contextless" (
	m: ^FixedSlotMap($N, $T, $KT/Key),
	data: T,
) -> (
	KT,
	bool,
) #optional_ok {
	if is_slot_map_full(m) {
		return KT{}, false
	}

	user_key := generate_new_user_key(m)

	// Copy the passed data in the data array
	m.data[m.size] = data

	create_slot(m, &user_key)

	return user_key, true
}


// Asks the slot map for a new Key
// Return said Key, a pointer to the beginning of data in the slot map and a boolean indicating the success or not of the operation
@(require_results)
fixed_slot_map_insert_get_ptr :: proc "contextless" (
	m: ^FixedSlotMap($N, $T, $KT/Key),
) -> (
	KT,
	^T,
	bool,
) {
	if is_slot_map_full(m) {
		return KT{}, nil, false
	}

	user_key := generate_new_user_key(m)

	create_slot(m, &user_key)

	return user_key, &m.data[m.size - 1], true
}


// Try to give back the Key and a slot of data to the slot map
// The Key might has already been given back
// The return value confirms the success of the deletion, or not
// ! This makes data move in the slot map, old data is not cleared !
fixed_slot_map_remove :: proc "contextless" (
	m: ^FixedSlotMap($N, $T, $KT/Key),
	user_key: KT,
) -> bool {
	if !fixed_slot_map_is_valid(m, user_key) {
		return false
	}

	key := user_key_get_array_key_ptr(m, user_key)

	delete_slot(m, key, user_key)

	return true
}


// Try to give back the Key and a slot of data to the slot map
// The Key might has already been given back
// Returns a copy of the deleted data, and the success or not of the operation
// ! This makes data move in the slot map, old data is not cleared !
fixed_slot_map_remove_value :: proc "contextless" (
	m: ^FixedSlotMap($N, $T, $KT/Key),
	user_key: KT,
) -> (
	T,
	bool,
) #optional_ok {
	if !fixed_slot_map_is_valid(m, user_key) {
		return {}, false
	}

	key := user_key_get_array_key_ptr(m, user_key)

	// Make a copy of the deleted data before overwriting it
	deleted_data_copy := m.data[key.idx]

	delete_slot(m, key, user_key)

	return deleted_data_copy, true
}


// If the Key is valid, returns a copy of the data
@(require_results)
fixed_slot_map_get :: #force_inline proc "contextless" (
	m: ^FixedSlotMap($N, $T, $KT/Key),
	user_key: KT,
) -> (
	T,
	bool,
) #optional_ok {
	if !fixed_slot_map_is_valid(m, user_key) {
		return {}, false
	}

	key_from_array := user_key_get_array_key_ptr(m, user_key)

	return m.data[key_from_array.idx], true
}


// If the Key is valid, returns a ptr to the data
@(require_results)
fixed_slot_map_get_ptr :: #force_inline proc "contextless" (
	m: ^FixedSlotMap($N, $T, $KT/Key),
	user_key: KT,
) -> (
	^T,
	bool,
) #optional_ok {
	if !fixed_slot_map_is_valid(m, user_key) {
		return nil, false
	}

	key_from_array := user_key_get_array_key_ptr(m, user_key)

	return &m.data[key_from_array.idx], true
}


fixed_slot_map_set :: proc "contextless" (
	m: ^FixedSlotMap($N, $T, $KT/Key),
	user_key: KT,
	new_data: T,
) -> bool {
	if !fixed_slot_map_is_valid(m, user_key) {
		return false
	}

	key_from_array := user_key_get_array_key_ptr(m, user_key)

	m.data[key_from_array.idx] = new_data

	return true
}


// Check if the user Key is valid
@(require_results)
fixed_slot_map_is_valid :: #force_inline proc "contextless" (
	m: ^FixedSlotMap($N, $T, $KT/Key),
	user_key: KT,
) -> bool #no_bounds_check {
	// Manual bound checking
	// Then check if the generation is the same
	return(
		!(user_key.idx >= N || user_key.idx < 0 || user_key.gen == 0) &&
		user_key.gen == m.keys[user_key.idx].gen \
	)
}

// Returns number of used slots
@(require_results)
fixed_slot_map_len :: #force_inline proc "contextless" (
	m: ^FixedSlotMap($N, $T, $KT/Key),
) -> uint {
	return m.size
}


@(private = "file")
is_slot_map_full :: #force_inline proc "contextless" (m: ^FixedSlotMap($N, $T, $KT/Key)) -> bool {
	// Means there is only 1 slot left in the free list
	// We keep 1 slot free to not mess the free list
	return m.free_list_head == m.free_list_tail
}


// Generate user Key (! Not the same as the Key in the Indices array !)
// Its index should point to the Key in the Key array
// Its gen should match the gen from the Key in array
@(private = "file")
generate_new_user_key :: #force_inline proc "contextless" (
	m: ^FixedSlotMap($N, $T, $KT/Key),
) -> KT {
	return KT{idx = m.free_list_head, gen = m.keys[m.free_list_head].gen}
}


// Helper method to convert a user passed Key to its corresponding one in the Key array
// The user Key index basically points to it  
@(private = "file")
user_key_get_array_key_ptr :: #force_inline proc "contextless" (
	m: ^FixedSlotMap($N, $T, $KT/Key),
	key: KT,
) -> ^KT {
	return &m.keys[key.idx]
}


// Helper method to create a slot
@(private = "file")
create_slot :: #force_inline proc "contextless" (
	m: ^FixedSlotMap($N, $T, $KT/Key),
	user_key: ^KT,
) {
	// Save the index of the index of the current head
	next_free_slot_idx := m.keys[m.free_list_head].idx

	// Use the Key slot pointed by the free list head
	new_slot := &m.keys[m.free_list_head]
	// We now make it point to the last slot of the data array
	new_slot.idx = m.size

	// Save the index position of the Key in the Keys array in the erase array
	m.erase[m.size] = user_key.idx

	// Update the free head list to point to the next free slot in the Key array
	m.free_list_head = next_free_slot_idx

	m.size += 1
}


// Helper method to delete a slot
@(private = "file")
delete_slot :: #force_inline proc "contextless" (
	m: ^FixedSlotMap($N, $T, $KT/Key),
	key: ^KT,
	user_key: KT,
) {
	m.size -= 1

	// Overwrite the data of the deleted slot with the data from the last slot
	m.data[key.idx] = m.data[m.size]
	// Same for the erase array, to keep them at the same position in their respective arrays
	m.erase[key.idx] = m.erase[m.size]


	// Since the erase array contains the index of the correspondant Key in the Key array, we just have to change 
	// the index of the Key pointed by the erase value to make this same Key points correctly to its moved data
	m.keys[m.erase[key.idx]].idx = key.idx


	// Free the key, makes it the tail of the free list
	key.idx = user_key.idx
	key.gen += 1

	// Update the free list tail
	m.keys[m.free_list_tail].idx = key.idx
	m.free_list_tail = key.idx
}
