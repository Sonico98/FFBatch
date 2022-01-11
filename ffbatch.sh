#!/bin/bash

###########
# Options #
###########
# Set the video codec, pixel format, bitrate, etc
video_params='-c:v libx264 -crf 20 -pix_fmt yuv420p -profile:v high -bf 2 -tune animation'

# Set the audio codec and bitrate. Will be ignored if the source's codec is AAC
audio_params='-c:a libfdk_aac -b:a 350k' 

# Optional parameters
other_params='-movflags -faststart -metadata title= '

# Enable or disable copying the file to RAM before transcoding
# MAKE SURE YOU HAVE ENOUGH SPACE
copy2ram=false
ramdir="/tmp"


##########
# Script #
##########
# Don't modify anything below unless you know what you're doing

if [[ $# -ne 1 ]]
then
	echo "[ USAGE ]"
	echo "Execute the script inside a folder with a bunch of MKVs"
	echo ""
	echo "ffbatch.sh [output path]"
	echo ""
	echo "You have to specify where to place the encoded files"
	echo "The script only accepts one parameter"
	exit 2
fi


# Functions
check_audio_transcode () {
	get_audio_codec="$(ffprobe -v error -select_streams a:0 -show_entries \
		stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$ramdir"/"$base".mkv)"

	if [[ "$get_audio_codec" = aac ]]; then
		audio_parameters='-c:a copy'
	fi
}


cleanup () {
	rm -rf "$ramdir"/subs
	rm -rf "$HOME"/.local/share/fonts/ffbatch_fonts
	if [[ ! "$ramdir" = "." ]];then
		rm -f "$ramdir/$base.mkv"
	fi
}


copy_to_ram () {
	if [[ $copy2ram = true ]]; then
		echo "Copying file to RAM, to minimize disk usage"
		cp -v "$video" "$ramdir"
		status=$?
	else
		ramdir="."
		status=0
	fi
}


extract_fonts () {
	work_dir="$(pwd)"
	echo "Extracting fonts..."
	mkdir -p "$ramdir"/.fonts
	cd "$ramdir"/.fonts
	ffmpeg -y -dump_attachment:t "" -i ../"$base".mkv &>/dev/null

	mv * "$HOME"/.local/share/fonts/ffbatch_fonts
	cd .. && rm -rf .fonts
	cd "$work_dir"
	# clear
}


set_ffbin () {
	which ffpb &> /dev/null
	if [[ $? -eq 0 ]]
	then
		ffbin=$(which ffpb)
	else
		ffbin=$(which ffmpeg)
	fi
}
# End functions

# If set to false, fonts will be extracted
FONTS_EX=false
set_ffbin
mkdir -p "$1"
mkdir -p "$HOME"/.local/share/fonts/ffbatch_fonts

for video in *.mkv; do
	audio_parameters="$audio_params"
	base=$(basename "$video" .mkv)

	# Copy the file to RAM (or not)
	copy_to_ram
	mkdir -p "$ramdir"/subs

	# If there were no problems copying to RAM, proceed
	if [[ $status -eq 0 ]]; then
		echo ""	
		if [[ $FONTS_EX = false ]]; then
			extract_fonts
			FONTS_EX=true
		fi

		# Determine if transcoding the audio is necessary
		check_audio_transcode

		echo "Attempting to extract subs..."
		$(which ffmpeg) -v quiet -stats -y -i "$ramdir"/"$base".mkv "$ramdir"/subs/"$base".ass
		subs_state="$?"

		# Transcode the file
		if [[ $subs_state -eq 0 ]]; then
			echo "Subtitles extracted. Transcoding..."
			$ffbin -i "$ramdir"/"$base".mkv  -vf "ass='$ramdir/subs/$base.ass'" \
				$audio_parameters $video_params $other_params "$ramdir"/"$base".mp4
		else
			echo "No subtitles found. Converting to MP4 anyways..."
			$ffbin -i "$ramdir"/"$base".mkv $audio_parameters \
				$video_params $other_params "$ramdir"/"$base".mp4
		fi

		# Remove the mkv from RAM
		if [[ ! $ramdir = "." ]];then
			rm -f "$ramdir"/"$base".mkv
		fi

		# Move the MP4 to its final destination
		mv "$ramdir"/"$base".mp4 "$1"/"$base".mp4 &
	else
		echo "An error ocurred"
		cleanup
		exit 1
	fi
done

cleanup
echo "All done!"
exit 0
