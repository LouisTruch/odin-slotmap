package slot_map

import "base:runtime"
import "core:mem"


// TODO Allow explicit passing of allocator ? To be able to make all the procs "contextless"


// Dynamic Dense Slot Map \
// Its internal arrays are always on the heap \
// It can only grow and never shrinks \
// Uses key.gen = 0 as error value 
DynamicSlotMap :: struct($T: typeid, $KeyType: typeid) {
	size:           uint,
	capacity:       uint,
	free_list_head: uint,
	free_list_tail: uint,
	keys:           []KeyType,
	data:           []T,
	erase:          []uint,
}


@(require_results)
dynamic_slot_map_make :: #force_inline proc(
	$T: typeid,
	$KeyType: typeid,
	initial_cap: uint,
) -> (
	slot_map: DynamicSlotMap(T, KeyType),
	ok: bool,
) #optional_ok {
	alloc_error: runtime.Allocator_Error

	if slot_map.keys, alloc_error = make([]KeyType, initial_cap); alloc_error != .None {
		return slot_map, false
	}
	if slot_map.data, alloc_error = make([]T, initial_cap); alloc_error != .None {
		return slot_map, false
	}
	if slot_map.erase, alloc_error = make([]uint, initial_cap); alloc_error != .None {
		return slot_map, false
	}

	slot_map.capacity = initial_cap

	for i: uint = 0; i < initial_cap; i += 1 {
		slot_map.keys[i].idx = i + 1
		slot_map.keys[i].gen = 1
	}

	slot_map.free_list_head = 0
	slot_map.free_list_tail = initial_cap - 1

	// Last element points on itself 
	slot_map.keys[slot_map.free_list_tail].idx = initial_cap - 1

	return slot_map, true
}


// TODO Add return value to see if delete worked
dynamic_slot_map_delete :: #force_inline proc(m: ^DynamicSlotMap($T, $KeyType/Key)) {
	delete(m.keys)
	delete(m.data)
	delete(m.erase)
}


// Try and get a Slot, returning a Key to this slot \
// This should only fails when there is an Allocation Error \
// Operation is O(1) unless the Slot Map has to realloc \
@(require_results)
dynamic_slot_map_insert :: proc(
	m: ^DynamicSlotMap($T, $KeyType/Key),
	growth_factor: f64 = 1.5,
) -> (
	KeyType,
	bool,
) #optional_ok {
	return insert_internal(m, growth_factor)
}


@(require_results)
dynamic_slot_map_insert_set :: proc(
	m: ^DynamicSlotMap($T, $KeyType/Key),
	data: T,
	growth_factor: f64 = 1.5,
) -> (
	user_key: KeyType,
	ok: bool,
) #optional_ok {
	user_key = insert_internal(m, growth_factor) or_return

	m.data[m.keys[user_key.idx].idx] = data

	return user_key, true
}


@(require_results)
dynamic_slot_map_insert_get_ptr :: proc(
	m: ^DynamicSlotMap($T, $KeyType/Key),
	growth_factor: f64 = 1.5,
) -> (
	user_key: KeyType,
	ptr: ^T,
	ok: bool,
) {
	user_key = insert_internal(m, growth_factor) or_return

	return user_key, &m.data[m.size - 1], true
}


@(private = "file")
@(require_results)
insert_internal :: #force_inline proc(
	m: ^DynamicSlotMap($T, $KeyType/Key),
	growth_factor: f64 = 1.5,
) -> (
	KeyType,
	bool,
) {
	// Means we have only 1 slot left and it will be taken after this call
	// It's our condition to re-alloc bigger arrays
	if m.free_list_head == m.free_list_tail {
		// Move the arrays
		current_cap := int(m.capacity)
		new_cap := uint(f64(current_cap) * growth_factor)

		if new_keys, error := make([]KeyType, uint(new_cap)); error != .None {
			return KeyType{}, false
		} else {
			mem.copy(&new_keys[0], &m.keys[0], current_cap * size_of(KeyType))
			delete(m.keys)
			m.keys = new_keys

			// Rebuild the free list starting from the head
			for i := m.free_list_head; i < new_cap; i += 1 {
				new_keys[i].idx = i + 1
				new_keys[i].gen = 1
			}

			m.free_list_tail = new_cap - 1
			m.keys[m.free_list_tail].idx = new_cap - 1
		}

		if new_data, error := make([]T, uint(new_cap)); error != .None {
			return KeyType{}, false
		} else {
			mem.copy(&new_data[0], &m.data[0], current_cap * size_of(T))
			delete(m.data)
			m.data = new_data
		}

		if new_erase, error := make([]uint, uint(new_cap)); error != .None {
			return KeyType{}, false
		} else {
			mem.copy(&new_erase[0], &m.erase[0], current_cap * size_of(uint))
			delete(m.erase)
			m.erase = new_erase
		}

		m.capacity = new_cap
	}

	// Generate the user Key
	// It points to its associated Key in the Key array and has the same gen
	user_key := KeyType {
		idx = m.free_list_head,
		gen = m.keys[m.free_list_head].gen,
	}

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

	return user_key, true
}


dynamic_slot_map_remove :: proc "contextless" (
	m: ^DynamicSlotMap($T, $KeyType/Key),
	user_key: KeyType,
) -> bool {
	if !dynamic_slot_map_is_valid(m, user_key) {
		return false
	}

	key := &m.keys[user_key.idx]

	remove_internal(m, key, user_key)

	return true
}


dynamic_slot_map_remove_value :: proc "contextless" (
	m: ^DynamicSlotMap($T, $KeyType/Key),
	user_key: KeyType,
) -> (
	T,
	bool,
) #optional_ok {
	if !dynamic_slot_map_is_valid(m, user_key) {
		return {}, false
	}

	key := &m.keys[user_key.idx]

	deleted_data_copy := m.data[key.idx]

	remove_internal(m, key, user_key)

	return deleted_data_copy, true
}


@(private = "file")
remove_internal :: #force_inline proc "contextless" (
	m: ^DynamicSlotMap($T, $KeyType/Key),
	key: ^KeyType,
	user_key: KeyType,
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


dynamic_slot_map_set :: #force_inline proc "contextless" (
	m: ^DynamicSlotMap($T, $KeyType/Key),
	user_key: KeyType,
	data: T,
) -> bool {
	if !dynamic_slot_map_is_valid(m, user_key) {
		return false
	}

	key := m.keys[user_key.idx]

	m.data[key.idx] = data

	return true
}


@(require_results)
dynamic_slot_map_get :: #force_inline proc "contextless" (
	m: ^DynamicSlotMap($T, $KeyType/Key),
	user_key: KeyType,
) -> (
	T,
	bool,
) #optional_ok {
	if !dynamic_slot_map_is_valid(m, user_key) {
		return {}, false
	}

	key := m.keys[user_key.idx]

	return m.data[key.idx], true
}


@(require_results)
dynamic_slot_map_get_ptr :: #force_inline proc "contextless" (
	m: ^DynamicSlotMap($T, $KeyType/Key),
	user_key: KeyType,
) -> (
	^T,
	bool,
) #optional_ok {
	if !dynamic_slot_map_is_valid(m, user_key) {
		return nil, false
	}

	key := m.keys[user_key.idx]

	return &m.data[key.idx], true
}


@(require_results)
dynamic_slot_map_is_valid :: #force_inline proc "contextless" (
	m: ^DynamicSlotMap($T, $KeyType/Key),
	user_key: KeyType,
) -> bool #no_bounds_check {
	// Manual bound checking
	// Then check if the generation is the same
	return(
		!(user_key.idx >= m.capacity || user_key.idx < 0 || user_key.gen == 0) &&
		user_key.gen == m.keys[user_key.idx].gen \
	)
}
