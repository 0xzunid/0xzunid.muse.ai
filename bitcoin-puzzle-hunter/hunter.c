/* hunter.c — Bitcoin puzzle lottery hunter (1 CPU core)
 *
 * Random-lottery scanner for the 78 unsolved Bitcoin puzzles (bits 71-160).
 * Method: pick a puzzle weighted by expected value (prize / range size),
 * pick a uniform-random block start inside its range, then scan a block of
 * sequential keys using fast EC point addition (one scalar mult per block,
 * ~4096 point additions) with Montgomery batch inversion. Each tested key
 * is uniform-random in its puzzle's range (random block starts).
 *
 * This is a LOTTERY, not a brute-forcer: puzzle 71 alone has 2^70 keys.
 * At ~500k keys/s the chance of hitting #71 on any given day is ~1 in
 * 100 million. Never expect a win; the value is a running ticket.
 *
 * Safety: private keys are NEVER printed or logged. On a HIT the key is
 * written only to HIT-<bits>.json (mode 0600) and that puzzle stops.
 *
 * Build: see build.sh. Uses libsecp256k1 internal API (compiled in from
 * vendor/secp256k1/src/secp256k1.c) + its internal SHA-256, plus a local
 * RIPEMD-160 implementation (verified against known vectors).
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdarg.h>
#include <math.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <signal.h>
#include <errno.h>
#include <sys/random.h>
#include <sys/stat.h>

/* ---- libsecp256k1, compiled into this TU for internal-API access ---- */
#include "secp256k1.c"

/* ================= RIPEMD-160 =================
 * Via OpenSSL (verified against known vectors on this VM). A hand-rolled
 * table-driven implementation was tried first and dropped: its round
 * tables carried a typo (self-test vectors failed) and chasing it was
 * not worth the ~0.5us/key vs the verified library call. */
#include <openssl/ripemd.h>
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
static void ripemd160(const unsigned char *msg, size_t len, unsigned char out[20]) {
    RIPEMD160(msg, len, out);
}
#pragma GCC diagnostic pop

/* ================= helpers ================= */
static void die(const char *m) { fprintf(stderr, "FATAL: %s\n", m); exit(1); }

static void getrandom_bytes(void *buf, size_t n) {
    unsigned char *p = buf;
    while (n > 0) {
        ssize_t r = getrandom(p, n, 0);
        if (r < 0) { if (errno == EINTR) continue; die("getrandom failed"); }
        p += r; n -= (size_t)r;
    }
}

static double rand_double(void) { /* uniform [0,1) */
    uint64_t v; getrandom_bytes(&v, sizeof v);
    return (double)(v >> 11) * (1.0 / 9007199254740992.0);
}

static void iso_now(char *buf, size_t n) {
    struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
    struct tm tm; gmtime_r(&ts.tv_sec, &tm);
    strftime(buf, n, "%Y-%m-%dT%H:%M:%SZ", &tm);
}

static void hex_encode(const unsigned char *in, size_t n, char *out) {
    static const char *H = "0123456789abcdef";
    for (size_t i = 0; i < n; i++) { out[2*i] = H[in[i] >> 4]; out[2*i+1] = H[in[i] & 15]; }
    out[2*n] = 0;
}

static int hex_decode(const char *in, unsigned char *out, size_t n) {
    for (size_t i = 0; i < n; i++) {
        unsigned v;
        if (sscanf(in + 2*i, "%2x", &v) != 1) return 0;
        out[i] = (unsigned char)v;
    }
    return 1;
}

/* big-endian 256-bit key helpers */
static void key_add_u32(unsigned char k[32], uint32_t d) {
    uint64_t c = d;
    for (int i = 31; i >= 0 && c; i--) { c += k[i]; k[i] = (unsigned char)c; c >>= 8; }
}
static void key_add(const unsigned char a[32], uint32_t d, unsigned char out[32]) {
    memcpy(out, a, 32); key_add_u32(out, d);
}
/* return 1 if k + d would set any bit >= nbits (i.e. leave the range) */
static int key_add_overflows_bits(const unsigned char k[32], uint32_t d, int nbits) {
    unsigned char t[32]; key_add(k, d, t);
    /* bit nbits is index: byte 31 - nbits/8, bit nbits%8 (and anything above) */
    int byte = 31 - nbits / 8, bit = nbits % 8;
    if (bit && (t[byte] & (0xFFu << bit))) return 1;
    for (int i = 0; i < byte; i++) if (t[i]) return 1;
    return 0;
}

/* ================= targets ================= */
#define MAX_TARGETS 256
typedef struct {
    int bits;
    char address[64];
    unsigned char hash160[20];
    double btc;
    double weight;      /* btc / range_size, for weighted pick */
    uint64_t scanned;   /* keys tested for this puzzle */
    int solved;         /* 1 after a HIT (stop scanning it) */
} target_t;

static target_t g_targets[MAX_TARGETS];
static int g_ntargets = 0;
static double g_weight_total = 0.0;

static int load_targets(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "cannot open targets file %s\n", path); return 0; }
    fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
    char *buf = malloc(sz + 1);
    if (fread(buf, 1, sz, f) != (size_t)sz) { fclose(f); return 0; }
    fclose(f); buf[sz] = 0;
    /* minimal parser for the generated targets.json layout */
    char *p = buf;
    while ((p = strstr(p, "\"bits\":")) && g_ntargets < MAX_TARGETS) {
        target_t *t = &g_targets[g_ntargets];
        memset(t, 0, sizeof *t);
        t->bits = atoi(p + 7);
        char *q;
        if (!(q = strstr(p, "\"address\": \""))) break;
        q += 12; char *e = strchr(q, '"'); if (!e || (size_t)(e - q) >= sizeof t->address) break;
        memcpy(t->address, q, e - q); t->address[e - q] = 0;
        if (!(q = strstr(p, "\"hash160\": \""))) break;
        q += 12; char hex[41]; memcpy(hex, q, 40); hex[40] = 0;
        if (!hex_decode(hex, t->hash160, 20)) break;
        if (!(q = strstr(p, "\"btc\":"))) break;
        t->btc = strtod(q + 6, NULL);
        t->weight = ldexp(t->btc, -(t->bits - 1)); /* btc / 2^(bits-1) */
        g_weight_total += t->weight;
        g_ntargets++;
        p = e;
    }
    free(buf);
    return g_ntargets > 0;
}

static target_t *pick_target(void) {
    double r = rand_double() * g_weight_total, acc = 0.0;
    for (int i = 0; i < g_ntargets; i++) {
        if (g_targets[i].solved) continue;
        acc += g_targets[i].weight;
        if (r <= acc) return &g_targets[i];
    }
    for (int i = 0; i < g_ntargets; i++) if (!g_targets[i].solved) return &g_targets[i];
    return NULL;
}

/* ================= EC + hashing ================= */
static secp256k1_ecmult_gen_context g_gen_ctx;
static secp256k1_hash_ctx g_hash_ctx;
static secp256k1_ge g_gen; /* affine generator G */

static void ec_init(void) {
    secp256k1_hash_ctx_init(&g_hash_ctx);
    secp256k1_ecmult_gen_context_build(&g_gen_ctx, &g_hash_ctx);
    secp256k1_scalar one; int ov = 0;
    unsigned char b[32] = {0}; b[31] = 1;
    secp256k1_scalar_set_b32(&one, b, &ov);
    secp256k1_gej gj;
    secp256k1_ecmult_gen_gej(&g_gen_ctx, &gj, &one);
    secp256k1_ge_set_gej(&g_gen, &gj);
}

/* compressed pubkey hash160 for a private key (single mult; used by self-test) */
static void hash160_of_key(const unsigned char key[32], unsigned char out20[20]) {
    secp256k1_scalar sc; int ov = 0;
    secp256k1_scalar_set_b32(&sc, key, &ov);
    secp256k1_gej gj; secp256k1_ecmult_gen_gej(&g_gen_ctx, &gj, &sc);
    secp256k1_ge ge; secp256k1_ge_set_gej(&ge, &gj);
    unsigned char pub[33];
    secp256k1_fe_normalize(&ge.x); secp256k1_fe_normalize(&ge.y);
    pub[0] = secp256k1_fe_is_odd(&ge.y) ? 0x03 : 0x02;
    secp256k1_fe_get_b32(pub + 1, &ge.x);
    unsigned char sha[32];
    secp256k1_sha256 sh; secp256k1_sha256_initialize(&sh);
    secp256k1_sha256_write(&g_hash_ctx, &sh, pub, 33);
    secp256k1_sha256_finalize(&g_hash_ctx, &sh, sha);
    ripemd160(sha, 32, out20);
}

/* ================= block scan ================= */
#define BLOCK 4096

static secp256k1_gej g_pts[BLOCK];
static secp256k1_fe g_zinv[BLOCK];
static secp256k1_fe g_prod[BLOCK];

/* Compute hash160s for n sequential keys starting at `start` (32-byte BE).
 * One scalar mult + (n-1) point adds + Montgomery batch inversion. */
static void block_hash160s(const unsigned char start[32], int n, unsigned char out[][20]) {
    secp256k1_scalar sc; int ov = 0;
    secp256k1_scalar_set_b32(&sc, start, &ov);
    secp256k1_gej pt;
    secp256k1_ecmult_gen_gej(&g_gen_ctx, &pt, &sc);
    for (int i = 0; i < n; i++) {
        g_pts[i] = pt;
        secp256k1_gej tmp;
        secp256k1_gej_add_ge_var(&tmp, &pt, &g_gen, NULL);
        pt = tmp;
    }
    /* Montgomery batch inversion of all z's: prefix products, one inverse */
    g_prod[0] = g_pts[0].z;
    for (int i = 1; i < n; i++) secp256k1_fe_mul(&g_prod[i], &g_prod[i-1], &g_pts[i].z);
    secp256k1_fe inv;
    secp256k1_fe_inv(&inv, &g_prod[n-1]);
    for (int i = n - 1; i >= 0; i--) {
        if (i == 0) { g_zinv[0] = inv; }
        else {
            secp256k1_fe_mul(&g_zinv[i], &inv, &g_prod[i-1]);
            secp256k1_fe_mul(&inv, &inv, &g_pts[i].z);
        }
    }
    for (int i = 0; i < n; i++) {
        secp256k1_ge ge;
        secp256k1_ge_set_gej_zinv(&ge, &g_pts[i], &g_zinv[i]);
        unsigned char pub[33];
        secp256k1_fe_normalize(&ge.x); secp256k1_fe_normalize(&ge.y);
        pub[0] = secp256k1_fe_is_odd(&ge.y) ? 0x03 : 0x02;
        secp256k1_fe_get_b32(pub + 1, &ge.x);
        unsigned char sha[32];
        secp256k1_sha256 sh; secp256k1_sha256_initialize(&sh);
        secp256k1_sha256_write(&g_hash_ctx, &sh, pub, 33);
        secp256k1_sha256_finalize(&g_hash_ctx, &sh, sha);
        ripemd160(sha, 32, out[i]);
    }
}

/* Scan BLOCK sequential keys starting at `start` (32-byte BE) for `t`.
 * On hit, writes *hit_key and returns 1. Else 0. Never prints the key. */
static int scan_block(target_t *t, const unsigned char start[32], unsigned char hit_key[32]) {
    static unsigned char hbuf[BLOCK][20];
    block_hash160s(start, BLOCK, hbuf);
    for (int i = 0; i < BLOCK; i++) {
        if (memcmp(hbuf[i], t->hash160, 20) == 0) {
            key_add(start, (uint32_t)i, hit_key);
            return 1;
        }
    }
    return 0;
}

/* ================= random starts ================= */
static void random_start_key(int bits, unsigned char out[32]) {
    int nbytes = (bits + 7) / 8;
    memset(out, 0, 32);
    getrandom_bytes(out + 32 - nbytes, nbytes);
    int topbits = bits % 8;
    unsigned char *top = out + 32 - nbytes;
    if (topbits) *top &= (unsigned char)((1u << topbits) - 1);
    *top |= (unsigned char)(1u << (topbits ? topbits - 1 : 7)); /* set bit bits-1 */
}

/* ================= HIT / state / logging ================= */
static char g_dir[1024] = ".";
static volatile sig_atomic_t g_stop = 0;
static void on_signal(int s) { (void)s; g_stop = 1; }

static uint64_t g_total = 0;
static time_t g_started = 0;

static void path_join(char *dst, size_t n, const char *name) {
    snprintf(dst, n, "%s/%s", g_dir, name);
}

static void save_state(void) {
    char tmp[1200], fin[1200];
    path_join(tmp, sizeof tmp, "state.json.tmp");
    path_join(fin, sizeof fin, "state.json");
    FILE *f = fopen(tmp, "w");
    if (!f) return;
    char now[32]; iso_now(now, sizeof now);
    fprintf(f, "{\n  \"started_at\": %lld,\n  \"updated_at\": \"%s\",\n  \"total_keys\": %llu,\n  \"keys_per_puzzle\": {",
            (long long)g_started, now, (unsigned long long)g_total);
    int first = 1;
    for (int i = 0; i < g_ntargets; i++) {
        fprintf(f, "%s\"%d\": %llu", first ? "" : ", ", g_targets[i].bits,
                (unsigned long long)g_targets[i].scanned);
        first = 0;
    }
    fprintf(f, "}\n}\n");
    fclose(f);
    rename(tmp, fin);
}

static void load_state(void) {
    char p[1200]; path_join(p, sizeof p, "state.json");
    FILE *f = fopen(p, "r");
    if (!f) return;
    char buf[65536]; size_t n = fread(buf, 1, sizeof buf - 1, f); fclose(f); buf[n] = 0;
    char *q;
    if ((q = strstr(buf, "\"total_keys\":"))) g_total = strtoull(q + 13, NULL, 10);
    for (int i = 0; i < g_ntargets; i++) {
        char key[16]; snprintf(key, sizeof key, "\"%d\":", g_targets[i].bits);
        if ((q = strstr(buf, key))) g_targets[i].scanned = strtoull(q + strlen(key), NULL, 10);
    }
}

static void log_line(const char *fmt, ...) {
    char p[1200]; path_join(p, sizeof p, "progress.log");
    FILE *f = fopen(p, "a");
    if (!f) return;
    char now[32]; iso_now(now, sizeof now);
    fprintf(f, "%s ", now);
    va_list ap; va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}

static void write_hit(target_t *t, const unsigned char key[32], uint64_t total, uint64_t puzzle_total) {
    char name[64]; snprintf(name, sizeof name, "HIT-%d.json", t->bits);
    char p[1200]; path_join(p, sizeof p, name);
    int fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) { fprintf(stderr, "FATAL: cannot write hit file %s\n", p); return; }
    fchmod(fd, 0600);
    char keyhex[65]; hex_encode(key, 32, keyhex);
    char now[32]; iso_now(now, sizeof now);
    dprintf(fd, "{\n  \"bits\": %d,\n  \"address\": \"%s\",\n  \"private_key\": \"%s\",\n  \"found_at\": \"%s\",\n  \"keys_scanned_total\": %llu,\n  \"keys_scanned_puzzle\": %llu\n}\n",
            t->bits, t->address, keyhex, now,
            (unsigned long long)total, (unsigned long long)puzzle_total);
    fsync(fd); close(fd);
}

/* ================= self-test ================= */
static int test_ripemd(void) {
    unsigned char out[20]; char hex[41];
    ripemd160((const unsigned char *)"", 0, out); hex_encode(out, 20, hex);
    if (strcmp(hex, "9c1185a5c5e9fc54612808977ee8f548b2258d31") != 0) {
        printf("FAIL ripemd160(\"\") = %s\n", hex); return 0;
    }
    ripemd160((const unsigned char *)"abc", 3, out); hex_encode(out, 20, hex);
    if (strcmp(hex, "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc") != 0) {
        printf("FAIL ripemd160(\"abc\") = %s\n", hex); return 0;
    }
    printf("PASS ripemd160 vectors\n");
    return 1;
}

static int test_key1(void) {
    unsigned char key[32] = {0}; key[31] = 1;
    unsigned char h[20]; char hex[41];
    hash160_of_key(key, h); hex_encode(h, 20, hex);
    if (strcmp(hex, "751e76e8199196d454941c45d1b3a323f1433bd6") != 0) {
        printf("FAIL key1 hash160 = %s\n", hex); return 0;
    }
    printf("PASS key 1 -> hash160 751e76e8199196d454941c45d1b3a323f1433bd6\n");
    return 1;
}

static int test_block_add(void) {
    /* P(k+1) via point-add must equal a fresh scalar mult of k+1 */
    unsigned char k[32] = {0};
    getrandom_bytes(k + 24, 8); k[24] |= 0x40; /* random 71-bit-ish key */
    unsigned char h_add[20], h_mul[20];
    secp256k1_scalar sc; int ov = 0;
    secp256k1_scalar_set_b32(&sc, k, &ov);
    secp256k1_gej pt; secp256k1_ecmult_gen_gej(&g_gen_ctx, &pt, &sc);
    secp256k1_gej tmp; secp256k1_gej_add_ge_var(&tmp, &pt, &g_gen, NULL);
    secp256k1_ge ge; secp256k1_ge_set_gej(&ge, &tmp);
    unsigned char pub[33];
    secp256k1_fe_normalize(&ge.x); secp256k1_fe_normalize(&ge.y);
    pub[0] = secp256k1_fe_is_odd(&ge.y) ? 0x03 : 0x02;
    secp256k1_fe_get_b32(pub + 1, &ge.x);
    unsigned char sha[32];
    secp256k1_sha256 sh; secp256k1_sha256_initialize(&sh);
    secp256k1_sha256_write(&g_hash_ctx, &sh, pub, 33);
    secp256k1_sha256_finalize(&g_hash_ctx, &sh, sha);
    ripemd160(sha, 32, h_add);
    unsigned char k2[32]; key_add(k, 1, k2);
    hash160_of_key(k2, h_mul);
    if (memcmp(h_add, h_mul, 20) != 0) { printf("FAIL block-add != scalar mult\n"); return 0; }
    printf("PASS point-add chain matches fresh scalar mult\n");
    return 1;
}

static int test_batch(void) {
    /* batch-inversion path must match fresh scalar mults, key by key */
    unsigned char k[32] = {0};
    getrandom_bytes(k + 24, 8); k[24] |= 0x40;
    static unsigned char hbuf[4096][20];
    block_hash160s(k, 4096, hbuf);
    for (int i = 0; i < 4096; i++) {
        unsigned char ki[32]; key_add(k, (uint32_t)i, ki);
        unsigned char expect[20]; hash160_of_key(ki, expect);
        if (memcmp(hbuf[i], expect, 20) != 0) {
            char a[41], b[41];
            hex_encode(hbuf[i], 20, a); hex_encode(expect, 20, b);
            printf("FAIL batch key %d: got %s expect %s\n", i, a, b);
            return 0;
        }
    }
    printf("PASS batch inversion matches scalar mults (4096 keys)\n");
    return 1;
}

static int test_planted_hit(void) {
    /* plant a random key's hash160 as a fake target; scan a block
       containing it and confirm detection + secure HIT file write.
       (target = key k+3, block starts at k, so the hit is at index 3) */
    unsigned char k[32] = {0};
    getrandom_bytes(k + 24, 8); k[24] |= 0x40;
    unsigned char k3[32]; key_add(k, 3, k3);
    unsigned char h[20]; hash160_of_key(k3, h);
    target_t fake; memset(&fake, 0, sizeof fake);
    fake.bits = 71; memcpy(fake.hash160, h, 20);
    strcpy(fake.address, "SELFTEST");
    unsigned char hit[32];
    if (!scan_block(&fake, k, hit)) { printf("FAIL planted hit not found\n"); return 0; }
    if (memcmp(hit, k3, 32) != 0) { printf("FAIL planted hit key mismatch\n"); return 0; }
    char p[1200]; snprintf(p, sizeof p, "%s/SELFTEST-HIT.json", g_dir);
    int fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) { printf("FAIL cannot write self-test hit file\n"); return 0; }
    fchmod(fd, 0600);
    struct stat st; fstat(fd, &st);
    dprintf(fd, "{\"selftest\": true}\n"); close(fd);
    if ((st.st_mode & 0777) != 0600) { printf("FAIL hit file mode != 0600\n"); unlink(p); return 0; }
    unlink(p);
    printf("PASS planted hit detected, key matches, HIT file mode 0600\n");
    return 1;
}

static int self_test(void) {
    int ok = 1;
    ok &= test_ripemd();
    ok &= test_key1();
    ok &= test_block_add();
    ok &= test_batch();
    ok &= test_planted_hit();
    printf(ok ? "SELF-TEST: ALL PASS\n" : "SELF-TEST: FAILURES\n");
    return ok ? 0 : 1;
}

/* ================= main ================= */
static void usage(const char *a0) {
    fprintf(stderr,
        "usage: %s [--dir PATH] [--targets FILE] [--block N] [--self-test] [--benchmark SECS]\n"
        "  --dir PATH       work dir (targets.json, state.json, progress.log, HIT-*.json)\n"
        "  --targets FILE   targets file (default <dir>/targets.json)\n"
        "  --block N        keys per block (default 4096)\n"
        "  --self-test      run test vectors + planted-hit check, then exit\n"
        "  --benchmark SECS scan for SECS seconds, print keys/sec, exit\n", a0);
}

static int g_block = BLOCK;

int main(int argc, char **argv) {
    const char *targets_path = NULL;
    int do_selftest = 0, bench_secs = 0;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--dir") && i + 1 < argc) { strncpy(g_dir, argv[++i], sizeof g_dir - 1); }
        else if (!strcmp(argv[i], "--targets") && i + 1 < argc) { targets_path = argv[++i]; }
        else if (!strcmp(argv[i], "--block") && i + 1 < argc) { g_block = atoi(argv[++i]); if (g_block < 16 || g_block > 65536) die("bad --block"); }
        else if (!strcmp(argv[i], "--self-test")) { do_selftest = 1; }
        else if (!strcmp(argv[i], "--benchmark") && i + 1 < argc) { bench_secs = atoi(argv[++i]); }
        else { usage(argv[0]); return 2; }
    }
    /* NOTE: scan_block uses the compile-time BLOCK; --block is accepted but
       only values <= BLOCK are honoured by the fixed arrays. Keep default. */
    if (g_block != BLOCK) { fprintf(stderr, "note: --block is fixed to %d in this build\n", BLOCK); }

    char tp[1200];
    if (targets_path) { strncpy(tp, targets_path, sizeof tp - 1); }
    else { path_join(tp, sizeof tp, "targets.json"); }
    if (!load_targets(tp)) die("no targets loaded");
    ec_init();
    g_started = time(NULL);

    if (do_selftest) return self_test();

    load_state();
    signal(SIGTERM, on_signal);
    signal(SIGINT, on_signal);
    signal(SIGHUP, on_signal);

    char now[32]; iso_now(now, sizeof now);
    log_line("START targets=%d total_keys_resumed=%llu", g_ntargets, (unsigned long long)g_total);
    fprintf(stderr, "[%s] hunter started: %d targets, total_keys=%llu\n",
            now, g_ntargets, (unsigned long long)g_total);

    struct timespec last_save = {0, 0}, last_log = {0, 0};
    clock_gettime(CLOCK_MONOTONIC, &last_save);
    last_log = last_save;
    uint64_t last_total = g_total;
    struct timespec t0; clock_gettime(CLOCK_MONOTONIC, &t0);

    if (bench_secs > 0) {
        struct timespec b0; clock_gettime(CLOCK_MONOTONIC, &b0);
        uint64_t b_start = g_total;
        while (!g_stop) {
            struct timespec cur; clock_gettime(CLOCK_MONOTONIC, &cur);
            if (cur.tv_sec - b0.tv_sec >= bench_secs) break;
            target_t *t = pick_target();
            if (!t) break;
            unsigned char start[32];
            do { random_start_key(t->bits, start); }
            while (key_add_overflows_bits(start, BLOCK, t->bits));
            unsigned char hit[32];
            if (scan_block(t, start, hit)) {
                /* a hit during benchmark: record it properly, then stop */
                write_hit(t, hit, g_total + BLOCK, t->scanned + BLOCK);
                printf("HIT puzzle %d (key saved to HIT-%d.json)\n", t->bits, t->bits);
                t->solved = 1;
            }
            t->scanned += BLOCK; g_total += BLOCK;
        }
        struct timespec b1; clock_gettime(CLOCK_MONOTONIC, &b1);
        double secs = (b1.tv_sec - b0.tv_sec) + (b1.tv_nsec - b0.tv_nsec) / 1e9;
        printf("BENCHMARK: %llu keys in %.1fs -> %.0f keys/sec (1 core)\n",
               (unsigned long long)(g_total - b_start), secs,
               (g_total - b_start) / secs);
        save_state();
        return 0;
    }

    while (!g_stop) {
        target_t *t = pick_target();
        if (!t) { log_line("STOP all puzzles solved or none left"); break; }
        unsigned char start[32];
        do { random_start_key(t->bits, start); }
        while (key_add_overflows_bits(start, BLOCK, t->bits));
        unsigned char hit[32];
        if (scan_block(t, start, hit)) {
            t->scanned += BLOCK; g_total += BLOCK;
            write_hit(t, hit, g_total, t->scanned);
            log_line("HIT puzzle %d address=%s (key saved to HIT-%d.json, mode 0600)",
                     t->bits, t->address, t->bits);
            fprintf(stderr, "HIT puzzle %d! key saved to HIT-%d.json\n", t->bits, t->bits);
            t->solved = 1;
            save_state();
            continue;
        }
        t->scanned += BLOCK; g_total += BLOCK;

        struct timespec cur; clock_gettime(CLOCK_MONOTONIC, &cur);
        double since_save = (cur.tv_sec - last_save.tv_sec) + (cur.tv_nsec - last_save.tv_nsec) / 1e9;
        if (since_save >= 30.0) { save_state(); last_save = cur; }
        double since_log = (cur.tv_sec - last_log.tv_sec) + (cur.tv_nsec - last_log.tv_nsec) / 1e9;
        if (since_log >= 60.0) {
            double rate = (g_total - last_total) / since_log;
            log_line("PROGRESS total=%llu rate=%.0f/s puzzle71=%llu",
                     (unsigned long long)g_total, rate,
                     (unsigned long long)g_targets[0].scanned);
            last_total = g_total; last_log = cur;
        }
    }

    save_state();
    log_line("STOP total_keys=%llu", (unsigned long long)g_total);
    fprintf(stderr, "hunter stopped: total_keys=%llu\n", (unsigned long long)g_total);
    return 0;
}
