#include "NSHostsParser.h"
#include <arpa/inet.h>
#include <stdint.h>
#include <string.h>

/* Reject non-shortest forms, surrogates, out-of-range scalars and controls.
 * Non-ASCII UTF-8 is permitted in comments, but never in address/name fields. */
static bool ValidEncoding(const unsigned char *bytes, size_t length) {
    size_t i = 0;
    while (i < length) {
        uint32_t scalar = bytes[i++];
        if (scalar < 0x80) {
            if ((scalar < 0x20 && scalar != '\t' && scalar != '\n' && scalar != '\r') || scalar == 0x7f) {
                return false;
            }
            continue;
        }
        size_t remaining;
        uint32_t minimum;
        if (scalar >= 0xc2 && scalar <= 0xdf) {
            remaining = 1;
            minimum = 0x80;
            scalar &= 0x1f;
        } else if (scalar >= 0xe0 && scalar <= 0xef) {
            remaining = 2;
            minimum = 0x800;
            scalar &= 0x0f;
        } else if (scalar >= 0xf0 && scalar <= 0xf4) {
            remaining = 3;
            minimum = 0x10000;
            scalar &= 0x07;
        } else {
            return false;
        }
        if (remaining > length - i) {
            return false;
        }
        while (remaining-- != 0) {
            unsigned char next = bytes[i++];
            if ((next & 0xc0) != 0x80) {
                return false;
            }
            scalar = (scalar << 6) | (next & 0x3f);
        }
        if (scalar < minimum || scalar > 0x10ffff || (scalar >= 0xd800 && scalar <= 0xdfff) ||
            scalar <= 0x9f) {
            return false;
        }
    }
    return true;
}

static bool Space(unsigned char byte) {
    return byte == ' ' || byte == '\t';
}

/* -1 invalid, 0 redirect, 1 block. Compare bytes, not IPv6 spellings. */
static int AddressKind(const unsigned char *bytes, size_t length) {
    char text[INET6_ADDRSTRLEN];
    unsigned char address[16];
    if (length == 0 || length >= sizeof(text)) {
        return -1;
    }
    memcpy(text, bytes, length);
    text[length] = '\0';
    if (inet_pton(AF_INET, text, address) == 1) {
        return (address[0] == 0 && address[1] == 0 && address[2] == 0 && address[3] == 0) ||
               (address[0] == 127 && address[1] == 0 && address[2] == 0 && address[3] == 1);
    }
    if (inet_pton(AF_INET6, text, address) == 1) {
        for (size_t i = 0; i < 15; i++) {
            if (address[i] != 0) {
                return 0;
            }
        }
        return address[15] <= 1;
    }
    return -1;
}

static bool Domain(const unsigned char *bytes, size_t length, char output[254]) {
    if (length != 0 && bytes[length - 1] == '.') {
        length--;
    }
    if (length == 0 || length > 253) {
        return false;
    }
    size_t label = 0;
    bool letter = false;
    for (size_t i = 0; i < length; i++) {
        unsigned char c = bytes[i];
        if (c >= 'A' && c <= 'Z') {
            c = (unsigned char)(c + ('a' - 'A'));
        }
        if (c == '.') {
            if (label == 0 || output[i - 1] == '-') {
                return false;
            }
            label = 0;
        } else {
            bool alpha = c >= 'a' && c <= 'z';
            if ((!alpha && !(c >= '0' && c <= '9') && c != '-') || (label == 0 && c == '-') || ++label > 63) {
                return false;
            }
            letter = letter || alpha;
        }
        output[i] = (char)c;
    }
    if (!letter || label == 0 || output[length - 1] == '-') {
        return false;
    }
    output[length] = '\0';
    return true;
}

static bool LocalName(const char *name) {
    static const char *const names[] = {"localhost", "localhost.localdomain", "ip6-localhost", "ip6-loopback",
                                        "broadcasthost", "ip6-allnodes", "ip6-allrouters",
                                        /* Conventional /etc/hosts IPv6 network/multicast metadata aliases. */
                                        "ip6-localnet", "ip6-mcastprefix", "ip6-allhosts"};
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        if (strcmp(name, names[i]) == 0) {
            return true;
        }
    }
    size_t length = strlen(name);
    return length > 10 && strcmp(name + length - 10, ".localhost") == 0;
}

NSHostsParseStatus NSHostsParse(const unsigned char *bytes, size_t length, NSHostsDomainConsumer consumer,
                                void *context, NSHostsParseStats *stats) {
    NSHostsParseStats discarded;
    if (stats == NULL) {
        stats = &discarded;
    }
    memset(stats, 0, sizeof(*stats));
    if (length > NSHostsMaximumBytes) {
        return NSHostsParseTooLarge;
    }
    if ((bytes == NULL && length != 0) || !ValidEncoding(bytes, length)) {
        return NSHostsParseInvalidEncoding;
    }
    size_t cursor = 0;
    if (length >= 3 && memcmp(bytes, "\xef\xbb\xbf", 3) == 0) {
        cursor = 3;
    }
    while (cursor < length) {
        size_t start = cursor;
        while (cursor < length && bytes[cursor] != '\r' && bytes[cursor] != '\n') {
            cursor++;
        }
        size_t end = cursor;
        if (cursor < length) {
            unsigned char newline = bytes[cursor++];
            if (newline == '\r' && cursor < length && bytes[cursor] == '\n') {
                cursor++;
            }
        }
        stats->lines++;
        for (size_t i = start; i < end; i++) {
            if (bytes[i] == '#') {
                end = i;
                break;
            }
        }
        while (start < end && Space(bytes[start])) {
            start++;
        }
        if (start == end) {
            stats->ignoredLines++;
            continue;
        }
        size_t addressEnd = start;
        while (addressEnd < end && !Space(bytes[addressEnd])) {
            addressEnd++;
        }
        int kind = AddressKind(bytes + start, addressEnd - start);
        start = addressEnd;
        while (start < end && Space(bytes[start])) {
            start++;
        }
        if (kind < 0 || start == end) {
            stats->invalidLines++;
            continue;
        }
        if (kind == 0) {
            stats->redirectLines++;
            continue;
        }
        while (start < end) {
            size_t nameEnd = start;
            while (nameEnd < end && !Space(bytes[nameEnd])) {
                nameEnd++;
            }
            char domain[254];
            if (!Domain(bytes + start, nameEnd - start, domain)) {
                stats->invalidNames++;
            } else if (LocalName(domain)) {
                stats->localNames++;
            } else {
                if (consumer == NULL) {
                    return NSHostsParseConsumerStopped;
                }
                stats->acceptedNames++;
                if (!consumer(domain, context)) {
                    return NSHostsParseConsumerStopped;
                }
            }
            start = nameEnd;
            while (start < end && Space(bytes[start])) {
                start++;
            }
        }
    }
    return NSHostsParseOK;
}
