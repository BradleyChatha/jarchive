module jarchive.memory;

import std.conv : emplace;
import core.stdc.stdlib : malloc, cfree = free;

@nogc:

T* alloc(T, Args...)(Args args)
{
    scope ptr = cast(T*)malloc(T.sizeof);
    return emplace(ptr, args);
}

T[] allocArray(T)(size_t amount)
{
    if(amount == 0)
        return null;
    return (cast(T*)malloc(T.sizeof * amount))[0..amount];
}

void free(void* ptr)
{
    cfree(ptr);
}

void free(T)(ref T[] slice)
{
    assert(slice !is null);

    free(slice.ptr);
    slice = null;
}