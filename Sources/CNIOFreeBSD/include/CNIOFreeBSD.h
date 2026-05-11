//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2026 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
#ifndef C_NIO_FREEBSD_H
#define C_NIO_FREEBSD_H

#if defined(__FreeBSD__)
#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <pthread.h>
#include <pthread_np.h>

typedef struct {
    struct msghdr msg_hdr;
    unsigned int msg_len;
} CNIOFreeBSD_mmsghdr;

typedef struct {
    struct in6_addr ipi6_addr;
    unsigned int ipi6_ifindex;
} CNIOFreeBSD_in6_pktinfo;

int CNIOFreeBSD_sendmmsg(int sockfd, CNIOFreeBSD_mmsghdr *msgvec, unsigned int vlen, int flags);
int CNIOFreeBSD_recvmmsg(int sockfd, CNIOFreeBSD_mmsghdr *msgvec, unsigned int vlen, int flags, struct timespec *timeout);

int CNIOFreeBSD_pthread_setname_np(pthread_t thread, const char *name);
int CNIOFreeBSD_pthread_getname_np(pthread_t thread, char *name, size_t len);

struct cmsghdr *CNIOFreeBSD_CMSG_FIRSTHDR(const struct msghdr *);
struct cmsghdr *CNIOFreeBSD_CMSG_NXTHDR(struct msghdr *, struct cmsghdr *);
const void *CNIOFreeBSD_CMSG_DATA(const struct cmsghdr *);
void *CNIOFreeBSD_CMSG_DATA_MUTABLE(struct cmsghdr *);
size_t CNIOFreeBSD_CMSG_LEN(size_t);
size_t CNIOFreeBSD_CMSG_SPACE(size_t);

extern const int CNIOFreeBSD_IP_PKTINFO;
extern const int CNIOFreeBSD_IPV6_RECVPKTINFO;
extern const int CNIOFreeBSD_IPV6_PKTINFO;

const char *CNIOFreeBSD_inet_ntop(int af, const void *src, char *dst, socklen_t size);
int CNIOFreeBSD_inet_pton(int af, const char *src, void *dst);

#endif
#endif
