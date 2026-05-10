void CNIOFreeBSD_i_do_nothing_just_working_around_a_darwin_toolchain_bug(void) {}

#if defined(__FreeBSD__)                                                                                                                                                                                           
#include <arpa/inet.h>                                                                                                                                                                                             
                                                                                                                                                                                                                     
const char *CNIOFreeBSD_inet_ntop(int af, const void *src, char *dst, socklen_t size) {                                                                                                                            
    return inet_ntop(af, src, dst, size);                                                                                                                                                                          
}                                                                                                                                                                                                                  
                  
int CNIOFreeBSD_inet_pton(int af, const char *src, void *dst) {                                                                                                                                                    
    return inet_pton(af, src, dst);
}                                                                                                                                                                                                                  
#endif
