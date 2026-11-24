# Latency and Data Format

## Number format

All floating-point values are IEEE 754 binary64: sign bit 63, biased exponent bits [62:52] (bias 1023), fraction bits [51:0], precision 53 bits.

| Class | Encoding |
| --- | --- |
| Zero | exponent 0, fraction 0 (both signs) |
| Subnormal | exponent 0, fraction nonzero; smallest 0000000000000001 |
| Normal | exponent 1..2046; smallest 0010000000000000, largest finite 7fefffffffffffff |
| Infinity | exponent 2047, fraction 0 |
| Quiet NaN | exponent 2047, fraction bit 51 = 1 |
| Signaling NaN | exponent 2047, fraction bit 51 = 0, fraction nonzero |

Subnormal inputs and results are fully supported; there is no flush-to-zero or denormals-are-zero mode.

## Results

| Operation | Result bits |
| --- | --- |
| ADD, SUB, MUL, DIV, SQRT, int to binary64, FMIN, FMAX | binary64 in [63:0] |
| binary64 to int32 / uint32 | integer in [31:0], bits [63:32] zero for both signed and unsigned |
| FEQ, FLT, FLE | 0 or 1 in bit 0, bits [63:1] zero |
| FCLASS | one-hot mask in [9:0], bits [63:10] zero |

Integer inputs of the int-to-binary64 conversions are read from operand A bits [31:0]; bits [63:32] are ignored.

### NaN results

An invalid arithmetic operation, or arithmetic with a NaN input, returns the canonical quiet NaN `7ff8000000000000`; the sign and payload of input NaNs are not propagated. NV is set when the operation is invalid or when an input is a signaling NaN; a quiet NaN input alone does not set NV. FMIN and FMAX return the non-NaN operand when exactly one input is NaN, bit for bit.

### Invalid conversions

NaN, infinity, or a value whose rounded integer is out of range sets NV only (NX is not set) and returns:

| Input | binary64 to int32 | binary64 to uint32 |
| --- | --- | --- |
| NaN (any sign) | 7fffffff | ffffffff |
| +Inf, or rounded value above the maximum | 7fffffff | ffffffff |
| -Inf, or rounded value below the minimum | 80000000 | 00000000 |

A negative value that rounds to zero is a valid uint32 result (0, with NX if the input was not zero).

### Signed zero

An exact zero from ADD/SUB of operands with opposite effective signs is -0 in RDN and +0 in the other modes. MUL and DIV give the exclusive OR of the input signs. SQRT(-0) = -0. FMIN(-0, +0) = -0 and FMAX(-0, +0) = +0 in either order.

## Flags

Flags are per transaction; one operation never affects the flags of another. Overflow is decided on the result rounded to 53 bits with an unbounded exponent: an overflowing result sets OF and NX and returns infinity or the largest finite value according to the rounding direction. Underflow uses tininess detected after rounding, and UF is set only when the result is also inexact; an exact subnormal result sets no flag. There are no traps.

## Latency

Latency is counted in clock edges: an input sampled at rising edge n produces a valid output after rising edge n+L. A block with L = 0 has one output register.

| Block | L (edges) | Accepts a new input |
| --- | ---: | --- |
| `vrm_fpu_add_sub_64` | 2 | every cycle |
| `vrm_fpu_mul_64` | 5 | every cycle |
| `vrm_fpu_div_64` | 56 | every cycle |
| `vrm_fpu_sqrt_64` | 56 | every cycle |
| `vrm_fpu_conv_64` | 1 | every cycle |
| `vrm_fpu_misc_64` | 0 | every cycle |
| `vrm_fpu_native_64` (any operation) | 56 | every cycle |
| `vrm_fpu_round_64`, `vrm_fpu_prenorm_64` | combinational | - |

Each lane and the dispatcher are checked for this exact latency on every record by the testbenches. Through `vrm_fpu_axi_64`, the time from operand B to the result beat adds the request and result FIFOs; it is not a fixed value and is not specified.

At 100 MHz, the dispatcher accepts one operation per cycle. The AXI4-Stream input needs two beats per operation, so a continuous stream through the wrapper is limited to one operation every two cycles. With one simple-mode DMA transfer per operation, software overhead dominates; the board test measured about 1,200 operations per second on a Kria KR260.

## Vector file format

Testbench vectors in `tb/mem/` are ASCII hexadecimal, one 256-bit word per line. Word 0 is the magic value `f7540001`, word 1 is the record count, then one record per line:

| Bits | Field |
| --- | --- |
| [255:240] | record number |
| [239:232] | OP |
| [231:224] | FUNCT3 |
| [223:216] | RM |
| [215:152] | operand A |
| [151:88] | operand B |
| [87:24] | expected result |
| [20:16] | expected flags {NV, DZ, OF, UF, NX} |
| other | zero |

`round.mem` uses the same layout with the round/pack inputs: sign in bit 215, signed exponent in [165:152], significand in [143:88].
