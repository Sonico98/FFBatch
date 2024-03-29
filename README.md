# FFBatch
Simple script to convert a folder of MKVs to MP4 with hardsubs. It's made mostly with Anime in mind, and is by no means bulletproof.

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
If you want your parameters to be permanent, simply open up the script in any text editor and modify the parameters at the top of the file, just be careful to not remove the quotes. Otherwise, you can control what the script will do with parameters (they override the constants set at the top of the file). Check --help<br />

```video_params```: Set the video codec, pixel format, bitrate, etc. <br />
```audio_params```: Set the audio codec and bitrate. Will be ignored if the source's codec is AAC. <br />
```other_params```: Optional parameters. By default, we optimize the file for streaming, and clear the title metadata (if any). <br />
You can ignore any of those 3 and use ffmpeg's defaults by commenting them (adding a # to the start of the line)

**MOVING TO RAM DOES NOT CHECK FOR AVAILABLE SPACE** (for now) <br />
- ```copy2ram```: enables or disables copying the MKVs to RAM before transcoding. It's useful to minimize reads and writes on the disk, and it may improve performance (untested). It moves a single MKV to RAM, creates the encode using the file on RAM, and after encoding is done, removes the MKV from RAM, then repeats. <br />

- ```write2ram```: enables or disables writing the output MP4 to RAM before copying it to disk. Useful for fragmented file systems (like BTRFS), as the resulting file will be written to disk at once when the transcode finishes. Just like the ```copy2ram``` option, it writes a single file to RAM first, moves it to disk once it finishes, and repeats.

- ```ramdir```: Sets the RAM directory, ```/tmp``` by default. For myself, I setup a zram device on ```/zram``` and use that dir: ```ramdir="/zram"```

# TO-DO
- [X] Encode the MP4 directly into the output_path if moving to RAM is disabled.
- [ ] Check available space before moving files to RAM, and transcode in place if there's not enough space.
- [X] Handle terminating the script properly, by cleaning up everything if Ctrl+C is received.
