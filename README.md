# (Dense) Slot Map in Odin

Very small implementation of what's described [here](https://www.youtube.com/watch?v=SHaAR7XPtNU) by [Allan Deutsch](https://allandeutsch.com/)

For now there is only a fixed size implementation, and more testing is still to be added


## What's a slot map (Also called Handle array)

It's an associative data structure made for high-performance look-ups, insertions and deletions. All these operations should take O(1) for every case from worst to best. For a non fixed-size slot map, when the container needs re-allocate to get more memory and move it, this is not guaranteed. For a fixed-size one the problem does not exist but you might have to be more carefull about the object you're allocating.

Since it's an associative data structure, it needs some sort of key system to retrieve the data you store. It uses handle to do so. A handle is just an index and a generation, the index keep tracks of where you data is located in the internal data array. The generation is really just a counter which get increased everytime the handle gets deleted. The point is to keep track of when the object has been allocated, so that everything that stores a handle can now if the object associated to it has been recycled or not. This can avoid pointer invalidation and other not so fun problems, see the ABA problem in References.

A dense slot map also guarantees that all the used data is in a contiguous block of memory, making iterating over the data very fast since the CPU can work with fully used cache lines and so minimizing the amount of cache misses. It does so by moving deleted object at the end of its data array.

To achieve all of this it has to do some extra book keeping, if you are interested in it you should check the references.


## Usage

Todo


## References

C++Now 2017: Allan Deutsch “The Slot Map Data Structure": \
https://www.youtube.com/watch?v=SHaAR7XPtNU

CppCon 2017: Allan Deutsch “Esoteric Data Structures and Where to Find Them” \
(Almost the same presentation but with some other interesting data structures) \
https://www.youtube.com/watch?v=-8UZhDjgeZU

Data Structures for Game Developers: The Slot Map: \
https://web.archive.org/web/20180121142549/http://seanmiddleditch.com/data-structures-for-game-developers-the-slot-map/

Handles are the better pointers \
https://floooh.github.io/2018/06/17/handles-vs-pointers.html

ABA Problem \
https://en.wikipedia.org/wiki/ABA_problem