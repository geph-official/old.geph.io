#!/bin/bash
mimetype=$(file -bN --mime-type "$1")
content=$(base64 -w0 < "$1")
if [ "${1##*.}" = "svg" ]
then
	mimetype="image/svg"
fi
echo "data:$mimetype;base64,$content"
