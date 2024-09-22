# FFBatch
Simple script to convert a folder of MKVs to MP4 with hardsubs. It's made mostly with Anime in mind, and is by no means bulletproof.

# Dependencies
For the script to work, you'll just need
```
ffmpeg with libass support
ffprobe
mkvmerge
ffpb (optional)
```
Most distros already package ffmpeg with libass, and ffprobe should come with the ffmpeg package.
By installing [ffpb](https://github.com/althonos/ffpb), a progress bar will be shown for each file.
# Usage
```
ffbatch.sh <parameters> [output path]
```
Run the script from within the folder with your MKV files, and indicate where to place the transcoded MP4 files (output path).
You may override the defaults by passing your own parameters. Check available parameters with `--help`.

# The script will
- Copy the file to a temporary directory first (disabled by default).
- Extract embedded fonts from the file (required for proper font and effect rendering).
- Avoid needlessly transcoding the audio (from AAC to AAC).
- Burn-in the subtitles to the video (if embedded into the MKV).
    - Subtitles can be choosen by language code or by their track title.
- Move the transcoded file to its final destination.
- Cleanup any temporary files created during the process.

# Customization
The default settings will create high quality, highly compatible MP4 videos. You can, however, easily pass your own ffmpeg parameters to customize your output.
If you want your parameters to be permanent, simply open up the script in any text editor and modify the variables at the top of the file, just be careful to not remove the quotes. Otherwise, you can control what the script will do by passing your desired parameters (they override the constants set at the top of the file). Check `--help`<br />

```video_params```: Set the video codec, pixel format, bitrate, etc. <br />
```audio_params```: Set the audio codec and bitrate. Will be ignored if the source's codec is AAC. <br />
```other_params```: Optional parameters. By default, we optimize the file for streaming, and clear the title metadata (if any). <br />
You can ignore any of those 3 and use ffmpeg's defaults by commenting them (adding a # to the start of the line)

```subs_lang```: Set the default subtitle language to burn.
```audio_lang```: Set the default audio language to transcode.
```always_transcode```: Transcode even if no subtitles are found.

**MOVING TO TMP DIR DOES NOT CHECK FOR AVAILABLE SPACE** (for now) <br />
- ```copy2dir```: enables or disables copying the MKVs to a temporary directory before transcoding. It's useful to minimize reads and writes on the disk, or for dealing with files in remote filesystems. It moves a single MKV to a temporary directory, creates the encode using the copied file, and after encoding is done, removes the MKV from the temporary directory, then repeats. <br />

- ```write2dir```: enables or disables writing the transcoded MP4 to a temporary directory first before moving it to its final destination. Useful for fragmented file systems (like BTRFS), as the whole file will be written to disk at once when the transcode finishes. Just like the ```copy2ram``` option, it writes a single file to a temp directory first, moves it to its final destination once it finishes, and repeats.

- ```tmpdir```: Sets the temporary directory, ```/tmp``` by default. For myself, I setup a zram device on ```/zram``` and use that dir: ```ramdir="/zram"```

# TO-DO
- [X] Encode the MP4 directly into the output_path if moving to RAM is disabled.
- [ ] Check available space before moving files to TMP dir, and transcode in place if there's not enough space.
- [X] Handle terminating the script properly, by cleaning up everything if Ctrl+C is received.
