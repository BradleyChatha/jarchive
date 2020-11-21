module jarchive.results;

enum 
{
    JARC_OK         = 0,
    JARC_EOF        = 1000,
    JARC_BAD_DATA   = 1001
}
alias JarcResult = int;