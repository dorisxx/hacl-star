#include "tweetnacl.h"
#include "testlib.h"
#include "testutils.h"

#define SIZE (1024*1024)
#define ROUNDS (1000)
#define MESSAGE_LEN 44
#define secretbox_MACBYTES   16
#define CIPHERTEXT_LEN (secretbox_MACBYTES + MESSAGE_LEN + 32)
#define secretbox_NONCEBYTES 24
#define secretbox_KEYBYTES   32
#define box_MACBYTES         16
#define box_PUBLICKEYBYTES   32
#define box_SECRETKEYBYTES   32
#define box_NONCEBYTES       24

uint8_t *msg = (uint8_t*) "testtesttesttesttesttesttesttesttesttesttest";

uint8_t nonce[secretbox_NONCEBYTES] = {
  0x00, 0x01, 0x02, 0x03,
  0x04, 0x05, 0x06, 0x07,
  0x08, 0x09, 0x10, 0x11,
  0x12, 0x13, 0x14, 0x15,
  0x16, 0x17, 0x18, 0x19,
  0x20, 0x21, 0x22, 0x23,
};

uint8_t key[secretbox_KEYBYTES] = {
  0x85, 0xd6, 0xbe, 0x78,
  0x57, 0x55, 0x6d, 0x33,
  0x7f, 0x44, 0x52, 0xfe,
  0x42, 0xd5, 0x06, 0xa8,
  0x01, 0x03, 0x80, 0x8a,
  0xfb, 0x0d, 0xb2, 0xfd,
  0x4a, 0xbf, 0xf6, 0xaf,
  0x41, 0x49, 0xf5, 0x1b
};

uint8_t sk[secretbox_KEYBYTES] = {
  0x85, 0xd6, 0xbe, 0x78,
  0x57, 0x55, 0x6d, 0x33,
  0x7f, 0x44, 0x52, 0xfe,
  0x42, 0xd5, 0x06, 0xa8,
  0x01, 0x03, 0x80, 0x8a,
  0xfb, 0x0d, 0xb2, 0xfd,
  0x4a, 0xbf, 0xf6, 0xaf,
  0x41, 0x49, 0xf5, 0x1c
};

void test_box(unsigned char* plain, unsigned char* cipher) {
  uint8_t mac[16];
  clock_t c1, c2;
  double t1, t2;
  unsigned long long a,b,d1,d2;
  int i;
  c1 = clock();
  a = rdtsc();
  for (i=0; i < ROUNDS; i++) crypto_secretbox(cipher, plain, SIZE, nonce, key);
  b = rdtsc();
  c2 = clock();
  t2 = ((double)c2 - c1)/CLOCKS_PER_SEC;
  d2 = b - a;
  printf("[Box] No of cycles for TweetNacl: %llu\n", d2);
  printf("[Box] User time for TweetNacl: %f\n", t2);
  printf("[Box] Cycles/byte ratio TweetNacl): %lf\n", (double)d2/SIZE/ROUNDS);
}

void test_poly1305(unsigned char* plain) {
  uint8_t mac[16];
  clock_t c1, c2;
  double t1, t2;
  unsigned long long a,b,d1,d2;
  int i;
  c1 = clock();
  a = rdtsc();
  for (i=0; i < ROUNDS; i++) crypto_onetimeauth(plain, plain, SIZE, key);
  b = rdtsc();
  c2 = clock();
  t2 = ((double)c2 - c1)/CLOCKS_PER_SEC;
  d2 = b - a;
  printf("[Poly1305] No of cycles for TweetNacl: %llu\n", d2);
  printf("[Poly1305] User time for TweetNacl: %f\n", t2);
  printf("[Poly1305] Cycles/byte ratio TweetNacl): %lf\n", (double)d2/SIZE/ROUNDS);
}

void test_xsalsa20(unsigned char* plain, unsigned char* cipher) {
  uint8_t mac[16];
  clock_t c1, c2;
  double t1, t2;
  unsigned long long a,b,d1,d2;
  int i;
  c1 = clock();
  a = rdtsc();
  for (i=0; i < ROUNDS; i++) crypto_stream_salsa20_xor(cipher, plain, SIZE, nonce, key);
  b = rdtsc();
  c2 = clock();
  t2 = ((double)c2 - c1)/CLOCKS_PER_SEC;
  d2 = b - a;
  printf("[XSalsa20] No of cycles for TweetNacl: %llu\n", d2);
  printf("[XSalsa20] User time for TweetNacl: %f\n", t2);
  printf("[XSalsa20] Cycles/byte ratio TweetNacl): %lf\n", (double)d2/SIZE/ROUNDS);
}

void test_curve25519(unsigned char* plain, unsigned char* cipher) {
  uint8_t mac[16];
  clock_t c1, c2;
  double t1, t2;
  unsigned long long a,b,d1,d2;
  unsigned char pk[32];
  int i;
  c1 = clock();
  a = rdtsc();
  for (i=0; i < ROUNDS; i++) crypto_scalarmult_curve25519(pk, key, sk);
  b = rdtsc();
  c2 = clock();
  t2 = ((double)c2 - c1)/CLOCKS_PER_SEC;
  d2 = b - a;
  printf("[Curve25519] No of cycles for TweetNacl: %llu\n", d2);
  printf("[Curve25519] User time for TweetNacl: %f\n", t2);
  printf("[Curve25519] Cycles/round ratio TweetNacl): %lf\n", (double)d2/ROUNDS);
}

int main(){
  void *plain = malloc(SIZE+32+16), *cipher = malloc(SIZE+32+16);
  test_box(plain, cipher);
  test_poly1305(plain);
  test_xsalsa20(plain, cipher);
  test_curve25519(plain, cipher);
  free(plain);
  free(cipher);
  return EXIT_SUCCESS;
}
