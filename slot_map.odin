package slot_map

import "base:intrinsics"

// Only works with int for now
Handle :: struct($T: typeid) where intrinsics.type_is_integer(T) {
	idx: T,
	gen: T,
}


// Allows to store a 64 bits Handle in a ptr
@(require_results)
pack_handle :: #force_inline proc "contextless" (handle: Handle(int)) -> rawptr {
	packed := (u64(handle.gen) << 32) | u64(handle.idx)
	return rawptr(uintptr(packed))
}
@(require_results)
unpack_handle :: #force_inline proc "contextless" (ptr: rawptr) -> Handle(int) {
	packed := u64(uintptr(ptr))
	return {idx = int(packed & 0xFFFFFFFF), gen = int(packed >> 32)}
}


// Fixed Size Dense Slot Map
// Of size N ( > 0 ) ! It can't be full, max used slots is N - 1
// Type T
// Handle of type HT
// Not protected against gen overflow
// Uses handle.gen = 0 as error value
// It makes 0 allocation since the arrays are of fixed size
// You should be careful about stack overflows if you don't alloc it
FixedSlotMap :: struct($N: int, $T: typeid, $HT: typeid) where N > 1 {
	size:           int,
	free_list_head: int,
	free_list_tail: int,
	// Array of every possible Handle
	// Unused Handles are used as an in place free list
	handles:        [N]HT,
	// Used to keep track of the data of a given Handle when deleting
	erase:          [N]int,
	data:           [N]T,
}


// Returns an initialized slot map
@(require_results)
fixed_slot_map_make :: #force_inline proc "contextless" (
	$N: int,
	$T: typeid,
	$HT: typeid,
) -> (
	slot_map: FixedSlotMap(N, T, HT),
) {
	fixed_slot_map_init(&slot_map)
	return slot_map
}


fixed_slot_map_init :: #force_inline proc "contextless" (m: ^FixedSlotMap($N, $T, $HT/Handle)) {
	for &handle, i in m.handles {
		handle.idx = i + 1
		handle.gen = 1
	}

	m.free_list_head = 0
	m.free_list_tail = N - 1

	// Last element points on itself 
	m.handles[m.free_list_tail].idx = N - 1

	m.erase = -1
}


fixed_slot_map_clear :: #force_inline proc "contextless" (m: ^FixedSlotMap($N, $T, $HT/Handle)) {
	m.size = 0
	for &handle, i in m.handles {
		handle.idx = i + 1
		handle.gen = 1
	}
	m.erase = -1
	m.data = {}
}


// Asks the slot map for a new Handle
// Return said Handle and a boolean indicating the success or not of the operation
@(require_results)
fixed_slot_map_new_handle :: proc "contextless" (
	m: ^FixedSlotMap($N, $T, $HT/Handle),
) -> (
	HT,
	bool,
) #optional_ok {
	// Means there is only 1 slot left in the free list, 
	if m.free_list_head == m.free_list_tail {
		return HT{0, 0}, false
	}

	user_handle := generate_new_user_handle(m)

	create_slot(m, &user_handle)

	return user_handle, true
}


// Asks the slot map for a new Handle
// Return said Handle, a pointer to the beginning of data in the slot map and a boolean indicating the success or not of the operation
@(require_results)
fixed_slot_map_new_handle_get_ptr :: proc "contextless" (
	m: ^FixedSlotMap($N, $T, $HT/Handle),
) -> (
	HT,
	^T,
	bool,
) {
	// Means there is only 1 slot left in the free list, 
	if m.free_list_head == m.free_list_tail {
		return HT{0, 0}, false
	}

	user_handle := generate_new_user_handle(m)

	create_slot(m, &user_handle)

	return user_handle, &m.data[m.size - 1], true
}


// Asks the slot map for a new Handle and put the data you pass in the slot map
// Return said Handle and a boolean indicating the success or not of the operation
@(require_results)
fixed_slot_map_new_handle_value :: proc "contextless" (
	m: ^FixedSlotMap($N, $T, $HT/Handle),
	data: T,
) -> (
	HT,
	bool,
) #optional_ok {
	// Means there is only 1 slot left in the free list, 
	if m.free_list_head == m.free_list_tail {
		return HT{0, 0}, false
	}

	user_handle := generate_new_user_handle(m)

	// Copy the passed data in the data array
	m.data[m.size] = data

	create_slot(m, &user_handle)

	return user_handle, true
}


// Try to give back the Handle and a slot of data to the slot map
// The Handle might has already been given back
// The return value confirms the success of the deletion, or not
// ! This makes data move in the slot map, old data is not cleared !
fixed_slot_map_delete_handle :: proc "contextless" (
	m: ^FixedSlotMap($N, $T, $HT/Handle),
	user_handle: HT,
) -> bool {
	if !fixed_slot_map_is_valid(m, user_handle) {
		return false
	}

	delete_slot(m, user_handle)

	return true
}


// Try to give back the Handle and a slot of data to the slot map
// The Handle might has already been given back
// Returns a copy of the deleted data, and the success or not of the operation
// ! This makes data move in the slot map, old data is not cleared !
fixed_slot_map_delete_handle_value :: proc "contextless" (
	m: ^FixedSlotMap($N, $T, $HT/Handle),
	user_handle: HT,
) -> (
	T,
	bool,
) #optional_ok {
	if !fixed_slot_map_is_valid(m, user_handle) {
		return {}, false
	}

	handle_from_array := user_handle_get_array_handle_ptr(m, user_handle)

	// Make a copy of the deleted data before overwriting it
	deleted_data_copy := m.data[handle_from_array.idx]

	delete_slot(m, handle_from_array)

	return deleted_data_copy, true
}


// If the Handle is valid, returns a ptr to the data
@(require_results)
fixed_slot_map_get_ptr :: #force_inline proc "contextless" (
	m: ^FixedSlotMap($N, $T, $HT/Handle),
	handle: HT,
) -> (
	^T,
	bool,
) #optional_ok {
	if !fixed_slot_map_is_valid(m, handle) {
		return nil, false
	}

	handle_from_array := user_handle_get_array_handle_ptr(m, handle)

	return &m.data[handle_from_array.idx], true
}


// If the Handle is valid, returns a copy of the data
@(require_results)
fixed_slot_map_get :: #force_inline proc "contextless" (
	m: ^FixedSlotMap($N, $T, $HT/Handle),
	handle: HT,
) -> (
	T,
	bool,
) #optional_ok {
	if !fixed_slot_map_is_valid(m, handle) {
		return {}, false
	}

	handle_from_array := user_handle_get_array_handle_ptr(m, handle)

	return m.data[handle_from_array.idx], true
}


// Check if the user Handle is valid
// First by manual bound check
// Then by checking if the generation is the same
@(require_results)
fixed_slot_map_is_valid :: #force_inline proc "contextless" (
	m: ^FixedSlotMap($N, $T, $HT/Handle),
	handle: HT,
) -> bool #no_bounds_check {
	return(
		!(handle.idx >= N || handle.idx < 0 || handle.gen == 0) &&
		handle.gen == m.handles[handle.idx].gen \
	)
}


// Generate user handle (! Not the same as the handle in the Indices array !)
// Its index should point to the Handle in the Handle array
// Its gen should match the gen from the Handle in array
@(private = "file")
generate_new_user_handle :: #force_inline proc "contextless" (
	m: ^FixedSlotMap($N, $T, $HT/Handle),
) -> HT {
	return HT{idx = m.free_list_head, gen = m.handles[m.free_list_head].gen}
}


// Helper method to convert a user passed Handle to its corresponding one in the Handle array
// The user Handle index basically points to it  
@(private = "file")
user_handle_get_array_handle_ptr :: #force_inline proc "contextless" (
	m: ^FixedSlotMap($N, $T, $HT/Handle),
	handle: HT,
) -> ^HT {
	return &m.handles[handle.idx]
}


// Helper method to create a slot
@(private = "file")
create_slot :: #force_inline proc "contextless" (
	m: ^FixedSlotMap($N, $T, $HT/Handle),
	user_handle: ^HT,
) {
	// Save the index of the index of the current head
	next_free_slot_idx := m.handles[m.free_list_head].idx

	// Use the Handle slot pointed by the free list head
	new_slot := &m.handles[m.free_list_head]
	// We now make it point to the last slot of the data array
	new_slot.idx = m.size

	// Save the index position of the Handle in the Handles array in the erase array
	m.erase[m.size] = user_handle.idx

	// Update the free head list to point to the next free slot in the Handle array
	m.free_list_head = next_free_slot_idx

	m.size += 1
}


// Helper method to delete a slot
@(private = "file")
delete_slot :: #force_inline proc "contextless" (
	m: ^FixedSlotMap($N, $T, $HT/Handle),
	user_handle: HT,
) {
	handle := user_handle_get_array_handle_ptr(m, user_handle)

	m.size -= 1

	// Overwrite the data of the deleted slot with the data from the last slot
	m.data[handle.idx] = m.data[m.size]
	// Same for the erase array, to keep them at the same position in their respective arrays
	m.erase[handle.idx] = m.erase[m.size]


	// Since the erase array contains the index of the correspondant Handle in the Handle array, we just have to change 
	// the index of the Handle pointed by the erase value to make this same Handle points correctly to its moved data
	m.handles[m.erase[handle.idx]].idx = handle.idx


	// Free the handle, makes it the tail of the free list
	handle.idx = user_handle.idx
	handle.gen += 1

	// Update the free list tail
	m.handles[m.free_list_tail].idx = handle.idx
	m.free_list_tail = handle.idx
}
