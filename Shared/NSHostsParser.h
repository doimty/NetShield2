#ifndef NS_HOSTS_PARSER_H
#define NS_HOSTS_PARSER_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define NSHostsMaximumBytes (2u * 1024u * 1024u)

typedef enum NSHostsParseStatus {
    NSHostsParseOK = 0,
    NSHostsParseTooLarge,
    NSHostsParseInvalidEncoding,
    NSHostsParseConsumerStopped
} NSHostsParseStatus;

typedef struct NSHostsParseStats {
    size_t lines, ignoredLines, redirectLines, invalidLines;
    size_t localNames, invalidNames, acceptedNames;
} NSHostsParseStats;

typedef bool (*NSHostsDomainConsumer)(const char *domain, void *context);

/* Synchronous, bounded, allocation-free; input is never modified. UTF-8 is
 * validated in full before callbacks. NULL bytes is valid only for length 0.
 * stats may be NULL; otherwise it is reset, including on validation failure.
 * Lines count physical lines (CRLF counts once; no phantom line after EOF).
 * ignoredLines: blank/comment; invalidLines: bad address or missing aliases;
 * redirectLines: valid non-block address with aliases (aliases not examined).
 * On block lines each alias counts as localNames, invalidNames or acceptedNames.
 * Domains are lowercase, with one final dot removed; duplicates are emitted.
 * domain is borrowed only for the callback: copy it to retain it. The callback
 * returning false is counted in acceptedNames, then stops immediately. NULL
 * consumer stops at the first eligible domain without counting an emission.
 * Callers own deduplication, capacity policy and transactional persistence.
 */
NSHostsParseStatus NSHostsParse(const unsigned char *bytes, size_t length, NSHostsDomainConsumer consumer,
                                void *context, NSHostsParseStats *stats);

#ifdef __cplusplus
}
#endif
#endif
