package slot_map

import "base:intrinsics"

// Only works with int for now
Handle :: struct($T: typeid) where intrinsics.type_is_integer(T) {
	idx: T,
	gen: T,
}

// Fixed Size Dense Slot Map
// Of size N ( > 0 )
// Type T
// Handle of type HT
// Not protected against gen overflow
// Uses handle.gen = 0 as error value
FixedSlotMap :: struct($N: int, $T: typeid, $HT: typeid) where N > 0 {
	size:           int,
	cap:            int,
	// Array of every possible Handle
	// Unused Handles are used as an in place free list
	handles:        [N]HT,
	free_list_head: int,
	// TODO: Remove, not needed for fixed size array I think
	free_list_tail: int,
	// Used to keep track of the data of a given Handle when deleting
	erase:          [N]int,
	data:           [N]T,
}

fixed_slot_map_init :: proc "contextless" (m: ^FixedSlotMap($N, $T, $HT/Handle)) {
	m.cap = N

	for &handle, i in m.handles {
		handle.idx = i + 1
		handle.gen = 1
	}

	m.free_list_head = 0
	m.free_list_tail = N - 1

	// Last element points on itself 
	m.handles[m.free_list_tail].idx = N - 1

	for &e in m.erase {
		// Use -1 as uninitialized value
		e = -1
	}
}

// Get a slot in the SlotMap 
@(require_results)
fixed_slot_map_new_handle :: proc "contextless" (
	m: ^FixedSlotMap($N, $T, $HT/Handle),
) -> (
	HT,
	bool,
) #optional_ok {
	if m.size == m.cap {
		return HT{0, 0}, false
	}

	user_handle := generate_user_handle(m)

	// Save the index of the index of the current head
	next_free_slot_idx := m.handles[m.free_list_head].idx

	// Use the slot pointed by the free list head, we have to make it points to 
	// the end of the data array
	new_slot := &m.handles[m.free_list_head]
	new_slot.idx = m.size
	// Save the index position of the handle in the Handles Array
	m.erase[m.size] = user_handle.idx

	// Update the free head list to point to the next link
	m.free_list_head = next_free_slot_idx

	m.size += 1
	return user_handle, true
}

@(require_results)
fixed_slot_map_new_handle_value :: proc "contextless" (
	m: ^FixedSlotMap($N, $T, $HT/Handle),
	value: T,
) -> (
	HT,
	bool,
) #optional_ok {
	if m.size == m.cap {
		return HT{0, 0}, false
	}

	user_handle := generate_user_handle(m)

	// Save the index of the index of the current head
	next_free_slot_idx := m.handles[m.free_list_head].idx

	// Use the slot pointed by the free list head, we have to make it points to 
	// the end of the data array
	new_slot := &m.handles[m.free_list_head]
	new_slot.idx = m.size
	// Save the index position of the handle in the Handles Array
	m.erase[m.size] = user_handle.idx

	m.data[m.size] = value

	// Update the free head list to point to the next link
	m.free_list_head = next_free_slot_idx


	m.size += 1
	return user_handle, true
}

// Generate user handle (! Not the same as the handle in the Indices array !)
// Its index should point to the Handle in the Handle array
// Its gen should match the gen from the Handle in array
@(private = "file")
generate_user_handle :: #force_inline proc "contextless" (
	m: ^FixedSlotMap($N, $T, $HT/Handle),
) -> HT {
	return HT{idx = m.free_list_head, gen = m.handles[m.free_list_head].gen}
}

// ! Old data location is not cleared/zeroed
fixed_slot_map_delete_handle :: proc "contextless" (
	m: ^FixedSlotMap($N, $T, $HT/Handle),
	handle: HT,
) -> bool {
	if !fixed_slot_map_is_valid(m, handle) {
		return false
	}
	m.size -= 1

	// Retrieve the handle from the array with the handle passed by the user
	handle_from_array := &m.handles[handle.idx]

	// Copy the last used data slot to the newly freed one
	m.data[handle_from_array.idx] = m.data[m.size]
	// Same for the erase array
	m.erase[handle_from_array.idx] = m.erase[m.size]

	// Since the erase array contains the index of the correspondant Handle, we just have to replace 
	// the Handle index to point at our moved data
	m.handles[m.erase[handle_from_array.idx]].idx = m.erase[handle_from_array.idx]

	// Update the free list tail to point to this delete slot
	m.handles[m.free_list_tail].idx = handle_from_array.idx
	m.free_list_tail = handle_from_array.idx

	handle_from_array.gen += 1

	return true
}

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

	// Retrieve the handle from the array with the handle passed by the user
	handle_from_array := &m.handles[handle.idx]

	return &m.data[handle_from_array.idx], true
}

@(require_results)
fixed_slot_map_get :: #force_inline proc "contextless" (
	m: ^FixedSlotMap($N, $T, $HT/Handle),
	handle: HT,
) -> (
	^T,
	bool,
) #optional_ok {
	if !fixed_slot_map_is_valid(m, handle) {
		return nil, false
	}

	// Retrieve the handle from the array with the handle passed by the user
	handle_from_array := &m.handles[handle.idx]

	return m.data[handle_from_array.idx], true
}

@(require_results)
fixed_slot_map_is_valid :: #force_inline proc "contextless" (
	m: ^FixedSlotMap($N, $T, $HT/Handle),
	handle: HT,
) -> bool {
	if handle.idx >= N || handle.gen == 0 {
		return false
	}

	// Check if the handle's generation matches the stored generation
	return handle.gen == m.handles[handle.idx].gen
}
