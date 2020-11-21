module jarchive.enums;

enum 
{
    JARC_OK             = 0,
    JARC_EOF            = 1000,
    JARC_BAD_DATA       = 1001,
    JARC_UNKNOWN_ERROR  = 1002
}
alias JarcResult = int;

package enum JarcBinaryMode
{
    memory,
    file
}