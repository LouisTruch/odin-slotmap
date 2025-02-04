package slot_map


DynamicSlotMap :: struct($T: typeid, $KeyType: typeid) {
	size:           uint,
	free_list_head: uint,
	free_list_tail: uint,
	keys:           [dynamic]KeyType,
	data:           [dynamic]T,
	erase:          [dynamic]uint,
}


@(require_results)
dynamic_slot_map_make :: #force_inline proc(
	$T: typeid,
	$KeyType: typeid,
	initial_cap: uint,
) -> (
	slot_map: DynamicSlotMap(T, KeyType),
) {

	return slot_map
}
