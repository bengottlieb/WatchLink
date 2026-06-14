#if os(iOS)
import Foundation
@preconcurrency import CoreBluetooth
import WatchLinkCore

@WatchLinkActor
package final class BLEAdvertiser {
    private nonisolated(unsafe) let serviceUUID: CBUUID
    private nonisolated(unsafe) let ipCharacteristicUUID: CBUUID
    private let delegate: PeripheralDelegate
    // Created lazily in startAdvertising, NOT in init: instantiating a CBPeripheralManager eagerly
    // spins up CoreBluetooth, which then runs continuous TCC-authorization preflight + XPC + os_log
    // on the main thread — sustained device heat even when advertising never starts and no central
    // is present.
    private var peripheralManager: CBPeripheralManager?
    private var ipCharacteristic: CBMutableCharacteristic?

    package nonisolated init(serviceUUID: UUID, ipCharacteristicUUID: UUID) {
        self.serviceUUID = CBUUID(nsuuid: serviceUUID)
        self.ipCharacteristicUUID = CBUUID(nsuuid: ipCharacteristicUUID)
        self.delegate = PeripheralDelegate()
    }

    package func startAdvertising(ip: String) {
        let serviceCBUUID = serviceUUID
        let ipCBUUID = ipCharacteristicUUID
        let ipData = Data(ip.utf8)
        let manager = peripheralManager ?? CBPeripheralManager(delegate: delegate, queue: nil)
        peripheralManager = manager

        let characteristic = CBMutableCharacteristic(
            type: ipCBUUID,
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable]
        )
        ipCharacteristic = characteristic

        delegate.onReadyToAdvertise = {
            let service = CBMutableService(type: serviceCBUUID, primary: true)
            service.characteristics = [characteristic]
            manager.add(service)
            manager.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [serviceCBUUID],
            ])
        }

        delegate.onReadRequest = { request in
            request.value = ipData
            manager.respond(to: request, withResult: .success)
        }

        delegate.onSubscription = { central in
            manager.updateValue(
                ipData,
                for: characteristic,
                onSubscribedCentrals: [central]
            )
        }

        if manager.state == .poweredOn {
            delegate.onReadyToAdvertise?()
        }
    }

    package func stopAdvertising() {
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
    }

    package func updateIP(_ ip: String) {
        guard let characteristic = ipCharacteristic else { return }
        let data = Data(ip.utf8)
        peripheralManager?.updateValue(data, for: characteristic, onSubscribedCentrals: nil)
    }
}


private final class PeripheralDelegate: NSObject, CBPeripheralManagerDelegate, @unchecked Sendable {
    var onReadyToAdvertise: (() -> Void)?
    var onReadRequest: ((CBATTRequest) -> Void)?
    var onSubscription: ((CBCentral) -> Void)?

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            onReadyToAdvertise?()
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveRead request: CBATTRequest
    ) {
        onReadRequest?(request)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        onSubscription?(central)
    }
}
#endif
