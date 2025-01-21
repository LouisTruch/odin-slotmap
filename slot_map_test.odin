package slot_map

import "core:testing"

@(test)
fixed_map_test :: proc(t: ^testing.T) {
	init_test :: proc(t: ^testing.T) {
		slot_map: FixedSlotMap(5, int, Handle(int))
		fixed_slot_map_init(&slot_map)

		testing.expect(t, slot_map.size == 0, "Initial size should be 0")
		testing.expect(t, slot_map.free_list_head == 0, "Free list head should start at 0")
		testing.expect(t, slot_map.free_list_tail == 4, "Free list tail should be N-1")

		// Check if handles are properly initialized
		for handle, i in slot_map.handles {
			testing.expect(t, handle.gen == 1, "Initial generation should be 1")
			if i < len(slot_map.handles) - 1 {
				testing.expect(t, handle.idx == i + 1, "Handle should point to next slot")
			} else {
				testing.expect(t, handle.idx == i, "Last handle should point to itself")
			}
		}
	}

	insertion_test :: proc(t: ^testing.T) {
		slot_map: FixedSlotMap(5, int, Handle(int))
		fixed_slot_map_init(&slot_map)

		handle1, ok1 := fixed_slot_map_new_handle_value(&slot_map, 42)
		testing.expect(t, ok1, "First insertion should succeed")
		testing.expect(t, slot_map.size == 1, "Size should be 1 after first insertion")

		value1, ok2 := fixed_slot_map_get_ptr(&slot_map, handle1)
		testing.expect(t, ok2, "Should be able to get first value")
		testing.expect(t, value1^ == 42, "Retrieved value should match inserted value")

		// Test filling the slot_map
		handles: [5]Handle(int)
		for i in 1 ..< 5 {
			h, ok := fixed_slot_map_new_handle_value(&slot_map, i * 10)
			testing.expect(t, ok, "Insertion within capacity should succeed")
			handles[i] = h
		}

		// Test insertion when full
		_, ok3 := fixed_slot_map_new_handle_value(&slot_map, 100)
		testing.expect(t, !ok3, "Insertion when full should fail")
	}

	deletion_test :: proc(t: ^testing.T) {
		slot_map: FixedSlotMap(5, int, Handle(int))
		fixed_slot_map_init(&slot_map)

		handle1, _ := fixed_slot_map_new_handle_value(&slot_map, 42)
		handle2, _ := fixed_slot_map_new_handle_value(&slot_map, 43)

		ok := fixed_slot_map_delete_handle(&slot_map, handle1)
		testing.expect(t, ok, "Deletion should succeed")
		testing.expect(t, slot_map.size == 1, "Size should decrease after deletion")

		// Test that the handle is invalid after deletion
		_, ok2 := fixed_slot_map_get(&slot_map, handle1)
		testing.expect(t, !ok2, "Deleted handle should be invalid")

		// Test that we can still access other values
		value2, ok3 := fixed_slot_map_get_ptr(&slot_map, handle2)
		testing.expect(t, ok3, "Non-deleted handle should still be valid")
		testing.expect(t, value2^ == 43, "Non-deleted value should be unchanged")
	}

	// Test handle validation
	validation_test :: proc(t: ^testing.T) {
		slot_map: FixedSlotMap(5, int, Handle(int))
		fixed_slot_map_init(&slot_map)

		// Test invalid handle
		invalid_handle := Handle(int) {
			idx = 999,
			gen = 1,
		}
		testing.expect(
			t,
			!fixed_slot_map_is_valid(&slot_map, invalid_handle),
			"Invalid index should be rejected",
		)

		// Test generation mismatch
		handle1, _ := fixed_slot_map_new_handle_value(&slot_map, 42)
		invalid_gen_handle := Handle(int) {
			idx = handle1.idx,
			gen = handle1.gen + 1,
		}
		testing.expect(
			t,
			!fixed_slot_map_is_valid(&slot_map, invalid_gen_handle),
			"Generation mismatch should be rejected",
		)
	}

	// Run all tests
	init_test(t)
	insertion_test(t)
	deletion_test(t)
	validation_test(t)
}
