#ifndef CSystemBridge_h
#define CSystemBridge_h

#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>
#include <stdint.h>

// Private IOReport API (libIOReport.dylib). Signatures follow the ones used by
// other open-source Apple Silicon monitors; this app is distributed outside the
// App Store, so private API use is acceptable.
typedef struct IOReportSubscription *IOReportSubscriptionRef;

CF_ASSUME_NONNULL_BEGIN

CFMutableDictionaryRef _Nullable IOReportCopyChannelsInGroup(
    CFStringRef group, CFStringRef _Nullable subgroup,
    uint64_t a, uint64_t b, uint64_t c) CF_RETURNS_RETAINED;

IOReportSubscriptionRef _Nullable IOReportCreateSubscription(
    const void *_Nullable allocator, CFMutableDictionaryRef desired,
    CFMutableDictionaryRef _Nullable *_Nullable subscribed,
    uint64_t channelID, CFTypeRef _Nullable unused);

CFDictionaryRef _Nullable IOReportCreateSamples(
    IOReportSubscriptionRef subscription, CFMutableDictionaryRef subscribed,
    CFTypeRef _Nullable unused) CF_RETURNS_RETAINED;

CFDictionaryRef _Nullable IOReportCreateSamplesDelta(
    CFDictionaryRef previous, CFDictionaryRef current,
    CFTypeRef _Nullable unused) CF_RETURNS_RETAINED;

CFStringRef _Nullable IOReportChannelGetChannelName(CFDictionaryRef channel) CF_RETURNS_NOT_RETAINED;
CFStringRef _Nullable IOReportChannelGetUnitLabel(CFDictionaryRef channel) CF_RETURNS_NOT_RETAINED;
int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef channel, int32_t index);

// AppleSMC: reads a 4-byte float key (e.g. "PSTR" = total system power, watts).
bool smc_read_float(const char *key, float *value);

// AppleSMC: key name (4 chars + NUL) at a given index; false once past the last key.
bool smc_key_at_index(uint32_t index, char *key);

// AppleSMC: raw value of any key with its size and four-character type; fails when the value
// does not fit in `capacity` bytes.
bool smc_read_bytes(const char *key, uint8_t *bytes, uint32_t capacity, uint32_t *size, uint32_t *type);

// AppleSMC: writes a key of four-character `type` (e.g. "ui8 ", "flt ") and exactly `size` bytes;
// refuses a key whose type or size differs. Only succeeds for root (the fan helper).
bool smc_write_bytes(const char *key, const char *type, const uint8_t *bytes, uint32_t size);

CF_ASSUME_NONNULL_END

#endif
