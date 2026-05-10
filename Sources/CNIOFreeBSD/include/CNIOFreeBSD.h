#ifndef C_NIO_FREEBSD_H                                                                                                                                                                                            
#define C_NIO_FREEBSD_H                                                                                                                                                                                            
                                                                                                                                                                                                                     
#if defined(__FreeBSD__)                                                                                                                                                                                           
#include <arpa/inet.h>                                                                                                                                                                                             
#include <netinet/in.h>                                                                                                                                                                                            
#include <netinet/ip.h>                                                                                                                                                                                            
#include <sys/socket.h>                                                                                                                                                                                            

const char *CNIOFreeBSD_inet_ntop(int af, const void *src, char *dst, socklen_t size);                                                                                                                             
int CNIOFreeBSD_inet_pton(int af, const char *src, void *dst);

#endif                                                                                                                                                                                                             
                                                                                                                                                                                                                     
#endif
