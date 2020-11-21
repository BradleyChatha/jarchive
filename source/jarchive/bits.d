module jarchive.bits;

import core.stdc.stdio, core.stdc.config;
import jarchive;

extern(C) @nogc:

struct JarcBinaryReader
{
    private:

    const(ubyte)[] data;
    FILE*          file;
    JarcBinaryMode mode;

    union
    {
        size_t cursor;
        c_long fileSize;
    }

    @nogc
    public this(const(ubyte[]) data) // Public so std.conv.emplace can see it.
    {
        this.data = data;
        this.mode = JarcBinaryMode.memory;
    }

    @nogc
    public this(FILE* file)
    {
        assert(file !is null);
        this.file = file;
        this.mode = JarcBinaryMode.file;

        fseek(file, 0, SEEK_END);
        this.fileSize = ftell(file);
        fseek(file, 0, SEEK_SET);
    }

    @nogc
    public ~this()
    {
        if(this.mode == JarcBinaryMode.file
        && this.file !is null)
            fclose(this.file);
    }
}

JarcBinaryReader* jarcBinaryReader_openMemory(scope const ubyte* bytes, size_t length)
{
    return alloc!JarcBinaryReader(bytes[0..length]);
}

extern(D)
JarcBinaryReader* jarcBinaryReader_openMemory(T)(scope T[] slice)
{
    return jarcBinaryReader_openMemory(cast(ubyte*)slice.ptr, T.sizeof * slice.length);
}

JarcBinaryReader* jarcBinaryReader_openFileByNamez(scope const ubyte* name)
{
    FILE* file = fopen(cast(char*)name, "r");
    if(file is null)
        return null;

    scope reader = alloc!JarcBinaryReader(file);
    if(reader is null)
        fclose(file);

    return reader;
}

JarcBinaryReader* jarcBinaryReader_openFileByName(scope const ubyte* name_, size_t length)
{
    scope name = allocArray!ubyte(length + 1);
    if(name is null)
        return null;

    name[0..$-1] = name_[0..length];
    name[$-1] = '\0';

    scope reader = jarcBinaryReader_openFileByNamez(name.ptr);
    free(name);

    return reader;
}

void jarcBinaryReader_free(
    JarcBinaryReader* reader
)
{
    free!JarcBinaryReader(reader);
}

JarcResult jarcBinaryReader_setCursor(
    JarcBinaryReader* reader,
    c_long offset
)
{
    if(reader.mode == JarcBinaryMode.memory)
    {
        reader.cursor = cast(size_t)offset;
        return (!jarcBinaryReader_isEof(reader)) ? JARC_OK : JARC_EOF;
    }
    else if(reader.mode == JarcBinaryMode.file)
    {
        const result = fseek(reader.file, offset, SEEK_SET);
        return (result != 0) ? JARC_UNKNOWN_ERROR : JARC_OK;
    }
    else assert(false);
}

c_long jarcBinaryReader_getCursor(
    JarcBinaryReader* reader
)
{
    return (reader.mode == JarcBinaryMode.memory)
    ? cast(c_long)reader.cursor
    : ftell(reader.file);
}

bool jarcBinaryReader_isEof(
    JarcBinaryReader* reader
)
{
    return (reader.mode == JarcBinaryMode.memory)
    ? reader.cursor >= reader.data.length
    : ftell(reader.file) >= reader.fileSize;
}

size_t jarcBinaryReader_readBytes(
    JarcBinaryReader* reader, 
    scope ubyte*      buffer, 
    size_t*           bufferSize, 
    size_t            amount
)
{
    import std.algorithm : min;

    auto toRead = (bufferSize is null)
    ? min(amount, reader.data.length - reader.cursor)
    : min(amount, reader.data.length - reader.cursor, *bufferSize);

    if(toRead != 0)
    {
        if(reader.mode == JarcBinaryMode.memory)
            buffer[0..toRead] = reader.data[reader.cursor..reader.cursor+toRead];
        else if(reader.mode == JarcBinaryMode.file)
            fread(buffer, 1, toRead, reader.file);
        else
            assert(false);
    }

    reader.cursor += toRead;
    return toRead;
}

extern(D)
JarcResult jarcBinaryReader_readPrimitive(T)(
    JarcBinaryReader* reader,
    T* data
)
{
    import std.bitmanip : bigEndianToNative;

    ubyte[T.sizeof] bytes;
    const read = jarcBinaryReader_readBytes(reader, bytes.ptr, null, T.sizeof);
    if(read != bytes.length)
        return JARC_EOF;

    *data = bytes.bigEndianToNative!T;
    return JARC_OK;
}

private mixin template readPrimitive(string name, T) 
{
    mixin(`
    JarcResult jarcBinaryReader_read`~name~`(JarcBinaryReader* reader, T* data)
    {
        return jarcBinaryReader_readPrimitive!T(reader, data); 
    }
    `);
}

mixin readPrimitive!("U8",  ubyte);
mixin readPrimitive!("U16", ushort);
mixin readPrimitive!("U32", uint);
mixin readPrimitive!("U64", ulong);

JarcResult jarcBinaryReader_read7BitEncodedU(
    JarcBinaryReader* reader,
    ulong* data
)
{
    ulong value  = 0;
    ulong offset = 0;
    
    while(true)
    {
        if(offset >= 10)
            return JARC_BAD_DATA;

        ubyte next;
        const result = jarcBinaryReader_readPrimitive!ubyte(reader, &next);
        if(result != JARC_OK)
            return result;

        const nextShifted = (next & 0b0111_1111) << (7 * offset++);
        value |= nextShifted;

        if((next & 0b1000_0000) > 0)
            break;
    }

    *data = value;
    return JARC_OK;
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

    static T readOk(T, alias Func)(JarcBinaryReader* reader)
    {
        T value;
        assert(Func(reader, &value) == JARC_OK);

        return value;
    }

    scope reader = jarcBinaryReader_openMemory(bytes);
    scope(exit) jarcBinaryReader_free(reader);

    ubyte data;
    assert(jarcBinaryReader_readBytes(reader, &data, null, 1) == 1);
    assert(data == 0xAA);

    assert(readOk!(ushort, jarcBinaryReader_readU16)(reader) == 0xAABB);
    assert(readOk!(uint, jarcBinaryReader_readU32)(reader) == 0xAABBCCDD);

    assert(readOk!(ulong, jarcBinaryReader_read7BitEncodedU)(reader) == 0x7F);
    assert(readOk!(ulong, jarcBinaryReader_read7BitEncodedU)(reader) == 0x3FFF);
    assert(readOk!(ulong, jarcBinaryReader_read7BitEncodedU)(reader) == 0x1FFFFF);
    assert(readOk!(ulong, jarcBinaryReader_read7BitEncodedU)(reader) == ulong.max);
    assert(jarcBinaryReader_getCursor(reader) == bytes.length);

    assert(jarcBinaryReader_isEof(reader));
    assert(jarcBinaryReader_setCursor(reader, 0) == JARC_OK);
    assert(readOk!(ubyte, jarcBinaryReader_readU8)(reader) == 0xAA);
    assert(jarcBinaryReader_setCursor(reader, 200000) == JARC_EOF);
}