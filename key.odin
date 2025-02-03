package slot_map

import "base:intrinsics"


// A Key represents an entry in a Slot Map \
// Usage: `MyHandle :: distinct Key(uint, 32, 32)`
Key :: struct($BackingType: typeid,
$IndexWidth: uint,
$GenWidth: uint,) where intrinsics.type_is_unsigned(BackingType)
{
	using bits:
	bit_field BackingType
	{
		idx: BackingType | IndexWidth,
		gen: BackingType | GenWidth,
	},
}


// Packs a Key into a ptr \
// Key's backing type size must be equal or less than the size of a ptr 
@(require_results)
key_pack_ptr :: #force_inline proc "contextless" (
	key: Key($BackingType, $IndexWidth, $GenWidth),
) -> rawptr where size_of(BackingType) <=
	size_of(rawptr) {
	packed := (BackingType(key.bits.gen) << IndexWidth) | BackingType(key.bits.idx)
	return rawptr(uintptr(packed))
}


// Unpacks a Key from a ptr \
// Key's backing type size must be equal or less than the size of a ptr 
@(require_results)
key_unpack_ptr :: #force_inline proc "contextless" (
	ptr: rawptr,
	$KeyType: typeid/Key($BackingType, $IndexWidth, $GenWidth),
) -> KeyType where size_of(BackingType) <=
	size_of(rawptr) {

	packed := BackingType(uintptr(ptr))
	index_mask: BackingType = (1 << IndexWidth) - 1

	return KeyType{bits = {idx = packed & index_mask, gen = packed >> IndexWidth}}
}
