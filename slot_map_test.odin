package slot_map

import "core:math/rand"
import "core:testing"


/// FIXED SLOT MAP
@(test)
key_pack_unpack_test :: proc(t: ^testing.T) {
	{
		MyKey :: distinct Key(uint, 32, 32)
		key: MyKey
		key.idx = 42
		key.gen = 36

		packed_ptr := key_pack_ptr(key)
		unpacked := key_unpack_ptr(packed_ptr, MyKey)

		testing.expect(t, unpacked.idx == key.idx)
		testing.expect(t, unpacked.gen == key.gen)
	}
	{
		MyKey :: distinct Key(uint, 24, 8)
		key: MyKey
		key.idx = 0
		key.gen = 0

		packed_ptr := key_pack_ptr(key)
		unpacked := key_unpack_ptr(packed_ptr, MyKey)

		testing.expect(t, unpacked.bits.idx == key.bits.idx)
		testing.expect(t, unpacked.bits.gen == key.bits.gen)
	}
}


@(test)
fixed_slot_map_make_test :: proc(t: ^testing.T) {
	N :: 5
	MyKey :: distinct Key(uint, 32, 32)
	slot_map := fixed_slot_map_make(N, int, MyKey)

	testing.expect(t, slot_map.size == 0, "Initial size should be 0")
	testing.expect(t, slot_map.free_list_head == 0, "Free list head should start at 0")
	testing.expect(t, slot_map.free_list_tail == 4, "Free list tail should be N-1")

	// Check if handles are properly initialized
	for key, i in slot_map.keys {
		testing.expect(t, key.gen == 1, "Initial generation should be 1")
		if uint(i) < N - 1 {
			testing.expect(t, key.idx == uint(i + 1), "Handle should point to next slot")
		} else {
			testing.expect(t, key.idx == uint(i), "Last handle should point to itself")
		}
	}
}


@(test)
fixed_slot_map_clear_test :: proc(t: ^testing.T) {
	CoolStruct :: struct {
		v: int,
		p: ^int,
	}
	HandleCoolStruct :: distinct Key(uint, 32, 32)

	STRUCT_MAX :: 6

	slot_map: FixedSlotMap(STRUCT_MAX, CoolStruct, HandleCoolStruct)
	fixed_slot_map_init(&slot_map)

	cool_struct_array: [STRUCT_MAX]CoolStruct
	for i in 0 ..< STRUCT_MAX {
		cool_struct_array[i].v = i
		cool_struct_array[i].p = &cool_struct_array[i].v
		_ = fixed_slot_map_new_with_data(&slot_map, cool_struct_array[i])
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
fixed_slot_map_new_test :: proc(t: ^testing.T) {
	N :: 5
	MyKey :: distinct Key(uint, 32, 32)
	slot_map: FixedSlotMap(N, int, MyKey)
	fixed_slot_map_init(&slot_map)

	handle1, ok1 := fixed_slot_map_new_with_data(&slot_map, 42)
	testing.expect(t, slot_map.size == 1, "Size should be 1 after first insertion")
	testing.expect(t, slot_map.free_list_head == 1, "Head should have advanced by one")
	testing.expect(t, slot_map.free_list_tail == 4, "Tail should not move")

	value1, ok2 := fixed_slot_map_get_ptr(&slot_map, handle1)
	testing.expect(t, ok2, "Should be able to get first value")
	testing.expect(t, value1^ == 42, "Retrieved value should match inserted value")

	// Test filling the slot_map
	handles: [N - 1]MyKey
	for i in 1 ..< N - 1 {
		h, ok := fixed_slot_map_new_with_data(&slot_map, i * 10)
		testing.expect(t, ok, "Insert within N - 1 should succeed")
		handles[i] = h
	}

	// Test insertion when full
	_, ok3 := fixed_slot_map_new_with_data(&slot_map, 100)
	testing.expect(t, !ok3, "Insert when full should fail")
}


@(test)
fixed_slot_map_new_with_data_test :: proc(t: ^testing.T) {
	N :: 5
	MyKey :: distinct Key(uint, 32, 32)
	slot_map := fixed_slot_map_make(N, int, MyKey)

	handle1, _ := fixed_slot_map_new_with_data(&slot_map, 999)

	value1, _ := fixed_slot_map_get(&slot_map, handle1)

	testing.expect(t, value1 == 999, "Value not set correctly")
	testing.expect(t, slot_map.data[0] == 999, "Value not set correctly")
}


@(test)
fixed_slot_map_new_get_ptr_test :: proc(t: ^testing.T) {
	N :: 5
	MyKey :: distinct Key(uint, 32, 32)
	slot_map := fixed_slot_map_make(N, int, MyKey)

	handle1, ptr1, _ := fixed_slot_map_new_get_ptr(&slot_map)
	ptr1^ = 999
	testing.expect(t, slot_map.data[0] == 999, "Value not set correctly")
}


@(test)
fixed_slot_map_set_test :: proc(t: ^testing.T) {
	N :: 5
	MyKey :: distinct Key(uint, 32, 32)
	slot_map := fixed_slot_map_make(N, int, MyKey)

	key, _ := fixed_slot_map_new(&slot_map)
	fixed_slot_map_set(&slot_map, key, 42)
	testing.expect(t, slot_map.data[0] == 42)
}


@(test)
fixed_slot_map_remove_test :: proc(t: ^testing.T) {
	MyKey :: distinct Key(uint, 32, 32)
	slot_map: FixedSlotMap(5, int, MyKey)
	fixed_slot_map_init(&slot_map)

	handle1, _ := fixed_slot_map_new_with_data(&slot_map, 10)
	handle2, _ := fixed_slot_map_new_with_data(&slot_map, 20)
	handle3, _ := fixed_slot_map_new_with_data(&slot_map, 30)

	ok := fixed_slot_map_remove(&slot_map, handle1)
	testing.expect(t, ok, "Deletion should succeed")
	testing.expect(t, slot_map.size == 2, "Size should decrease after deletion")
	// Deleted first handle so the last one gets its slot
	testing.expect(t, slot_map.data[0] == 30, "Data was not correctly moved")
	testing.expect(t, slot_map.free_list_tail == 0, "Tail was not set properly")
	testing.expect(t, slot_map.keys[slot_map.free_list_tail].idx == 0, "Tail was not set properly")
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
fixed_slot_map_remove_value_test :: proc(t: ^testing.T) {
	MyKey :: distinct Key(uint, 32, 32)
	slot_map: FixedSlotMap(5, int, MyKey)
	fixed_slot_map_init(&slot_map)

	handle1, _ := fixed_slot_map_new_with_data(&slot_map, 10)
	handle2, _ := fixed_slot_map_new_with_data(&slot_map, 20)
	handle3, _ := fixed_slot_map_new_with_data(&slot_map, 30)

	value1, ok := fixed_slot_map_remove_value(&slot_map, handle1)
	testing.expect(t, value1 == 10, "Deleted value is not correct")
}


@(test)
fixed_slot_map_is_valid_test :: proc(t: ^testing.T) {
	MyKey :: distinct Key(uint, 32, 32)
	slot_map: FixedSlotMap(5, int, MyKey)
	fixed_slot_map_init(&slot_map)

	// Test invalid handle
	invalid_handle := MyKey {
		idx = 999,
		gen = 1,
	}
	testing.expect(
		t,
		!fixed_slot_map_is_valid(&slot_map, invalid_handle),
		"Invalid index should be rejected",
	)

	// Test generation mismatch
	handle1, _ := fixed_slot_map_new_with_data(&slot_map, 42)
	invalid_gen_handle := MyKey {
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
		MyKey :: distinct Key(uint, 32, 32)
		slot_map: FixedSlotMap(10, Entity, MyKey)
		fixed_slot_map_init(&slot_map)

		// Create and insert entities
		player := make_entity("Player", 0, 0, 0, 100)
		enemy := make_entity("Enemy", 10, 0, 10, 50)

		player_handle, ok1 := fixed_slot_map_new_with_data(&slot_map, player)
		testing.expect(t, ok1, "Player insertion should succeed")

		enemy_handle, ok2 := fixed_slot_map_new_with_data(&slot_map, enemy)
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
		fixed_slot_map_remove(&slot_map, enemy_handle)

		// Test reuse of slot
		npc := make_entity("NPC", -5, 0, -5, 30)
		new_handle, ok3 := fixed_slot_map_new_with_data(&slot_map, npc)
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
fixed_slot_map_new_remove_test :: proc(t: ^testing.T) {
	N :: 4
	MyKey :: distinct Key(uint, 32, 32)
	slot_map := fixed_slot_map_make(N, int, MyKey)

	handle1, ok1 := fixed_slot_map_new_with_data(&slot_map, 10)
	handle2, ok2 := fixed_slot_map_new_with_data(&slot_map, 20)
	handle3, ok3 := fixed_slot_map_new_with_data(&slot_map, 30)
	// Slot Map has N - 1 slots so can't use the 4th one
	handle4, ok4 := fixed_slot_map_new(&slot_map)
	testing.expect(t, ok4 == false, "Should not be able to fill the slot map completly")

	// There Head and Tail should be = 3
	testing.expect(t, slot_map.free_list_head == 3)
	testing.expect(t, slot_map.free_list_tail == 3)

	// Delete the second slot, so last slot is moved to [1]
	ok2 = fixed_slot_map_remove(&slot_map, handle2)
	testing.expect(t, slot_map.data[1] == 30)
	testing.expect(t, slot_map.free_list_head == 3)
	testing.expect(t, slot_map.free_list_tail == 1)

	handle4, ok4 = fixed_slot_map_new_with_data(&slot_map, 40)
	testing.expect(t, slot_map.data[2] == 40)
	testing.expect(t, slot_map.free_list_head == 1)
	testing.expect(t, slot_map.free_list_tail == 1)

	ok1 = fixed_slot_map_remove(&slot_map, handle1)
	testing.expect(t, slot_map.data[0] == 40)
	testing.expect(t, slot_map.free_list_tail == 0)
}


@(test)
fixed_slot_map_random_new_remove_test :: proc(t: ^testing.T) {
	N :: 1000
	MyKey :: distinct Key(uint, 32, 32)
	slot_map := fixed_slot_map_make(N, int, MyKey)

	keys := make([dynamic]MyKey)
	defer delete(keys)

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
			new_handle, ok := fixed_slot_map_new_with_data(&slot_map, 0)
			if ok {
				append(&keys, new_handle)

				// Check for collisions, 2 same Handles should never be returned
				for handle1, i in keys {
					for handle2, j in keys {
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
			if len(keys) > 0 {
				testing.expect(t, len(keys) == int(slot_map.size))

				idx := rand.int_max(max(int)) % len(keys)
				handle := keys[idx]
				unordered_remove(&keys, idx)

				old_tail := slot_map.free_list_tail
				ok := fixed_slot_map_remove(&slot_map, handle)
				testing.expect(t, ok)

				pointed_handle_idx := handle.idx
				new_tail := slot_map.free_list_tail
				testing.expect(t, new_tail == pointed_handle_idx)
			}
		}
	}
}

import "core:log"

/// DYNAMIC SLOT MAP
@(test)
dynamic_slot_map_make_test :: proc(t: ^testing.T) {
	CoolStruct :: struct {
		x, y: int,
	}
	CoolKey :: distinct Key(uint, 32, 32)

	initial_cap: uint = 5
	slot_map := dynamic_slot_map_make(CoolStruct, CoolKey, initial_cap)
	defer dynamic_slot_map_delete(&slot_map)

	testing.expect(t, slot_map.size == 0)
	testing.expect(t, slot_map.free_list_head == 0, "Free list head should start at 0")
	testing.expect(t, slot_map.free_list_tail == 4, "Free list tail should be N-1")
	testing.expect(t, len(slot_map.data) == int(initial_cap))
	testing.expect(t, len(slot_map.keys) == int(initial_cap))
	testing.expect(t, len(slot_map.erase) == int(initial_cap))
}


@(test)
dynamic_slot_map_new_test :: proc(t: ^testing.T) {
	MyKey :: distinct Key(uint, 32, 32)

	slot_map := dynamic_slot_map_make(int, MyKey, 3)
	defer dynamic_slot_map_delete(&slot_map)

	key1, ok1 := dynamic_slot_map_new(&slot_map)
	testing.expect(t, ok1, "Could not create a new Key")

	key2 := dynamic_slot_map_new(&slot_map)
	key3 := dynamic_slot_map_new(&slot_map, growth_factor = 2)
	testing.expect(t, len(slot_map.keys) == 6, "Did not re alloc properly")
}


@(test)
dynamic_slot_map_is_valid_test :: proc(t: ^testing.T) {
	MyKey :: distinct Key(uint, 32, 32)

	slot_map := dynamic_slot_map_make(int, MyKey, 3)
	defer dynamic_slot_map_delete(&slot_map)

	key1 := dynamic_slot_map_new(&slot_map)
	ok := dynamic_slot_map_is_valid(&slot_map, key1)
	testing.expect(t, ok, "Key should be valid")

	key1.gen = 0
	ok = dynamic_slot_map_is_valid(&slot_map, key1)
	testing.expect(t, ok == false, "Key should not be valid, gen = 0")

	key1.gen = 1
	key1.idx = 10
	ok = dynamic_slot_map_is_valid(&slot_map, key1)
	testing.expect(t, ok == false, "Key should not be valid, idx > slot map capacity")
}


@(test)
dynamic_slot_map_remove_test :: proc(t: ^testing.T) {
	MyKey :: distinct Key(uint, 32, 32)

	slot_map := dynamic_slot_map_make(int, MyKey, 3)
	defer dynamic_slot_map_delete(&slot_map)


	key1 := dynamic_slot_map_new(&slot_map)
	ok_del := dynamic_slot_map_remove(&slot_map, key1)
	testing.expect(t, ok_del, "Could not remove")
	testing.expect(t, slot_map.free_list_tail == 0)
	testing.expect(t, slot_map.keys[0].idx == 0)
}


@(test)
dynamic_slot_map_set_test :: proc(t: ^testing.T) {
	MyKey :: distinct Key(uint, 32, 32)

	slot_map := dynamic_slot_map_make(int, MyKey, 3)
	defer dynamic_slot_map_delete(&slot_map)


	key1 := dynamic_slot_map_new(&slot_map)
	set_value: int = 4
	ok_set := dynamic_slot_map_set(&slot_map, key1, set_value)
	testing.expect(t, ok_set)
	testing.expect(t, slot_map.data[0] == set_value)
}
