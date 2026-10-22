#include "CSystemBridge.h"

#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <string.h>

#define SMC_HANDLE_EVENT 2
#define SMC_CMD_READ_KEY 5
#define SMC_CMD_GET_KEY_FROM_INDEX 8
#define SMC_CMD_GET_KEY_INFO 9
#define SMC_TYPE_FLOAT 0x666c7420u /* 'flt ' */

typedef struct {
    char major, minor, build, reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version, length;
    uint32_t cpuPLimit, gpuPLimit, memPLimit;
} SMCPLimit;

typedef struct {
    uint32_t dataSize, dataType;
    uint8_t dataAttributes;
} SMCKeyInfo;

typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimit pLimitData;
    SMCKeyInfo keyInfo;
    uint8_t result, status, data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParam;

static io_connect_t smcConnection = 0;

static bool smc_open(void) {
    if (smcConnection != 0) return true;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == 0) return false;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &smcConnection);
    IOObjectRelease(service);
    return result == KERN_SUCCESS;
}

static kern_return_t smc_call(const SMCParam *input, SMCParam *output) {
    size_t outputSize = sizeof(SMCParam);
    return IOConnectCallStructMethod(smcConnection, SMC_HANDLE_EVENT,
                                     input, sizeof(SMCParam), output, &outputSize);
}

static uint32_t smc_fourcc(const char *key) {
    uint32_t value = 0;
    for (int i = 0; i < 4; i++) value = (value << 8) | (uint8_t)key[i];
    return value;
}

bool smc_key_at_index(uint32_t index, char key[5]) {
    if (!smc_open()) return false;

    SMCParam input, output;
    memset(&input, 0, sizeof input);
    memset(&output, 0, sizeof output);
    input.data8 = SMC_CMD_GET_KEY_FROM_INDEX;
    input.data32 = index;
    if (smc_call(&input, &output) != KERN_SUCCESS || output.result != 0) return false;

    for (int i = 0; i < 4; i++) key[i] = (char)(output.key >> (8 * (3 - i)));
    key[4] = '\0';
    return true;
}

bool smc_read_float(const char *key, float *value) {
    if (strlen(key) != 4 || !smc_open()) return false;

    SMCParam input, output;
    memset(&input, 0, sizeof input);
    memset(&output, 0, sizeof output);
    input.key = smc_fourcc(key);
    input.data8 = SMC_CMD_GET_KEY_INFO;
    if (smc_call(&input, &output) != KERN_SUCCESS || output.result != 0) return false;
    if (output.keyInfo.dataSize != 4 || output.keyInfo.dataType != SMC_TYPE_FLOAT) return false;

    input.keyInfo.dataSize = output.keyInfo.dataSize;
    input.data8 = SMC_CMD_READ_KEY;
    memset(&output, 0, sizeof output);
    if (smc_call(&input, &output) != KERN_SUCCESS || output.result != 0) return false;

    memcpy(value, output.bytes, sizeof(float));
    return true;
}
