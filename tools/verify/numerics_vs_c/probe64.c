// probe64.c: R1, the C half. Rung B's primitives in IEEE doubles, inputs made from integers so
// the Rail half (probe64.rail) builds the very same values without parsing a float. Every result
// prints as its 64 bits; the gate diffs the outputs of the four runs (Rail and C, arm64 and x86).
//   cc -O2 -ffp-contract=off probe64.c -o probe64 -lm         (gcc on the x86 runner likewise)
// T1 dot_plain: acc = acc + a*b as two statements (no fma anywhere)
// T2 div, T3 one_over_sqrt, T4 floor, T5 exp_poly (Horner, mul then add), T6 tanh_poly (Pade),
// T7 dot_fma through libm fma (correctly rounded by IEEE 754-2008; the contract's sentence 17
//    says libm is not pinned, this measures whether fma is an exception)
// T8 exp_hw: libm exp, printed and NOT claimed (expected to differ across libms)
#include <stdio.h>
#include <string.h>
#include <math.h>
typedef unsigned long long u64;
static u64 bits(double d) { u64 u; memcpy(&u, &d, 8); return u; }
static double val(long i, long m, long a) { return (double)(((i*m + a) % 1000) - 500)/500.0; }
static void line(const char* t, const char* name, int i, double x) { printf("%s %s %d %016llx\n", t, name, i, bits(x)); }
static double pow2(int k) { double p = 1.0; if (k >= 0) { for (int i = 0; i < k; i++) p = p*2.0; } else { for (int i = 0; i < -k; i++) p = p*0.5; } return p; }

int main(void) {
  // T1: eight chains of 1024 products, no fma
  for (int c = 0; c < 8; c++) { double acc = 0.0;
    for (int k = 0; k < 1024; k++) { double a = val(k + 1024*c, 131, 7), b = val(k + 1024*c, 97, 13); double p = a*b; acc = acc + p; }
    line("T1", "dot_plain", c, acc); }
  // T2: division
  for (int i = 0; i < 8; i++) { double a = val(i, 131, 7), b = val(i, 97, 13) + 1.25; line("T2", "div", i, a/b); }
  // T3: 1/sqrt
  for (int i = 0; i < 8; i++) { double x = val(i, 131, 7) + 1.5; line("T3", "one_over_sqrt", i, 1.0/sqrt(x)); }
  // T4: floor of a scaled value
  for (int i = 0; i < 8; i++) { double x = val(i, 131, 7)*7.0; double t = x*1.4426950408889634; line("T4", "floor", i, floor(t + 0.5)); }
  // T5: exp as 2^(x log2 e), Horner with separate multiply and add, 2^k by exact doubling
  for (int i = 0; i < 8; i++) { double x = val(i, 131, 7)*4.0;
    double t = x*1.4426950408889634; double k = floor(t + 0.5); double f = t - k;
    double p = 0.0013333558; p = p*f; p = p + 0.0096181291; p = p*f; p = p + 0.0555041087; p = p*f; p = p + 0.2402265069;
    p = p*f; p = p + 0.6931471805; p = p*f; p = p + 1.0;
    int ki = (int)k; if (ki < -126) ki = -126; if (ki > 127) ki = 127; line("T5", "exp_poly", i, p*pow2(ki)); }
  // T6: tanh as the Pade (27 + x^2) x / (27 + 9 x^2), clamped
  for (int i = 0; i < 8; i++) { double x = val(i, 131, 7)*6.0; if (x < -5.0) x = -5.0; if (x > 5.0) x = 5.0;
    double x2 = x*x; double n1 = x2 + 27.0; double num = x*n1; double d1 = x2*9.0; double den = d1 + 27.0; line("T6", "tanh_poly", i, num/den); }
  // T7: the same eight chains through libm fma
  for (int c = 0; c < 8; c++) { double acc = 0.0;
    for (int k = 0; k < 1024; k++) { double a = val(k + 1024*c, 131, 7), b = val(k + 1024*c, 97, 13); acc = fma(a, b, acc); }
    line("T7", "dot_fma_libm", c, acc); }
  // T8: libm exp, no claim
  for (int i = 0; i < 8; i++) { double x = val(i, 131, 7)*4.0; line("T8", "exp_libm_noclaim", i, exp(x)); }
  printf("done\n"); return 0; }
