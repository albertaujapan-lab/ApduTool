//
//  TransmitCommand.h
//  ApduTool
//
//  Created by Ken Cheung on 10/22/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TransmitCommand : NSObject
- (uint32_t) transfer:(const char*) szReader andSendData:(uint8_t*) sendData andSendLength:(uint32_t) sendLength andRecvData:(uint8_t*) recvData andPRecvLength:(uint32_t*) pRecvLength;
@end

NS_ASSUME_NONNULL_END
