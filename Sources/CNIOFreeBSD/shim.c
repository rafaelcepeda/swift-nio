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

void CNIOFreeBSD_i_do_nothing_just_working_around_a_darwin_toolchain_bug(void) {}

#if defined(__FreeBSD__)

#include <CNIOFreeBSD.h>
#include <assert.h>

int CNIOFreeBSD_sendmmsg(int sockfd, CNIOFreeBSD_mmsghdr *msgvec, unsigned int vlen, int flags) {
    return sendmmsg(sockfd, (struct mmsghdr *)msgvec, vlen, flags);
}

int CNIOFreeBSD_recvmmsg(int sockfd, CNIOFreeBSD_mmsghdr *msgvec, unsigned int vlen, int flags, struct timespec *timeout) {
    return recvmmsg(sockfd, (struct mmsghdr *)msgvec, vlen, flags, timeout);
}

int CNIOFreeBSD_pthread_setname_np(pthread_t thread, const char *name) {
    pthread_set_name_np(thread, name);
    return 0;
}

int CNIOFreeBSD_pthread_getname_np(pthread_t thread, char *name, size_t len) {
    pthread_get_name_np(thread, name, len);
    return 0;
}

struct cmsghdr *CNIOFreeBSD_CMSG_FIRSTHDR(const struct msghdr *mhdr) {
    assert(mhdr != NULL);
    return CMSG_FIRSTHDR(mhdr);
}

struct cmsghdr *CNIOFreeBSD_CMSG_NXTHDR(struct msghdr *mhdr, struct cmsghdr *cmsg) {
    assert(mhdr != NULL);
    assert(cmsg != NULL);
    return CMSG_NXTHDR(mhdr, cmsg);
}

const void *CNIOFreeBSD_CMSG_DATA(const struct cmsghdr *cmsg) {
    assert(cmsg != NULL);
    return CMSG_DATA(cmsg);
}

void *CNIOFreeBSD_CMSG_DATA_MUTABLE(struct cmsghdr *cmsg) {
    assert(cmsg != NULL);
    return CMSG_DATA(cmsg);
}

size_t CNIOFreeBSD_CMSG_LEN(size_t payloadSizeBytes) {
    return CMSG_LEN(payloadSizeBytes);
}

size_t CNIOFreeBSD_CMSG_SPACE(size_t payloadSizeBytes) {
    return CMSG_SPACE(payloadSizeBytes);
}

const char *CNIOFreeBSD_inet_ntop(int af, const void *src, char *dst, socklen_t size) {
    return inet_ntop(af, src, dst, size);
}

int CNIOFreeBSD_inet_pton(int af, const char *src, void *dst) {
    return inet_pton(af, src, dst);
}

#endif
