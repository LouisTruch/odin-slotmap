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


@(test)
fixed_map_struct_test :: proc(t: ^testing.T) {
	Entity :: struct {
		name:      string,
		position:  ^[3]f32, // Heap allocated position
		health:    int,
		is_active: bool,
	}

	make_entity :: proc(name: string, x, y, z: f32, health: int) -> Entity {
		pos := new([3]f32)
		pos^ = [3]f32{x, y, z}
		return Entity{name = name, position = pos, health = health, is_active = true}
	}

	destroy_entity :: proc(entity: ^Entity) {
		free(entity.position)
		entity^ = Entity{}
	}


	struct_test :: proc(t: ^testing.T) {
		slot_map: FixedSlotMap(10, Entity, Handle(int))
		fixed_slot_map_init(&slot_map)

		// Create and insert entities
		player := make_entity("Player", 0, 0, 0, 100)
		enemy := make_entity("Enemy", 10, 0, 10, 50)

		player_handle, ok1 := fixed_slot_map_new_handle_value(&slot_map, player)
		testing.expect(t, ok1, "Player insertion should succeed")

		enemy_handle, ok2 := fixed_slot_map_new_handle_value(&slot_map, enemy)
		testing.expect(t, ok2, "Enemy insertion should succeed")

		// Test accessing and modifying data
		if player_ptr, ok := fixed_slot_map_get_ptr(&slot_map, player_handle); ok {
			testing.expect(t, player_ptr.name == "Player", "Name should match")
			testing.expect(t, player_ptr.health == 100, "Health should match")
			testing.expect(t, player_ptr.position^[0] == 0, "Position X should match")

			// Modify the entity
			player_ptr.health -= 30
			player_ptr.position^[0] = 5
		} else {
			testing.fail(t)
		}

		// Verify modifications
		if player_data, ok := fixed_slot_map_get(&slot_map, player_handle); ok {
			testing.expect(t, player_data.health == 70, "Modified health should persist")
			testing.expect(t, player_data.position^[0] == 5, "Modified position should persist")
		}

		// Test deletion with cleanup
		if enemy_ptr, ok := fixed_slot_map_get_ptr(&slot_map, enemy_handle); ok {
			destroy_entity(enemy_ptr)
		}
		fixed_slot_map_delete_handle(&slot_map, enemy_handle)

		// Test reuse of slot
		npc := make_entity("NPC", -5, 0, -5, 30)
		new_handle, ok3 := fixed_slot_map_new_handle_value(&slot_map, npc)
		testing.expect(t, ok3, "Insertion into freed slot should succeed")

		if npc_ptr, ok := fixed_slot_map_get_ptr(&slot_map, new_handle); ok {
			testing.expect(t, npc_ptr.name == "NPC", "New entity should be accessible")
		}

		// Cleanup remaining entities
		if player_ptr, ok := fixed_slot_map_get_ptr(&slot_map, player_handle); ok {
			destroy_entity(player_ptr)
		}
		if npc_ptr, ok := fixed_slot_map_get_ptr(&slot_map, new_handle); ok {
			destroy_entity(npc_ptr)
		}
	}


	struct_test(t)
}
