//
//  EscapeCommand.h
//  ApduTool
//
//  Created by Ken Cheung on 2/6/23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EscapeCommand : NSObject
- (uint32_t)transfer: (const char*)szReader andSendData: (uint8_t*)sendData andSendLength: (uint32_t)sendLength andRecvData: (uint8_t*)recvData andPRecvLength: (uint32_t*)pRecvLength;
@end

NS_ASSUME_NONNULL_END
