module jarchive.bits;

import core.stdc.stdio, core.stdc.config;
import jarchive;

extern(C) @nogc:

struct JarcBinaryStream
{
    private:

    const(ubyte)[] data;
    FILE*          file;
    JarcBinaryMode mode;
    JarcReadWrite  readWriteMode;

    union
    {
        size_t cursor;
        c_long fileSize;
    }

    @nogc
    public this(const(ubyte[]) data, JarcReadWrite readWrite) // Public so std.conv.emplace can see it.
    {
        this.data = data;
        this.mode = JarcBinaryMode.memory;
        this.readWriteMode = readWrite;
    }

    @nogc
    public this(FILE* file, JarcReadWrite readWrite)
    {
        assert(file !is null);
        this.file = file;
        this.mode = JarcBinaryMode.file;
        this.readWriteMode = readWrite;

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

JarcBinaryStream* jarcBinaryStream_openMemory(JarcReadWrite readWrite, scope const ubyte* bytes, size_t length)
{
    return alloc!JarcBinaryStream(bytes[0..length], readWrite);
}

extern(D)
JarcBinaryStream* jarcBinaryStream_openMemory(T)(JarcReadWrite readWrite, scope T[] slice)
{
    return jarcBinaryStream_openMemory(readWrite, cast(ubyte*)slice.ptr, T.sizeof * slice.length);
}

JarcBinaryStream* jarcBinaryStream_openFileByNamez(JarcReadWrite readWrite, scope const ubyte* name)
{
    // Taken from std.file. It's a private method unfortunately.
    bool existsImpl(const(char)* namez) @trusted nothrow @nogc
    {
        version (Windows)
        {
            import core.sys.windows.winbase;
            return GetFileAttributesA(namez) != 0xFFFFFFFF;
        }
        else version (Posix)
        {
            import core.sys.posix.sys.stat;
            stat_t statbuf = void;
            return lstat(namez, &statbuf) == 0;
        }
        else
            static assert(0);
    }
    const fileExists = existsImpl(cast(char*)name);
    string fileMode  = (fileExists) ? "r+" : "w+";

    FILE* file = fopen(cast(char*)name, fileMode.ptr); // Literals always have a null terminator.
    if(file is null)
        return null;

    scope reader = alloc!JarcBinaryStream(file, readWrite);
    if(reader is null)
        fclose(file);

    return reader;
}

JarcBinaryStream* jarcBinaryStream_openFileByName(JarcReadWrite readWrite, scope const ubyte* name_, size_t length)
{
    scope name = allocArray!ubyte(length + 1);
    if(name is null)
        return null;

    name[0..$-1] = name_[0..length];
    name[$-1] = '\0';

    scope reader = jarcBinaryStream_openFileByNamez(readWrite, name.ptr);
    free(name);

    return reader;
}

void jarcBinaryStream_free(
    JarcBinaryStream* reader
)
{
    assert(reader !is null);
    free!JarcBinaryStream(reader);
}

JarcResult jarcBinaryStream_setCursor(
    JarcBinaryStream* reader,
    c_long offset
)
{
    if(reader.mode == JarcBinaryMode.memory)
    {
        reader.cursor = cast(size_t)offset;
        return (!jarcBinaryStream_isEof(reader)) ? JARC_OK : JARC_EOF;
    }
    else if(reader.mode == JarcBinaryMode.file)
    {
        const result = fseek(reader.file, offset, SEEK_SET);
        return (result != 0) ? JARC_UNKNOWN_ERROR : JARC_OK;
    }
    else assert(false);
}

c_long jarcBinaryStream_getCursor(
    JarcBinaryStream* reader
)
{
    return (reader.mode == JarcBinaryMode.memory)
    ? cast(c_long)reader.cursor
    : ftell(reader.file);
}

bool jarcBinaryStream_isEof(
    JarcBinaryStream* reader
)
{
    return (reader.mode == JarcBinaryMode.memory)
    ? reader.cursor >= reader.data.length
    : ftell(reader.file) >= reader.fileSize;
}

size_t jarcBinaryStream_readBytes(
    JarcBinaryStream* reader, 
    scope ubyte*      buffer, 
    size_t*           bufferSize, 
    size_t            amount
)
{
    import std.algorithm : min;

    if(!reader.readWriteMode.canRead)
        return 0;

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
JarcResult jarcBinaryStream_readPrimitive(T)(
    JarcBinaryStream* reader,
    T* data
)
{
    import std.bitmanip : bigEndianToNative;

    if(!reader.readWriteMode.canRead)
        return JARC_CANT_READ;

    ubyte[T.sizeof] bytes;
    const read = jarcBinaryStream_readBytes(reader, bytes.ptr, null, T.sizeof);
    if(read != bytes.length)
        return JARC_EOF;

    *data = bytes.bigEndianToNative!T;
    return JARC_OK;
}

private mixin template readPrimitive(string name, T) 
{
    mixin(`
    JarcResult jarcBinaryStream_read`~name~`(JarcBinaryStream* reader, T* data)
    {
        return jarcBinaryStream_readPrimitive!T(reader, data); 
    }
    `);
}

mixin readPrimitive!("U8",  ubyte);
mixin readPrimitive!("U16", ushort);
mixin readPrimitive!("U32", uint);
mixin readPrimitive!("U64", ulong);

JarcResult jarcBinaryStream_read7BitEncodedU(
    JarcBinaryStream* reader,
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
        const result = jarcBinaryStream_readPrimitive!ubyte(reader, &next);
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

    static T readOk(T, alias Func)(JarcBinaryStream* reader)
    {
        T value;
        assert(Func(reader, &value) == JARC_OK);

        return value;
    }

    scope reader = jarcBinaryStream_openMemory(JARC_READ, bytes);
    scope(exit) jarcBinaryStream_free(reader);

    ubyte data;
    assert(jarcBinaryStream_readBytes(reader, &data, null, 1) == 1);
    assert(data == 0xAA);

    assert(readOk!(ushort, jarcBinaryStream_readU16)(reader) == 0xAABB);
    assert(readOk!(uint, jarcBinaryStream_readU32)(reader) == 0xAABBCCDD);

    assert(readOk!(ulong, jarcBinaryStream_read7BitEncodedU)(reader) == 0x7F);
    assert(readOk!(ulong, jarcBinaryStream_read7BitEncodedU)(reader) == 0x3FFF);
    assert(readOk!(ulong, jarcBinaryStream_read7BitEncodedU)(reader) == 0x1FFFFF);
    assert(readOk!(ulong, jarcBinaryStream_read7BitEncodedU)(reader) == ulong.max);
    assert(jarcBinaryStream_getCursor(reader) == bytes.length);

    assert(jarcBinaryStream_isEof(reader));
    assert(jarcBinaryStream_setCursor(reader, 0) == JARC_OK);
    assert(readOk!(ubyte, jarcBinaryStream_readU8)(reader) == 0xAA);
    assert(jarcBinaryStream_setCursor(reader, 200000) == JARC_EOF);
}