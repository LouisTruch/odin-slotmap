package slot_map

import "core:math/rand"
import "core:testing"


@(test)
handle_pack_test :: proc(t: ^testing.T) {
	{
		handle := Handle(int){42, 26}

		packed_ptr := handle_pack(handle)
		unpacked := handle_unpack(packed_ptr)

		testing.expect(t, unpacked.idx == handle.idx)
		testing.expect(t, unpacked.gen == handle.gen)
	}
	{
		handle := Handle(int) {
			idx = 0xFFFFFFFF,
			gen = 0xFFFFFFFF,
		}
		packed_ptr := handle_pack(handle)
		unpacked := handle_unpack(packed_ptr)

		testing.expect(t, unpacked.idx == handle.idx)
		testing.expect(t, unpacked.gen == handle.gen)
	}
	{
		handle := Handle(int) {
			idx = 0,
			gen = 0,
		}
		packed_ptr := handle_pack(handle)
		unpacked := handle_unpack(packed_ptr)

		testing.expect(t, unpacked.idx == handle.idx)
		testing.expect(t, unpacked.gen == handle.gen)
	}
}

@(test)
fixed_slot_map_make_test :: proc(t: ^testing.T) {
	N :: 5
	slot_map := fixed_slot_map_make(N, int, Handle(int))

	testing.expect(t, slot_map.size == 0, "Initial size should be 0")
	testing.expect(t, slot_map.free_list_head == 0, "Free list head should start at 0")
	testing.expect(t, slot_map.free_list_tail == 4, "Free list tail should be N-1")

	// Check if handles are properly initialized
	for handle, i in slot_map.handles {
		testing.expect(t, handle.gen == 1, "Initial generation should be 1")
		if i < N - 1 {
			testing.expect(t, handle.idx == i + 1, "Handle should point to next slot")
		} else {
			testing.expect(t, handle.idx == i, "Last handle should point to itself")
		}
	}
}


@(test)
fixed_slot_map_clear_test :: proc(t: ^testing.T) {
	CoolStruct :: struct {
		v: int,
		p: ^int,
	}
	HandleCoolStruct :: distinct Handle(int)

	STRUCT_MAX :: 6

	slot_map: FixedSlotMap(STRUCT_MAX, CoolStruct, HandleCoolStruct)
	fixed_slot_map_init(&slot_map)

	cool_struct_array: [STRUCT_MAX]CoolStruct
	for i in 0 ..< STRUCT_MAX {
		cool_struct_array[i].v = i
		cool_struct_array[i].p = &cool_struct_array[i].v
		_ = fixed_slot_map_new_handle_value(&slot_map, cool_struct_array[i])
	}

	for i in 0 ..< STRUCT_MAX - 1 {
		testing.expect(t, slot_map.data[i].v == cool_struct_array[i].v)
		testing.expect(t, slot_map.data[i].p == cool_struct_array[i].p)
	}

	fixed_slot_map_clear(&slot_map)
	testing.expect(t, slot_map.size == 0)

	for i in 0 ..< STRUCT_MAX - 1 {
		testing.expect(t, slot_map.data[i].v == 0)
		testing.expect(t, slot_map.data[i].p == nil)
	}
}

@(test)
fixed_slot_map_insert_test :: proc(t: ^testing.T) {
	N :: 5
	slot_map: FixedSlotMap(N, int, Handle(int))
	fixed_slot_map_init(&slot_map)

	handle1, ok1 := fixed_slot_map_new_handle_value(&slot_map, 42)
	testing.expect(t, slot_map.size == 1, "Size should be 1 after first insertion")
	testing.expect(t, slot_map.free_list_head == 1, "Head should have advanced by one")
	testing.expect(t, slot_map.free_list_tail == 4, "Tail should not move")

	value1, ok2 := fixed_slot_map_get_ptr(&slot_map, handle1)
	testing.expect(t, ok2, "Should be able to get first value")
	testing.expect(t, value1^ == 42, "Retrieved value should match inserted value")

	// Test filling the slot_map
	handles: [N - 1]Handle(int)
	for i in 1 ..< N - 1 {
		h, ok := fixed_slot_map_new_handle_value(&slot_map, i * 10)
		testing.expect(t, ok, "Insert within N - 1 should succeed")
		handles[i] = h
	}

	// Test insertion when full
	_, ok3 := fixed_slot_map_new_handle_value(&slot_map, 100)
	testing.expect(t, !ok3, "Insert when full should fail")
}


@(test)
fixed_slot_map_insert_value_test :: proc(t: ^testing.T) {
	N :: 5
	slot_map := fixed_slot_map_make(N, int, Handle(int))

	handle1, _ := fixed_slot_map_new_handle_value(&slot_map, 999)

	value1, _ := fixed_slot_map_get(&slot_map, handle1)

	testing.expect(t, value1 == 999, "Value not set correctly")
	testing.expect(t, slot_map.data[0] == 999, "Value not set correctly")
}


@(test)
fixed_slot_map_insert_ptr_test :: proc(t: ^testing.T) {
	N :: 5
	slot_map := fixed_slot_map_make(N, int, Handle(int))

	handle1, ptr1, _ := fixed_slot_map_new_handle_get_ptr(&slot_map)
	ptr1^ = 999
	testing.expect(t, slot_map.data[0] == 999, "Value not set correctly")
}


@(test)
fixed_slot_map_delete_test :: proc(t: ^testing.T) {
	slot_map: FixedSlotMap(5, int, Handle(int))
	fixed_slot_map_init(&slot_map)

	handle1, _ := fixed_slot_map_new_handle_value(&slot_map, 10)
	handle2, _ := fixed_slot_map_new_handle_value(&slot_map, 20)
	handle3, _ := fixed_slot_map_new_handle_value(&slot_map, 30)

	ok := fixed_slot_map_delete_handle(&slot_map, handle1)
	testing.expect(t, ok, "Deletion should succeed")
	testing.expect(t, slot_map.size == 2, "Size should decrease after deletion")
	// Deleted first handle so the last one gets its slot
	testing.expect(t, slot_map.data[0] == 30, "Data was not correctly moved")
	testing.expect(t, slot_map.free_list_tail == 0, "Tail was not set properly")
	testing.expect(
		t,
		slot_map.handles[slot_map.free_list_tail].idx == 0,
		"Tail was not set properly",
	)
	testing.expect(
		t,
		slot_map.free_list_head != slot_map.free_list_tail,
		"Tail was not set properly",
	)

	_, ok2 := fixed_slot_map_get(&slot_map, handle1)
	testing.expect(t, !ok2, "Deleted handle should be invalid")

	// Test that we can still access other values
	moved_value, ok3 := fixed_slot_map_get(&slot_map, handle3)
	testing.expect(t, ok3, "Non-deleted handle should still be valid")
	testing.expect(t, moved_value == 30, "Non-deleted value should be unchanged")
}


@(test)
fixed_slot_map_delete_value_test :: proc(t: ^testing.T) {
	slot_map: FixedSlotMap(5, int, Handle(int))
	fixed_slot_map_init(&slot_map)

	handle1, _ := fixed_slot_map_new_handle_value(&slot_map, 10)
	handle2, _ := fixed_slot_map_new_handle_value(&slot_map, 20)
	handle3, _ := fixed_slot_map_new_handle_value(&slot_map, 30)

	value1, ok := fixed_slot_map_delete_handle_value(&slot_map, handle1)
	testing.expect(t, value1 == 10, "Deleted value is not correct")
}


@(test)
fixed_slot_map_valid_test :: proc(t: ^testing.T) {
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


@(test)
fixed_slot_map_struct_with_ptr_test :: proc(t: ^testing.T) {
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
			player_ptr.health = 70
			player_ptr.position^[0] = 5
		} else {
			testing.expect(t, false, "Could not retrieve ptr from slot_map")
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


@(test)
fixed_slot_map_insert_delete_test :: proc(t: ^testing.T) {
	N :: 4
	slot_map := fixed_slot_map_make(N, int, Handle(int))

	handle1, ok1 := fixed_slot_map_new_handle_value(&slot_map, 10)
	handle2, ok2 := fixed_slot_map_new_handle_value(&slot_map, 20)
	handle3, ok3 := fixed_slot_map_new_handle_value(&slot_map, 30)
	// Slot Map has N - 1 slots so can't use the 4th one
	handle4, ok4 := fixed_slot_map_new_handle(&slot_map)
	testing.expect(t, ok4 == false, "Should not be able to fill the slot map completly")

	// There Head and Tail should be = 3
	testing.expect(t, slot_map.free_list_head == 3)
	testing.expect(t, slot_map.free_list_tail == 3)

	// Delete the second slot, so last slot is moved to [1]
	ok2 = fixed_slot_map_delete_handle(&slot_map, handle2)
	testing.expect(t, slot_map.data[1] == 30)
	testing.expect(t, slot_map.free_list_head == 3)
	testing.expect(t, slot_map.free_list_tail == 1)

	handle4, ok4 = fixed_slot_map_new_handle_value(&slot_map, 40)
	testing.expect(t, slot_map.data[2] == 40)
	testing.expect(t, slot_map.free_list_head == 1)
	testing.expect(t, slot_map.free_list_tail == 1)

	ok1 = fixed_slot_map_delete_handle(&slot_map, handle1)
	testing.expect(t, slot_map.data[0] == 40)
	testing.expect(t, slot_map.free_list_tail == 0)
}


@(test)
fixed_slot_map_random_insert_delete_test :: proc(t: ^testing.T) {
	N :: 1000
	slot_map := fixed_slot_map_make(N, int, Handle(int))

	handles := make([dynamic]Handle(int))
	defer delete(handles)

	Operation :: enum {
		Ins,
		Del,
	}
	random_ope :: proc() -> Operation {
		opes := [2]Operation{.Ins, .Del}
		return rand.choice(opes[:])
	}

	TURNS :: 1000
	for _ in 0 ..< TURNS {
		ope := random_ope()

		switch ope {
		case .Ins:
			new_handle, ok := fixed_slot_map_new_handle_value(&slot_map, 0)
			if ok {
				append(&handles, new_handle)

				// Check for collisions, 2 same Handles should never be returned
				for handle1, i in handles {
					for handle2, j in handles {
						if i == j {
							continue
						}

						testing.expectf(
							t,
							handle1 != handle2,
							"Slot Map returned 2 times the same Handle {%i %i}",
							handle1.idx,
							handle1.gen,
						)
					}
				}
			}
		case .Del:
			if len(handles) > 0 {
				testing.expect(t, len(handles) == slot_map.size)

				idx := rand.int_max(max(int)) % len(handles)
				handle := handles[idx]
				unordered_remove(&handles, idx)

				old_tail := slot_map.free_list_tail
				ok := fixed_slot_map_delete_handle(&slot_map, handle)
				testing.expect(t, ok)

				pointed_handle_idx := handle.idx
				new_tail := slot_map.free_list_tail
				testing.expect(t, new_tail == pointed_handle_idx)
			}
		}
	}
}
