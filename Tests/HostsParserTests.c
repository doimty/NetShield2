#include "../Shared/NSHostsParser.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static size_t checks;
#define CHECK(expression)                                                                                    \
    do {                                                                                                     \
        checks++;                                                                                            \
        if (!(expression)) {                                                                                 \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #expression);                            \
            exit(1);                                                                                         \
        }                                                                                                    \
    } while (0)

typedef struct Capture {
    size_t count, stop;
    char names[32][254];
} Capture;

static bool Consume(const char *domain, void *context) {
    Capture *capture = context;
    CHECK(capture->count < 32);
    CHECK(strlen(domain) <= 253);
    strcpy(capture->names[capture->count++], domain);
    return capture->stop == 0 || capture->count < capture->stop;
}

static NSHostsParseStats Parse(const char *text, Capture *capture) {
    NSHostsParseStats stats;
    CHECK(NSHostsParse((const unsigned char *)text, strlen(text), Consume, capture, &stats) ==
          NSHostsParseOK);
    CHECK(stats.acceptedNames == capture->count);
    return stats;
}

static void Syntax(void) {
    Capture c = {0};
    NSHostsParseStats s = Parse("\xef\xbb\xbf# UTF-8 \xe4\xb8\xad\xf0\x9f\x98\x80\r\n"
                                " \t\r0.0.0.0\tEXample.COM. www.Example.com alias#inline\r\n"
                                "127.0.0.1 example.com\n:: V6.example\r::1 end.example",
                                &c);
    CHECK(s.lines == 6 && s.ignoredLines == 2 && s.acceptedNames == 6);
    CHECK(strcmp(c.names[0], "example.com") == 0);
    CHECK(strcmp(c.names[1], "www.example.com") == 0);
    CHECK(strcmp(c.names[2], "alias") == 0);
    CHECK(strcmp(c.names[3], "example.com") == 0);
    CHECK(strcmp(c.names[4], "v6.example") == 0);
    CHECK(strcmp(c.names[5], "end.example") == 0);
    CHECK(s.invalidLines == 0 && s.redirectLines == 0);
    c = (Capture){0};
    s = Parse("0:0:0:0:0:0:0:0 a\n0000:0000:0000:0000:0000:0000:0000:0001 b\n"
              "::0.0.0.0 c\n::0.0.0.1 d\n"
              "127.0.0.2 ignored\n1.2.3.4 ignored\n::2 ignored\n"
              "::ffff:127.0.0.1 ignored\n2001:DB8::1 ignored\n"
              "255.255.255.255 ignored\n::ffff:0.0.0.0 ignored",
              &c);
    CHECK(s.lines == 11 && s.acceptedNames == 4 && s.redirectLines == 7);
    c = (Capture){0};
    s = Parse("bare.example\n||ad.example^\n0.0.0.0\n::1 #empty\n"
              "999.0.0.0 a\n01.2.3.4 a\n[::] a\nfe80::1%en0 a\n"
              "http://example.com a\n0.0.0 a\n0x00000000 a\n"
              "0.0.0.0 -a a- a..b .a a.. *.a a_b 123 1.2.3.4 ::1 [::1] "
              "\xe4\xb8\xad.example valid.example xn--fiqs8s.example\n",
              &c);
    CHECK(s.invalidLines == 11 && s.invalidNames == 12 && s.acceptedNames == 2);
    const char *ambiguous[] = {"00.0.0.0",         "127.00.0.1",        "127.0.0.", "::1%lo0", "::%lo0",
                               "fe80::1%nosuchif", "::ffff:127.00.0.1", "::0.0.0.", "[::1]"};
    for (size_t i = 0; i < sizeof(ambiguous) / sizeof(ambiguous[0]); i++) {
        char line[96];
        (void)snprintf(line, sizeof(line), "%s unsafe.example", ambiguous[i]);
        c = (Capture){0};
        s = Parse(line, &c);
        CHECK(s.invalidLines == 1 && s.redirectLines == 0 && s.acceptedNames == 0);
    }
    c = (Capture){0};
    s = Parse("0.0.0.0 LOCALHOST. a.localhost a.b.localhost localhost.localdomain "
              "ip6-localhost ip6-loopback broadcasthost ip6-allnodes ip6-allrouters "
              "ip6-localnet ip6-mcastprefix ip6-allhosts "
              "notlocalhost localhost.example localhost.localdomain.example",
              &c);
    CHECK(s.localNames == 12 && s.acceptedNames == 3);
    c = (Capture){0};
    s = Parse("\n\r\n\r", &c);
    CHECK(s.lines == 3 && s.ignoredLines == 3);
    s = Parse("", &c);
    CHECK(s.lines == 0);
    s = Parse("\xef\xbb\xbf", &c);
    CHECK(s.lines == 0);
}

static void DomainLimits(void) {
    char input[400];
    for (size_t n = 0; n <= 255; n++) {
        char domain[257];
        memset(domain, 'a', n);
        /* Labels <= 63, testing normalized total length independently. */
        for (size_t i = 63; i < n; i += 64) {
            domain[i] = '.';
        }
        domain[n] = '\0';
        for (size_t dot = 0; dot < 2; dot++) {
            if (dot) {
                domain[n] = '.';
                domain[n + 1] = '\0';
            }
            (void)snprintf(input, sizeof(input), "0.0.0.0 %s", domain);
            Capture c = {0};
            NSHostsParseStats s = Parse(input, &c);
            size_t normalized = n;
            if (!dot && n && domain[n - 1] == '.') {
                normalized--;
            }
            bool valid = normalized > 0 && normalized <= 253 && domain[normalized - 1] != '.';
            CHECK(s.acceptedNames == (valid ? 1u : 0u));
        }
    }
    for (size_t n = 62; n <= 65; n++) {
        memset(input, 'a', sizeof(input));
        memcpy(input, "0.0.0.0 ", 8);
        input[8 + n] = '\0';
        Capture c = {0};
        NSHostsParseStats s = Parse(input, &c);
        CHECK(s.acceptedNames == (n <= 63 ? 1u : 0u));
        CHECK(s.invalidNames == (n > 63 ? 1u : 0u));
    }
}

static void EncodingFailure(const unsigned char *bad, size_t length) {
    unsigned char input[128] = "0.0.0.0 safe.example\n#";
    size_t prefix = strlen((const char *)input);
    CHECK(prefix + length <= sizeof(input));
    memcpy(input + prefix, bad, length);
    unsigned char before[128];
    memcpy(before, input, sizeof(input));
    Capture c = {0};
    NSHostsParseStats s;
    memset(&s, 0xff, sizeof(s));
    CHECK(NSHostsParse(input, prefix + length, Consume, &c, &s) == NSHostsParseInvalidEncoding);
    CHECK(c.count == 0 && s.acceptedNames == 0 && s.lines == 0);
    CHECK(s.ignoredLines == 0 && s.redirectLines == 0 && s.invalidLines == 0 && s.invalidNames == 0 &&
          s.localNames == 0);
    CHECK(memcmp(before, input, sizeof(input)) == 0);
}

static void Encoding(void) {
    static const struct {
        unsigned char bytes[4];
        size_t length;
    } bad[] = {{{0}, 1},
               {{0x80}, 1},
               {{0xc0, 0xaf}, 2},
               {{0xc1, 0xbf}, 2},
               {{0xc2}, 1},
               {{0xc2, 0x20}, 2},
               {{0xe0, 0x80, 0xaf}, 3},
               {{0xed, 0xa0, 0x80}, 3},
               {{0xef, 0xbb}, 2},
               {{0xf0, 0x80, 0x80, 0x80}, 4},
               {{0xf4, 0x90, 0x80, 0x80}, 4},
               {{0xf5, 0x80, 0x80, 0x80}, 4},
               {{0xf0, 0x90, 0x80}, 3},
               {{0xff, 0xfe}, 2},
               {{0xfe, 0xff}, 2},
               {{0, 0, 0xfe, 0xff}, 4},
               {{0xc2, 0x85}, 2},
               {{0xc2, 0x9f}, 2}};
    for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); i++) {
        EncodingFailure(bad[i].bytes, bad[i].length);
    }
    for (unsigned int i = 0; i <= 0x7f; i++) {
        if ((i < 0x20 && i != '\t' && i != '\r' && i != '\n') || i == 0x7f) {
            unsigned char byte = (unsigned char)i;
            EncodingFailure(&byte, 1);
        }
    }
    Capture c = {0};
    NSHostsParseStats s = Parse("#\xc2\xa0\xdf\xbf\xe0\xa0\x80\xed\x9f\xbf"
                                "\xee\x80\x80\xef\xbf\xbf\xf0\x90\x80\x80\xf4\x8f\xbf\xbf\n"
                                "0.0.0.0 valid",
                                &c);
    CHECK(s.acceptedNames == 1);
}

static void LimitsAndAbort(void) {
    unsigned char *input = malloc((size_t)NSHostsMaximumBytes + 1);
    CHECK(input != NULL);
    memset(input, ' ', (size_t)NSHostsMaximumBytes + 1);
    Capture c = {0};
    NSHostsParseStats s;
    for (size_t n = NSHostsMaximumBytes - 1; n <= NSHostsMaximumBytes; n++) {
        CHECK(NSHostsParse(input, n, Consume, &c, &s) == NSHostsParseOK);
        CHECK(s.lines == 1 && s.ignoredLines == 1);
    }
    CHECK(NSHostsParse(input, (size_t)NSHostsMaximumBytes + 1, Consume, &c, &s) == NSHostsParseTooLarge);
    CHECK(s.lines == 0 && c.count == 0);
    /* Size rejection precedes dereferencing even an absent buffer. */
    CHECK(NSHostsParse(NULL, (size_t)-1, Consume, &c, &s) == NSHostsParseTooLarge);
    CHECK(NSHostsParse(NULL, 1, Consume, &c, &s) == NSHostsParseInvalidEncoding);
    CHECK(NSHostsParse(NULL, 0, NULL, NULL, NULL) == NSHostsParseOK);
    memcpy(input, "0.0.0.0 ", 8);
    memset(input + 8, 'a', NSHostsMaximumBytes - 8);
    CHECK(NSHostsParse(input, NSHostsMaximumBytes, Consume, &c, &s) == NSHostsParseOK);
    CHECK(s.invalidNames == 1 && c.count == 0);
    memset(input, 'a', NSHostsMaximumBytes);
    CHECK(NSHostsParse(input, NSHostsMaximumBytes, Consume, &c, &s) == NSHostsParseOK);
    CHECK(s.invalidLines == 1);
    memset(input, '\n', NSHostsMaximumBytes);
    CHECK(NSHostsParse(input, NSHostsMaximumBytes, Consume, &c, &s) == NSHostsParseOK);
    CHECK(s.lines == NSHostsMaximumBytes && s.ignoredLines == NSHostsMaximumBytes);
    free(input);
    unsigned char text[] = "0.0.0.0 a b c\n0.0.0.0 d";
    c.stop = 2;
    CHECK(NSHostsParse(text, sizeof(text) - 1, Consume, &c, &s) == NSHostsParseConsumerStopped);
    CHECK(c.count == 2 && s.acceptedNames == 2 && s.lines == 1);
    CHECK(strcmp((const char *)text, "0.0.0.0 a b c\n0.0.0.0 d") == 0);
    CHECK(NSHostsParse(text, sizeof(text) - 1, NULL, NULL, &s) == NSHostsParseConsumerStopped);
    CHECK(s.acceptedNames == 0 && s.lines == 1);
    c = (Capture){0};
    CHECK(NSHostsParse(text, sizeof(text) - 1, Consume, &c, NULL) == NSHostsParseOK);
    CHECK(c.count == 4);
}

int main(void) {
    Syntax();
    DomainLimits();
    Encoding();
    LimitsAndAbort();
    printf("Hosts parser: %zu checks passed\n", checks);
    return 0;
}
