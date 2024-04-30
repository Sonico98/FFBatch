#!/bin/bash

###########
# Options #
###########
# Set the video codec, pixel format, bitrate, etc
video_params='-map 0:v:0 -c:v libx264 -crf 18 -pix_fmt yuv420p -profile:v high -bf 6 -tune animation -preset slow -aq-mode 3 -aq-strength 0.75 -rc-lookahead 80 -level:v 4.2'

# Set the audio codec and bitrate. Will be ignored if the source's codec is AAC
audio_params='-c:a libfdk_aac -profile:a aac_low -vbr 5'

# Optional parameters
other_params='-movflags faststart -metadata title= '

# Set the subtitle language to burn into the video.
# The subtitle stream should be properly tagged with the desired language code (e.g. using mkvtoolnix).
# If there are multiple subtitles for the same language, the first one that matches will be chosen.
subs_lang='eng'

# Set the audio language to use.
# The audio stream should be properly tagged with the desired language code (e.g. using mkvtoolnix).
# If there are multiple audio streams for the same language, all of them will be transcoded.
audio_lang='jpn'

# Enable or disable transcoding with RAM
# MAKE SURE YOU HAVE ENOUGH SPACE
# --------------------------------------
# If true, copies the original file to ram
copy2ram=false
# If true, writes the transcoded file to ram before
# moving it to its final destination (reduces disk fragmentation)
write2ram=false
# Determines the directory that points to RAM
ramdir="/tmp"

# Always extract fonts
# May be useful if the resulting videos are using the wrong fonts
always_ex_fonts=true

# Transcode even if no subs are found
always_transcode=false


##########
# Script #
##########
# Don't modify anything below unless you know what you're doing

print_usage () {
	echo "[USAGE]"
	echo "ffbatch.sh [OPTIONS] <output path>"
	echo ""
	echo "Execute the script inside a folder with a bunch of MKVs"
	echo "You have to specify an output path where the encoded files will be placed"
	echo "If copying or writing to RAM, make sure you have enough space for the files"
	echo ""
	echo "[OPTIONS]"
	echo " -c | --copy2ram        : Copies each MKV to RAM before transcoding, reducing reads from disk"
	echo " -w | --write2ram       : Writes the MP4 to RAM before moving it to its final destination,"
	echo "                          reducing writes to disk and fragmentation"
	echo " -d | --ramdir <dir>    : Sets the temporary directory to copy the files to if -c or -w is used"
	echo " -f | --force           : Always transcodes the video, even if no subtitles are found"
	echo " -v | --videoParams <p> : Pass your own ffmpeg parameters (in quotes) related to the transcoded video"
	echo " -a | --audioParams <p> : Pass your own ffmpeg parameters (in quotes) related to the transcoded audio"
	echo " -p | --otherParams <p> : Pass your own miscellaneous ffmpeg parameters (in quotes)"
	echo " -S | --subLang <lang>  : Try to burn subtitles matching a specific language code"
	echo " -A | --audioLang <lang>: Try to encode audio tracks matching a specific language code"
	echo " -h | --help            : Print this help text"
}

if [[ $# -lt 1 ]]
then
	print_usage
	exit 2
fi

# Process arguments
while [ "$1" != "" ]; do
	case "$1" in
		-c | --copy2ram)
			copy2ram=true
			;;
		-w | --write2ram)
			write2ram=true
			;;
		-d | --ramdir)
			shift
			if [ -d "$1" ] && [ "$#" -ne 1 ]; then
				ramdir="$1"
			elif [ "$#" -eq 1 ]; then
				echo "$0: No output path specified."
				echo ""
				print_usage >&2
				exit 2
			else
				echo "$0: $1 is not a valid directory" >&2
				exit 2
			fi
			echo
			;;
		-f | --force)
			always_transcode=true
			;;
		-v | --videoParams)
			shift
			video_params="$1"
			;;
		-a | --audioParams)
			shift
			audio_params="$1"
			;;
		-p | --otherParams)
			shift
			other_params="$1"
			;;
		-S | --subLang)
			shift
			subs_lang="$1"
			;;
		-A | --audioLang)
			shift
			audio_lang="$1"
			;;
		-h | --help)
			print_usage
			exit
			;;
		*)
			if [ "$#" -eq 1 ]; then
				if [ "$1" != "" ]; then
					final_dir="$1"
				else
					echo "$0: No output path specified."
					echo ""
					print_usage >&2
					exit 2
				fi
			else
				echo "$0: '$1' invalid argument."
				echo ""
				print_usage >&2
				exit 2
			fi
			;;
	esac
	shift
done

# Functions
# https://stackoverflow.com/a/29310477
expandPath() {
	local path
	local -a pathElements resultPathElements
	IFS=':' read -r -a pathElements <<<"$1"
	: "${pathElements[@]}"
	for path in "${pathElements[@]}"; do
		: "$path"
		case $path in
			"~+"/*)
				path=$PWD/${path#"~+/"}
				;;
			"~-"/*)
				path=$OLDPWD/${path#"~-/"}
				;;
			"~"/*)
				path=$HOME/${path#"~/"}
				;;
			"~"*)
				username=${path%%/*}
				username=${username#"~"}
				IFS=: read -r _ _ _ _ _ homedir _ < <(getent passwd "$username")
				if [[ $path = */* ]]; then
					path=${homedir}/${path#*/}
				else
					path=$homedir
				fi
				;;
		esac
		resultPathElements+=( "$path" )
	done
	local result
	printf -v result '%s:' "${resultPathElements[@]}"
	printf '%s\n' "${result%:}"
}


check_audio_transcode () {
	stream="a:0"
	if [ "$audiomap" != "-map 0:a:0" ]; then
		stream="a:m:language:$audio_lang"
	fi

	get_audio_codec="$(ffprobe -v error -select_streams "$stream" -show_entries \
		stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$ramdir"/"$base".mkv | tr -d '\n' | tr -d ' ')"

	if [[ "$get_audio_codec" = "aac" ]]; then
		audio_parameters="-map 0:$stream -c:a copy"
	else
		audio_parameters="$audio_params -map 0:$stream"
	fi
}


select_audio_stream () {
	audiomap="-map 0:a:0"
	audio_exists="$(ffprobe -i "$ramdir"/"$base".mkv -hide_banner -v quiet -show_streams -select_streams a:m:language:"$audio_lang")"
	if [ -n "$audio_exists" ]; then
		audiomap="-map 0:a:m:language:$audio_lang"
	else
		echo "The requested audio language could not be found. Picking the first audio track available."
	fi
}

# Code reuse? What's that?
select_subs_stream () {
	submap="-map 0:s:0"
	subs_exists="$(ffprobe -i "$ramdir"/"$base".mkv -hide_banner -v quiet -show_streams -select_streams s:m:language:"$subs_lang")"
	if [ -n "$subs_exists" ]; then
		submap="-map 0:s:m:language:$subs_lang"
	else
		echo "The requested subtitle language could not be found. Picking the first subtitle track available."
	fi
}


cleanup () {
	rm -rf "$subsdir"/.subs
	rm -rf "$ramdir"/.fonts
	if [[ ! "$ramdir" = "." ]];then
		rm -f "$ramdir/$base.mkv"
	fi
}


# trap ctrl-c and call ctrl_c()
trap ctrl_c INT
ctrl_c () {
	cleanup
	rm -f "$outputdir"/"$base.mp4"
	exit 2
}


copy_to_ram () {
	# Set subsdir to RAM
	subsdir="$ramdir"
	copy_info_text="Copying file to RAM ($ramdir), to minimize disk usage."
	transcode_info_text="The transcoded file will be written to RAM first ($ramdir)."

	if [[ $copy2ram = true ]] && [[ $write2ram = true ]]; then
		echo "$copy_info_text"
		echo "$transcode_info_text"
		outputdir="$ramdir"
		status=$?
	elif [[ $copy2ram = true ]] && [[ $write2ram = false ]]; then
		echo "$copy_info_text"
		outputdir="$final_dir"
		status=$?
	elif [[ $write2ram = true ]] && [[ $copy2ram = false ]]; then
		echo "$transcode_info_text"
		outputdir="$ramdir"
		ramdir="."
		status=$?
	else
		ramdir="."
		outputdir="$final_dir"
		# Set subsdir to the current working directory
		subsdir="$ramdir"
		status=0
	fi
}


extract_fonts () {
	work_dir="$(pwd)"
	echo "Extracting fonts..."
	mkdir -p "$ramdir"/.fonts
	cd "$ramdir"/.fonts
	ffmpeg -y -dump_attachment:t "" -i ../"$base".mkv &>/dev/null

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


transcode () {
	if [[ $subs_state -eq 0 ]]; then
		echo "Subtitles extracted. Transcoding..."
		$ffbin -i "$ramdir"/"$base".mkv -vf "subtitles='$subsdir/.subs/$base.ass:fontsdir=$ramdir/.fonts'" \
			$audio_parameters $video_params $other_params "$outputdir"/"$base".mp4
	else
		if [ $always_transcode = true ]; then
			echo "No subtitles found. Converting to MP4 anyways..."
			$ffbin -i "$ramdir"/"$base".mkv $audio_parameters \
				$video_params $other_params "$outputdir"/"$base".mp4
		else
			echo "No subtitles found. Skipping file..."
			echo ""
			VID_TRANSCODED=false
		fi
	fi
}


move2final_dest () {
	if [[ ! $ramdir = "." ]];then
		rm -f "$ramdir"/"$base".mkv
		if [[ $write2ram = true ]]; then
			if [ $VID_TRANSCODED = true ]; then
				mv "$ramdir"/"$base".mp4 "$final_dir"/"$base".mp4 &
			fi
		fi
	elif [[ $write2ram = true ]] && [[ $copy2ram = false ]]; then
		if [ $VID_TRANSCODED = true ]; then
			mv "$outputdir"/"$base".mp4 "$final_dir"/"$base".mp4 &
		fi
	fi
}
# End functions

final_dir=$(expandPath "$final_dir")
FONTS_EXTRACTED=false
set_ffbin
mkdir -p "$final_dir"

# Check if we want to work with files on RAM
copy_to_ram "$final_dir"

for video in *.mkv; do
	if [[ $copy2ram = true ]]; then
		cp -v "$video" "$ramdir"
	fi

	VID_TRANSCODED=true
	base=$(basename "$video" .mkv)

	mkdir -p "$subsdir"/.subs

	# If there were no problems copying to RAM, proceed
	if [[ $status -eq 0 ]]; then
		echo ""	
		if [[ $FONTS_EXTRACTED = false ]]; then
			extract_fonts
			FONTS_EXTRACTED=true
		fi

		# Try to select the subtitle language
		select_subs_stream

		# Try to select the audio language
		select_audio_stream

		# Determine if transcoding the audio is necessary
		check_audio_transcode

		echo "Trying to extract subs..."
		 $(which ffmpeg) -v quiet -y -i "$ramdir"/"$base".mkv $submap -f matroska - | \
		 	$(which ffmpeg) -v quiet -stats -i - -map 0:s:0 "$subsdir"/.subs/"$base".ass
		subs_state="$?"

		# Transcode the file
		transcode

		# Remove the mkv from RAM and move the MP4
		move2final_dest

		if [[ $always_ex_fonts = true ]]; then
			rm -rf "$ramdir"/.fonts
			FONTS_EXTRACTED=false
		fi

	else
		echo "An error ocurred"
		cleanup
		exit 1
	fi
done

cleanup
echo "All done!"
exit 0
