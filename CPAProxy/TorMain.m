//  CPAThread.m
//
//  Copyright (c) 2013 Claudiu-Vlad Ursache.
//  See LICENCE for licensing information
//

#import "TorMain.h"
#import "tor_cpaproxy.h"

void TorMain(NSArray *params)
{
    int count = (int)params.count;
    size_t size = sizeof(char*) * (count + 1);
    char **argv = malloc(size);
    memset(argv, 0, size);

    for (int i = 0; i < count; ++i) {
        argv[i] = strdup([params[i] UTF8String]);
        NSLog(@"%@", params[i]);
    }

    tor_main(count, (const char**)argv);

    for (int i = 0; i < count; ++i) {
        free(argv[i]);
    }
    free(argv);
}

// Function definitions to get version numbers of dependencies to avoid including headers
/** Returns OpenSSL version */
extern const char *OpenSSL_version(int type);
/** Returns Libevent version */
extern const char *event_get_version(void);
/** Returns Tor version */
extern const char *get_version(void);

NSString *getOpenSSLVersion(void)
{
    return [NSString stringWithUTF8String: OpenSSL_version(0)];
}

NSString *getLibEventVersion(void)
{
    return [NSString stringWithUTF8String: event_get_version()];
}

NSString *getTorVersion(void)
{
    return [NSString stringWithUTF8String: get_version()];
}
