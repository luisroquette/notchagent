import Foundation
import IOKit
import IOKit.serial

private func registryInteger(_ service: io_service_t, key: String) -> Int? {
    let options = IOOptionBits(kIORegistryIterateParents | kIORegistryIterateRecursively)
    guard let value = IORegistryEntrySearchCFProperty(
        service,
        kIOServicePlane,
        key as CFString,
        kCFAllocatorDefault,
        options
    ) as? NSNumber else { return nil }
    return value.intValue
}

private func deskPaths() -> [String] {
    guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else { return [] }
    let matchingDictionary = matching as NSMutableDictionary
    matchingDictionary[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
        return []
    }
    defer { IOObjectRelease(iterator) }

    var paths: [String] = []
    while true {
        let service = IOIteratorNext(iterator)
        guard service != 0 else { break }
        defer { IOObjectRelease(service) }
        guard registryInteger(service, key: "idVendor") == 0x303A,
              registryInteger(service, key: "idProduct") == 0x1001,
              let path = IORegistryEntryCreateCFProperty(
                service,
                kIOCalloutDeviceKey as CFString,
                kCFAllocatorDefault,
                0
              )?.takeRetainedValue() as? String else { continue }
        paths.append(path)
    }
    return Array(Set(paths)).sorted()
}

let paths = deskPaths()
if CommandLine.arguments.count == 2 {
    let requested = CommandLine.arguments[1]
    guard paths.contains(requested) else {
        FileHandle.standardError.write(Data("FAIL: requested port is not a NotchAgent Desk Beta 1.\n".utf8))
        exit(1)
    }
    print(requested)
} else {
    paths.forEach { print($0) }
}
