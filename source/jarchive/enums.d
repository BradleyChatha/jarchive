module jarchive.enums;

@nogc:

enum : int
{
    JARC_OK             = 0,
    JARC_EOF            = 1000,
    JARC_BAD_DATA       = 1001,
    JARC_UNKNOWN_ERROR  = 1002,
    JARC_CANT_READ      = 1003,
    JARC_CANT_WRITE     = 1004
}
alias JarcResult = int;

package enum JarcBinaryMode
{
    memory,
    file
}

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