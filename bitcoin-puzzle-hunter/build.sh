#!/bin/bash
# Build the hunter. libsecp256k1 is compiled in from vendor/ (no system install needed).
set -e
cd "$(dirname "$0")"
gcc -O3 -march=native -std=c11 \
  -DUSE_ASM_X86_64=1 -DECMULT_WINDOW_SIZE=15 \
  -I vendor/secp256k1 -I vendor/secp256k1/src \
  hunter.c vendor/secp256k1/src/precomputed_ecmult.c vendor/secp256k1/src/precomputed_ecmult_gen.c \
  -o hunter -lm -lcrypto
echo "built: ./hunter"
