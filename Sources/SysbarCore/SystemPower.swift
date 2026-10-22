import CSystemBridge

public enum SystemPower {
    /// Total machine power draw in watts (AppleSMC `PSTR`), or nil when the key is unavailable.
    public static func watts() -> Double? {
        var value: Float = 0
        guard smc_read_float("PSTR", &value), value.isFinite, value >= 0 else { return nil }
        return Double(value)
    }

    /// Every readable float SMC key whose name starts with `prefix` (diagnostics for `--probe`).
    public static func floatKeys(prefix: String) -> [(key: String, value: Float)] {
        var keys: [(key: String, value: Float)] = []
        var name = [CChar](repeating: 0, count: 5)
        var index: UInt32 = 0
        while index < 4_096, smc_key_at_index(index, &name) {
            let key = String(cString: name)
            var value: Float = 0
            if key.hasPrefix(prefix), smc_read_float(name, &value) {
                keys.append((key, value))
            }
            index += 1
        }
        return keys
    }
}
