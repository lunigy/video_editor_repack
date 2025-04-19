import 'dart:io';
import 'dart:typed_data';
import 'package:ffmpeg_kit_flutter_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min/return_code.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_editor_repack/src/controller.dart';
import 'package:video_editor_repack/src/models/cover_data.dart';
import 'package:path/path.dart' as path; // Import path package with prefix

// Helper function to generate a single thumbnail using FFmpeg
Future<Uint8List?> _generateFFmpegThumbnail(
  String videoPath,
  int timeMs,
  int quality, // Quality parameter (0-100 for JPEG) might need adjustment based on FFmpeg options
  String tempDir,
) async {
  final String outputFileName = 'thumbnail_${DateTime.now().millisecondsSinceEpoch}_${timeMs}.jpg';
  final String outputPath = path.join(tempDir, outputFileName); // Use path.join
  final double timeInSeconds = timeMs / 1000.0;

  // Basic FFmpeg command:
  // -ss: seek to position (input option, should be before -i for faster seeking)
  // -i: input video file
  // -vframes 1: extract only one frame
  // -q:v : quality scale for variable bitrate (lower is better, 2-5 is often good for JPEG)
  // -an: disable audio recording
  // -y: overwrite output file without asking
  final String command =
      '-ss $timeInSeconds -i "$videoPath" -vframes 1 -q:v ${quality ~/ 10 + 1} -an -y "$outputPath"'; // Adjust quality mapping if needed

  debugPrint("Executing FFmpeg command: $command");

  final session = await FFmpegKit.execute(command);
  final returnCode = await session.getReturnCode();

  if (ReturnCode.isSuccess(returnCode)) {
    debugPrint("FFmpeg thumbnail generation successful for time $timeMs ms");
    final file = File(outputPath);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      await file.delete(); // Clean up temporary file
      debugPrint("Thumbnail file read and deleted: $outputPath");
      return bytes;
    } else {
      debugPrint("FFmpeg generated file not found: $outputPath");
      return null;
    }
  } else {
    debugPrint("FFmpeg thumbnail generation failed for time $timeMs ms. Return code: $returnCode");
    final logs = await session.getAllLogsAsString();
    debugPrint("FFmpeg logs: $logs");
    // Attempt to delete the file even if FFmpeg failed, in case it was partially created
    final file = File(outputPath);
     if (await file.exists()) {
       try {
         await file.delete();
         debugPrint("Deleted potentially incomplete thumbnail file: $outputPath");
       } catch (e) {
        debugPrint("Error deleting potentially incomplete thumbnail file: $e");
       }
     }
    return null;
  }
}


Stream<List<Uint8List>> generateTrimThumbnails(
  VideoEditorController controller, {
  required int quantity,
}) async* {
  final String videoPath = controller.file.path;
  final double eachPart = controller.videoDuration.inMilliseconds / quantity;
  List<Uint8List> byteList = [];
  final Directory tempDir = await getTemporaryDirectory();
  debugPrint("Temporary directory for thumbnails: ${tempDir.path}");


  for (int i = 1; i <= quantity; i++) {
    try {
      final int timeMs = (eachPart * i).toInt();
      final Uint8List? bytes = await _generateFFmpegThumbnail(
        videoPath,
        timeMs,
        controller.trimThumbnailsQuality,
        tempDir.path,
      );
      if (bytes != null) {
        byteList.add(bytes);
        yield List.from(byteList); // Yield a copy of the list
      } else {
         debugPrint("generateTrimThumbnails: Thumbnail generation returned null for time $timeMs");
         // Optionally yield the current list even if one fails, or handle error differently
         yield List.from(byteList);
      }
    } catch (e, s) {
      debugPrint("Error in generateTrimThumbnails loop: $e\n$s");
      // Handle error, maybe yield current list or rethrow
       yield List.from(byteList);
    }
  }
   debugPrint("generateTrimThumbnails completed. Generated ${byteList.length} thumbnails.");
}


Stream<List<CoverData>> generateCoverThumbnails(
  VideoEditorController controller, {
  required int quantity,
}) async* {
  final String videoPath = controller.file.path;
  final int duration = controller.isTrimmed
      ? controller.trimmedDuration.inMilliseconds
      : controller.videoDuration.inMilliseconds;
  final double eachPart = duration / quantity;
  List<CoverData> byteList = [];
   final Directory tempDir = await getTemporaryDirectory();
   debugPrint("Temporary directory for cover thumbnails: ${tempDir.path}");


  for (int i = 0; i < quantity; i++) {
    try {
       final int timeMs = (controller.isTrimmed
                ? (eachPart * i) + controller.startTrim.inMilliseconds
                : (eachPart * i))
            .toInt();

      final Uint8List? thumbData = await _generateFFmpegThumbnail(
        videoPath,
        timeMs,
        controller.coverThumbnailsQuality,
        tempDir.path,
      );

      if (thumbData != null) {
        byteList.add(CoverData(thumbData: thumbData, timeMs: timeMs));
         yield List.from(byteList); // Yield a copy
      } else {
         debugPrint("generateCoverThumbnails: Thumbnail generation returned null for time $timeMs");
         yield List.from(byteList);
      }
    } catch (e, s) {
       debugPrint("Error in generateCoverThumbnails loop: $e\n$s");
      yield List.from(byteList);
    }
  }
  debugPrint("generateCoverThumbnails completed. Generated ${byteList.length} covers.");
}

/// Generate a cover at [timeMs] in video using FFmpeg
///
/// Returns a [CoverData] depending on [timeMs] milliseconds
Future<CoverData> generateSingleCoverThumbnail(
  String filePath, {
  int timeMs = 0,
  int quality = 10, // Note: FFmpeg quality might work differently
}) async {
   final Directory tempDir = await getTemporaryDirectory();
   debugPrint("Temporary directory for single cover thumbnail: ${tempDir.path}");
  final Uint8List? thumbData = await _generateFFmpegThumbnail(
    filePath,
    timeMs,
    quality,
    tempDir.path,
  );
  if (thumbData == null){
    debugPrint("generateSingleCoverThumbnail failed for time $timeMs");
  }
  return CoverData(thumbData: thumbData, timeMs: timeMs);
}