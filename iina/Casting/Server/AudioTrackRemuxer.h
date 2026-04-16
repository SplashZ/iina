#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Remuxes a local media file keeping all video streams and only the specified audio stream.
/// Uses libavformat stream-copy (no re-encoding) so it is very fast.
/// Returns the path to a newly created temp MKV file, or nil on failure.
@interface AudioTrackRemuxer : NSObject

/// @param inputPath   Path to the source file.
/// @param streamIndex The stream index (zero-based across all streams, i.e. MPVTrack.srcId)
///                    of the audio track to preserve.
/// @param outError    Set on failure.
/// @return Absolute path to the temp file, or nil on failure.
+ (nullable NSString *)remuxFile:(NSString *)inputPath
                audioStreamIndex:(int)streamIndex
                           error:(NSError *_Nullable *_Nullable)outError;

@end

NS_ASSUME_NONNULL_END
