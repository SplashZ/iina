#import "AudioTrackRemuxer.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#import <libavformat/avformat.h>
#import <libavutil/avutil.h>
#pragma clang diagnostic pop

@implementation AudioTrackRemuxer

+ (nullable NSString *)remuxFile:(NSString *)inputPath
                audioStreamIndex:(int)targetStreamIndex
                           error:(NSError *_Nullable *_Nullable)outError {

  AVFormatContext *inCtx = NULL;
  if (avformat_open_input(&inCtx, inputPath.UTF8String, NULL, NULL) < 0) {
    if (outError) {
      *outError = [NSError errorWithDomain:@"AudioTrackRemuxer" code:1
                                 userInfo:@{NSLocalizedDescriptionKey: @"Cannot open input file"}];
    }
    return nil;
  }

  if (avformat_find_stream_info(inCtx, NULL) < 0) {
    avformat_close_input(&inCtx);
    if (outError) {
      *outError = [NSError errorWithDomain:@"AudioTrackRemuxer" code:2
                                 userInfo:@{NSLocalizedDescriptionKey: @"Cannot read stream info"}];
    }
    return nil;
  }

  // Build stream mapping: all video streams + the audio stream at targetStreamIndex.
  // streamRemap[srcIndex] = dstIndex, or -1 to discard.
  int *streamRemap = (int *)calloc(inCtx->nb_streams, sizeof(int));
  for (unsigned int i = 0; i < inCtx->nb_streams; i++) {
    streamRemap[i] = -1;
  }

  int dstIdx = 0;
  BOOL foundAudio = NO;
  for (unsigned int i = 0; i < inCtx->nb_streams; i++) {
    AVStream *s = inCtx->streams[i];
    enum AVMediaType type = s->codecpar->codec_type;
    if (type == AVMEDIA_TYPE_VIDEO) {
      streamRemap[i] = dstIdx++;
    } else if (type == AVMEDIA_TYPE_AUDIO && inCtx->streams[i]->id == targetStreamIndex) {
      // Compare with AVStream.id, NOT the loop index.
      // mpv's src-id corresponds to AVStream.id (format-specific track number,
      // e.g. MKV track numbers start at 1, so index 0 has id 1, etc.).
      streamRemap[i] = dstIdx++;
      foundAudio = YES;
    }
  }

  if (!foundAudio) {
    // Fallback: keep all audio streams if target not found
    for (unsigned int i = 0; i < inCtx->nb_streams; i++) {
      if (streamRemap[i] < 0 && inCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
        streamRemap[i] = dstIdx++;
        break; // just keep the first audio
      }
    }
  }

  // Create temp output file
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *outName = [NSString stringWithFormat:@"iina_cast_%@.mkv", [NSUUID UUID].UUIDString];
  NSString *outputPath = [tmpDir stringByAppendingPathComponent:outName];

  AVFormatContext *outCtx = NULL;
  if (avformat_alloc_output_context2(&outCtx, NULL, "matroska", outputPath.UTF8String) < 0) {
    avformat_close_input(&inCtx);
    free(streamRemap);
    if (outError) {
      *outError = [NSError errorWithDomain:@"AudioTrackRemuxer" code:3
                                 userInfo:@{NSLocalizedDescriptionKey: @"Cannot create output context"}];
    }
    return nil;
  }

  // Add output streams
  for (unsigned int i = 0; i < inCtx->nb_streams; i++) {
    if (streamRemap[i] < 0) continue;
    AVStream *inStream = inCtx->streams[i];
    AVStream *outStream = avformat_new_stream(outCtx, NULL);
    if (!outStream) continue;
    avcodec_parameters_copy(outStream->codecpar, inStream->codecpar);
    outStream->codecpar->codec_tag = 0;
    outStream->time_base = inStream->time_base;
  }

  if (avio_open(&outCtx->pb, outputPath.UTF8String, AVIO_FLAG_WRITE) < 0) {
    avformat_close_input(&inCtx);
    avformat_free_context(outCtx);
    free(streamRemap);
    if (outError) {
      *outError = [NSError errorWithDomain:@"AudioTrackRemuxer" code:4
                                 userInfo:@{NSLocalizedDescriptionKey: @"Cannot open output file"}];
    }
    return nil;
  }

  if (avformat_write_header(outCtx, NULL) < 0) {
    avformat_close_input(&inCtx);
    avio_closep(&outCtx->pb);
    avformat_free_context(outCtx);
    free(streamRemap);
    return nil;
  }

  // Copy packets
  AVPacket *pkt = av_packet_alloc();
  while (av_read_frame(inCtx, pkt) >= 0) {
    int srcIdx = pkt->stream_index;
    int dst = (srcIdx < (int)inCtx->nb_streams) ? streamRemap[srcIdx] : -1;
    if (dst >= 0) {
      AVStream *inStream = inCtx->streams[srcIdx];
      AVStream *outStream = outCtx->streams[dst];
      pkt->stream_index = dst;
      pkt->pts = av_rescale_q_rnd(pkt->pts, inStream->time_base, outStream->time_base,
                                  AV_ROUND_NEAR_INF | AV_ROUND_PASS_MINMAX);
      pkt->dts = av_rescale_q_rnd(pkt->dts, inStream->time_base, outStream->time_base,
                                  AV_ROUND_NEAR_INF | AV_ROUND_PASS_MINMAX);
      pkt->duration = av_rescale_q(pkt->duration, inStream->time_base, outStream->time_base);
      pkt->pos = -1;
      av_interleaved_write_frame(outCtx, pkt);
    }
    av_packet_unref(pkt);
  }
  av_packet_free(&pkt);

  av_write_trailer(outCtx);
  avio_closep(&outCtx->pb);
  avformat_free_context(outCtx);
  avformat_close_input(&inCtx);
  free(streamRemap);

  return outputPath;
}

@end
