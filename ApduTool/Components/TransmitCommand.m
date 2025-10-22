//
//  TransmitCommand.m
//  ApduTool
//
//  Created by Ken Cheung on 10/22/25.
//

#import "TransmitCommand.h"
#import <TargetConditionals.h>
#if TARGET_OS_OSX
#import <PCSC/PCSC.h>

#else
#define SCARD_E_UNSUPPORTED_FEATURE    0x80100022
#endif
@implementation TransmitCommand
- (uint32_t) transfer:(const char*) szReader andSendData:(uint8_t *) sendData andSendLength:(uint32_t) sendLength andRecvData:(uint8_t *) recvData andPRecvLength:(uint32_t*) pRecvLength
{
#if TARGET_OS_OSX
    uint32_t res = SCARD_S_SUCCESS;
    SCARDCONTEXT hContext = SCARD_E_INVALID_HANDLE;
    SCARDHANDLE hCard = SCARD_E_INVALID_HANDLE;
    SCARD_IO_REQUEST ioSendPci;
    SCARD_IO_REQUEST ioRecvPci;
    uint32_t dwActiveProtocol = 0;
    res = SCardEstablishContext(SCARD_SCOPE_USER, NULL, NULL, &hContext);
    if (res != SCARD_S_SUCCESS) {
        goto exit1;
    }
    res = SCardConnect(hContext, szReader, SCARD_SHARE_SHARED, SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1, &hCard, &dwActiveProtocol);
    if (res != SCARD_S_SUCCESS) {
        goto exit2;
    }
    ioSendPci.dwProtocol = dwActiveProtocol;
    ioSendPci.cbPciLength = 8;
    res = SCardTransmit(hCard, &ioSendPci, sendData, sendLength, &ioRecvPci, recvData, pRecvLength);
    SCardDisconnect(hCard, SCARD_LEAVE_CARD);
exit2:
    {
        dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC));
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        dispatch_queue_attr_t qosAttribute = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, QOS_CLASS_UTILITY, 0);
        dispatch_queue_t myQueue = dispatch_queue_create("com.acs.TempQueue", qosAttribute);
        dispatch_block_t myBlock;
        myBlock = dispatch_block_create_with_qos_class(0, QOS_CLASS_UTILITY, -8, ^{
            SCardReleaseContext(hContext);
            dispatch_semaphore_signal(semaphore);
        });
        dispatch_async(myQueue, myBlock);
        dispatch_semaphore_wait(semaphore, timeout);
    }
exit1:
    return res;
#else
    return SCARD_E_UNSUPPORTED_FEATURE;
#endif
}
@end
