#include "DJIUSBTransport.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <stdlib.h>

struct DJIUSBTransport {
    IOUSBDeviceInterface300 **device;
    IOUSBInterfaceInterface300 **interface;
    uint8_t pipeReference;
};

static void setNumber(CFMutableDictionaryRef dictionary, CFStringRef key, int value) {
    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &value);
    if (number != NULL) {
        CFDictionarySetValue(dictionary, key, number);
        CFRelease(number);
    }
}

static IOUSBDeviceInterface300 **openDevice(
    io_service_t service,
    IOReturn *status
) {
    IOCFPlugInInterface **plugin = NULL;
    IOUSBDeviceInterface300 **device = NULL;
    SInt32 score = 0;

    *status = IOCreatePlugInInterfaceForService(
        service,
        kIOUSBDeviceUserClientTypeID,
        kIOCFPlugInInterfaceID,
        &plugin,
        &score
    );
    if (*status != kIOReturnSuccess || plugin == NULL) {
        return NULL;
    }

    HRESULT query = (*plugin)->QueryInterface(
        plugin,
        CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID300),
        (LPVOID *)&device
    );
    (*plugin)->Release(plugin);
    if (query != S_OK || device == NULL) {
        *status = kIOReturnNotFound;
        return NULL;
    }
    return device;
}

static IOUSBInterfaceInterface300 **openInterface(
    IOUSBDeviceInterface300 **device,
    uint8_t interfaceNumber,
    uint8_t endpointAddress,
    uint8_t *pipeReference,
    IOReturn *status
) {
    IOUSBFindInterfaceRequest request = {
        kIOUSBFindInterfaceDontCare,
        kIOUSBFindInterfaceDontCare,
        kIOUSBFindInterfaceDontCare,
        kIOUSBFindInterfaceDontCare
    };
    io_iterator_t iterator = IO_OBJECT_NULL;
    *status = (*device)->CreateInterfaceIterator(device, &request, &iterator);
    if (*status != kIOReturnSuccess) {
        return NULL;
    }

    IOUSBInterfaceInterface300 **result = NULL;
    io_service_t service;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        IOCFPlugInInterface **plugin = NULL;
        SInt32 score = 0;
        IOReturn createStatus = IOCreatePlugInInterfaceForService(
            service,
            kIOUSBInterfaceUserClientTypeID,
            kIOCFPlugInInterfaceID,
            &plugin,
            &score
        );
        IOObjectRelease(service);
        if (createStatus != kIOReturnSuccess || plugin == NULL) {
            continue;
        }

        IOUSBInterfaceInterface300 **candidate = NULL;
        HRESULT query = (*plugin)->QueryInterface(
            plugin,
            CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300),
            (LPVOID *)&candidate
        );
        (*plugin)->Release(plugin);
        if (query != S_OK || candidate == NULL) {
            continue;
        }

        UInt8 number = 0;
        IOReturn numberStatus = (*candidate)->GetInterfaceNumber(candidate, &number);
        if (numberStatus != kIOReturnSuccess || number != interfaceNumber) {
            (*candidate)->Release(candidate);
            continue;
        }

        IOReturn openStatus = (*candidate)->USBInterfaceOpen(candidate);
        if (openStatus != kIOReturnSuccess) {
            (*candidate)->Release(candidate);
            *status = openStatus;
            break;
        }

        UInt8 endpointCount = 0;
        *status = (*candidate)->GetNumEndpoints(candidate, &endpointCount);
        for (UInt8 pipe = 1; *status == kIOReturnSuccess && pipe <= endpointCount; pipe++) {
            UInt8 direction = 0;
            UInt8 endpointNumber = 0;
            UInt8 transferType = 0;
            UInt16 maxPacketSize = 0;
            UInt8 interval = 0;
            *status = (*candidate)->GetPipeProperties(
                candidate,
                pipe,
                &direction,
                &endpointNumber,
                &transferType,
                &maxPacketSize,
                &interval
            );
            uint8_t address = endpointNumber | (direction == kUSBIn ? 0x80 : 0x00);
            if (*status == kIOReturnSuccess && address == endpointAddress) {
                *pipeReference = pipe;
                result = candidate;
                break;
            }
        }

        if (result == NULL) {
            (*candidate)->USBInterfaceClose(candidate);
            (*candidate)->Release(candidate);
            if (*status == kIOReturnSuccess) {
                *status = kIOReturnNotFound;
            }
        }
        break;
    }

    IOObjectRelease(iterator);
    return result;
}

DJIUSBTransport *DJIUSBTransportOpen(
    uint16_t vendorID,
    uint16_t productID,
    uint8_t interfaceNumber,
    uint8_t endpointAddress,
    int32_t *statusOut
) {
    IOReturn status = kIOReturnNotFound;
    CFMutableDictionaryRef matching = IOServiceMatching("IOUSBHostDevice");
    if (matching == NULL) {
        if (statusOut != NULL) *statusOut = kIOReturnNoMemory;
        return NULL;
    }
    setNumber(matching, CFSTR("idVendor"), vendorID);
    setNumber(matching, CFSTR("idProduct"), productID);

    io_iterator_t iterator = IO_OBJECT_NULL;
    status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator);
    if (status != kIOReturnSuccess) {
        if (statusOut != NULL) *statusOut = status;
        return NULL;
    }

    DJIUSBTransport *transport = NULL;
    io_service_t service;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        IOUSBDeviceInterface300 **device = openDevice(service, &status);
        IOObjectRelease(service);
        if (device == NULL) {
            continue;
        }

        uint8_t pipeReference = 0;
        IOUSBInterfaceInterface300 **interface = openInterface(
            device,
            interfaceNumber,
            endpointAddress,
            &pipeReference,
            &status
        );
        if (interface == NULL) {
            (*device)->Release(device);
            continue;
        }

        transport = calloc(1, sizeof(*transport));
        if (transport == NULL) {
            (*interface)->USBInterfaceClose(interface);
            (*interface)->Release(interface);
            (*device)->Release(device);
            status = kIOReturnNoMemory;
            break;
        }
        transport->device = device;
        transport->interface = interface;
        transport->pipeReference = pipeReference;
        status = kIOReturnSuccess;
        break;
    }
    IOObjectRelease(iterator);
    if (statusOut != NULL) *statusOut = status;
    return transport;
}

int32_t DJIUSBTransportRead(
    DJIUSBTransport *transport,
    uint8_t *bytes,
    uint32_t *length,
    uint32_t timeoutMilliseconds
) {
    if (transport == NULL || bytes == NULL || length == NULL) {
        return kIOReturnBadArgument;
    }
    return (*transport->interface)->ReadPipeTO(
        transport->interface,
        transport->pipeReference,
        bytes,
        length,
        timeoutMilliseconds,
        timeoutMilliseconds
    );
}

void DJIUSBTransportClose(DJIUSBTransport *transport) {
    if (transport == NULL) return;
    (*transport->interface)->USBInterfaceClose(transport->interface);
    (*transport->interface)->Release(transport->interface);
    (*transport->device)->Release(transport->device);
    free(transport);
}
