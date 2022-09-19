# FFBatch
Simple script to convert a folder of MKVs to MP4. It's made mostly with Anime in mind, and is by no means bulletproof.

# Dependencies
For the script to work, you'll just need
```
ffmpeg with libass support
ffprobe
ffpb (optional)
```
Most distros already package ffmpeg with libass, and ffprobe should come with the ffmpeg package.
By installing [ffpb](https://github.com/althonos/ffpb), a progress bar will be shown for each file.
# Usage
```
ffbatch.sh [output path]
```
Run the script from within the folder with your MKV files, and indicate where to place the transcoded MP4 files (output path).

# The script will
- Copy the file to RAM first (disabled by default).
- Extract embedded fonts from the file (required for proper font rendering).
- Avoid needlessly transcoding the audio (from AAC to AAC).
- Burn-in the subtitles to the video (if embedded into the MKV).
- Move the file to its final destination.
- Cleanup any temporary files created during the process.

# Customization
The default settings will create high quality, highly compatible MP4 videos. You can, however, easily pass your own ffmpeg parameters to customize your output.
Simply open up the script in any text editor and modify the parameters at the top of the file, just be careful to not remove the quotes. <br />

```video_params```: Set the video codec, pixel format, bitrate, etc. <br />
```audio_params```: Set the audio codec and bitrate. Will be ignored if the source's codec is AAC. <br />
```other_params```: Optional parameters. By default, we optimize the file for streaming, and clear the title metadata (if any). <br />
You can ignore any of those 3 and use ffmpeg's defaults by commenting them (adding a # to the start of the line)

**MOVING TO RAM DOES NOT CHECK FOR AVAILABLE SPACE** (for now) <br />
```copy2ram```: enables or disables copying the MKVs to RAM before transcoding. It's useful to minimize reads and writes on the disk, and it may improve performance (untested). It moves a single MKV to RAM, creates the MP4 on RAM as well, and after encoding is done, moves the MP4 away and removes the MKV from RAM, then repeats. <br />
```ramdir```: Sets the RAM directory, ```/tmp``` by default. For myself, I setup a zram device on ```/zram``` and use that dir: ```ramdir="/zram"```

# TO-DO
- [X] Encode the MP4 directly into the output_path if moving to RAM is disabled.
- [ ] Check available space before moving files to RAM, and transcode in place if there's not enough space.
- [ ] Handle terminating the script properly, by cleaning up everything if Ctrl+C is received.
