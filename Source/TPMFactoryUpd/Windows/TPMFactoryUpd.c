/** Windows entry point for TPMFactoryUpd 02.03.4733.00. */
#include "StdInclude.h"
#include "Controller.h"

int wmain(int argc, wchar_t* argv[])
{
    unsigned int rc = Controller_Proceed(argc, (const wchar_t* const*)argv);
    return (RC_SUCCESS == rc) ? 0 : 1;
}
