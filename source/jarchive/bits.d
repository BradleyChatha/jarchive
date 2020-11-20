module jarchive.bits;

import jarchive;

extern(C) @nogc:

struct JarchiveBinaryReader
{
    private:

    const(ubyte)[] data;
    size_t cursor;
}

JarchiveBinaryReader* jarcBinaryReader_openMemory(scope const ubyte* bytes, size_t length)
{
    return alloc!JarchiveBinaryReader(bytes[0..length]);
}

extern(D)
JarchiveBinaryReader* jarcBinaryReader_openMemory(T)(scope T[] slice)
{
    return jarcBinaryReader_openMemory(cast(ubyte*)slice.ptr, T.sizeof * slice.length);
}

bool jarcBinaryReader_isEof(
    JarchiveBinaryReader* reader
)
{
    return reader.cursor >= reader.data.length;
}

size_t jarcBinaryReader_readBytes(
    JarchiveBinaryReader* reader, 
    scope ubyte*          buffer, 
    size_t*               bufferSize, 
    size_t                amount
)
{
    import std.algorithm : min;

    auto toRead = (bufferSize is null)
    ? min(amount, reader.data.length - reader.cursor)
    : min(amount, reader.data.length - reader.cursor, *bufferSize);

    if(toRead != 0)
        buffer[0..toRead] = reader.data[reader.cursor..reader.cursor+toRead];

    reader.cursor += toRead;
    return toRead;
}

extern(D)
T jarcBinaryReader_readPrimitive(T)(
    JarchiveBinaryReader* reader
)
{
    import std.bitmanip : bigEndianToNative;

    ubyte[T.sizeof] data;
    const read = jarcBinaryReader_readBytes(reader, data.ptr, null, T.sizeof);
    assert(read > 0);

    return data.bigEndianToNative!T;
}

private mixin template readPrimitive(string name, T) 
{
    mixin("T jarcBinaryReader_read"~name~"(JarchiveBinaryReader* reader){ return jarcBinaryReader_readPrimitive!T(reader); }");
}

mixin readPrimitive!("U8",  ubyte);
mixin readPrimitive!("U16", ushort);
mixin readPrimitive!("U32", uint);
mixin readPrimitive!("U64", ulong);

ulong jarcBinaryReader_read7BitEncodedU(
    JarchiveBinaryReader* reader
)
{
    ulong value  = 0;
    ulong offset = 0;
    
    while(true)
    {
        assert(offset < 10);

        const next = jarcBinaryReader_readPrimitive!ubyte(reader);
        const nextShifted = (next & 0b0111_1111) << (7 * offset++);
        value |= nextShifted;

        if((next & 0b1000_0000) > 0)
            break;
    }

    return value;
}

unittest
{
    import core.stdc.stdio : printf;

    static ubyte[] bytes = [
        0xAA,
        0xAA, 0xBB,
        0xAA, 0xBB, 0xCC, 0xDD,
        0b1111_1111,
        0b0111_1111, 0b1111_1111,
        0b0111_1111, 0b0111_1111, 0b1111_1111,
        0b0111_1111, 0b0111_1111, 0b0111_1111, 0b0111_1111, 0b0111_1111, 0b0111_1111, 0b0111_1111, 0b0111_1111, 0b0111_1111, 0b1000_0001
    ];

    scope reader = jarcBinaryReader_openMemory(bytes);

    ubyte data;
    assert(jarcBinaryReader_readBytes(reader, &data, null, 1) == 1);
    assert(data == 0xAA);

    assert(jarcBinaryReader_readU16(reader) == 0xAABB);
    assert(jarcBinaryReader_readU32(reader) == 0xAABBCCDD);

    assert(jarcBinaryReader_read7BitEncodedU(reader) == 0x7F);
    assert(jarcBinaryReader_read7BitEncodedU(reader) == 0x3FFF);
    assert(jarcBinaryReader_read7BitEncodedU(reader) == 0x1FFFFF);
    assert(jarcBinaryReader_read7BitEncodedU(reader) == ulong.max);

    assert(jarcBinaryReader_isEof(reader));
}