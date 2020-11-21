module jarchive.memory;

import std.conv : emplace;
import core.stdc.stdlib : malloc, cfree = free, realloc;

@nogc:

T* alloc(T, Args...)(Args args)
{
    scope ptr = cast(T*)malloc(T.sizeof);
    if(ptr is null)
        return null;

    return emplace(ptr, args);
}

T[] allocArray(T)(size_t amount)
{
    if(amount == 0)
        return null;

    scope ptr = malloc(T.sizeof * amount);
    return (ptr is null) ? null : (cast(T*)ptr)[0..amount];
}

void resizeArray(T)(ref T[] array, size_t size)
{
    if(size == 0)
    {
        free(array);
        array = null;
        return;
    }

    scope ptr = cast(T*)realloc(array.ptr, size);
    array = (ptr is null) ? null : (cast(T*)ptr)[0..size];
}

void free(void* ptr)
{
    cfree(ptr);
}

void free(T)(T* ptr)
{
    static if(__traits(hasMember, T, "__xdtor"))
        ptr.__xdtor();

    cfree(ptr);
}

void free(T)(ref T[] slice)
{
    assert(slice !is null);

    free(slice.ptr);
    slice = null;
}