package slot_map

import "core:testing"

// TODO 
// !!! Really ugly code below
@(test)
fixed_map_test :: proc(t: ^testing.T) {
	S :: struct {
		x, y: int,
	}

	StructHandle :: distinct Handle(int)

	m := new(FixedSlotMap(6, S, StructHandle))
	fixed_slot_map_init(m)
	defer free(m)

	{
		handle1, ok1 := fixed_slot_map_new_handle(m)
		testing.expect(t, ok1 == true)

		value1 := fixed_slot_map_get_ptr(m, handle1)
		value1^ = S{9, 9}
		testing.expect(t, m.data[0] == S{9, 9})

		handle2, ok2 := fixed_slot_map_new_handle(m)
		testing.expect(t, ok2 == true)

		value2 := fixed_slot_map_get_ptr(m, handle2)
		value2^ = S{10, 10}
		testing.expect(t, m.data[1] == S{10, 10})

		fixed_slot_map_delete_handle(m, handle1)
		testing.expect(t, m.data[0] == S{10, 10})

		fixed_slot_map_delete_handle(m, handle2)
		testing.expect(t, m.size == 0)


		testing.expect(t, fixed_slot_map_is_valid(m, handle1) == false)
		testing.expect(t, fixed_slot_map_is_valid(m, handle2) == false)
	}
	{
		handle1 := fixed_slot_map_new_handle_value(m, S{9, 9})
		testing.expect(t, m.data[0] == S{9, 9})

		handle2 := fixed_slot_map_new_handle_value(m, S{10, 10})
		testing.expect(t, m.data[1] == S{10, 10})

		handle3 := fixed_slot_map_new_handle_value(m, S{11, 11})
		testing.expect(t, m.data[2] == S{11, 11})

		handle4 := fixed_slot_map_new_handle_value(m, S{12, 12})
		testing.expect(t, m.data[3] == S{12, 12})

		fixed_slot_map_delete_handle(m, handle2)
		testing.expect(t, m.data[1] == S{12, 12})

		handle5 := fixed_slot_map_new_handle_value(m, S{20, 20})
		testing.expect(t, m.data[3] == S{20, 20})
	}

}
