// Read-only SMC access. Uses only the read (5) and key info (9) commands, never a write command.
#include "smc.h"
#include <IOKit/IOKitLib.h>
#include <string.h>
#include <stdint.h>

typedef struct { char major, minor, build, reserved[1]; UInt16 release; } V;
typedef struct { UInt16 version, length; UInt32 cpu, gpu, mem; } P;
typedef struct { UInt32 dataSize, dataType; char attr; } KI;
typedef struct {
    UInt32 key; V v; P p; KI ki;
    char result, status, data8; UInt32 data32; unsigned char bytes[32];
} S;
_Static_assert(sizeof(S) == 80, "SMC struct size");

static UInt32 k4(const char *s) {
    return (UInt32)s[0] << 24 | (UInt32)s[1] << 16 | (UInt32)s[2] << 8 | (UInt32)s[3];
}
static int call(io_connect_t c, S *in, S *out) {
    size_t n = sizeof(S);
    return IOConnectCallStructMethod(c, 2, in, sizeof(S), out, &n) == KERN_SUCCESS && !out->result;
}
static int read_temp(io_connect_t c, const char *key, double *value) {
    S in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = k4(key); in.data8 = 9;
    if (!call(c, &in, &out)) return 0;
    UInt32 size = out.ki.dataSize, type = out.ki.dataType;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = k4(key); in.ki.dataSize = size; in.data8 = 5;
    if (!call(c, &in, &out)) return 0;
    if (type == k4("flt ") && size == 4) {
        float f; memcpy(&f, out.bytes, 4); *value = f; return 1;
    }
    if (type == k4("sp78") && size == 2) {
        *value = (int16_t)(out.bytes[0] << 8 | out.bytes[1]) / 256.0; return 1;
    }
    return 0;
}
double smc_battery_temperature(void) {
    io_service_t s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!s) return -1;
    io_connect_t c = 0;
    kern_return_t r = IOServiceOpen(s, mach_task_self(), 0, &c);
    IOObjectRelease(s);
    if (r != KERN_SUCCESS) return -1;
    const char *keys[] = {"TB0T", "TB1T", "TB2T"};
    double sum = 0; int n = 0;
    for (int i = 0; i < 3; i++) {
        double t;
        if (read_temp(c, keys[i], &t) && t > 0 && t < 100) { sum += t; n++; }
    }
    IOServiceClose(c);
    return n ? sum / n : -1;
}
