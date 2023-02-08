//
//  EscapeCommand.m
//  ApduTool
//
//  Created by Ken Cheung on 2/6/23.
//

#import "EscapeCommand.h"
#import <TargetConditionals.h>
#if TARGET_OS_OSX
#import <PCSC/PCSC.h>

#define SCARD_CTRL_CODE(x) (0x310000 + (x) * 4)
#else
#define SCARD_E_UNSUPPORTED_FEATURE    0x80100022
#endif
@implementation EscapeCommand
- (uint32_t) transfer:(const char*) szReader andSendData:(uint8_t *) sendData andSendLength:(uint32_t) sendLength andRecvData:(uint8_t *) recvData andPRecvLength:(uint32_t*) pRecvLength
{
#if TARGET_OS_OSX
    uint32_t res = SCARD_S_SUCCESS;
    SCARDCONTEXT hContext = SCARD_E_INVALID_HANDLE;
    SCARDHANDLE hCard = SCARD_E_INVALID_HANDLE;
    uint32_t dwActiveProtocol = 0;
    uint32_t recvLength = 256;
    res = SCardEstablishContext(SCARD_SCOPE_USER, NULL, NULL, &hContext);
    if (res != SCARD_S_SUCCESS) {
        goto exit1;
    }
    res = SCardConnect(hContext, szReader, SCARD_SHARE_DIRECT, SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1, &hCard, &dwActiveProtocol);
    if (res != SCARD_S_SUCCESS) {
        goto exit2;
    }
    res = SCardControl(hCard, SCARD_CTRL_CODE(3500), sendData, sendLength, recvData, recvLength, pRecvLength);
    SCardDisconnect(hCard, SCARD_LEAVE_CARD);
exit2:
    SCardReleaseContext(hContext);
exit1:
    return res;
#else
    return SCARD_E_UNSUPPORTED_FEATURE;
#endif
}
@end
