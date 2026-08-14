#ifndef DJI_USB_TRANSPORT_H
#define DJI_USB_TRANSPORT_H

#include <stdint.h>

typedef struct DJIUSBTransport DJIUSBTransport;

DJIUSBTransport *DJIUSBTransportOpen(
    uint16_t vendorID,
    uint16_t productID,
    uint8_t interfaceNumber,
    uint8_t endpointAddress,
    int32_t *status
);

int32_t DJIUSBTransportRead(
    DJIUSBTransport *transport,
    uint8_t *bytes,
    uint32_t *length,
    uint32_t timeoutMilliseconds
);

void DJIUSBTransportClose(DJIUSBTransport *transport);

#endif
