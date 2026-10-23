import Foundation

public enum MemoryPressure: Equatable, Sendable {
    case normal, warning, critical

    /// Maps `kern.memorystatus_vm_pressure_level` (1 normal, 2 warning, 4 critical).
    public init(kernelLevel: Int32) {
        switch kernelLevel {
        case 2: self = .warning
        case 4: self = .critical
        default: self = .normal
        }
    }
}

public struct MemoryReading: Equatable, Sendable {
    public let usedBytes: UInt64
    public let totalBytes: UInt64
    public let pressure: MemoryPressure

    public init(usedBytes: UInt64, totalBytes: UInt64, pressure: MemoryPressure) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.pressure = pressure
    }

    public var fraction: Double {
        totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes)
    }
}

/// Per-component power in watts. A component is nil when no trustworthy sensor exists for it.
public struct PowerReading: Equatable, Sendable {
    public let cpu: Double?
    public let gpu: Double?
    public let ane: Double?
    public let ram: Double?

    public init(cpu: Double?, gpu: Double?, ane: Double?, ram: Double?) {
        self.cpu = cpu
        self.gpu = gpu
        self.ane = ane
        self.ram = ram
    }

    /// Sum of the components that could be read.
    public var packageTotal: Double { [cpu, gpu, ane, ram].compactMap { $0 }.reduce(0, +) }
}

/// Bytes per second in each direction. Disk: read/write. Network: download/upload.
public struct IOThroughput: Equatable, Sendable {
    public let inbound: Double
    public let outbound: Double

    public init(inbound: Double, outbound: Double) {
        self.inbound = inbound
        self.outbound = outbound
    }

    public var total: Double { inbound + outbound }
}

public struct Snapshot: Equatable, Sendable {
    public let timestamp: Date
    /// 0...1
    public let cpuUsage: Double
    public let memory: MemoryReading
    public let power: PowerReading?
    /// Whole-machine power in watts (AppleSMC `PSTR`), when readable.
    public let systemPower: Double?
    /// GPU device utilization, 0...1.
    public let gpuUsage: Double?
    public let disk: IOThroughput?
    public let network: IOThroughput?
    /// Nil on machines without a battery.
    public let battery: BatteryInfo?
    /// Temperatures by source, fans and thermal state, when the sensors can be read.
    public let thermal: ThermalReading?

    public init(
        timestamp: Date, cpuUsage: Double, memory: MemoryReading,
        power: PowerReading?, systemPower: Double?,
        gpuUsage: Double? = nil, disk: IOThroughput? = nil, network: IOThroughput? = nil,
        battery: BatteryInfo? = nil, thermal: ThermalReading? = nil
    ) {
        self.battery = battery
        self.thermal = thermal
        self.timestamp = timestamp
        self.cpuUsage = cpuUsage
        self.memory = memory
        self.power = power
        self.systemPower = systemPower
        self.gpuUsage = gpuUsage
        self.disk = disk
        self.network = network
    }

    /// CPU temperature in °C: the hotter half of the CPU core sensors.
    public var cpuTemperature: Double? { thermal?.celsius(.cpu) }

    /// Best available headline power figure: whole system, else CPU+GPU+ANE+RAM.
    public var headlinePower: Double? {
        systemPower ?? power?.packageTotal
    }
}
