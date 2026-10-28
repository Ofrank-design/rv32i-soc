/* Checks the application image before the bootloader hands control to it.
 *
 * The image lives at APP_BASE: magic (4 bytes), payload length (4), HMAC-SHA256 (32), then the
 * payload itself. The MAC covers the magic, the length and the payload. boot_main() returns the
 * entry address, or 0 if anything looks wrong.
 *
 * There are no writable globals on purpose: this runs before .data/.bss are set up. */
#include <stdint.h>
#include "sha_consts.h"
#include "key.h"

#define APP_BASE 0x1000u
#define HDR_LEN  40u
#define APP_MAX  (0x1000u - HDR_LEN)
#define MAGIC    0xB007AB1Eu

typedef struct { uint32_t h[8]; uint32_t total; uint32_t n; uint8_t buf[64]; } sha_t;

static inline uint32_t ror(uint32_t x, unsigned n) { return (x >> n) | (x << (32u - n)); }

static void block(uint32_t h[8], const uint8_t *p) {
    uint32_t w[64], a, b, c, d, e, f, g, hh, t1, t2;
    unsigned i;
    for (i = 0; i < 16; i++)
        w[i] = ((uint32_t)p[4*i] << 24) | ((uint32_t)p[4*i+1] << 16) |
               ((uint32_t)p[4*i+2] << 8) | p[4*i+3];
    for (i = 16; i < 64; i++) {
        uint32_t s0 = ror(w[i-15], 7) ^ ror(w[i-15], 18) ^ (w[i-15] >> 3);
        uint32_t s1 = ror(w[i-2], 17) ^ ror(w[i-2], 19) ^ (w[i-2] >> 10);
        w[i] = w[i-16] + s0 + w[i-7] + s1;
    }
    a = h[0]; b = h[1]; c = h[2]; d = h[3]; e = h[4]; f = h[5]; g = h[6]; hh = h[7];
    for (i = 0; i < 64; i++) {
        t1 = hh + (ror(e, 6) ^ ror(e, 11) ^ ror(e, 25)) + ((e & f) ^ (~e & g)) + SHA_K[i] + w[i];
        t2 = (ror(a, 2) ^ ror(a, 13) ^ ror(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
}

static void sha_init(sha_t *s) {
    unsigned i;
    for (i = 0; i < 8; i++) s->h[i] = SHA_H0[i];
    s->total = 0; s->n = 0;
}

static void sha_update(sha_t *s, const uint8_t *d, uint32_t len) {
    while (len--) {
        s->buf[s->n++] = *d++;
        s->total++;
        if (s->n == 64) { block(s->h, s->buf); s->n = 0; }
    }
}

static void sha_final(sha_t *s, uint8_t out[32]) {
    uint32_t bits = s->total << 3;       /* total < 2^29 bytes */
    unsigned i;
    s->buf[s->n++] = 0x80;
    if (s->n > 56) { while (s->n < 64) s->buf[s->n++] = 0; block(s->h, s->buf); s->n = 0; }
    while (s->n < 60) s->buf[s->n++] = 0;
    s->buf[60] = bits >> 24; s->buf[61] = bits >> 16; s->buf[62] = bits >> 8; s->buf[63] = bits;
    block(s->h, s->buf);
    for (i = 0; i < 32; i++) out[i] = s->h[i >> 2] >> (24 - 8 * (i & 3));
}

static void hmac(const uint8_t *hdr8, const uint8_t *payload, uint32_t len, uint8_t out[32]) {
    uint8_t pad[64], inner[32];
    sha_t s;
    unsigned i;
    for (i = 0; i < 64; i++) pad[i] = (i < 32 ? HMAC_KEY[i] : 0) ^ 0x36;
    sha_init(&s); sha_update(&s, pad, 64); sha_update(&s, hdr8, 8); sha_update(&s, payload, len);
    sha_final(&s, inner);
    for (i = 0; i < 64; i++) pad[i] = (i < 32 ? HMAC_KEY[i] : 0) ^ 0x5c;
    sha_init(&s); sha_update(&s, pad, 64); sha_update(&s, inner, 32);
    sha_final(&s, out);
}

static uint32_t rd32(const uint8_t *p) {
    return p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

uint32_t boot_main(void) {
    const uint8_t *img = (const uint8_t *)APP_BASE;
    uint8_t mac[32];
    uint32_t len, diff = 0;
    unsigned i;
    if (rd32(img) != MAGIC) return 0;
    len = rd32(img + 4);
    if (len > APP_MAX || (len & 3u)) return 0;
    hmac(img, img + HDR_LEN, len, mac);
    for (i = 0; i < 32; i++) diff |= mac[i] ^ img[8 + i];   /* constant-time compare */
    return diff ? 0u : APP_BASE + HDR_LEN;
}
