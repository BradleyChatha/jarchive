module jarchive.memory;

import std.conv : emplace;
import core.stdc.stdlib : malloc, cfree = free, realloc;
import core.stdc.stdio : printf;

@nogc nothrow:

private size_t g_bytesAllocated;

T* alloc(T, Args...)(Args args)
{
    version(memory)
    {
        g_bytesAllocated += T.sizeof;
        printf("alloc: %llu bytes | total: %llu bytes\n", cast(ulong)T.sizeof, g_bytesAllocated);
    }

    scope ptr = cast(T*)malloc(T.sizeof);
    if(ptr is null)
        return null;

    return emplace(ptr, args);
}

T[] allocArray(T)(size_t amount)
{
    if(amount == 0)
        return null;
    
    version(memory)
    {
        g_bytesAllocated += T.sizeof * amount;
        printf("allocArray: %llu bytes | total: %llu bytes\n", cast(ulong)T.sizeof * amount, g_bytesAllocated);
    }

    scope ptr = malloc(T.sizeof * amount);
    scope retPtr = (ptr is null) ? null : (cast(T*)ptr)[0..amount];

    if(retPtr !is null)
        retPtr[0..$] = T.init;

    return retPtr;
}

void resizeArray(T)(ref T[] array, size_t size)
{
    version(memory)
    {
        g_bytesAllocated -= T.sizeof * array.length;
        g_bytesAllocated += T.sizeof * size;
        printf("resizeArray: %llu bytes | total: %llu bytes\n", cast(ulong)T.sizeof * size, g_bytesAllocated);
    }

    if(size == 0)
    {
        free(array);
        array = null;
        return;
    }

    scope ptr = cast(T*)realloc(array.ptr, T.sizeof * size);
    array = (ptr is null) ? null : (cast(T*)ptr)[0..size];
}

private void free(void* ptr)
{
    version(memory)
        printf("free: raw pointer | total: %llu bytes\n", g_bytesAllocated);

    cfree(ptr);
}

void free(T)(T* ptr)
{
    version(memory)
    {
        g_bytesAllocated -= T.sizeof;
        printf("free: %llu bytes | total: %llu bytes\n", cast(ulong)T.sizeof, g_bytesAllocated);
    }

    static if(__traits(hasMember, T, "__xdtor"))
        ptr.__xdtor();

    cfree(ptr);
}

void free(T)(ref T[] slice)
{
    assert(slice !is null);

    version(memory)
    {
        g_bytesAllocated -= T.sizeof * slice.length;
        printf("free(array): %llu bytes | total: %llu bytes\n", cast(ulong)T.sizeof * slice.length, g_bytesAllocated);
    }

    cfree(slice.ptr);
    slice = null;
}