package slot_map

import "base:runtime"
import "core:mem"


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
) -> (
	slot_map: DynamicSlotMap(T, KeyType),
	ok: bool,
) #optional_ok {
	DEFAULT_INITIAL_CAP :: 128

	alloc_error: runtime.Allocator_Error

	if slot_map.keys, alloc_error = make([]KeyType, DEFAULT_INITIAL_CAP); alloc_error != .None {
		return slot_map, false
	}
	if slot_map.data, alloc_error = make([]T, DEFAULT_INITIAL_CAP); alloc_error != .None {
		return slot_map, false
	}
	if slot_map.erase, alloc_error = make([]uint, DEFAULT_INITIAL_CAP); alloc_error != .None {
		return slot_map, false
	}

	slot_map.capacity = DEFAULT_INITIAL_CAP

	for i: uint = 0; i < DEFAULT_INITIAL_CAP; i += 1 {
		slot_map.keys[i].idx = i + 1
		slot_map.keys[i].gen = 1
	}

	slot_map.free_list_head = 0
	slot_map.free_list_tail = DEFAULT_INITIAL_CAP - 1

	// Last element points on itself 
	slot_map.keys[slot_map.free_list_tail].idx = DEFAULT_INITIAL_CAP - 1

	return slot_map, true
}


@(require_results)
dynamic_slot_map_make_cap :: #force_inline proc(
	$T: typeid,
	$KeyType: typeid,
	$INITIAL_CAP: uint,
) -> (
	slot_map: DynamicSlotMap(T, KeyType),
	ok: bool,
) where INITIAL_CAP >
	1 #optional_ok {
	alloc_error: runtime.Allocator_Error

	if slot_map.keys, alloc_error = make([]KeyType, INITIAL_CAP); alloc_error != .None {
		return slot_map, false
	}
	if slot_map.data, alloc_error = make([]T, INITIAL_CAP); alloc_error != .None {
		return slot_map, false
	}
	if slot_map.erase, alloc_error = make([]uint, INITIAL_CAP); alloc_error != .None {
		return slot_map, false
	}

	slot_map.capacity = INITIAL_CAP

	for i: uint = 0; i < INITIAL_CAP; i += 1 {
		slot_map.keys[i].idx = i + 1
		slot_map.keys[i].gen = 1
	}

	slot_map.free_list_head = 0
	slot_map.free_list_tail = INITIAL_CAP - 1

	// Last element points on itself 
	slot_map.keys[slot_map.free_list_tail].idx = INITIAL_CAP - 1

	return slot_map, true
}


dynamic_slot_map_delete :: #force_inline proc(m: ^DynamicSlotMap($T, $KeyType/Key)) {
	delete(m.keys)
	delete(m.data)
	delete(m.erase)
}


// Try and get a Slot, returning a Key to this slot \
// This should only fails when there is an Allocation Error \
// Operation is O(1) unless the Slot Map has to realloc
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
	assert(growth_factor > 1, "Dynamic Slot Map insert: Growth factor must be > 1.0")

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

	// Means we have only 1 free Slot left
	// It's our condition to re-alloc bigger arrays and move everything
	if m.free_list_head == m.free_list_tail {
		current_cap := m.capacity
		new_cap := uint(growth_factor * f64(m.capacity))
		// Ensure we are growing by at least 1
		if current_cap == new_cap {
			new_cap += 1
		}
		m.capacity = new_cap

		if new_keys, error := make([]KeyType, uint(new_cap)); error != .None {
			return KeyType{}, false
		} else {
			mem.copy(&new_keys[0], &m.keys[0], int(current_cap) * size_of(KeyType))
			delete(m.keys)
			m.keys = new_keys

			// m.free_list_head = current_cap
			m.free_list_tail = new_cap - 1

			for i := current_cap; i < new_cap; i += 1 {
				m.keys[i].idx = i + 1
				m.keys[i].gen = 1
			}

			m.keys[m.free_list_head].idx = current_cap
			m.keys[m.free_list_tail].idx = new_cap - 1
		}

		if new_data, error := make([]T, uint(new_cap)); error != .None {
			return KeyType{}, false
		} else {
			mem.copy(&new_data[0], &m.data[0], int(current_cap) * size_of(T))
			delete(m.data)
			m.data = new_data
		}

		if new_erase, error := make([]uint, uint(new_cap)); error != .None {
			return KeyType{}, false
		} else {
			mem.copy(&new_erase[0], &m.erase[0], int(current_cap) * size_of(uint))
			delete(m.erase)
			m.erase = new_erase
		}
	}

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
