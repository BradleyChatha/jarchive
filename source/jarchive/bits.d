module jarchive.bits;

import core.stdc.stdio, core.stdc.config;
import jarchive;

extern(C) @nogc:

//////// START TYPES ////////

struct JarcBinaryStream
{
    private:

    JarcBinaryMode mode;
    JarcReadWrite  readWriteMode;

    union
    {
        struct
        {
            ubyte[] data;
            size_t cursor;
            size_t usedCapacity;
        }

        struct
        {
            FILE* file;
            c_long fileSize;
        }
    }

    @disable
    public this(this){}

    @nogc
    public this(ubyte[] data, JarcReadWrite readWrite, bool owned) // Public so std.conv.emplace can see it.
    {
        this.data = data;
        this.mode = (owned) ? JarcBinaryMode.memoryOwned : JarcBinaryMode.memoryBorrowed;
        this.readWriteMode = readWrite;
        this.usedCapacity = this.data.length;
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

        if(this.mode == JarcBinaryMode.memoryOwned
        && this.data !is null)
            free(this.data);
    }
}

//////// START CONSTRUCTORS & DTOR ////////

// 'bytes' is 'borrowed'. JarcBinaryStream cannot grow its size (i.e. pointer won't invalidate), but can still modify it.
JarcBinaryStream* jarcBinaryStream_openBorrowedMemory(JarcReadWrite readWrite, scope ubyte* bytes, size_t length)
{
    return alloc!JarcBinaryStream(bytes[0..length], readWrite, false);
}

private JarcBinaryStream* jarcBinaryStream_openBorrowedMemory(T)(JarcReadWrite readWrite, scope T[] slice)
{
    return jarcBinaryStream_openBorrowedMemory(readWrite, cast(ubyte*)slice.ptr, T.sizeof * slice.length);
}

// 'bytes' is 'owned'. JarcBinaryStream can grow its size (i.e. the pointer can become invalidated, so never touch it again from your own code).
JarcBinaryStream* jarcBinaryStream_openOwnedMemory(JarcReadWrite readWrite, scope ubyte* bytes, size_t length)
{
    return alloc!JarcBinaryStream(bytes[0..length], readWrite, true);
}

// 'bytes' is 'copied'. JarcBinaryStream will duplicate the data, and then works the same as 'owned' memory.
JarcBinaryStream* jarcBinaryStream_openCopyOwnedMemory(JarcReadWrite readWrite, scope ubyte* bytes, size_t length)
{
    scope copied = allocArray!ubyte(length);
    if(copied is null)
        return null;
    copied[0..$] = bytes[0..length];

    auto stream = jarcBinaryStream_openOwnedMemory(readWrite, copied.ptr, length);
    if(stream is null)
    {
        free(copied);
        return null;
    }

    return stream;
}

// Start off with no memory, and dynamically allocate as we go along in 'owned' mode.
JarcBinaryStream* jarcBinaryStream_openNewMemory(JarcReadWrite readWrite)
{
    return alloc!JarcBinaryStream(null, readWrite, true);
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

    scope stream = alloc!JarcBinaryStream(file, readWrite);
    if(stream is null)
        fclose(file);

    return stream;
}

JarcBinaryStream* jarcBinaryStream_openFileByName(JarcReadWrite readWrite, scope const ubyte* name_, size_t length)
{
    scope name = allocArray!ubyte(length + 1);
    if(name is null)
        return null;

    name[0..$-1] = name_[0..length];
    name[$-1] = '\0';

    scope stream = jarcBinaryStream_openFileByNamez(readWrite, name.ptr);
    free(name);

    return stream;
}

void jarcBinaryStream_free(
    JarcBinaryStream* stream
)
{
    assert(stream !is null);
    free!JarcBinaryStream(stream);
}

//////// START CURSOR MANIPULATION ////////

JarcResult jarcBinaryStream_setCursor(
    JarcBinaryStream* stream,
    c_long offset
)
{
    if(stream.mode == JarcBinaryMode.memoryBorrowed || stream.mode == JarcBinaryMode.memoryOwned)
    {
        stream.cursor = cast(size_t)offset;
        return (!jarcBinaryStream_isEof(stream)) ? JARC_OK : JARC_EOF;
    }
    else if(stream.mode == JarcBinaryMode.file)
    {
        const result = fseek(stream.file, offset, SEEK_SET);
        return (result != 0) ? JARC_UNKNOWN_ERROR : JARC_OK;
    }
    else assert(false);
}

c_long jarcBinaryStream_getCursor(
    JarcBinaryStream* stream
)
{
    return (stream.mode == JarcBinaryMode.memoryBorrowed || stream.mode == JarcBinaryMode.memoryOwned)
    ? cast(c_long)stream.cursor
    : ftell(stream.file);
}

bool jarcBinaryStream_isEof(
    JarcBinaryStream* stream
)
{
    return (stream.mode == JarcBinaryMode.memoryBorrowed || stream.mode == JarcBinaryMode.memoryOwned)
    ? stream.cursor >= stream.usedCapacity
    : ftell(stream.file) >= stream.fileSize;
}

//////// START READING ////////

size_t jarcBinaryStream_readBytes(
    JarcBinaryStream* stream, 
    scope ubyte*      buffer, 
    size_t*           bufferSize, 
    size_t            amount
)
{
    import std.algorithm : min;

    if(!stream.readWriteMode.canRead)
        return 0;

    auto toRead = (bufferSize is null)
    ? min(amount, stream.usedCapacity - stream.cursor)
    : min(amount, stream.usedCapacity - stream.cursor, *bufferSize);

    if(toRead != 0)
    {
        if(stream.mode == JarcBinaryMode.memoryBorrowed || stream.mode == JarcBinaryMode.memoryOwned)
            buffer[0..toRead] = stream.data[stream.cursor..stream.cursor+toRead];
        else if(stream.mode == JarcBinaryMode.file)
            fread(buffer, 1, toRead, stream.file);
        else
            assert(false);
    }

    stream.cursor += toRead;
    return toRead;
}

private JarcResult jarcBinaryStream_readPrimitive(T)(
    JarcBinaryStream* stream,
    T* data
)
{
    import std.bitmanip : bigEndianToNative;

    if(!stream.readWriteMode.canRead)
        return JARC_CANT_READ;

    ubyte[T.sizeof] bytes;
    const read = jarcBinaryStream_readBytes(stream, bytes.ptr, null, T.sizeof);
    if(read != bytes.length)
        return JARC_EOF;

    *data = bytes.bigEndianToNative!T;
    return JARC_OK;
}

private mixin template readPrimitive(string name, T) 
{
    mixin(`
    JarcResult jarcBinaryStream_read`~name~`(JarcBinaryStream* stream, T* data)
    {
        return jarcBinaryStream_readPrimitive!T(stream, data); 
    }
    `);
}

mixin readPrimitive!("U8",  ubyte);
mixin readPrimitive!("U16", ushort);
mixin readPrimitive!("U32", uint);
mixin readPrimitive!("U64", ulong);

JarcResult jarcBinaryStream_read7BitEncodedU(
    JarcBinaryStream* stream,
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
        const result = jarcBinaryStream_readPrimitive!ubyte(stream, &next);
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

//////// START WRITING ////////

JarcResult jarcBinaryStream_writeBytes(
    JarcBinaryStream* stream,
    scope const ubyte* bytes,
    size_t amount
)
{
    import std.algorithm : max;

    if(!stream.readWriteMode.canWrite)
        return JARC_CANT_WRITE;

    const end = stream.cursor + amount; // NOT SAFE TO READ IN file MODE.
    final switch(stream.mode) with(JarcBinaryMode)
    {
        case memoryBorrowed:
            if(end >= stream.data.length)
                return JARC_EOF;

            stream.data[stream.cursor..end] = bytes[0..amount];
            stream.cursor = end;
            break;
        
        case memoryOwned:
            if(end >= stream.data.length)
                resizeArray(stream.data, max(4096, end * 2));

            if(end > stream.usedCapacity)
                stream.usedCapacity = end;

            stream.data[stream.cursor..end] = bytes[0..amount];
            stream.cursor = end;
            break;

        case file:
            fwrite(bytes, 1, amount, stream.file);
            break;
    }

    return JARC_OK;
}

private JarcResult jarcBinaryStream_writePrimitive(T)(
    JarcBinaryStream* stream,
    T data
)
{
    import std.bitmanip : nativeToBigEndian;

    if(!stream.readWriteMode.canWrite)
        return JARC_CANT_WRITE;

    const bytes = nativeToBigEndian(data);
    return jarcBinaryStream_writeBytes(stream, bytes.ptr, bytes.length);
}

private mixin template writePrimitive(string name, T) 
{
    mixin(`
    JarcResult jarcBinaryStream_write`~name~`(JarcBinaryStream* stream, T data)
    {
        return jarcBinaryStream_writePrimitive!T(stream, data); 
    }
    `);
}

mixin writePrimitive!("U8",  ubyte);
mixin writePrimitive!("U16", ushort);
mixin writePrimitive!("U32", uint);
mixin writePrimitive!("U64", ulong);

JarcResult jarcBinaryStream_write7BitEncodedU(
    JarcBinaryStream* stream,
    ulong data
)
{
    if(data == 0)
    {
        ubyte b = 0b1000_0000;
        return jarcBinaryStream_writeBytes(stream, &b, 1);
    }

    while(data > 0)
    {
        auto next = cast(ubyte)(data & 0b0111_1111);
        data >>= 7;

        if(data == 0)
            next |= 0b1000_0000;

        const result = jarcBinaryStream_writeBytes(stream, &next, 1);
        if(result != JARC_OK)
            return result;
    }

    return JARC_OK;
}

//////// START UNITTESTS ////////

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

    static T readOk(T, alias Func)(JarcBinaryStream* stream)
    {
        T value;
        assert(Func(stream, &value) == JARC_OK);

        return value;
    }

    static void writeOk(alias Func, T)(JarcBinaryStream* stream, T value)
    {
        assert(Func(stream, value) == JARC_OK);
    }

    static void genericTest(JarcBinaryStream* stream)
    {
        ubyte data;
        assert(jarcBinaryStream_readBytes(stream, &data, null, 1) == 1);
        assert(data == 0xAA);

        assert(readOk!(ushort, jarcBinaryStream_readU16)(stream) == 0xAABB);
        assert(readOk!(uint, jarcBinaryStream_readU32)(stream) == 0xAABBCCDD);

        assert(readOk!(ulong, jarcBinaryStream_read7BitEncodedU)(stream) == 0x7F);
        assert(readOk!(ulong, jarcBinaryStream_read7BitEncodedU)(stream) == 0x3FFF);
        assert(readOk!(ulong, jarcBinaryStream_read7BitEncodedU)(stream) == 0x1FFFFF);
        assert(readOk!(ulong, jarcBinaryStream_read7BitEncodedU)(stream) == ulong.max);
        assert(jarcBinaryStream_getCursor(stream) == bytes.length);

        assert(jarcBinaryStream_isEof(stream));
        assert(jarcBinaryStream_setCursor(stream, 0) == JARC_OK);
        assert(readOk!(ubyte, jarcBinaryStream_readU8)(stream) == 0xAA);
        assert(jarcBinaryStream_setCursor(stream, 200000) == JARC_EOF);
    }

    static void writeTestData(JarcBinaryStream* stream)
    {
        ubyte data = 0xAA;
        assert(jarcBinaryStream_writeBytes(stream, &data, 1) == JARC_OK);

        writeOk!jarcBinaryStream_writeU16(stream, cast(ushort)0xAABB);
        writeOk!jarcBinaryStream_writeU32(stream, 0xAABBCCDD);
        writeOk!jarcBinaryStream_write7BitEncodedU(stream, 0x7F);
        writeOk!jarcBinaryStream_write7BitEncodedU(stream, 0x3FFF);
        writeOk!jarcBinaryStream_write7BitEncodedU(stream, 0x1FFFFF);
        writeOk!jarcBinaryStream_write7BitEncodedU(stream, ulong.max);
        assert(jarcBinaryStream_getCursor(stream) == bytes.length);
        assert(jarcBinaryStream_isEof(stream));
    }

    scope stream = jarcBinaryStream_openBorrowedMemory(JARC_READ, bytes);
    scope(exit) jarcBinaryStream_free(stream);
    genericTest(stream);

    auto ownedBytes = allocArray!ubyte(bytes.length);
    ownedBytes[0..$] = bytes[0..$];
    scope ownedStream = jarcBinaryStream_openOwnedMemory(JARC_READ, ownedBytes.ptr, ownedBytes.length);
    scope(exit) jarcBinaryStream_free(ownedStream);
    genericTest(ownedStream);

    scope copiedStream = jarcBinaryStream_openCopyOwnedMemory(JARC_READ, bytes.ptr, bytes.length);
    genericTest(copiedStream);
    jarcBinaryStream_free(copiedStream); // 'bytes' will be in static data block, so free() would crash if we didn't copy properly

    scope writeStream = jarcBinaryStream_openNewMemory(JARC_READ_WRITE);
    scope(exit) jarcBinaryStream_free(writeStream);
    assert(jarcBinaryStream_writeBytes(writeStream, bytes.ptr, bytes.length) == JARC_OK);
    jarcBinaryStream_setCursor(writeStream, 0);
    genericTest(writeStream);

    scope longWriteStream = jarcBinaryStream_openNewMemory(JARC_READ_WRITE);
    scope(exit) jarcBinaryStream_free(longWriteStream);
    writeTestData(longWriteStream);
    jarcBinaryStream_setCursor(longWriteStream, 0);
    genericTest(longWriteStream);
}