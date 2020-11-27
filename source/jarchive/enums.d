module jarchive.enums;

@nogc nothrow:

enum : ubyte
{
    JARC_VERSION_1 = 1,
    JARC_VERSION_LATEST = JARC_VERSION_1
}
alias JarcVersion = ubyte;

enum : int
{
    JARC_OK             = 0,
    JARC_EOF            = 1000,
    JARC_BAD_DATA       = 1001,
    JARC_UNKNOWN_ERROR  = 1002,
    JARC_CANT_READ      = 1003,
    JARC_CANT_WRITE     = 1004,
    JARC_WRONG_MODE     = 1005,
    JARC_OOM            = 1006,
    JARC_NO_HANDLER     = 1007,
    JARC_NO_CHUNK       = 1008
}
alias JarcResult = int;

package enum JarcBinaryMode
{
    memoryBorrowed,
    memoryOwned,
    file
}

enum : ushort
{
    JARC_FLAG_NONE = 0,
    JARC_FLAG_COMPRESSED = 1 << 0
}
alias JarcFlags = ushort;

enum JarcReadWrite : int
{
    none,
    read      = 1 << 0,
    write     = 1 << 1,
    readWrite = read | write
}
alias JARC_READ       = JarcReadWrite.read;
alias JARC_WRITE      = JarcReadWrite.write;
alias JARC_READ_WRITE = JarcReadWrite.readWrite;

bool canRead(JarcReadWrite readWrite)  { return (readWrite & JarcReadWrite.read) != 0; }
bool canWrite(JarcReadWrite readWrite) { return (readWrite & JarcReadWrite.write) != 0; }